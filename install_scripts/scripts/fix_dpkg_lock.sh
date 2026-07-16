#!/bin/bash

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

# Function to run commands with appropriate privileges
run_privileged() {
    if [ "$EUID" -eq 0 ]; then
        # Already running as root, no sudo needed
        "$@"
    else
        # Not root, use sudo
        sudo "$@"
    fi
}

# Function to find processes using dpkg
find_dpkg_processes() {
    local processes=$(lsof /var/lib/dpkg/lock-frontend 2>/dev/null | awk 'NR>1 {print $2}' | sort -u)
    echo "$processes"
}

# Function to clean package cache
clean_package_cache() {
    print_status "Cleaning package cache..."

    # Remove corrupted package cache files
    run_privileged rm -f /var/cache/apt/*.bin
    run_privileged find /var/lib/apt/lists/ -maxdepth 1 -type f -delete
    run_privileged rm -f /var/lib/apt/lists/partial/*

    # Update package lists (quiet mode)
    run_privileged apt-get clean -qq
    show_progress "📦 Refreshing package lists" "run_privileged apt-get update -qq --fix-missing" 3 600
}

# Better lock detection - check for actual lock files AND processes
check_dpkg_lock() {
    local lock_detected=false

    # Check if lock files exist AND are being used by processes
    if [ -f "/var/lib/dpkg/lock-frontend" ]; then
        local processes=$(find_dpkg_processes)
        if [ -n "$processes" ]; then
            lock_detected=true
        fi
    fi

    # Alternative: Check if dpkg/apt commands are actually blocked
    if ! $lock_detected; then
        # Try a simple dpkg status check (less likely to fail for other reasons)
        if ! timeout 3 run_privileged dpkg --audit >/dev/null 2>&1; then
            # Double-check with fuser to see if lock files are actually in use
            if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
               fuser /var/lib/dpkg/lock >/dev/null 2>&1; then
                lock_detected=true
            fi
        fi
    fi

    echo $lock_detected
}

# Watch-only variant for dpkg TRANSACTIONS. Killing dpkg/apt mid-write
# corrupts package state, so this never sends a signal. It waits as long
# as the transaction needs. Output handling matches show_progress.
show_progress_no_kill() {
    local message="$1"
    local command="$2"
    local interval="${3:-5}"
    local log_file
    log_file=$(mktemp /tmp/progress.XXXXXX.log)
    printf "\033[34m%s\033[0m\n" "$message"

    # Debug mode: stream output live.
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

    eval "$command" >"$log_file" 2>&1 &
    local cmd_pid=$!
    while kill -0 $cmd_pid 2>/dev/null; do
        printf "."
        sleep "$interval"
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

print_status "Checking for dpkg/lock-frontend and package cache issues..."

# Test if we have a real dpkg lock issue
if [ "$(check_dpkg_lock)" = "false" ]; then
    # A lock-free system can still be blocked: a package left half-configured
    # makes every apt-get install exit 1 (seen with update-notifier-common
    # after python3 was repointed to 3.9). dpkg --audit reports it.
    if [ -n "$(run_privileged dpkg --audit 2>/dev/null)" ]; then
        print_warning "Half-configured packages found. Repairing..."
        # dpkg TRANSACTION — watch-only wrapper, never killed (see Step 4).
        if show_progress_no_kill "🔧 Configuring pending packages (dpkg --configure -a)" "run_privileged dpkg --configure -a" 5; then
            print_success "Pending packages configured"
            exit 0
        else
            print_error "Repair failed. Run by hand to see the error: sudo dpkg --configure -a"
            exit 1
        fi
    fi
    print_success "No dpkg lock detected. System is ready for package operations."
    exit 0
else
    print_warning "dpkg lock detected. Attempting to fix..."
fi

# Step 1: Find and kill processes using dpkg lock
print_status "Finding and killing dpkg processes..."
dpkg_processes=$(find_dpkg_processes)

if [ -n "$dpkg_processes" ]; then
    print_warning "Found processes: $dpkg_processes"
    for pid in $dpkg_processes; do
        run_privileged kill -9 "$pid" 2>/dev/null || true
    done
    sleep 2
    print_success "Processes killed"
else
    print_success "No active processes found"
fi

# Step 2: Remove lock files
print_status "Removing dpkg lock files..."

lock_files=("/var/lib/dpkg/lock-frontend" "/var/lib/dpkg/lock")
lock_files_removed=0
for lock_file in "${lock_files[@]}"; do
    if [ -f "$lock_file" ]; then
        run_privileged rm -f "$lock_file"
        ((lock_files_removed++))
    fi
done

if [ $lock_files_removed -gt 0 ]; then
    print_success "Removed $lock_files_removed lock files"
else
    print_success "No lock files found"
fi

# Step 3: Clean package cache
print_status "Cleaning package cache..."
clean_package_cache
print_success "Package cache cleaned"

# Step 4: Configure dpkg
# NOTE: dpkg --configure -a and apt-get install -f are dpkg TRANSACTIONS — a
# timeout kill mid-run corrupts package state. Watch-only wrapper, no kill.
if show_progress_no_kill "🔧 Configuring dpkg (dpkg --configure -a)" "run_privileged dpkg --configure -a" 5; then
    print_success "dpkg configured"
else
    print_error "dpkg configuration failed"
fi

# Step 5: Fix broken dependencies
if show_progress_no_kill "🔗 Fixing dependencies (apt-get install -f)" "run_privileged apt-get install -f -qq" 5; then
    print_success "Dependencies fixed"
else
    print_error "Dependency fix failed"
fi

# Step 6: Test if fix worked
print_status "Testing fix..."
if [ "$(check_dpkg_lock)" = "false" ]; then
    print_success "Success! dpkg lock resolved"
    exit 0
else
    print_error "dpkg lock persists"
    exit 1
fi
