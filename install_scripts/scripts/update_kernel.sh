#!/usr/bin/env bash
set -e

export DEBIAN_FRONTEND=noninteractive

# --- Inline utility functions ---
show_progress() {
    local message="$1"
    local command="$2"
    local interval="${3:-5}"
    local timeout="${4:-600}"
    local log_file
    log_file=$(mktemp /tmp/progress.XXXXXX.log)
    printf "\033[34m%s\033[0m\n" "$message"

    # Debug mode: stream output live. No dots, no kill timer.
    if [ "${FLSUN_DEBUG:-0}" = "1" ]; then
        eval "$command" 2>&1 | tee "$log_file"
        local exit_code=${PIPESTATUS[0]}
        if [ "$exit_code" -eq 0 ]; then
            rm -f "$log_file"
        else
            printf "\033[31m❌ Command failed (exit %s). Full log: %s\033[0m\n" "$exit_code" "$log_file"
        fi
        return "$exit_code"
    fi

    # Normal mode: capture output to the log. Show dots.
    eval "$command" >"$log_file" 2>&1 &
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
            printf "\033[31mLast output before timeout:\033[0m\n"
            tail -n 20 "$log_file"
            printf "\033[33mFull log: %s\033[0m\n" "$log_file"
            return 1
        fi
    done
    wait $cmd_pid 2>/dev/null
    local exit_code=$?
    printf "\n"
    if [ "$exit_code" -ne 0 ]; then
        printf "\033[31m❌ Command failed (exit %s). Last output:\033[0m\n" "$exit_code"
        tail -n 20 "$log_file"
        printf "\033[33mFull log: %s\033[0m\n" "$log_file"
    else
        rm -f "$log_file"
    fi
    return "$exit_code"
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

show_progress "📦 Updating package lists" "sudo apt-get update -qq" 3 600

# --force-confnew auto-answers dpkg conffile prompts (e.g. the /etc/sudoers
# "Y/I/N/O/D/Z" dialog) by installing the package maintainer's version — the
# "Y/I" option — unattended. NOTE: confnew must NOT be paired with confdef, or
# confdef's default action (keep current) would win instead.
show_progress "⬆️  Installing latest kernel and security updates" \
    "sudo apt-get dist-upgrade -y -o Dpkg::Options::=\"--force-confnew\" -qq" 5 1800

show_progress "🧹 Removing old kernels" \
    "sudo apt-get autoremove --purge -y -qq" 3 600

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
