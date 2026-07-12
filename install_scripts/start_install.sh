#!/bin/bash

#Todo
# 01.💡 Fix pressing enter issue for continue   
# 03.   Figure out favicon issue with Mainsail
# 04.💡 Build a script for a service to disable and reanable the network adapter every 5 minutes
# 05.💡 Review smb settings
# 06.💡  Remove the change username and password script to only change the password of the current user
# 07.💡  Update main menu and documentation with the instructions for all options and phases


# =============================================================================
# FLSUN V400 Speeder Pad — Installation Menu
# =============================================================================

debugMode=0

STATE_DIR="/var/lib/linuxsetups"
LOG_FILE="/var/log/install_scripts.log"
export LOG_FILE

# -----------------------------------------------------------------------------
# KIAUH version pin (optional)
# Leave empty to use the latest master. Set to a tag, branch, or commit SHA
# to pin to a specific version. Example: "v5.3.0" or "v4.2.1"
# Override with:  KIAUH_TAG=v5.3.0 sudo bash start_install.sh
# -----------------------------------------------------------------------------
export KIAUH_TAG="${KIAUH_TAG:-}"

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

# Migrate old phase marker files if needed
bash "$SCRIPT_DIR/scripts/migrate_phase_markers.sh"

# =============================================================================
# PHASE DEFINITIONS
# =============================================================================

# Phase 1 — OS preparation (ends with reboot)
PHASE1_SCRIPTS=(
    "set_scripts_executable.sh"
    "update_password.sh"        # Set new password
    "fix_xauthority.sh"         # Ensures .Xauthority won't hinder the process
    "cleanup_repositories.sh"
    "add_ssh.sh"
    "updates_install_and_clean.sh"
    "update_kernel.sh"
    "upgrade_distro.sh"
    "add_bash_show_branch_name.sh"
    "configure_locale_and_wifi_country.sh"
    "adaaaaaa
    "install_wifi_toggle_service.sh"          # Install the timed WiFi toggle service (Network manager causes WiFi instability, this will keep that minimized)
    # Print Phase 1 completion message before network disruption
    "mark_phase1_complete.sh"              # Mark Phase 1 as complete
    "add_flsun_speeder_pad_installer.sh"  # Guilouz sp_installer1 — reboots the system!
    "reboot.sh"                           # This is for testing
)

# Phase 2 — Flsun sp_installer1 prep and KIAUH prep (ends with sp_installer1 reboot)
PHASE2_SCRIPTS=(
    "set_scripts_executable.sh"
    "cleanup_repositories.sh"
    "install_python.sh"                   # ensure python3.9 + venv tooling before pip/setuptools fixes
    "add_flsun_sp_installer2.sh"          # step 058-059: Guilouz sp_installer2
    "add_kiauh.sh"
    "fix_pip_venvs.sh"                    # patch ensurepip + setuptools before KIAUH
    "start_kiauh.sh 1"                    # SESSION 1: remove old Flsun packages
    "cleanup_flsun_builds.sh"             # remove Flsun-specific dirs/configs
    "start_kiauh.sh 2"                    # SESSION 2: install Klipper/Moonraker/Mainsail
    "fix_klipper_venv.sh"                 # fix aenum + re-install klippy requirements
    "add_klipperscreen_guilouz.sh"        # install Guilouz KlipperScreen fork
    "add_usb_symlink.sh"                  # ln -s gcode_files/USB-Disk printer_data/gcodes/
    "fix_moonraker_shutdown.sh"           # policykit rules + [machine] shutdown_action
    "restore_flsun_configs.sh"            # restore Guilouz configs for Klipper, Moonraker, Mainsail, and KlipperScreen
    "configure_printer_settings.sh"       # set up moonraker.conf and printer.cfg for FLSUN V400
    "add_flsun_theme.sh"                  # copy custom theme files to Mainsail
)

