#!/usr/bin/env bash
set -e

# =============================================================================
# Create USB-Disk symlink in printer_data/gcodes (step 100)
# =============================================================================
# ln -s ~/gcode_files/USB-Disk ~/printer_data/gcodes/USB-Disk
# =============================================================================

print_status()  { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning() { printf "\033[33m⚠️  %s\033[0m\n" "$1"; }
print_error()   { printf "\033[31m❌ %s\033[0m\n" "$1"; }
print_header()  { printf "\n\033[36m=== %s ===\033[0m\n" "$1"; }

if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must run with sudo/root privileges."
    exit 1
fi

TARGET_USER="${SUDO_USER:-}"
if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
    id pi >/dev/null 2>&1 && TARGET_USER="pi" || TARGET_USER="$(whoami)"
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

SYMLINK_TARGET="${TARGET_HOME}/gcode_files/USB-Disk"
SYMLINK_LINK="${TARGET_HOME}/printer_data/gcodes/USB-Disk"

print_header "Create USB-Disk Symlink (step 100)"

# Ensure gcodes directory exists
GCODES_DIR="${TARGET_HOME}/printer_data/gcodes"
if [ ! -d "$GCODES_DIR" ]; then
    print_warning "gcodes directory not found: $GCODES_DIR"
    print_warning "Klipper/Mainsail must be installed first. Skipping."
    exit 0
fi

# Check if symlink already exists
if [ -L "$SYMLINK_LINK" ]; then
    existing_target=$(readlink "$SYMLINK_LINK")
    if [ "$existing_target" = "$SYMLINK_TARGET" ]; then
        print_warning "USB-Disk symlink already exists and is correct — skipping."
        exit 0
    else
        print_warning "USB-Disk symlink exists but points to: $existing_target"
        print_status "Updating symlink to: $SYMLINK_TARGET"
        rm -f "$SYMLINK_LINK"
    fi
elif [ -e "$SYMLINK_LINK" ]; then
    print_warning "$SYMLINK_LINK exists as a real file/dir — not replacing."
    exit 0
fi

# Create the symlink
sudo -u "$TARGET_USER" ln -s "$SYMLINK_TARGET" "$SYMLINK_LINK"
print_success "Created symlink: $SYMLINK_LINK → $SYMLINK_TARGET"
print_warning "Note: $SYMLINK_TARGET will only exist when a USB drive is mounted."
