#!/bin/bash
set -e

# Repository Cleanup Script
# Removes problematic repositories and cleans apt cache

# Function to check and fix DPKG locks (calls dedicated script)
check_and_fix_dpkg_lock() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local fix_script="$script_dir/fix_dpkg_lock.sh"
    
    if [ -f "$fix_script" ]; then
        print_status "Checking for DPKG locks..."
        if bash "$fix_script"; then
            print_success "DPKG lock check completed"
        else
            print_warning "DPKG lock check failed, continuing anyway"
        fi
    else
        print_warning "DPKG lock fix script not found, continuing without lock check"
    fi
}

# Function to print status messages
print_status() {
    printf "\033[34m🔧 %s\033[0m\n" "$1"
}

# Function to print success messages
print_success() {
    printf "\033[32m✅ %s\033[0m\n" "$1"
}

# Function to print warnings
print_warning() {
    printf "\033[33m⚠️ %s\033[0m\n" "$1"
}

# Function to print errors
print_error() {
    printf "\033[31m❌ %s\033[0m\n" "$1"
}

# Inline show_progress function (always used)
show_progress() {
    local message="$1"
    local command="$2"
    local interval="${3:-5}"
    local timeout="${4:-600}"
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

print_status "Cleaning up problematic repositories..."

# Check and fix any DPKG locks before proceeding with package operations
check_and_fix_dpkg_lock

# Simple approach: remove known problematic repositories
print_status "Checking for problematic repositories..."

# Run apt-get update ONCE and capture its output — every repository check below
# greps this capture instead of re-running a full (slow, silent) update per repo.
APT_PROBE_OUT=$(mktemp)
trap 'rm -f "$APT_PROBE_OUT"' EXIT
show_progress "📦 Probing repositories (apt-get update)" \
    "sudo apt-get update > '$APT_PROBE_OUT' 2>&1 || true" 3 600

# Remove webmin repository if it has GPG issues
if [ -f "/etc/apt/sources.list.d/webmin.list" ]; then
    if grep -qi "gpg error.*webmin\|no valid openpgp data found.*webmin\|signatures were invalid.*webmin" "$APT_PROBE_OUT"; then
        print_status "Removing problematic webmin repository"
        sudo rm -f /etc/apt/sources.list.d/webmin.list
        sudo rm -f /usr/share/keyrings/webmin.gpg
        print_success "Webmin repository removed"
    fi
fi

# Check for other common problematic repositories
for repo_file in /etc/apt/sources.list.d/*.list; do
    if [ -f "$repo_file" ]; then
        repo_name=$(basename "$repo_file" .list)
        # Test if this specific repository causes issues (grep the single probe above)
        if grep -qi "gpg error.*$repo_name\|no valid openpgp data found.*$repo_name\|signatures were invalid.*$repo_name" "$APT_PROBE_OUT"; then
            print_status "Removing problematic repository: $repo_name"
            sudo rm -f "$repo_file"
            
            # Remove associated GPG keys if they exist
            keyring_file="/usr/share/keyrings/${repo_name}.gpg"
            if [ -f "$keyring_file" ]; then
                sudo rm -f "$keyring_file"
                print_status "Removed associated keyring: $keyring_file"
            fi
            print_success "Repository $repo_name removed"
        fi
    fi
done

# Clean apt cache and update
print_status "Cleaning package cache..."
sudo apt-get clean 2>/dev/null || true

if show_progress "📦 Updating package lists" "sudo apt-get update -qq --fix-missing >/dev/null 2>&1" 3 180; then
    print_success "Package lists updated successfully"
else
    print_warning "Some repositories may still have issues"
    # Try one more time with verbose output for debugging
    print_status "Running verbose update to identify remaining issues..."
    timeout 180 sudo apt-get update 2>&1 | grep -E "(ERROR|WARNING|GPG error)" || print_success "No critical errors found"
fi

print_success "Repository cleanup completed!"