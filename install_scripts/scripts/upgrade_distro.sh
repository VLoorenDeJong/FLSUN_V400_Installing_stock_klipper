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

# --- Helper: detect whether to show reboot messages ---
# Return 0 (true) when script is run standalone (not called from start_sinstall.sh).
# Return 1 (false) when an ancestor process command line contains "start_sinstall.sh".
should_show_reboot_messages() {
    # Walk up the parent chain and look for start_sinstall.sh in any ancestor cmdline.
    local pid parent_cmdline
    pid=$$
    while [ "$pid" -gt 1 ]; do
        # Read the command line for this pid (replace NULs with spaces)
        if parent_cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true); then
            # Normalize to lower-case for matching
            local lc
            lc=$(printf '%s' "$parent_cmdline" | tr '[:upper:]' '[:lower:]')
            if [[ "$lc" == *"start_sinstall.sh"* ]] || [[ "$lc" == *"start-sinstall.sh"* ]]; then
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
    print_status "Installing upgrade tool..."
    sudo apt-get install -y -qq ubuntu-release-upgrader-core >/dev/null 2>&1
fi

# --- Confirm ---
printf "Choose upgrade channel:\n"
printf "  1) LTS releases only (safer)\n"
printf "  2) Any normal release\n\n"
read -rp "Enter 1 or 2 [default 1]: " CHANNEL_CHOICE
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
read -rp "Are you sure you want to continue? (yes/N): " CONFIRM
if [ "${CONFIRM:-}" != "yes" ]; then
    print_status "Upgrade cancelled."
    exit 0
fi

# --- Step 1: Fully update current system first ---
print_header "Step 1 of 3 — Update current system"
show_progress "📦 Updating package lists" "sudo apt-get update -qq >/dev/null 2>&1"
show_progress "⬆️  Applying all current updates" \
    "sudo apt-get dist-upgrade -y -qq >/dev/null 2>&1"
show_progress "🧹 Cleaning up" \
    "sudo apt-get autoremove --purge -y -qq >/dev/null 2>&1"
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
CHECK_OUTPUT=$(sudo do-release-upgrade -c 2>&1 || true)
if printf '%s' "$CHECK_OUTPUT" | grep -qi "No new release found"; then
    print_success "No new release available for channel: $UPGRADE_CHANNEL"
    exit 0
fi

# --- Step 3: Run distro upgrade ---
print_header "Step 3 of 3 — Running distro upgrade"
print_status "Running do-release-upgrade. This will take a while..."
print_warning "If prompted during upgrade, press Enter to accept defaults."
printf "\n"

# Run the upgrade and capture exit code
if sudo do-release-upgrade -f DistUpgradeViewNonInteractive; then
    print_success "Upgrade command completed successfully."
else
    print_error "do-release-upgrade exited with an error. Check logs in /var/log/dist-upgrade/ for details."
    # Even on failure, continue to check for reboot-required file to reflect system state
fi

# --- Reboot message logic: only show when this script is run standalone ---
if [ -f /var/run/reboot-required ]; then
    if should_show_reboot_messages; then
        print_warning "Reboot is required to finish applying some changes."
        print_status "No reboot was performed by this script. Reboot when ready."
    else
        # When called from another script (e.g., start_sinstall.sh), do not print the reboot messages.
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
