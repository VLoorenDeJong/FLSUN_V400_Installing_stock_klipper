#!/usr/bin/env bash
set -e

export DEBIAN_FRONTEND=noninteractive

# --- Inline utility functions ---
show_progress() {
    local message="$1"
    local command="$2"
    local interval="${3:-3}"
    local timeout="${4:-300}"
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
CURRENT_KERNEL=$(uname -r)
NEW_KERNEL=$(uname -r)

# --- Main ---
print_header "Kernel Update"
print_status "Current kernel: $CURRENT_KERNEL"

show_progress "📦 Updating package lists" "sudo apt-get update -qq >/dev/null 2>&1" 3 600

show_progress "⬆️  Installing latest kernel and security updates" \
    "sudo apt-get dist-upgrade -y -qq >/dev/null 2>&1" 5 1800

show_progress "🧹 Removing old kernels" \
    "sudo apt-get autoremove --purge -y -qq >/dev/null 2>&1" 3 600

NEW_KERNEL=$(dpkg -l 'linux-image-*' 2>/dev/null | awk '/^ii/ {print $2}' | sed 's/linux-image-//' | sort -V | tail -n 1)

print_success "Kernel packages updated. Running kernel: $CURRENT_KERNEL"
if [ -n "$NEW_KERNEL" ] && [ "$NEW_KERNEL" != "$CURRENT_KERNEL" ]; then
    print_warning "New installed kernel detected: $NEW_KERNEL"
fi

if [ -f /var/run/reboot-required ]; then
    print_warning "Reboot is required to load the new kernel."
    print_status "No reboot was performed by this script. Reboot when ready."
else
    print_success "No reboot required right now."
fi
