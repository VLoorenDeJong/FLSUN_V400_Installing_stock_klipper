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

# Basic status helpers (same style as your Samba script)
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

# Paths we care about
KS_PATH="$ACTUAL_HOME/KlipperScreen"
KS_VENV="$ACTUAL_HOME/.KlipperScreen-env"
KS_REQ="$KS_PATH/scripts/KlipperScreen-requirements.txt"
KS_SYS="$KS_PATH/scripts/system-dependencies.json"

MOONRAKER_CONF="$ACTUAL_HOME/printer_data/config/moonraker.conf"
PRINTER_CFG="$ACTUAL_HOME/printer_data/config/printer.cfg"

print_status "Verifying KlipperScreen and Klipper configuration paths..."

# Verify KlipperScreen repo
if [ -d "$KS_PATH" ]; then
    print_success "KlipperScreen folder found: $KS_PATH"
else
    print_error "KlipperScreen folder missing: $KS_PATH"
    exit 1
fi

# Verify KlipperScreen venv
if [ -d "$KS_VENV" ]; then
    print_success "KlipperScreen virtualenv found: $KS_VENV"
else
    print_error "KlipperScreen virtualenv missing: $KS_VENV"
    exit 1
fi

# Verify requirements file
if [ -f "$KS_REQ" ]; then
    print_success "KlipperScreen requirements file found: $KS_REQ"
else
    print_error "KlipperScreen requirements file missing: $KS_REQ"
    exit 1
fi

# Verify system dependencies file
if [ -f "$KS_SYS" ]; then
    print_success "KlipperScreen system-dependencies.json found: $KS_SYS"
else
    print_error "KlipperScreen system-dependencies.json missing: $KS_SYS"
    exit 1
fi

# Verify Moonraker config
if [ -f "$MOONRAKER_CONF" ]; then
    print_success "Moonraker config found: $MOONRAKER_CONF"
else
    print_error "Moonraker config missing: $MOONRAKER_CONF"
    exit 1
fi

# Verify printer.cfg
if [ -f "$PRINTER_CFG" ]; then
    print_success "printer.cfg found: $PRINTER_CFG"
else
    print_error "printer.cfg missing: $PRINTER_CFG"
    exit 1
fi

# Detect MCU serial
print_status "Detecting MCU serial from /dev/serial/by-id..."
MCU_SERIAL=$(ls /dev/serial/by-id/* 2>/dev/null | head -n1 || true)

if [ -z "$MCU_SERIAL" ]; then
    print_error "No MCU serial detected in /dev/serial/by-id"
    exit 1
fi

print_success "Detected MCU serial: $MCU_SERIAL"

# Inject MCU serial into printer.cfg [mcu] section
print_status "Updating [mcu] serial in printer.cfg..."

if grep -q "^

\[mcu\]

" "$PRINTER_CFG"; then
    # Replace serial line inside [mcu] block
    sed -i "/^

\[mcu\]

/,/^

\[/ s|^serial:.*|serial: $MCU_SERIAL|" "$PRINTER_CFG"
    print_success "Updated [mcu] serial in printer.cfg"
else
    print_warning "[mcu] section not found in printer.cfg, appending one at the end"
    {
        echo ""
        echo "[mcu]"
        echo "serial: $MCU_SERIAL"
    } >> "$PRINTER_CFG"
    print_success "Appended [mcu] section with serial to printer.cfg"
fi

# Inject KlipperScreen update_manager block into Moonraker config
print_status "Ensuring KlipperScreen update_manager block in moonraker.conf..."

UPDATE_BLOCK="[update_manager KlipperScreen]
type: git_repo
path: $KS_PATH
origin: https://github.com/Guilouz/KlipperScreen-Flsun-Speeder-Pad.git
virtualenv: $KS_VENV
requirements: scripts/KlipperScreen-requirements.txt
system_dependencies: scripts/system-dependencies.json
managed_services: KlipperScreen
"

if grep -q "^

\[update_manager KlipperScreen\]

" "$MOONRAKER_CONF"; then
    print_warning "KlipperScreen update_manager block already present in moonraker.conf"
else
    print_status "Adding KlipperScreen update_manager block to moonraker.conf..."
    {
        echo ""
        echo "$UPDATE_BLOCK"
    } >> "$MOONRAKER_CONF"
    print_success "KlipperScreen update_manager block added to moonraker.conf"
fi

print_status "Final verification of Moonraker configuration..."

if command -v testparm >/dev/null 2>&1; then
    if sudo testparm -s "$MOONRAKER_CONF" >/dev/null 2>&1; then
        print_success "Moonraker configuration syntax validated successfully"
    else
        print_warning "Moonraker configuration validation reported issues (testparm)"
    fi
else
    print_warning "testparm not available, skipping Samba-style validation for Moonraker"
fi

print_success "KlipperScreen + MCU serial configuration completed."
echo
echo "➡ After Phase 2 reboot, Moonraker will automatically load:"
echo "   • Updated [mcu] serial in printer.cfg"
echo "   • KlipperScreen update_manager block in moonraker.conf"
echo
echo "You can then open Mainsail → Machine to confirm gauges and update manager."
