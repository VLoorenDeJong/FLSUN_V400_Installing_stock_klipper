#!/bin/bash

# =============================================================================
# FLSUN V400 Speeder Pad — Installation Menu
# =============================================================================

debugMode=0
installNetworkManager=0
overrideMode=0

STATE_DIR="/var/lib/linuxsetups"

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
    "change_username_password.sh"   # Interactive — rename current user and/or set new password
    "fix_xauthority.sh"         # Ensures .Xauthority won't hinder the process
    "cleanup_repositories.sh"
    "add_ssh.sh"
    "updates_install_and_clean.sh"
    "update_kernel.sh"
    "upgrade_distro.sh"
    "configure_locale_and_wifi_country.sh"
    "add_network_manager.sh"
    "add_bash_show_branch_name.sh"
    # Print Phase 1 completion message before network disruption
    "print_phase1_success.sh"              # Custom script to notify user before connection loss
    "mark_phase1_complete.sh"              # Mark Phase 1 as complete
    "add_flsun_speeder_pad_installer.sh"  # Guilouz sp_installer1 — reboots the system!
    "reboot.sh"                           # This is for testing
)

# Phase 2 — Flsun sp_installer1 prep and KIAUH prep (ends with sp_installer1 reboot)
PHASE2_SCRIPTS=(
    "cleanup_repositories.sh"
    "mark_phase2_complete.sh"             # Mark Phase 2 as complete
    "add_flsun_sp_installer2.sh"          # step 058-059: Guilouz sp_installer2
    "add_kiauh.sh"
    "install_python39.sh"                 # ensure python3.9 + venv tooling before pip/setuptools fixes
    "fix_pip_venvs.sh"                    # patch ensurepip + setuptools before KIAUH
    "start_kiauh.sh 1"                    # SESSION 1: remove old Flsun packages
    "cleanup_flsun_builds.sh"             # remove Flsun-specific dirs/configs
    "start_kiauh.sh 2"                    # SESSION 2: install Klipper/Moonraker/Mainsail
    "fix_klipper_venv.sh"                 # fix aenum + re-install klippy requirements
    "add_klipperscreen_guilouz.sh"        # install Guilouz KlipperScreen fork
    "add_usb_symlink.sh"                  # ln -s gcode_files/USB-Disk printer_data/gcodes/
    "fix_moonraker_shutdown.sh"           # policykit rules + [machine] shutdown_action
    "reboot.sh"                           # final reboot to bring up all services cleanly
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
        add_apache_webserver.sh|add_smb.sh|install_python39.sh)
            run_lock_fix ;;
    esac

    echo -e "\e[34m🚀 Running: $script_name\e[0m"
    local run_cmd="bash"
    [[ "$debugMode" -eq 1 ]] && run_cmd="bash -x"
    export FLSUN_DEBUG=$debugMode

    # Redirect stdin from /dev/tty so child scripts read from the terminal
    # directly and cannot exhaust the parent script's stdin.
    local tty_src="/dev/tty"
    [[ ! -r /dev/tty ]] && tty_src="/dev/stdin"

    if $run_cmd "$script_path" "${script_args[@]}" <"$tty_src"; then
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

    for script_entry in "${scripts[@]}"; do
        # Split entry into script name + optional args
        read -ra parts <<< "$script_entry"
        local script="${parts[0]}"
        local extra_args=("${parts[@]:1}")
        run_script "$script" "${extra_args[@]}" || all_ok=false
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
        read -rp "Choice: " opt </dev/tty
        case "$opt" in
            a) for i in "${!toggles[@]}"; do toggles[i]="on"; done ;;
            n) for i in "${!toggles[@]}"; do toggles[i]="off"; done ;;
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
}

