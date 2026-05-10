#!/bin/bash

# Suppress confirmation prompts for apt
export DEBIAN_FRONTEND=noninteractive

# Source shared utilities (safe - no breaking changes)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/shared_utilities.sh" ]; then
    source "$SCRIPT_DIR/shared_utilities.sh"
else
    # Fallback to inline functions if shared file not found (maintains compatibility)
    echo "Warning: shared_utilities.sh not found, using inline functions"
fi

# Function to check and fix DPKG locks (calls dedicated script)
check_and_fix_dpkg_lock() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local fix_script="$script_dir/fix_dpkg_lock.sh"
    
    if [ -f "$fix_script" ]; then
        echo -e "\e[34m🔧 Checking and fixing DPKG locks...\e[0m"
        if bash "$fix_script"; then
            echo -e "\e[32m✅ DPKG lock check/fix completed\e[0m"
            return 0
        else
            echo -e "\e[31m❌ DPKG lock fix failed, continuing anyway...\e[0m"
            return 1
        fi
    else
        echo -e "\e[33m⚠️  fix_dpkg_lock.sh not found, proceeding without DPKG lock check\e[0m"
        return 1
    fi
}

# Enable or disable confirmation prompts (true = ask, false = skip)
ASK_CONFIRMATION=false

# Function to prompt the user if confirmation is enabled
ask_user() {
    if [[ "$ASK_CONFIRMATION" == true ]]; then
        read -r -p "$1 (Y/n): " choice
        choice=${choice:-Y}  # Default to "Y" if no input is given
        [[ "$choice" =~ ^[Yy]$ ]]
    else
        return 0  # Automatically proceed without asking
    fi
}

# Ask for system update confirmation
if ask_user "Do you want to update and upgrade the system?"; then
    # Check and fix any DPKG locks before proceeding with package operations
    check_and_fix_dpkg_lock
    
    if show_progress "� Updating package lists" "sudo apt-get update -qq >/dev/null 2>&1"; then
        echo -e "\e[32m✅ Package lists updated successfully\e[0m"
        
        if show_progress "⬆️ Upgrading system packages" "sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -o Dpkg::Options::=\"--force-confdef\" -o Dpkg::Options::=\"--force-confold\" -qq >/dev/null 2>&1"; then
            echo -e "\e[32m✅ System upgrade completed successfully\e[0m"
        else
            echo -e "\e[31m❌ System upgrade failed\e[0m"
            exit 1
        fi
    else
        echo -e "\e[31m❌ Package list update failed\e[0m"
        exit 1
    fi

    # Ask for cleanup confirmation
    if ask_user "Do you want to clean up unused packages?"; then
        # Remove unused packages
        if show_progress "🗑️ Removing unused packages" "sudo apt-get autoremove -y -qq >/dev/null 2>&1"; then
            echo -e "\e[32m✅ Unused packages removed\e[0m"
        fi

        # Purge leftover configuration files, only if any exist
        leftover_configs=$(dpkg -l | awk '/^rc/ { print $2 }')
        if [ -n "$leftover_configs" ]; then
            if show_progress "🧹 Removing leftover configurations" "sudo apt-get purge -y -qq $leftover_configs >/dev/null 2>&1"; then
                echo -e "\e[32m✅ Leftover configurations removed\e[0m"
            fi
        fi

        # Clean up cached packages
        if show_progress "🧽 Cleaning package cache" "sudo apt-get autoclean -y -qq >/dev/null 2>&1 && sudo apt-get clean -y -qq >/dev/null 2>&1"; then
            echo -e "\e[32m✅ Package cache cleaned\e[0m"
        fi

        echo -e "\e[32m✅ System cleanup completed!\e[0m"
    fi
fi
