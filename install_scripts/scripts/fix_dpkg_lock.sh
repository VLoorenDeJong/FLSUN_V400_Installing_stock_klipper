#!/bin/bash

print_status()  { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning() { printf "\033[33m⚠️  %s\033[0m\n" "$1"; }
print_error()   { printf "\033[31m❌ %s\033[0m\n" "$1"; }

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
    run_privileged apt-get update -qq --fix-missing
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

print_status "Checking for dpkg/lock-frontend and package cache issues..."

# Test if we have a real dpkg lock issue
if [ "$(check_dpkg_lock)" = "false" ]; then
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
print_status "Configuring dpkg..."
if run_privileged dpkg --configure -a >/dev/null 2>&1; then
    print_success "dpkg configured"
else
    print_error "dpkg configuration failed"
fi

# Step 5: Fix broken dependencies
print_status "Fixing dependencies..."
if run_privileged apt-get install -f -qq >/dev/null 2>&1; then
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
