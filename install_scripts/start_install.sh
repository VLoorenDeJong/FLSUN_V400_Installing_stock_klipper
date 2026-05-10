#!/bin/bash

# =============================================================================
# CONFIGURATION
# =============================================================================
# Set to 0 to skip reboot prompt, set to 1 to ask user about reboot
# If reboot.sh is present in SCRIPT_PARAMS, it controls reboot timing.
ASK_FOR_REBOOT=0

debugMode=0
verboseMode=0

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -q|--quiet)
            verboseMode=0
            shift
            ;;
        -v|--verbose)
            verboseMode=1
            shift
            ;;
        -d|--debug)
            debugMode=1
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Installation script for Linux server setup"
            echo ""
            echo "Options:"
            echo "  -q, --quiet     Run in quiet mode (less output) [default]"
            echo "  -v, --verbose   Run in verbose mode (more output)"
            echo "  -d, --debug     Enable debug mode (bash -x)"
            echo "  -h, --help      Show this help message"
            echo ""
            echo "Configuration:"
            echo "  Scripts to run are hardcoded in this file"
            echo "  For different configurations, use different branches"
            echo ""
            echo "Examples:"
            echo "  sudo $0                    # Normal verbose mode"
            echo "  sudo $0 --quiet           # Quiet mode"
            echo "  sudo $0 --debug           # Debug mode"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Export verbosity setting for child scripts
export VERBOSE_MODE="$verboseMode"

# Check if running with sudo privileges
if [ "$(id -u)" -ne 0 ]; then
    echo -e "\e[31m❌ This script requires sudo privileges to run properly.\e[0m"
    echo -e "\e[33m💡 Please run with: \e[36msudo $0\e[0m"
    echo -e "\e[33m   This will avoid password prompts during installation.\e[0m"
    exit 1
fi

# Get the directory where this script resides
SCRIPT_DIR=$(dirname "$0")
INSTALL_DIR="$(cd "$SCRIPT_DIR" && pwd)/scripts"

# Set common parameters
USER_PARAM="$SUDO_USER"

# Define the scripts to run with their parameters
# Format: "script_name" or "script_name:param1" or "script_name:param1:param2"
SCRIPT_PARAMS=(
    "cleanup_repositories.sh"
    "fix_dpkg_lock.sh"
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
    "add_flsun_speeder_pad_installer.sh"
    "add_kiauh.sh"
    "start_kiauh.sh"
    "add_webmin.sh"
    #// ToDo Figure out the path for the gcode files and add the parameter in smb.conf
#    "add_smb.sh"
    "set_scripts_executable.sh"
    "reboot.sh"
)

echo -e "\e[34m🚀 Beginning installation sequence...\e[0m"

# Detect if reboot is already handled as part of the script pipeline
HAS_REBOOT_SCRIPT=false
for script_entry in "${SCRIPT_PARAMS[@]}"; do
    script_name=$(echo "$script_entry" | cut -d':' -f1)
    if [[ "$script_name" == "reboot.sh" ]]; then
        HAS_REBOOT_SCRIPT=true
        break
    fi
done

# Configure reboot behavior based on setting
if [ "$ASK_FOR_REBOOT" -eq 1 ]; then
    # Ask user about reboot preference
    printf "\e[34mDo you want to reboot after all scripts complete successfully? [Y/n]:\e[0m "
    read -r REBOOT_CHOICE
    # Default to Y if empty input or Y/y, otherwise no reboot
    case "$REBOOT_CHOICE" in
        [Nn]*)
            SHOULD_REBOOT=false
            ;;
        *)
            SHOULD_REBOOT=true
            ;;
    esac
else
    # Don't ask for reboot - default to no automatic reboot in this wrapper
    SHOULD_REBOOT=false
fi

# Avoid double reboot if reboot.sh is already part of the execution array
if $HAS_REBOOT_SCRIPT; then
    SHOULD_REBOOT=false
fi

# Track missing scripts
MISSING=()

# Check for existence of all scripts first
for script_entry in "${SCRIPT_PARAMS[@]}"; do
    # Extract just the script name (before any colon)
    script_name=$(echo "$script_entry" | cut -d':' -f1)
    if [[ ! -f "$INSTALL_DIR/$script_name" ]]; then
        MISSING+=("$script_name")
    fi
done

