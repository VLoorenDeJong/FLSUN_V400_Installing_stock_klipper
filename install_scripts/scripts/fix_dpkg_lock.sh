#!/bin/bash

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
    echo -e "\e[34m🔄 Cleaning package cache...\e[0m"

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

echo -e "\e[34m🔍 Checking for dpkg/lock-frontend and package cache issues...\e[0m"

# Test if we have a real dpkg lock issue
if [ "$(check_dpkg_lock)" = "false" ]; then
    echo -e "\e[32m✅ No dpkg lock detected. System is ready for package operations.\e[0m"
    exit 0
else
    echo -e "\e[33m⚠️  dpkg lock detected. Attempting to fix...\e[0m"
fi

# Step 1: Find and kill processes using dpkg lock
echo -e "\e[34m🔄 Finding and killing dpkg processes...\e[0m"
dpkg_processes=$(find_dpkg_processes)

if [ -n "$dpkg_processes" ]; then
    echo -e "\e[33m📋 Found processes: $dpkg_processes\e[0m"
    for pid in $dpkg_processes; do
        run_privileged kill -9 "$pid" 2>/dev/null || true
    done
    sleep 2
    echo -e "\e[32m✅ Processes killed\e[0m"
else
    echo -e "\e[32m✅ No active processes found\e[0m"
fi

# Step 2: Remove lock files
echo -e "\e[34m🔄 Removing dpkg lock files...\e[0m"

lock_files=("/var/lib/dpkg/lock-frontend" "/var/lib/dpkg/lock")
lock_files_removed=0
for lock_file in "${lock_files[@]}"; do
    if [ -f "$lock_file" ]; then
        run_privileged rm -f "$lock_file"
        ((lock_files_removed++))
    fi
done

if [ $lock_files_removed -gt 0 ]; then
    echo -e "\e[32m✅ Removed $lock_files_removed lock files\e[0m"
else
    echo -e "\e[32m✅ No lock files found\e[0m"
fi

# Step 3: Clean package cache
echo -e "\e[34m🔄 Cleaning package cache...\e[0m"
clean_package_cache
echo -e "\e[32m✅ Package cache cleaned\e[0m"

# Step 4: Configure dpkg
echo -e "\e[34m🔄 Configuring dpkg...\e[0m"
if run_privileged dpkg --configure -a >/dev/null 2>&1; then
    echo -e "\e[32m✅ dpkg configured\e[0m"
else
    echo -e "\e[31m❌ dpkg configuration failed\e[0m"
fi

# Step 5: Fix broken dependencies
echo -e "\e[34m🔄 Fixing dependencies...\e[0m"
if run_privileged apt-get install -f -qq >/dev/null 2>&1; then
    echo -e "\e[32m✅ Dependencies fixed\e[0m"
else
    echo -e "\e[31m❌ Dependency fix failed\e[0m"
fi

# Step 6: Test if fix worked
echo -e "\e[34m🔄 Testing fix...\e[0m"
if [ "$(check_dpkg_lock)" = "false" ]; then
    echo -e "\e[32m🎉 Success! dpkg lock resolved\e[0m"
    exit 0
else
    echo -e "\e[31m❌ dpkg lock persists\e[0m"
    exit 1
fi