#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# --- Inline utility functions ---
show_progress() {
    local message="$1"
    local command="$2"
    local interval="${3:-5}"
    local timeout="${4:-1800}"
    printf "\033[34m%s\033[0m\n" "$message"
    eval "$command" &
    local cmd_pid=$!
    local start_time
    start_time=$(date +%s)
    while kill -0 "$cmd_pid" 2>/dev/null; do
        printf "."
        sleep "$interval"
        local current_time
        current_time=$(date +%s)
        if (( current_time - start_time > timeout )); then
            printf "\n\033[31m❌ Command timed out after %d seconds\033[0m\n" "$timeout"
            kill -TERM "$cmd_pid" 2>/dev/null || true
            sleep 2
            kill -KILL "$cmd_pid" 2>/dev/null || true
            return 1
        fi
    done
    wait "$cmd_pid" 2>/dev/null
    local exit_code=$?
    printf "\n"
    return $exit_code
}

print_status()  { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning() { printf "\033[33m⚠️  %s\033[0m\n" "$1"; }
print_error()   { printf "\033[31m❌ %s\033[0m\n" "$1"; }
print_header()  { printf "\n\033[36m=== %s ===\033[0m\n" "$1"; }

# Like show_progress, but for commands that must NEVER be killed (a half-done
# release upgrade can leave the OS unbootable): no timeout, watch-only. Surfaces
# the newest line of a log file as progress, dots while it's quiet.
# Usage: run_with_log_progress "command" "/path/to/log" [poll_seconds]
run_with_log_progress() {
    local command="$1"
    local log_file="$2"
    local poll="${3:-10}"
    eval "$command" &
    local cmd_pid=$!
    local last_line="" cur_line
    while kill -0 "$cmd_pid" 2>/dev/null; do
        sleep "$poll"
        cur_line="$(sudo tail -n 1 "$log_file" 2>/dev/null || true)"
        if [ -n "$cur_line" ] && [ "$cur_line" != "$last_line" ]; then
            printf '\n\033[34m⏳ %.120s\033[0m' "$cur_line"
            last_line="$cur_line"
        else
            printf "."
        fi
    done
    printf "\n"
    local exit_code=0
    wait "$cmd_pid" || exit_code=$?
    return $exit_code
}

# --- Helper: detect whether to show reboot messages ---
# Return 0 (true) when script is run standalone (not called from start_install.sh).
# Return 1 (false) when an ancestor process command line contains "start_install.sh".
should_show_reboot_messages() {
    # Walk up the parent chain and look for start_install.sh in any ancestor cmdline.
    local pid parent_cmdline
    pid=$$
    while [ "$pid" -gt 1 ]; do
        # Read the command line for this pid (replace NULs with spaces)
        if parent_cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true); then
            # Normalize to lower-case for matching
            local lc
            lc=$(printf '%s' "$parent_cmdline" | tr '[:upper:]' '[:lower:]')
            if [[ "$lc" == *"start_install.sh"* ]] || [[ "$lc" == *"start-install.sh"* ]]; then
                return 1
            fi
        fi

        # Get parent pid
        if [ -r "/proc/$pid/status" ]; then
            pid=$(awk '/^PPid:/{print $2}' "/proc/$pid/status" 2>/dev/null || echo 1)
        else
            # Fallback: break out if we can't read status
            break
        fi
    done

    # Also suppress when running under common orchestration wrappers that are likely to call this script:
    # e.g., systemd-run, some CI runners, or when invoked as part of another script via sh -c.
    # If the immediate parent is "systemd" or "init" we still consider this standalone.
    return 0
}

# --- Variables ---
CURRENT_VERSION=$(lsb_release -rs 2>/dev/null || echo "unknown")
DISTRO_ID=$(lsb_release -is 2>/dev/null || echo "unknown")
UPGRADE_CHANNEL="lts"

# --- Pre-flight checks ---
print_header "Ubuntu Distro Upgrade"
print_status "Current version: $DISTRO_ID $CURRENT_VERSION"

if [ "$DISTRO_ID" != "Ubuntu" ]; then
    print_error "This script currently supports Ubuntu only. Detected distro: $DISTRO_ID"
    exit 1
fi

if ! command -v do-release-upgrade &>/dev/null; then
    show_progress "🔧 Installing upgrade tool (ubuntu-release-upgrader-core)" \
        "sudo apt-get install -y -qq ubuntu-release-upgrader-core >/dev/null 2>&1" 3 600
fi

