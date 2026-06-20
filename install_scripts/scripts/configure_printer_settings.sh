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

# Paths
KS_PATH="$ACTUAL_HOME/KlipperScreen"
KS_VENV="$ACTUAL_HOME/.KlipperScreen-env"
KS_REQ="$KS_PATH/scripts/KlipperScreen-requirements.txt"
KS_SYS="$KS_PATH/scripts/system-dependencies.json"

MOONRAKER_CONF="$ACTUAL_HOME/printer_data/config/moonraker.conf"
PRINTER_CFG="$ACTUAL_HOME/printer_data/config/printer.cfg"

print_status "Verifying KlipperScreen and Klipper configuration paths..."

[ -d "$KS_PATH" ] && print_success "KlipperScreen folder found: $KS_PATH" \
    || { print_error "KlipperScreen folder missing: $KS_PATH"; exit 1; }

[ -d "$KS_VENV" ] && print_success "KlipperScreen virtualenv found: $KS_VENV" \
    || { print_error "KlipperScreen virtualenv missing: $KS_VENV"; exit 1; }

[ -f "$KS_REQ" ] && print_success "KlipperScreen requirements file found: $KS_REQ" \
    || { print_error "KlipperScreen requirements file missing: $KS_REQ"; exit 1; }

[ -f "$KS_SYS" ] && print_success "KlipperScreen system-dependencies.json found: $KS_SYS" \
    || { print_error "KlipperScreen system-dependencies.json missing: $KS_SYS"; exit 1; }

[ -f "$MOONRAKER_CONF" ] && print_success "Moonraker config found: $MOONRAKER_CONF" \
    || { print_error "Moonraker config missing: $MOONRAKER_CONF"; exit 1; }

[ -f "$PRINTER_CFG" ] && print_success "printer.cfg found: $PRINTER_CFG" \
    || { print_error "printer.cfg missing: $PRINTER_CFG"; exit 1; }

# Detect MCU serial
print_status "Detecting MCU serial from /dev/serial/by-id..."
MCU_SERIAL=$(ls /dev/serial/by-id/* 2>/dev/null | head -n1 || true)

if [ -z "$MCU_SERIAL" ]; then
    print_error "No MCU serial detected in /dev/serial/by-id"
    exit 1
fi

print_success "Detected MCU serial: $MCU_SERIAL"

# ---------------------------------------------------------------------------
#  PURE UNIX MCU SERIAL INJECTION — NO REGEX, NO AWK, NO SED RANGES
# ---------------------------------------------------------------------------

print_status "Updating [mcu] serial in printer.cfg..."

TMP_FILE=$(mktemp)

in_mcu_block=false
serial_written=false
mcu_found=false

while IFS= read -r line; do
    # Detect start of [mcu]
    if [[ "$line" == "[mcu]" ]]; then
        mcu_found=true
        in_mcu_block=true
        echo "$line" >> "$TMP_FILE"
        continue
    fi

    # Detect next section header
    if [[ "$line" == [* ]]; then
        if $in_mcu_block && ! $serial_written; then
            echo "serial: $MCU_SERIAL" >> "$TMP_FILE"
            serial_written=true
        fi
        in_mcu_block=false
        echo "$line" >> "$TMP_FILE"
        continue
    fi

    # Inside [mcu] block
    if $in_mcu_block; then
        if [[ "$line" == serial:* ]]; then
            echo "serial: $MCU_SERIAL" >> "$TMP_FILE"
            serial_written=true
        else
            echo "$line" >> "$TMP_FILE"
        fi
        continue
    fi

    # Normal line
    echo "$line" >> "$TMP_FILE"

done < "$PRINTER_CFG"

# If [mcu] existed but serial was never written
if $mcu_found && ! $serial_written; then
    echo "serial: $MCU_SERIAL" >> "$TMP_FILE"
fi

# If [mcu] never existed, append at EOF
if ! $mcu_found; then
    print_warning "[mcu] section not found, appending at EOF..."
    {
        echo ""
        echo "[mcu]"
        echo "serial: $MCU_SERIAL"
    } >> "$TMP_FILE"
fi

mv "$TMP_FILE" "$PRINTER_CFG"
print_success "Updated [mcu] serial in printer.cfg"

# ---------------------------------------------------------------------------
#  UPDATE MANAGER BLOCK FOR KLIPPERSCREEN
# ---------------------------------------------------------------------------

print_status "Ensuring KlipperScreen update_manager block in moonraker.conf..."

UPDATE_BLOCK="[update_manager KlipperScreen]
type: git_repo
path: $KS_PATH
origin: https://github.com/Guilouz/KlipperScreen-Flsun-Speeder-Pad.git
virtualenv: $KS_VENV
requirements: scripts/KlipperScreen-requirements.txt
system_dependencies: scripts/system-dependencies.json
managed_services: KlipperScreen"

if grep -q "^

\[update_manager KlipperScreen\]

" "$MOONRAKER_CONF"; then
    print_warning "KlipperScreen update_manager block already present"
else
    print_status "Adding KlipperScreen update_manager block..."
    {
        echo ""
        echo "$UPDATE_BLOCK"
    } >> "$MOONRAKER_CONF"
    print_success "Added KlipperScreen update_manager block"
fi

# ---------------------------------------------------------------------------
#  EXCLUDE OBJECT SUPPORT — Moonraker + printer.cfg
# ---------------------------------------------------------------------------

print_status "Ensuring [file_manager] section exists in moonraker.conf..."

if grep -q "^

\[file_manager\]

" "$MOONRAKER_CONF"; then
    print_success "[file_manager] section already present"
else
    print_status "Adding [file_manager] section at EOF..."
    {
        echo ""
        echo "[file_manager]"
        echo "enable_object_processing: True"
    } >> "$MOONRAKER_CONF"
    print_success "Added [file_manager] section"
fi

print_status "Ensuring [exclude_object] section exists in printer.cfg..."

if grep -q "^

\[exclude_object\]

" "$PRINTER_CFG"; then
    print_success "[exclude_object] section already present"
else
    print_status "Adding [exclude_object] section at EOF..."
    {
        echo ""
        echo "[exclude_object]"
    } >> "$PRINTER_CFG"
    print_success "Added [exclude_object] section"
fi

print_success "KlipperScreen + MCU serial + Exclude Object configuration completed."
echo
echo "➡ After Phase 2 reboot, Moonraker will automatically load:"
echo "   • Updated [mcu] serial"
echo "   • KlipperScreen update manager"
echo "   • Exclude Object Support (file_manager + exclude_object)"
echo
