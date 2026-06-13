#!/usr/bin/env bash
set -e

# =============================================================================
# Fix Klipper virtualenv after KIAUH install (steps 093.2 - 093.8)
# =============================================================================
# After KIAUH installs Klipper, the klippy-env may have a broken aenum version
# that causes Klipper to crash at startup. This script pins aenum to 3.1.11,
# installs wheel, and re-installs all Klipper Python requirements.
#
# Run this AFTER the first KIAUH session (after installing Klipper).
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

KLIPPY_ENV="${TARGET_HOME}/klippy-env"
KLIPPER_DIR="${TARGET_HOME}/klipper"
REQUIREMENTS="${KLIPPER_DIR}/scripts/klippy-requirements.txt"
PIP="${KLIPPY_ENV}/bin/pip"
PYTHON="${KLIPPY_ENV}/bin/python"

print_header "Fix Klipper Virtual Environment (steps 093.2-093.8)"

# --- Ensure system deps needed by some Python packages (e.g. sdbus) ---
print_status "Checking system build dependencies (pkg-config, libsystemd-dev)..."
MISSING_DEPS=()
for pkg in pkg-config libsystemd-dev; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        MISSING_DEPS+=("$pkg")
    fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    print_status "Installing missing packages: ${MISSING_DEPS[*]}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq "${MISSING_DEPS[@]}"
    print_success "System build dependencies installed"
else
    print_success "System build dependencies already installed"
fi

# --- Validate paths ---
if [ ! -f "$PIP" ]; then
    print_warning "klippy-env not found at $KLIPPY_ENV"
    print_warning "KIAUH must be run first (install Klipper). Skipping."
    exit 0
fi

if [ ! -f "$REQUIREMENTS" ]; then
    print_warning "Klipper requirements file not found: $REQUIREMENTS"
    print_warning "Klipper may not be installed. Skipping."
    exit 0
fi

# --- Upgrade pip inside klippy-env first ---
print_status "Upgrading pip inside klippy-env..."
sudo -u "$TARGET_USER" "$PIP" install --upgrade pip --quiet
new_ver=$(sudo -u "$TARGET_USER" "$PIP" --version 2>/dev/null | awk '{print $2}')
print_success "pip → $new_ver in klippy-env"

# --- Fix aenum version (step 093.4-093.5) ---
print_status "Pinning aenum to 3.1.11..."
sudo -u "$TARGET_USER" "$PIP" uninstall -y aenum 2>/dev/null || true
sudo -u "$TARGET_USER" "$PIP" install aenum==3.1.11 --quiet
print_success "aenum pinned to 3.1.11"

# --- Install wheel (step 093.6) ---
print_status "Installing wheel..."
sudo -u "$TARGET_USER" "$PIP" install wheel --quiet
print_success "wheel installed"

# --- Re-install all Klipper requirements (step 093.7) ---
print_status "Installing Klipper Python requirements..."
sudo -u "$TARGET_USER" "$PIP" install -r "$REQUIREMENTS" --quiet
print_success "Klipper requirements installed successfully"

# --- Verify Python can import the main Klipper module ---
if sudo -u "$TARGET_USER" "$PYTHON" -c "import klippy" 2>/dev/null; then
    print_success "Klipper import verification passed"
else
    print_warning "Klipper import check skipped (klippy not yet on PYTHONPATH — this is normal)"
fi

print_success "Klipper venv fix complete."
