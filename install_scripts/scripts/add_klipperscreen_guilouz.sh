#!/usr/bin/env bash
set -e

# =============================================================================
# Install Guilouz KlipperScreen fork for FLSUN Speeder Pad (steps 094-099)
# =============================================================================
# Installs the custom KlipperScreen fork from:
#   https://github.com/Guilouz/KlipperScreen-Flsun-Speeder-Pad
# and appends the update_manager section to moonraker.conf.
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

REPO_URL="https://github.com/Guilouz/KlipperScreen-Flsun-Speeder-Pad.git"
KLIPPERSCREEN_DIR="${TARGET_HOME}/KlipperScreen"
MOONRAKER_CONF="${TARGET_HOME}/printer_data/config/moonraker.conf"
INSTALL_SCRIPT="${KLIPPERSCREEN_DIR}/scripts/KlipperScreen-install.sh"
STATE_DIR="/var/lib/linuxsetups"
STATE_FILE="${STATE_DIR}/klipperscreen_guilouz.done"
FORCE_RUN="${FORCE_RUN_KLIPPERSCREEN:-0}"

if [ -f "$STATE_FILE" ] && [ "$FORCE_RUN" != "1" ]; then
    print_warning "Guilouz KlipperScreen already installed. Skipping."
    print_warning "To force rerun: sudo env FORCE_RUN_KLIPPERSCREEN=1 bash $0"
    exit 0
fi

print_header "Install Guilouz KlipperScreen Fork (steps 094-099)"

# --- Clone or update the repo (step 095) ---
if [ -d "${KLIPPERSCREEN_DIR}/.git" ]; then
    print_status "Existing KlipperScreen clone found, updating..."
    sudo -u "$TARGET_USER" git -C "$KLIPPERSCREEN_DIR" pull --ff-only || \
        print_warning "Git pull failed — using existing clone"
else
    print_status "Cloning KlipperScreen from Guilouz fork..."
    sudo -u "$TARGET_USER" git clone "$REPO_URL" "$KLIPPERSCREEN_DIR"
    print_success "Cloned to $KLIPPERSCREEN_DIR"
fi

chown -R "$TARGET_USER":"$TARGET_USER" "$KLIPPERSCREEN_DIR"

# --- Run the installer (steps 096-099) ---
if [ ! -f "$INSTALL_SCRIPT" ]; then
    print_error "Install script not found: $INSTALL_SCRIPT"
    exit 1
fi

chmod +x "$INSTALL_SCRIPT"
print_status "Running KlipperScreen installer (non-interactive)..."

# Run as TARGET_USER with preset answers:
#   - standalone / default display server (X)
#   - do NOT install NetworkManager (already done)
sudo -u "$TARGET_USER" bash "$INSTALL_SCRIPT"

# --- Append update_manager section to moonraker.conf (steps 105-112) ---
if [ -f "$MOONRAKER_CONF" ]; then
    if grep -q "KlipperScreen-Flsun-Speeder-Pad" "$MOONRAKER_CONF"; then
        print_warning "moonraker.conf already contains KlipperScreen update_manager entry — skipping."
    else
        print_status "Adding KlipperScreen update_manager to moonraker.conf..."
        cat >> "$MOONRAKER_CONF" << 'EOF'

[update_manager KlipperScreen]
type: git_repo
path: ~/KlipperScreen
origin: https://github.com/Guilouz/KlipperScreen-Flsun-Speeder-Pad.git
virtualenv: ~/.KlipperScreen-env
requirements: scripts/KlipperScreen-requirements.txt
system_dependencies: scripts/system-dependencies.json
managed_services: KlipperScreen
EOF
        chown "$TARGET_USER":"$TARGET_USER" "$MOONRAKER_CONF"
        print_success "moonraker.conf updated with KlipperScreen update_manager"
    fi
else
    print_warning "moonraker.conf not found at $MOONRAKER_CONF"
    print_warning "Add the update_manager section manually after Moonraker is configured."
fi

mkdir -p "$STATE_DIR"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$STATE_FILE"
print_success "Guilouz KlipperScreen installation complete."