# Optional extras (shown as checklist in Phase 2 and standalone menu)
declare -A OPTIONAL_LABELS=(
    ["add_webmin.sh"]="Webmin  (web-based admin panel)"
    ["add_smb.sh"]="Samba   (SMB/Windows file sharing)"
)
OPTIONAL_ORDER=("add_webmin.sh" "add_smb.sh")

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
    shift
    local script_args=("$@")   # any extra arguments are passed to the child script
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
        add_apache_webserver.sh|add_smb.sh|install_python39.sh|fix_klipper_venv.sh)
            run_lock_fix ;;
    esac

    echo "[INFO] Starting: $script_name at $(date -Iseconds)" >> "$LOG_FILE"

    echo -e "\e[34m🚀 Running: $script_name\e[0m"
    local run_cmd="bash"
    [[ "$debugMode" -eq 1 ]] && run_cmd="bash -x"
    export FLSUN_DEBUG=$debugMode

    # Redirect stdin from /dev/tty so child scripts read from the terminal
    # directly and cannot exhaust the parent script's stdin.
    local tty_src="/dev/tty"
    [[ ! -r /dev/tty ]] && tty_src="/dev/stdin"

    if $run_cmd "$script_path" "${script_args[@]}" <"$tty_src"; then
        echo "[SUCCESS] $script_name completed at $(date -Iseconds)" >> "$LOG_FILE"
        echo -e "\e[32m✅ Finished: $script_name\e[0m"
        echo ""
        return 0
    else
        local code=$?
        echo "[ERROR] $script_name failed with exit code $code at $(date -Iseconds)" >> "$LOG_FILE"
        echo -e "\e[31m❌ Failed: $script_name (exit code: $code)\e[0m"
        echo -e "\e[33m💡 To debug: sudo bash -x '$script_path'\e[0m"
        echo ""
        return 1
    fi
}

run_sequence() {
    local scripts=("$@")

    for script_entry in "${scripts[@]}"; do
        # Split entry into script name + optional args
        read -ra parts <<< "$script_entry"
        local script="${parts[0]}"
        local extra_args=("${parts[@]:1}")
        if ! run_script "$script" "${extra_args[@]}"; then
            echo -e "\e[33m⚠️  Sequence stopped due to failure in: $script\e[0m"
            return 1
        fi
    done

    echo -e "\e[32m🎉 All steps completed successfully!\e[0m"
    return 0
}

 # Show a numbered checklist and return selected script names in SELECTED array
