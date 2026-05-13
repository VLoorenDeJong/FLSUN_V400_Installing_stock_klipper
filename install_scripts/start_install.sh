#!/bin/bash

# =============================================================================
# FLSUN V400 Speeder Pad — Installation Menu
# =============================================================================

debugMode=0

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--debug) debugMode=1; shift ;;
        -h|--help)
            echo "Usage: sudo $0 [OPTIONS]"
            echo "  -d, --debug   Enable bash -x debug output"
            echo "  -h, --help    Show this help"
            exit 0
            ;;
        *) echo "Unknown option: $1 (use -h for help)"; exit 1 ;;
    esac
done

# Must run as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "\e[31m❌ Run with sudo: sudo $0\e[0m"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$SCRIPT_DIR/scripts"

# =============================================================================
# PHASE DEFINITIONS
# =============================================================================

# Phase 1 — OS preparation (ends with reboot)
PHASE1_SCRIPTS=(
    "cleanup_repositories.sh"
    "fix_xauthority.sh"
    "set_scripts_executable.sh"
    "update_user_password.sh"
    "updates_install_and_clean.sh"
    "update_kernel.sh"
    "upgrade_distro.sh"
    "configure_locale_and_wifi_country.sh"
    "add_ufw.sh"
    "add_ssh.sh"
    "add_bash_show_branch_name.sh"
    "set_scripts_executable.sh"
    "reboot.sh"
)

# Phase 2 — Klipper stack (required steps, run in order)
PHASE2_SCRIPTS=(
    "cleanup_repositories.sh"
    "add_network_manager.sh"
    "add_flsun_speeder_pad_installer.sh"
    "add_flsun_sp_installer2.sh"
    "add_kiauh.sh"
    "start_kiauh.sh"
    "cleanup_flsun_builds.sh"
    "start_kiauh.sh"
)

# Optional extras (shown as checklist in Phase 2 and standalone menu)
declare -A OPTIONAL_LABELS=(
    ["add_webmin.sh"]="Webmin  (web-based admin panel)"
    ["add_apache_webserver.sh"]="Apache  (web server)"
    ["add_smb.sh"]="Samba   (SMB/Windows file sharing)"
)
OPTIONAL_ORDER=("add_webmin.sh" "add_apache_webserver.sh" "add_smb.sh")

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

run_lock_fix() {
    local fix_script="$INSTALL_DIR/fix_dpkg_lock.sh"
    if [[ -f "$fix_script" ]]; then
        echo -e "\e[34m🔧 Checking and fixing DPKG locks...\e[0m"
        bash "$fix_script" && echo -e "\e[32m✅ DPKG locks resolved\e[0m" || \
            echo -e "\e[33m⚠️  DPKG lock fix failed, continuing anyway...\e[0m"
    fi
}

run_script() {
    local script_name="$1"
    local script_path="$INSTALL_DIR/$script_name"

    if [[ ! -f "$script_path" ]]; then
        echo -e "\e[31m❌ Script not found: $script_name\e[0m"
        return 1
    fi

    # Run dpkg lock fix before every apt-touching script
    case "$script_name" in
        updates_install_and_clean.sh|update_kernel.sh|upgrade_distro.sh|\
        add_network_manager.sh|add_flsun_speeder_pad_installer.sh|\
        add_flsun_sp_installer2.sh|add_kiauh.sh|add_webmin.sh|\
        add_apache_webserver.sh|add_smb.sh)
            run_lock_fix ;;
    esac

    echo -e "\e[34m🚀 Running: $script_name\e[0m"
    local run_cmd="bash"
    [[ "$debugMode" -eq 1 ]] && run_cmd="bash -x"

    # Redirect stdin from /dev/tty so child scripts read from the terminal
    # directly and cannot exhaust the parent script's stdin.
    local tty_src="/dev/tty"
    [[ ! -r /dev/tty ]] && tty_src="/dev/stdin"

    if $run_cmd "$script_path" <"$tty_src"; then
        echo -e "\e[32m✅ Finished: $script_name\e[0m"
        echo ""
        return 0
    else
        local code=$?
        echo -e "\e[31m❌ Failed: $script_name (exit code: $code)\e[0m"
        echo -e "\e[33m💡 To debug: sudo bash -x '$script_path'\e[0m"
        echo ""
        return 1
    fi
}

run_sequence() {
    local scripts=("$@")
    local all_ok=true

    for script in "${scripts[@]}"; do
        # Skip reboot if previous steps failed
        if [[ "$script" == "reboot.sh" && "$all_ok" == "false" ]]; then
            echo -e "\e[33m⏭️  Skipping reboot — previous steps failed\e[0m"
            continue
        fi
        run_script "$script" || all_ok=false
    done

    if $all_ok; then
        echo -e "\e[32m🎉 All steps completed successfully!\e[0m"
    else
        echo -e "\e[33m⚠️  Completed with failures. Check output above.\e[0m"
    fi
}