# If any scripts are missing, display and exit
if [ ${#MISSING[@]} -gt 0 ]; then
    echo -e "\e[31m🚫 The following script(s) are missing:\e[0m"
    for script in "${MISSING[@]}"; do
        echo -e "\e[31m - $script\e[0m"
    done
    exit 1
fi

# Run the scripts
ALL_SUCCESS=true
FAILED_SCRIPTS=()
CRITICAL_FAILED=false

# Function to run DPKG lock fix
run_lock_fix() {
    local fix_script="$INSTALL_DIR/fix_dpkg_lock.sh"
    if [[ -f "$fix_script" ]]; then
        echo -e "\e[34m🔧 Checking and fixing DPKG locks...\e[0m"
        if bash "$fix_script"; then
            echo -e "\e[32m✅ DPKG locks resolved\e[0m"
            return 0
        else
            echo -e "\e[33m⚠️  DPKG lock fix failed, continuing anyway...\e[0m"
            return 1
        fi
    else
        echo -e "\e[33m⚠️  fix_dpkg_lock.sh not found, skipping lock check\e[0m"
        return 1
    fi
}

# Run initial lock fix before starting any scripts
run_lock_fix

for script_entry in "${SCRIPT_PARAMS[@]}"; do
    # Parse script entry: "script_name:param1:param2" or just "script_name"
    script_name=$(echo "$script_entry" | cut -d':' -f1)
    param1=$(echo "$script_entry" | cut -d':' -f2)
    param2=$(echo "$script_entry" | cut -d':' -f3)
    
    # Skip running fix_dpkg_lock.sh again since we handle it separately
    if [[ "$script_name" == "fix_dpkg_lock.sh" ]]; then
        echo -e "\e[34m⏭️  Skipping $script_name (handled separately)\e[0m"
        continue
    fi

    # Only run reboot.sh if all previous scripts have succeeded
    if [[ "$script_name" == "reboot.sh" && "$ALL_SUCCESS" != "true" ]]; then
        echo -e "\e[33m⏭️  Skipping reboot.sh because previous scripts failed\e[0m"
        continue
    fi
    
    # Run lock fix before each script (except the lock fix itself)
    run_lock_fix
    
    echo -e "\e[34m🚀 Running: $script_name\e[0m"
    
    # Choose execution method based on debugMode
    if [ "$debugMode" -eq 1 ]; then
        RUN_CMD="bash -x"
    else
        RUN_CMD="bash"
    fi
    
    # Build the command with parameters
    if [ -n "$param1" ] && [ -n "$param2" ]; then
        # Two parameters
        CMD="$RUN_CMD '$INSTALL_DIR/$script_name' '$param1' '$param2'"
    elif [ -n "$param1" ]; then
        # One parameter
        CMD="$RUN_CMD '$INSTALL_DIR/$script_name' '$param1'"
    else
        # No parameters
        CMD="$RUN_CMD '$INSTALL_DIR/$script_name'"
    fi
    
    # Execute the command
    if eval "$CMD"; then
        echo -e "\e[32m✅ Finished: $script_name\e[0m"
    else
        exit_code=$?
        echo -e "\e[31m❌ Failed: $script_name (exit code: $exit_code)\e[0m"
        echo -e "\e[33m💡 Check the error messages above for details\e[0m"
        echo -e "\e[33m📂 Script location: $INSTALL_DIR/$script_name\e[0m"
        echo -e "\e[33m🔍 To debug, run manually: sudo $CMD"
        ALL_SUCCESS=false
        FAILED_SCRIPTS+=("$script_name (exit code: $exit_code)")
        case "$script_name" in
            "add_pinecraft.sh")
                CRITICAL_FAILED=true
                echo -e "\e[33m⚠️  Note: Pinecraft failed - minecraft customizations may not work properly\e[0m"
                ;;
        esac
    fi
    echo "" # Add spacing between scripts
done

# Check if reboot is needed and requested
if $ALL_SUCCESS && $SHOULD_REBOOT; then
    echo -e "\e[32m🎉 All scripts completed successfully!\e[0m"
    echo -e "\e[34mRebooting in 5 seconds... (Press Ctrl+C to cancel)\e[0m"
    sleep 5
    bash "$INSTALL_DIR/reboot.sh"
elif $ALL_SUCCESS; then
    echo -e "\e[32m🎉 All scripts completed successfully! No reboot requested.\e[0m"
else
    echo -e "\e[33m⚠️  Installation completed with some failures.\e[0m"
    echo -e "\e[31m💥 Failed scripts:\e[0m"
    for failed_script in "${FAILED_SCRIPTS[@]}"; do
        echo -e "\e[31m - $failed_script\e[0m"
    done
    if $CRITICAL_FAILED; then
        echo -e "\e[33m⚠️  Critical components failed - some features may not work properly.\e[0m"
        echo -e "\e[33m💡 You can try running the failed scripts manually later.\e[0m"
    fi
    if $SHOULD_REBOOT; then
        printf "\e[33m❓ Some scripts failed. Do you still want to reboot? [y/N]: \e[0m"
        read -r REBOOT_ANYWAY
        case "$REBOOT_ANYWAY" in
            [Yy]*)
                echo -e "\e[34mRebooting in 5 seconds... (Press Ctrl+C to cancel)\e[0m"
                sleep 5
                bash "$INSTALL_DIR/reboot.sh"
                ;;
            *)
                echo -e "\e[33m🚫 Reboot skipped due to failed scripts.\e[0m"
                ;;
        esac
    else
        echo -e "\e[33m🚫 No reboot requested.\e[0m"
    fi
    exit 0
fi