#!/usr/bin/env bash
set -e

# ============================================
# Fix Moonraker Shutdown Button (steps 181-190)
# ============================================

# Status message functions
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

print_status "Fix Moonraker Shutdown Button (steps 181-190)"

# Detect actual user (same logic used in Samba installer)
if [ -n "$SUDO_USER" ]; then
    ACTUAL_USER="$SUDO_USER"
else
    ACTUAL_USER=$(whoami)
fi

ACTUAL_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)

MOONRAKER_DIR="$ACTUAL_HOME/moonraker"
POLICYKIT_SCRIPT="$MOONRAKER_DIR/scripts/set-policykit-rules.sh"
MOONRAKER_CONF="$ACTUAL_HOME/printer_data/config/moonraker.conf"

# Validate script existence
if [ ! -f "$POLICYKIT_SCRIPT" ]; then
    print_error "PolicyKit script not found: $POLICYKIT_SCRIPT"
    exit 1
fi

print_status "Running set-policykit-rules.sh..."

# Adaptive execution logic
if [ "$(id -u)" -eq 0 ]; then
    # Installer is running as root → switch to actual user
    print_warning "Installer running as root — switching to $ACTUAL_USER for PolicyKit setup..."
    sudo -u "$ACTUAL_USER" bash "$POLICYKIT_SCRIPT" >/dev/null 2>&1
else
    # Already running as correct user
    print_status "Running PolicyKit script as $ACTUAL_USER..."
    bash "$POLICYKIT_SCRIPT" >/dev/null 2>&1
fi

# Check result
if [ $? -ne 0 ]; then
    print_error "PolicyKit setup failed — Moonraker shutdown button may not work"
    exit 1
fi

print_success "PolicyKit rules applied successfully"

# Validate Moonraker config exists
if [ ! -f "$MOONRAKER_CONF" ]; then
    print_warning "Moonraker config not found: $MOONRAKER_CONF"
    print_warning "Shutdown button may still be unavailable"
    exit 0
fi

print_status "Verifying Moonraker configuration..."

# Check if shutdown service is enabled
if grep -q "system_power" "$MOONRAKER_CONF"; then
    print_success "Moonraker shutdown service already configured"
else
    print_warning "Moonraker shutdown service not found in config"
    print_warning "Add the following to moonraker.conf:"
    echo ""
    echo "  [system_power]"
    echo "  shutdown = sudo systemctl poweroff"
    echo ""
fi

print_success "Moonraker shutdown fix completed successfully!"
exit 0
