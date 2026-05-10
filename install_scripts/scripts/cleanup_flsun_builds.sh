#!/usr/bin/env bash
set -e

# --- Inline utility functions ---
print_status()  { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning() { printf "\033[33m⚠️  %s\033[0m\n" "$1"; }
print_error()   { printf "\033[31m❌ %s\033[0m\n" "$1"; }
print_header()  { printf "\n\033[36m=== %s ===\033[0m\n" "$1"; }

# --- Variables ---
readonly PI_HOME="/home/pi"
readonly KIAUH_DIR="${PI_HOME}/kiauh"

# --- Validation ---
if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must run with sudo/root privileges."
    exit 1
fi

if [ ! -d "$PI_HOME" ]; then
    print_error "Expected user home not found: $PI_HOME"
    exit 1
fi

# --- Main ---
print_header "Fix KIAUH Permissions"

# Steps 530-532: fix kiauh ownership and git safe directory
if [ -d "$KIAUH_DIR" ]; then
    print_status "Fixing ownership of $KIAUH_DIR..."
    sudo chown -R pi:pi "$KIAUH_DIR"
    sudo -u pi git config --global --add safe.directory "$KIAUH_DIR" 2>/dev/null || true
    print_success "KIAUH permissions fixed."
else
    print_warning "KIAUH directory not found at $KIAUH_DIR — skipping permission fix."
fi

print_header "Remove Flsun-Specific Files and Directories"
print_warning "This removes Flsun Klipper databases, configs, logs, and user cache directories."

# Steps 079-082: remove Flsun-specific dirs and files
readonly DIRS_TO_REMOVE=(
    "${PI_HOME}/.moonraker_database_1"
    "${PI_HOME}/.moonraker_database_2"
    "${PI_HOME}/.moonraker_database_3"
    "${PI_HOME}/klipper_config"
    "${PI_HOME}/klipper_logs"
    "${PI_HOME}/moonraker-timelapse"
    "${PI_HOME}/.cache"
    "${PI_HOME}/.gnupg"
    "${PI_HOME}/.local"
    "${PI_HOME}/.config"
)

readonly FILES_TO_REMOVE=(
    "${PI_HOME}/savedVariables1.cfg"
    "${PI_HOME}/savedVariables2.cfg"
    "${PI_HOME}/savedVariables3.cfg"
)

for dir in "${DIRS_TO_REMOVE[@]}"; do
    if [ -d "$dir" ]; then
        print_status "Removing directory: $dir"
        sudo rm -rf "$dir"
        print_success "Removed: $dir"
    else
        print_warning "Not found (skipping): $dir"
    fi
done

for file in "${FILES_TO_REMOVE[@]}"; do
    if [ -f "$file" ]; then
        print_status "Removing file: $file"
        sudo rm -f "$file"
        print_success "Removed: $file"
    else
        print_warning "Not found (skipping): $file"
    fi
done

print_success "Flsun cleanup complete."
