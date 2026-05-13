#!/bin/bash
set -e

# Launch KIAUH interactively.
# Optional argument: SESSION=1 or SESSION=2
#   1 = remove old Flsun packages
#   2 = install Klipper / Moonraker / Mainsail
SESSION="${1:-}"

TARGET_USER="${SUDO_USER:-}"
if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
    if id pi >/dev/null 2>&1; then
        TARGET_USER="pi"
    else
        TARGET_USER="$(whoami)"
    fi
fi

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
if [ -z "$TARGET_HOME" ]; then
    echo -e "\e[31m❌ Could not determine home directory for user: $TARGET_USER\e[0m"
    exit 1
fi

KIAUH_SCRIPT="${TARGET_HOME}/kiauh/kiauh.sh"

if [ ! -f "$KIAUH_SCRIPT" ]; then
    echo -e "\e[31m❌ KIAUH script not found: $KIAUH_SCRIPT\e[0m"
    echo -e "\e[33m💡 Run add_kiauh.sh first to clone KIAUH.\e[0m"
    exit 1
fi

chmod +x "$KIAUH_SCRIPT"

if pgrep -f "kiauh/kiauh\.sh" >/dev/null 2>&1; then
    echo -e "\e[33m⚠️ A stale KIAUH process was detected. Killing it before relaunching...\e[0m"
    pkill -f "kiauh/kiauh\.sh" || true
    sleep 1
fi

echo -e "\e[34m🚀 Starting KIAUH as user: $TARGET_USER\e[0m"

case "$SESSION" in
    1)
        echo -e ""
        echo -e "\e[36m╔══════════════════════════════════════════════════════════════╗\e[0m"
        echo -e "\e[36m║  KIAUH Session 1 — Remove old Flsun packages                 ║\e[0m"
        echo -e "\e[36m╠══════════════════════════════════════════════════════════════╣\e[0m"
        echo -e "\e[36m║  In KIAUH:                                                   ║\e[0m"
        echo -e "\e[36m║    4) Remove                                                 ║\e[0m"
        echo -e "\e[36m║       Remove: Klipper, Moonraker, Mainsail, KlipperScreen    ║\e[0m"
        echo -e "\e[36m║    q) Quit when done — script will continue automatically   ║\e[0m"
        echo -e "\e[36m╚══════════════════════════════════════════════════════════════╝\e[0m"
        echo -e ""
        ;;
    2)
        echo -e ""
        echo -e "\e[36m╔══════════════════════════════════════════════════════════════╗\e[0m"
        echo -e "\e[36m║  KIAUH Session 2 — Install fresh Klipper stack              ║\e[0m"
        echo -e "\e[36m╠══════════════════════════════════════════════════════════════╣\e[0m"
        echo -e "\e[36m║  In KIAUH, go to: 1) Install, then install in order:        ║\e[0m"
        echo -e "\e[36m║    1) Klipper      → choose Python 3.x, 1 instance          ║\e[0m"
        echo -e "\e[36m║    2) Moonraker                                              ║\e[0m"
        echo -e "\e[36m║    3) Mainsail     → answer n to recommended macros         ║\e[0m"
        echo -e "\e[36m║    b) Back, then q) Quit — script will continue             ║\e[0m"
        echo -e "\e[36m╚══════════════════════════════════════════════════════════════╝\e[0m"
        echo -e ""
        ;;
esac

if [ "$(id -u)" -eq 0 ] && [ "$TARGET_USER" != "root" ]; then
    exec sudo -u "$TARGET_USER" bash "$KIAUH_SCRIPT"
else
    exec bash "$KIAUH_SCRIPT"
fi