# Show a numbered checklist and return selected script names in SELECTED array
optional_checklist() {
    declare -g -a SELECTED=()
    local toggles=()
    for s in "${OPTIONAL_ORDER[@]}"; do toggles+=("off"); done

    while true; do
        echo ""
        echo -e "\e[36m--- Optional Extras (toggle with number, Enter to confirm) ---\e[0m"
        for i in "${!OPTIONAL_ORDER[@]}"; do
            local s="${OPTIONAL_ORDER[$i]}"
            local mark="[ ]"
            [[ "${toggles[$i]}" == "on" ]] && mark="[x]"
            printf "  %d) %s  %s\n" "$((i+1))" "$mark" "${OPTIONAL_LABELS[$s]}"
        done
        echo "  a) Select all"
        echo "  n) Select none"
        echo "  Enter) Confirm and continue"
        echo ""
        read -rp "Choice: " opt
        case "$opt" in
            a) for i in "${!toggles[@]}"; do toggles[$i]="on"; done ;;
            n) for i in "${!toggles[@]}"; do toggles[$i]="off"; done ;;
            "") break ;;
            [0-9]*)
                local idx=$((opt-1))
                if [[ $idx -ge 0 && $idx -lt ${#OPTIONAL_ORDER[@]} ]]; then
                    [[ "${toggles[$idx]}" == "on" ]] && toggles[$idx]="off" || toggles[$idx]="on"
                else
                    echo -e "\e[33m⚠️  Invalid number\e[0m"
                fi ;;
            *) echo -e "\e[33m⚠️  Invalid input\e[0m" ;;
        esac
    done

    for i in "${!OPTIONAL_ORDER[@]}"; do
        [[ "${toggles[$i]}" == "on" ]] && SELECTED+=("${OPTIONAL_ORDER[$i]}")
    done
}

# Individual scripts submenu
menu_individual() {
    local all_scripts=()
    while IFS= read -r -d '' f; do
        all_scripts+=("$(basename "$f")")
    done < <(find "$INSTALL_DIR" -maxdepth 1 -name "*.sh" -print0 | sort -z)

    while true; do
        echo ""
        echo -e "\e[36m=== Run Individual Script ===\e[0m"
        for i in "${!all_scripts[@]}"; do
            printf "  %2d) %s\n" "$((i+1))" "${all_scripts[$i]}"
        done
        echo "   b) Back"
        echo ""
        read -rp "Choice: " opt
        [[ "$opt" == "b" ]] && break
        if [[ "$opt" =~ ^[0-9]+$ ]]; then
            local idx=$((opt-1))
            if [[ $idx -ge 0 && $idx -lt ${#all_scripts[@]} ]]; then
                run_script "${all_scripts[$idx]}"
                read -rp "Press Enter to continue..." _
            else
                echo -e "\e[33m⚠️  Invalid number\e[0m"
            fi
        else
            echo -e "\e[33m⚠️  Invalid input\e[0m"
        fi
    done
}

# =============================================================================
# MAIN MENU
# =============================================================================

while true; do
    echo ""
    echo -e "\e[36m╔══════════════════════════════════════════════════╗\e[0m"
    echo -e "\e[36m║   FLSUN V400 Speeder Pad — Installation Menu     ║\e[0m"
    echo -e "\e[36m╚══════════════════════════════════════════════════╝\e[0m"
    echo ""
    echo -e "  \e[33m1)\e[0m Phase 1 — OS prep + distro upgrade  \e[90m(ends with reboot)\e[0m"
    echo -e "  \e[33m2)\e[0m Phase 2 — Klipper/Mainsail/Moonraker/KlipperScreen + optional extras"
    echo -e "  \e[33m3)\e[0m Optional extras only  \e[90m(Webmin, Apache, Samba)\e[0m"
    echo -e "  \e[33m4)\e[0m Run individual script"
    echo -e "  \e[33m5)\e[0m Run Phase 1 + Phase 2  \e[90m(full install — Phase 2 runs after reboot)\e[0m"
    if [[ "$debugMode" -eq 1 ]]; then
        echo -e "  \e[33md)\e[0m Debug mode  \e[32m[ON]\e[0m"
    else
        echo -e "  \e[33md)\e[0m Debug mode  \e[90m[off]\e[0m"
    fi
    echo -e "  \e[33mq)\e[0m Quit"
    echo ""
    read -rp "Choice: " MAIN_CHOICE || { echo -e "\n\e[32m👋 Goodbye!\e[0m"; exit 0; }

    case "$MAIN_CHOICE" in
        1)
            echo -e "\n\e[36m=== Phase 1 — OS Preparation ===\e[0m"
            run_sequence "${PHASE1_SCRIPTS[@]}"
            ;;
        2)
            echo -e "\n\e[36m=== Phase 2 — Klipper Stack ===\e[0m"
            # Ask about optional extras first
            echo -e "\nSelect optional extras to install after the required Phase 2 steps:"
            optional_checklist
            run_sequence "${PHASE2_SCRIPTS[@]}"
            if [[ ${#SELECTED[@]} -gt 0 ]]; then
                echo -e "\e[36m--- Running selected optional extras ---\e[0m"
                run_sequence "${SELECTED[@]}"
            fi
            ;;
        3)
            echo -e "\n\e[36m=== Optional Extras ===\e[0m"
            optional_checklist
            if [[ ${#SELECTED[@]} -gt 0 ]]; then
                run_sequence "${SELECTED[@]}"
            else
                echo -e "\e[33m⚠️  Nothing selected.\e[0m"
            fi
            ;;
        4)
            menu_individual
            ;;
        5)
            echo -e "\n\e[36m=== Full Install: Phase 1 + Phase 2 ===\e[0m"
            echo -e "\e[33m⚠️  Phase 1 ends with a reboot. After reboot, run this script again and choose option 2.\e[0m"
            read -rp "Start Phase 1 now? [y/N]: " confirm
            [[ "$confirm" =~ ^[Yy]$ ]] && run_sequence "${PHASE1_SCRIPTS[@]}"
            ;;
        d|D)
            if [[ "$debugMode" -eq 1 ]]; then
                debugMode=0
                echo -e "\e[33m🔕 Debug mode disabled.\e[0m"
            else
                debugMode=1
                echo -e "\e[32m🔔 Debug mode enabled. Scripts will run with bash -x.\e[0m"
            fi
            ;;
        q|Q)
            echo -e "\e[32m👋 Goodbye!\e[0m"
            exit 0
            ;;
        *)
            echo -e "\e[33m⚠️  Invalid choice, try again.\e[0m"
            ;;
    esac
done