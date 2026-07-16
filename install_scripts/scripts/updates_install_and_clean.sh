#!/bin/bash

# Suppress confirmation prompts for apt
export DEBIAN_FRONTEND=noninteractive

print_status()  { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning() { printf "\033[33m⚠️  %s\033[0m\n" "$1"; }
print_error()   { printf "\033[31m❌ %s\033[0m\n" "$1"; }

# Inline show_progress function (always used)
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

# Function to check and fix DPKG locks (calls dedicated script)
check_and_fix_dpkg_lock() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local fix_script="$script_dir/fix_dpkg_lock.sh"

    if [ -f "$fix_script" ]; then
        print_status "Checking and fixing DPKG locks..."
        if bash "$fix_script"; then
            print_success "DPKG lock check/fix completed"
            return 0
        else
            print_error "DPKG lock fix failed, continuing anyway..."
            return 1
        fi
    else
        print_warning "fix_dpkg_lock.sh not found, proceeding without DPKG lock check"
        return 1
    fi
}

# Enable or disable confirmation prompts (true = ask, false = skip)
ASK_CONFIRMATION=false

# Function to prompt the user if confirmation is enabled
ask_user() {
    if [[ "$ASK_CONFIRMATION" == true ]]; then
        read -r -p "$1 (Y/n): " choice </dev/tty
        choice=${choice:-Y}  # Default to "Y" if no input is given
        [[ "$choice" =~ ^[Yy]$ ]]
    else
        return 0  # Automatically proceed without asking
    fi
}

# Ask for system update confirmation
if ask_user "Do you want to update and upgrade the system?"; then
    # Check and fix any DPKG locks before proceeding with package operations
    check_and_fix_dpkg_lock

    if show_progress "📦 Updating package lists" "sudo apt-get update -qq"; then
        print_success "Package lists updated successfully"

        if show_progress "⬆️ Upgrading system packages" "sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -o Dpkg::Options::=\"--force-confnew\" -qq"; then
            print_success "System upgrade completed successfully"
        else
            print_error "System upgrade failed"
            exit 1
        fi
    else
        print_error "Package list update failed"
        exit 1
    fi

    # Ask for cleanup confirmation
    if ask_user "Do you want to clean up unused packages?"; then
        # Remove unused packages
        if show_progress "🗑️ Removing unused packages" "sudo apt-get autoremove -y -qq"; then
            print_success "Unused packages removed"
        fi

        # Purge leftover configuration files, only if any exist
        leftover_configs=$(dpkg -l | awk '/^rc/ { print $2 }')
        if [ -n "$leftover_configs" ]; then
            if show_progress "🧹 Removing leftover configurations" "sudo apt-get purge -y -qq $leftover_configs"; then
                print_success "Leftover configurations removed"
            fi
        fi

        # Clean up cached packages
        if show_progress "🧽 Cleaning package cache" "sudo apt-get autoclean -y -qq && sudo apt-get clean -y -qq"; then
            print_success "Package cache cleaned"
        fi

        print_success "System cleanup completed!"
    fi
fi
