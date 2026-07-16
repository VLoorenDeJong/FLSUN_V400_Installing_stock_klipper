#!/usr/bin/env bash
set -e

export DEBIAN_FRONTEND=noninteractive

# Detect actual user and home (sudo‑safe)
if [ -n "$SUDO_USER" ]; then
    ACTUAL_USER="$SUDO_USER"
    ACTUAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    ACTUAL_USER=$(whoami)
    ACTUAL_HOME="$HOME"
fi

# Basic status helpers
print_status() {
    printf "\033[34m🔧 %s\033[0m\n" "$1"
}

print_success() {
    printf "\033[32m✅ %s\033[0m\n" "$1"
}

print_warning() {
    printf "\033[33m⚠️ %s\033[0m\n" "$1"
}

print_error() {
    printf "\033[31m❌ %s\033[0m\n" "$1"
}

print_status "Preparing Mainsail theme installation..."

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Repo root is TWO levels up:
# install_scripts/scripts  →  install_scripts  →  repo root
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Theme source folder inside repo
THEME_SOURCE="$REPO_ROOT/backup_config/KlipperThemeFiles"

# Destination folder in Mainsail config
THEME_DIR="$ACTUAL_HOME/printer_data/config/.theme"

# ---------------------------------------------------------------------------
#  CREATE .theme FOLDER
# ---------------------------------------------------------------------------

print_status "Checking for .theme folder..."

if [ -d "$THEME_DIR" ]; then
    print_success ".theme folder already exists: $THEME_DIR"
else
    print_status "Creating .theme folder..."
    mkdir -p "$THEME_DIR"
    print_success "Created .theme folder: $THEME_DIR"
fi

# ---------------------------------------------------------------------------
#  COPY THEME FILES
# ---------------------------------------------------------------------------

print_status "Locating theme source files..."

if [ ! -d "$THEME_SOURCE" ]; then
    print_error "Theme source folder not found: $THEME_SOURCE"
    print_warning "Expected path: FLSUN_V400_Installing_stock_klipper/backup_config/KlipperThemeFiles"
    exit 1
fi

print_status "Copying theme files into .theme folder..."
cp -r "$THEME_SOURCE/"* "$THEME_DIR/" 2>/dev/null || true
print_success "Theme files copied to: $THEME_DIR"

# This script runs as root, so folder + files land root-owned. Moonraker
# runs as the real user — root-owned files are read-only in the web UI.
chown -R "$ACTUAL_USER":"$ACTUAL_USER" "$THEME_DIR"
print_success "Ownership set to $ACTUAL_USER — editable from Mainsail."

echo
print_success "Theme installation completed."
echo "➡ You can now select your theme in Mainsail."
echo
