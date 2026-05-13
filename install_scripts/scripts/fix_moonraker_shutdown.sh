#!/usr/bin/env bash
set -e

# =============================================================================
# Fix Moonraker shutdown button + append machine config (steps 181-190)
# =============================================================================
# 1. Runs moonraker's set-policykit-rules.sh so the shutdown button works
# 2. Appends [machine] shutdown_action: halt to moonraker.conf
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

MOONRAKER_DIR="${TARGET_HOME}/moonraker"
POLICYKIT_SCRIPT="${MOONRAKER_DIR}/scripts/set-policykit-rules.sh"
MOONRAKER_CONF="${TARGET_HOME}/printer_data/config/moonraker.conf"

print_header "Fix Moonraker Shutdown Button (steps 181-190)"

# --- Step 1: run policykit rules script (step 181-182) ---
if [ ! -f "$POLICYKIT_SCRIPT" ]; then
    print_warning "Moonraker policykit script not found: $POLICYKIT_SCRIPT"
    print_warning "Moonraker must be installed first. Skipping policykit step."
else
    print_status "Running set-policykit-rules.sh..."
    bash "$POLICYKIT_SCRIPT"
    print_success "Policykit rules applied — shutdown button should now work in Mainsail"
fi

# --- Step 2: append [machine] section to moonraker.conf (steps 187-190) ---
if [ ! -f "$MOONRAKER_CONF" ]; then
    print_warning "moonraker.conf not found at $MOONRAKER_CONF"
    print_warning "Add the [machine] section manually after Moonraker is configured."
    exit 0
fi

if grep -q "^\[machine\]" "$MOONRAKER_CONF"; then
    if grep -q "shutdown_action" "$MOONRAKER_CONF"; then
        print_warning "[machine] section with shutdown_action already present — skipping."
    else
        print_warning "[machine] section exists but shutdown_action is missing."
        print_warning "Add 'shutdown_action: halt' under [machine] in moonraker.conf manually."
    fi
else
    print_status "Appending [machine] shutdown config to moonraker.conf..."
    cat >> "$MOONRAKER_CONF" << 'EOF'

[machine]
shutdown_action: halt
EOF
    chown "$TARGET_USER":"$TARGET_USER" "$MOONRAKER_CONF"
    print_success "moonraker.conf updated with [machine] shutdown_action: halt"
fi

print_success "Moonraker shutdown fix complete."
print_warning "A reboot or Moonraker service restart is required for changes to take effect."