optional_checklist() {
    declare -g -a SELECTED=()
    local toggles=()
    for s in "${OPTIONAL_ORDER[@]}"; do toggles+=("on"); done

    while true; do
        echo ""
        echo -e "\e[36m--- Optional Extras ---\e[0m"
        echo "Optional extras are additional tools. The main install works without them."
        echo "These extras run before the final reboot."
        echo ""
        for i in "${!OPTIONAL_ORDER[@]}"; do
            local s="${OPTIONAL_ORDER[$i]}"
            local mark="\e[37m[ ]\e[0m"
            [[ "${toggles[$i]}" == "on" ]] && mark="\e[92m[x]\e[0m"
            printf "  %d) %b %s\n" "$((i+1))" "$mark" "${OPTIONAL_LABELS[$s]}"
        done
        echo ""
        echo "Commands:"
        echo "  1 or 2 = Toggle selection"
        echo "  a      = Select all"
        echo "  n      = Deselect all"
        echo "  b      = Back to main menu"
        echo "  Enter  = Continue"
        echo ""
        read -rp "Choice: " opt </dev/tty
        case "$opt" in
            a) for i in "${!toggles[@]}"; do toggles[i]="on"; done ;;
            n) for i in "${!toggles[@]}"; do toggles[i]="off"; done ;;
            b|B) return 1 ;;
            "") break ;;
            [0-9]*)
                local idx=$((opt-1))
                if [[ idx -ge 0 && idx -lt ${#OPTIONAL_ORDER[@]} ]]; then
                    [[ "${toggles[idx]}" == "on" ]] && toggles[idx]="off" || toggles[idx]="on"
                else
                    echo -e "\e[33m⚠️  Invalid number\e[0m"
                fi ;;
            *) echo -e "\e[33m⚠️  Invalid input\e[0m" ;;
        esac
    done

    for i in "${!OPTIONAL_ORDER[@]}"; do
        [[ "${toggles[$i]}" == "on" ]] && SELECTED+=("${OPTIONAL_ORDER[$i]}")
    done

    return 0
}
# Wrapper for Phase 2 optional extras
optional_phase2_extras() {
    if ! optional_checklist; then
        return 1
    fi

    # Copy SELECTED → PHASE2_OPTIONAL_SELECTED
    PHASE2_OPTIONAL_SELECTED=("${SELECTED[@]}")

    return 0
}



# =============================================================================
# PHASE STATE TRACKING
# =============================================================================

phase_done() { [[ -f "$STATE_DIR/phase${1}.done" ]]; }

mark_phase_done() {
    mkdir -p "$STATE_DIR"
    touch "$STATE_DIR/phase${1}.done"
    echo -e "\e[32m✅ Phase $1 marked as complete.\e[0m"
}

# Print one menu line for a numbered phase, showing ✅ if completed
phase_label() {
    local n="$1" label="$2"
    if phase_done "$n"; then
        echo -e "  \e[33m${n})\e[0m \e[32m✅\e[0m  ${label}  \e[90m(completed)\e[0m"
    else
        echo -e "  \e[33m${n})\e[0m  ○  ${label}"
    fi
}

# Run a numbered phase; blocks re-run unless overrideMode=1; marks done on full success
run_phase() {
    local phase_num="$1"; shift
    run_sequence "$@"
    local phase_result=$?
    [[ $phase_result -eq 0 ]] && mark_phase_done "$phase_num"
    return $phase_result
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
        read -rp "Choice: " opt </dev/tty
        [[ "$opt" == "b" ]] && break
        if [[ "$opt" =~ ^[0-9]+$ ]]; then
            local idx=$((opt-1))
            if [[ $idx -ge 0 && $idx -lt ${#all_scripts[@]} ]]; then
                run_script "${all_scripts[$idx]}"
                read -rp "Press Enter to continue..." _ </dev/tty
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
    phase_label 1 "Phase 1 — OS prep + distro upgrade      (ends with reboot)"
    phase_label 2 "Phase 2 — Flsun sp_installer1 + KIAUH prep (ends with reboot)"
    echo -e "  \e[33m3)\e[0m  Run individual script"
    if [[ "$debugMode" -eq 1 ]]; then
        echo -e "  \e[33md)\e[0m  Debug mode          \e[32m[ON]\e[0m"
    else
        echo -e "  \e[33md)\e[0m  Debug mode          \e[90m[off]\e[0m"
    fi 
    echo -e "  \e[33mq)\e[0m  Quit"
    echo ""
    read -rp "Choice: " MAIN_CHOICE </dev/tty || { echo -e "\n\e[32m👋 Goodbye!\e[0m"; exit 0; }

    case "$MAIN_CHOICE" in
        1)
            echo -e "\n\e[36m=== Phase 1 — OS Preparation ===\e[0m"
            echo -e "\e[33mTo monitor progress, run:\e[0m sudo tail -F $LOG_FILE"
            run_phase 1 "${PHASE1_SCRIPTS[@]}"
            ;;
        2)
            echo -e "\n\e[36m=== Phase 2 — Flsun sp_installer1 + KIAUH Prep ===\e[0m"
            echo -e "\e[33mTo monitor progress, run:\e[0m sudo tail -F $LOG_FILE"
            echo -e "\e[33m⚠️  This phase ends with a system reboot.\e[0m"

            echo ""
            echo -e "\e[36mSelect optional Phase 2 extras:\e[0m"
            if ! optional_phase2_extras; then
                echo -e "\e[33m↩️  Returning to main menu...\e[0m"
                continue
            fi

            if ! run_sequence "${PHASE2_SCRIPTS[@]}"; then
                echo -e "\e[31m❌ Phase 2 core steps failed. Returning to main menu for analysis.\e[0m"
                continue
            fi

            if [[ ${#PHASE2_OPTIONAL_SELECTED[@]} -gt 0 ]]; then
                echo -e "\n\e[36m=== Phase 2 Optional Extras ===\e[0m"
                if ! run_sequence "${PHASE2_OPTIONAL_SELECTED[@]}"; then
                    echo -e "\e[31m❌ Optional extras failed. Phase 2 was not marked complete and reboot was skipped.\e[0m"
                    continue
                fi
            else
                echo -e "\e[33m⚠️  No optional extras selected.\e[0m"
            fi

            if ! run_script "mark_phase2_complete.sh"; then
                echo -e "\e[31m❌ Could not mark Phase 2 complete. Reboot skipped.\e[0m"
                continue
            fi
            mark_phase_done 2

            if ! run_script "reboot.sh"; then
                echo -e "\e[31m❌ Reboot step failed. Returning to main menu for analysis.\e[0m"
                continue
            fi
            ;;

        3)
            menu_individual
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
