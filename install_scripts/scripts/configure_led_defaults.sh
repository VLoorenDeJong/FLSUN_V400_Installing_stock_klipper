#!/usr/bin/env bash
set -e

# =============================================================================
# Questionnaire: LED boot defaults in printer.cfg
# =============================================================================
# The V400 config defines two lights as output pins:
#   [output_pin LED_Hotend]  value: 0|1   (hotend light at boot)
#   [output_pin LED_Logo]    value: 0|1   (logo LED at boot)
# This script asks on/off for each and updates the 'value:' line.
# Safe to rerun any time. Makes a timestamped backup first.
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

# Resolve actual user home (works under sudo)
TARGET_USER="${SUDO_USER:-}"
if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
    id pi >/dev/null 2>&1 && TARGET_USER="pi" || TARGET_USER="$(whoami)"
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
PRINTER_CFG="${TARGET_HOME}/printer_data/config/printer.cfg"

print_header "LED Boot Defaults (printer.cfg)"

if [ ! -f "$PRINTER_CFG" ]; then
    print_error "printer.cfg not found: $PRINTER_CFG"
    print_warning "Run this after the printer configs are restored (end of Phase 2)."
    exit 1
fi

# Read the current 'value:' inside one [output_pin <name>] section.
get_value() {
    local name="$1"
    awk -v sec="[output_pin ${name}]" '
        $0 == sec { insec = 1; next }
        insec && /^\[/ { insec = 0 }
        insec && /^value:/ { gsub(/[^01]/, ""); print; exit }
    ' "$PRINTER_CFG"
}

# Set the 'value:' inside one [output_pin <name>] section.
set_value() {
    local name="$1" newval="$2"
    sed -i "/^\[output_pin ${name}\]/,/^\[/ s/^value:.*/value: ${newval}/" "$PRINTER_CFG"
}

# Ask on/off for one LED. Prompts on /dev/tty.
ask_led() {
    local label="$1" current="$2" suggested="$3" default_prompt="$4" ans state
    state="unknown"
    [ "$current" = "1" ] && state="ON"
    [ "$current" = "0" ] && state="OFF"

    printf "\n%s is currently %s at boot. Suggested: %s.\n" "$label" "$state" "$suggested"
    printf "Turn %s ON at boot? [%s]: " "$label" "$default_prompt"
    read -r ans </dev/tty

    case "$ans" in
        y|Y) ANSWER=1 ;;
        n|N) ANSWER=0 ;;
        *)   ANSWER="" ;;
    esac
}

CHANGED=0
BACKUP="${PRINTER_CFG}.bak-$(date +%Y%m%d-%H%M%S)"

for led in LED_Hotend LED_Logo; do
    case "$led" in
        LED_Hotend)
            label="Hotend light"
            suggested="ON"
            default_prompt="y/n/Enter=skip"
            ;;
        LED_Logo)
            label="Logo LED"
            suggested="OFF"
            default_prompt="y/n/Enter=skip"
            ;;
    esac

    current="$(get_value "$led")"
    if [ -z "$current" ]; then
        print_warning "[output_pin ${led}] not found in printer.cfg — skipping ${label}."
        continue
    fi

    ask_led "$label" "$current" "$suggested" "$default_prompt"

    if [ -n "$ANSWER" ] && [ "$ANSWER" != "$current" ]; then
        if [ "$CHANGED" -eq 0 ]; then
            cp -p "$PRINTER_CFG" "$BACKUP"
            print_status "Backup saved: $BACKUP"
        fi
        set_value "$led" "$ANSWER"
        CHANGED=1
        print_success "${label}: boot default set to $([ "$ANSWER" = "1" ] && echo ON || echo OFF)"
    else
        print_status "${label}: unchanged."
    fi
done

if [ "$CHANGED" -eq 0 ]; then
    print_success "No changes made."
    exit 0
fi

# sed -i can reset ownership when run as root — give it back to the user.
chown "$TARGET_USER":"$TARGET_USER" "$PRINTER_CFG"

printf "\nKlipper must restart to apply the new defaults.\n"
printf "Restart Klipper now? [y/N]: "
read -r restart_ans </dev/tty
if [ "$restart_ans" = "y" ] || [ "$restart_ans" = "Y" ]; then
    systemctl restart klipper
    print_success "Klipper restarted — new LED defaults active."
else
    print_warning "Not restarted. Apply later with: sudo systemctl restart klipper"
fi
