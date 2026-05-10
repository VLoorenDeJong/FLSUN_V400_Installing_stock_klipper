#!/usr/bin/env bash
set -e

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
    while kill -0 $cmd_pid 2>/dev/null; do
        printf "."
        sleep "$interval"
        local current_time
        current_time=$(date +%s)
        if (( current_time - start_time > timeout )); then
            printf "\n\033[31m❌ Command timed out after %d seconds\033[0m\n" "$timeout"
            kill -TERM $cmd_pid 2>/dev/null || true
            sleep 2
            kill -KILL $cmd_pid 2>/dev/null || true
            return 1
        fi
    done
    wait $cmd_pid 2>/dev/null
    local exit_code=$?
    printf "\n"
    return $exit_code
}

print_status()  { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning() { printf "\033[33m⚠️  %s\033[0m\n" "$1"; }
print_error()   { printf "\033[31m❌ %s\033[0m\n" "$1"; }
print_header()  { printf "\n\033[36m=== %s ===\033[0m\n" "$1"; }

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
case "$CHANNEL_CHOICE" in
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
if [ "$CONFIRM" != "yes" ]; then
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

sudo do-release-upgrade -f DistUpgradeViewNonInteractive

print_success "Upgrade command completed."
if [ -f /var/run/reboot-required ]; then
    print_warning "Reboot is required to finish applying some changes."
    print_status "No reboot was performed by this script. Reboot when ready."
else
    print_success "No reboot required right now."
fi