# --- Confirm ---
printf "Choose upgrade channel:\n"
printf "  1) LTS releases only (safer)\n"
printf "  2) Any normal release\n\n"
read -rp "Enter 1 or 2 [default 1]: " CHANNEL_CHOICE </dev/tty
case "${CHANNEL_CHOICE:-}" in
    2)
        UPGRADE_CHANNEL="normal"
        ;;
    *)
        UPGRADE_CHANNEL="lts"
        ;;
esac

print_warning "This will upgrade Ubuntu to the next available $UPGRADE_CHANNEL release."
print_warning "The process can take a long time and usually requires reboot later."
printf "\n"
read -rp "Are you sure you want to continue? (Y/n): " CONFIRM </dev/tty
CONFIRM="${CONFIRM:-Y}"   # Enter defaults to Yes
if [[ ! "$CONFIRM" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    print_status "Upgrade cancelled."
    exit 0
fi

# --- Content-aware sudoers protection across the upgrade ---
# We install the maintainer's version of conffiles (confnew below). If the printer
# user's passwordless-sudo rule lives directly in /etc/sudoers (not in a
# /etc/sudoers.d/ file), confnew can wipe it — and KIAUH in Phase 2 runs as that
# user and calls sudo, so losing it would break Phase 2. Strategy: snapshot
# sudoers now and remember the exact NOPASSWD rule(s) for the install user; if the
# upgrade drops them, restore JUST those rules afterwards, via a validated
# /etc/sudoers.d/ drop-in (never edit the main file, never install an invalid rule).
INSTALL_USER="${SUDO_USER:-}"
if [ -z "$INSTALL_USER" ] || [ "$INSTALL_USER" = "root" ]; then
    id pi >/dev/null 2>&1 && INSTALL_USER="pi" || INSTALL_USER=""
fi

SUDOERS_BACKUP_DIR="/var/backups/flsun-sudoers-$(date +%Y%m%d_%H%M%S)"
NOPASSWD_WAS_PRESENT=0
NOPASSWD_RULES=""

# Emit every NOPASSWD rule granting the install user passwordless sudo, across the
# main file and sudoers.d.
find_user_nopasswd_rules() {
    [ -n "$INSTALL_USER" ] || return 0
    grep -rhsE "^[[:space:]]*${INSTALL_USER}[[:space:]].*NOPASSWD" \
        /etc/sudoers /etc/sudoers.d/ 2>/dev/null
}

if [ -n "$INSTALL_USER" ]; then
    print_status "Snapshotting sudoers (protecting passwordless sudo for '$INSTALL_USER')..."
    sudo mkdir -p "$SUDOERS_BACKUP_DIR"
    sudo cp -a /etc/sudoers   "$SUDOERS_BACKUP_DIR/sudoers"   2>/dev/null || true
    sudo cp -a /etc/sudoers.d "$SUDOERS_BACKUP_DIR/sudoers.d" 2>/dev/null || true
    NOPASSWD_RULES="$(find_user_nopasswd_rules)"
    if [ -n "$NOPASSWD_RULES" ]; then
        NOPASSWD_WAS_PRESENT=1
        print_status "Passwordless sudo present for '$INSTALL_USER' — will restore it if the upgrade removes it."
    fi
fi

# --- Auto-answer dpkg conffile prompts for the whole upgrade ---
# The dist-upgrade below AND do-release-upgrade in Step 3 otherwise stop on
# interactive "Configuration file '/etc/sudoers' ... (Y/I/N/O/D/Z)" dialogs buried
# in verbose output. A temporary apt.conf.d drop-in makes every apt/dpkg call
# (including the release upgrader, which can't take -o flags) install the
# maintainer's version (the "Y/I" answer) so 22.04 gets clean new-release defaults.
CONFFILE_DROPIN="/etc/apt/apt.conf.d/99flsun-noninteractive"
sudo tee "$CONFFILE_DROPIN" >/dev/null <<'EOF'
Dpkg::Options { "--force-confnew"; };
APT::Get::Assume-Yes "true";
EOF

# Restore passwordless sudo if the upgrade dropped it, then remove the drop-in.
# Runs on every exit path (normal end, no-new-release, error) via the trap below.
restore_sudo_and_cleanup() {
    sudo rm -f "$CONFFILE_DROPIN"

    [ "$NOPASSWD_WAS_PRESENT" -eq 1 ] || return 0
    if find_user_nopasswd_rules | grep -q .; then
        print_success "Passwordless sudo for '$INSTALL_USER' survived the upgrade."
        return 0
    fi

    print_warning "Upgrade removed passwordless sudo for '$INSTALL_USER' — restoring via /etc/sudoers.d/."
    local dropin="/etc/sudoers.d/99-flsun-nopasswd"
    local tmp
    tmp="$(mktemp)"
    # Restore the EXACT rule(s) captured pre-upgrade — never widen the grant.
    printf '%s\n' "$NOPASSWD_RULES" > "$tmp"
    # Validate in isolation BEFORE installing — an invalid sudoers file locks out sudo.
    if sudo visudo -cf "$tmp" >/dev/null 2>&1; then
        sudo install -m 0440 -o root -g root "$tmp" "$dropin"
        if sudo visudo -c >/dev/null 2>&1; then
            print_success "Restored passwordless sudo for '$INSTALL_USER' ($dropin)."
        else
            sudo rm -f "$dropin"
            print_error "Full sudoers validation failed after restore — removed drop-in to keep sudo working."
            print_warning "Pre-upgrade sudoers backup: $SUDOERS_BACKUP_DIR"
        fi
    else
        print_error "Captured sudo rule did not validate standalone — not modifying sudo config."
        print_warning "Restore manually from: $SUDOERS_BACKUP_DIR"
    fi
    rm -f "$tmp"
}
trap restore_sudo_and_cleanup EXIT

print_status "Conffile prompts will be auto-answered (install maintainer's version) for this upgrade."

# --- Step 1: Fully update current system first ---
print_header "Step 1 of 3 — Update current system"
show_progress "📦 Updating package lists" "sudo apt-get update -qq >/dev/null 2>&1"
# dist-upgrade and autoremove are dpkg TRANSACTIONS — killing them mid-flight
# corrupts package state, so no show_progress timeout here. Watch-only progress
# from dpkg's own log (one line per package action) instead.
print_status "⬆️  Applying all current updates (per-package progress below)"
run_with_log_progress "sudo apt-get dist-upgrade -y -qq >/dev/null 2>&1" "/var/log/dpkg.log" 5
print_status "🧹 Cleaning up"
run_with_log_progress "sudo apt-get autoremove --purge -y -qq >/dev/null 2>&1" "/var/log/dpkg.log" 5
print_success "Current system fully updated."

# --- Step 2: Configure upgrade channel ---
print_header "Step 2 of 3 — Configure upgrade path"
if grep -q '^Prompt=' /etc/update-manager/release-upgrades 2>/dev/null; then
    sudo sed -i "s/^Prompt=.*/Prompt=$UPGRADE_CHANNEL/" /etc/update-manager/release-upgrades
else
    printf "Prompt=%s\n" "$UPGRADE_CHANNEL" | sudo tee -a /etc/update-manager/release-upgrades >/dev/null
fi
print_success "Upgrade channel set to: $UPGRADE_CHANNEL"

print_status "Checking if a new release is available..."
RELCHECK_OUT="$(mktemp)"
show_progress "🔍 Querying Ubuntu release servers" \
    "sudo do-release-upgrade -c > '$RELCHECK_OUT' 2>&1" 3 300 || true
CHECK_OUTPUT="$(cat "$RELCHECK_OUT" 2>/dev/null || true)"
rm -f "$RELCHECK_OUT"
if printf '%s' "$CHECK_OUTPUT" | grep -qi "No new release found"; then
    print_success "No new release available for channel: $UPGRADE_CHANNEL"
    exit 0
fi

# --- Step 3: Run distro upgrade ---
print_header "Step 3 of 3 — Running distro upgrade"
print_status "Running do-release-upgrade. This will take a while..."
print_warning "If prompted during upgrade, press Enter to accept defaults."
printf "\n"

# Run the upgrade with a live progress feed. The NonInteractive frontend prints
# almost nothing to the terminal — real progress goes to /var/log/dist-upgrade/.
UPG_RC=0
run_with_log_progress "sudo do-release-upgrade -f DistUpgradeViewNonInteractive" \
    "/var/log/dist-upgrade/main.log" 10 || UPG_RC=$?

if [ "$UPG_RC" -eq 0 ]; then
    print_success "Upgrade command completed successfully."
else
    print_error "do-release-upgrade exited with an error (code $UPG_RC). Check logs in /var/log/dist-upgrade/ for details."
    # Even on failure, continue to check for reboot-required file to reflect system state
fi

# --- Reboot message logic: only show when this script is run standalone ---
if [ -f /var/run/reboot-required ]; then
    if should_show_reboot_messages; then
        print_warning "Reboot is required to finish applying some changes."
        print_status "No reboot was performed by this script. Reboot when ready."
    else
        # When called from another script (e.g., start_install.sh), do not print the reboot messages.
        # Instead, write a concise state file for the caller to inspect.
        printf "reboot-required\n" > /var/run/sinstall_state 2>/dev/null || true
    fi
else
    if should_show_reboot_messages; then
        print_success "No reboot required right now."
    else
        printf "no-reboot-required\n" > /var/run/sinstall_state 2>/dev/null || true
    fi
fi

exit 0
