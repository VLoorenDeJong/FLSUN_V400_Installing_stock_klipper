#!/usr/bin/env bash
set -e

export DEBIAN_FRONTEND=noninteractive

# =============================================================================
# Install Python 3.9 + venv + distutils
# Manual step 083.2-083.4: required before KIAUH creates the Klipper venv.
# Raspbian Bullseye ships Python 3.9 but venv/distutils are separate packages
# that KIAUH needs to create the klippy-env virtualenv.
# =============================================================================

print_status()  { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning() { printf "\033[33m⚠️  %s\033[0m\n" "$1"; }
print_error()   { printf "\033[31m❌ %s\033[0m\n" "$1"; }
print_header()  { printf "\n\033[36m=== %s ===\033[0m\n" "$1"; }

STATE_DIR="/var/lib/linuxsetups"
STATE_FILE="${STATE_DIR}/install_python39.done"
FORCE_RUN="${FORCE_RUN_PYTHON39:-0}"

if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must run with sudo/root privileges."
    exit 1
fi

if [ -f "$STATE_FILE" ] && [ "$FORCE_RUN" != "1" ]; then
    print_warning "Python 3.9 packages already installed. Skipping."
    print_warning "To force rerun: FORCE_RUN_PYTHON39=1 sudo bash $0"
    exit 0
fi

print_header "Install Python 3.9 + venv + distutils"

print_status "Installing python3.9 python3.9-venv python3.9-distutils..."
apt-get install -y python3.9 python3.9-venv python3.9-distutils

INSTALLED_VER=$(python3.9 --version 2>&1 || true)
print_success "Installed: $INSTALLED_VER"

mkdir -p "$STATE_DIR"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$STATE_FILE"

print_success "Python 3.9 packages ready."