# Build and run a sequence, injecting add_network_manager.sh before reboot.sh
# when the installNetworkManager toggle is on.
run_sequence_with_flags() {
    local result=()
    for s in "$@"; do
        if [[ "$s" == "reboot.sh" && "$installNetworkManager" -eq 1 ]]; then
            result+=("add_network_manager.sh")
        fi
        result+=("$s")
    done
    run_sequence "${result[@]}"
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
    if phase_done "$phase_num" && [[ "$overrideMode" -eq 0 ]]; then
        echo -e "\e[32m✅ Phase $phase_num already completed.\e[0m"
        echo -e "\e[33m   Enable override mode (o) to re-run.\e[0m"
        return 0
    fi
    run_sequence_with_flags "$@"
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
    echo -e "  \e[33m4)\e[0m  Optional extras only  \e[90m(Webmin, Samba)\e[0m"
    echo -e "  \e[33m5)\e[0m  Run individual script"
    echo -e "  \e[33m6)\e[0m  Full install  \e[90m(Phase 1 → 2 → 3, reboots in between)\e[0m"
    if [[ "$debugMode" -eq 1 ]]; then
        echo -e "  \e[33md)\e[0m  Debug mode          \e[32m[ON]\e[0m"
    else
        echo -e "  \e[33md)\e[0m  Debug mode          \e[90m[off]\e[0m"
    fi
    if [[ "$installNetworkManager" -eq 1 ]]; then
        echo -e "  \e[33mn)\e[0m  NetworkManager      \e[32m[ON]\e[0m  \e[90m(replaces dhcpcd — may cause WiFi instability)\e[0m"
    else
        echo -e "  \e[33mn)\e[0m  NetworkManager      \e[90m[off]\e[0m"
    fi
    if [[ "$overrideMode" -eq 1 ]]; then
        echo -e "  \e[33mo)\e[0m  Override completed  \e[32m[ON]\e[0m  \e[90m(allows re-running completed phases)\e[0m"
    else
        echo -e "  \e[33mo)\e[0m  Override completed  \e[90m[off]\e[0m"
    fi
    echo -e "  \e[33mq)\e[0m  Quit"
    echo ""
    read -rp "Choice: " MAIN_CHOICE </dev/tty || { echo -e "\n\e[32m👋 Goodbye!\e[0m"; exit 0; }

    case "$MAIN_CHOICE" in
        1)
            echo -e "\n\e[36m=== Phase 1 — OS Preparation ===\e[0m"
            run_phase 1 "${PHASE1_SCRIPTS[@]}"
            ;;
        2)
            echo -e "\n\e[36m=== Phase 2 — Flsun sp_installer1 + KIAUH Prep ===\e[0m"
            echo -e "\e[33m⚠️  This phase ends with a system reboot (sp_installer1).\e[0m"
            read -rp "Continue? [y/N]: " confirm </dev/tty
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                run_phase 2 "${PHASE2_SCRIPTS[@]}"
            fi
            ;;
        4)
            echo -e "\n\e[36m=== Optional Extras ===\e[0m"
            optional_checklist
            if [[ ${#SELECTED[@]} -gt 0 ]]; then
                run_sequence "${SELECTED[@]}"
            else
                echo -e "\e[33m⚠️  Nothing selected.\e[0m"
            fi
            ;;
        5)
            menu_individual
            ;;
        6)
            echo -e "\n\e[36m=== Full Install: Phase 1 + 2 ===\e[0m"
            echo -e "\e[33m⚠️  Phase 1 and Phase 2 each end with a reboot. After each reboot, re-run this script and choose the next phase.\e[0m"
            read -rp "Start Phase 1 now? [y/N]: " confirm </dev/tty
            [[ "$confirm" =~ ^[Yy]$ ]] && run_phase 1 "${PHASE1_SCRIPTS[@]}"
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
        n|N)
            if [[ "$installNetworkManager" -eq 1 ]]; then
                installNetworkManager=0
                echo -e "\e[33m🔕 NetworkManager disabled — dhcpcd will be used.\e[0m"
            else
                installNetworkManager=1
                echo -e "\e[32m🔔 NetworkManager enabled — will install before reboot.\e[0m"
                echo -e "\e[33m⚠️  This replaces dhcpcd and may cause WiFi instability.\e[0m"
            fi
            ;;
        o|O)
            if [[ "$overrideMode" -eq 1 ]]; then
                overrideMode=0
                echo -e "\e[33m🔒 Override disabled — completed phases are protected.\e[0m"
            else
                overrideMode=1
                echo -e "\e[32m🔓 Override enabled — completed phases can be re-run.\e[0m"
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