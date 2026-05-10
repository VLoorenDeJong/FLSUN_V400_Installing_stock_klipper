#!/bin/bash

# Define the directories
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Get the installer user from the config file, or fall back to sudo/current user
INSTALLER_USER=""
if [ -f "/etc/manageserver-installer-user" ]; then
    INSTALLER_USER=$(cat /etc/manageserver-installer-user 2>/dev/null)
fi

# If we couldn't get installer user from file, use the traditional method
if [ -z "$INSTALLER_USER" ]; then
    if [ -n "$SUDO_USER" ]; then
        INSTALLER_USER="$SUDO_USER"
    else
        INSTALLER_USER="$(whoami)"
    fi
fi

# Get the installer user's home directory
if [ -n "$INSTALLER_USER" ]; then
    INSTALLER_HOME=$(getent passwd "$INSTALLER_USER" | cut -d: -f6)
else
    INSTALLER_HOME="$HOME"
fi

BACKUP_CONFIG_DIR="$INSTALLER_HOME/LinuxSetups/backup_config"

# Ensure the directories exist before applying permissions
echo -e "\e[34m🔧 Setting executable permissions for scripts...\e[0m"

if [[ -d "$REPO_DIR" ]]; then
    sudo chmod -R +x "$REPO_DIR"

    # Check if chmod was successful
    if [[ $? -eq 0 ]]; then
        echo -e "\e[32m✅ All scripts in $REPO_DIR are now executable!\e[0m"
    else
        echo -e "\e[31m❌ Failed to set executable permissions for $REPO_DIR!\e[0m"
        exit 1
    fi
else
    echo -e "\e[31m❌ Error: $REPO_DIR not found!\e[0m"
    exit 1
fi

# Also set executable permissions for backup_config scripts
if [[ -d "$BACKUP_CONFIG_DIR" ]]; then
    sudo chmod -R +x "$BACKUP_CONFIG_DIR"

    # Check if chmod was successful
    if [[ $? -eq 0 ]]; then
        echo -e "\e[32m✅ All scripts in $BACKUP_CONFIG_DIR are now executable!\e[0m"
    else
        echo -e "\e[31m❌ Failed to set executable permissions for $BACKUP_CONFIG_DIR!\e[0m"
        exit 1
    fi
else
    echo -e "\e[33m⚠️  Warning: $BACKUP_CONFIG_DIR not found (may not be created yet)\e[0m"
fi

# Also set executable permissions for maintenance_scripts and its subfolders
MAINTENANCE_SCRIPTS_DIR="$BACKUP_CONFIG_DIR/maintenance_scripts"
MAINTENANCE_SCRIPTS_SUBDIR="$MAINTENANCE_SCRIPTS_DIR/scripts"

# Ensure the scripts subdirectory exists
if [[ ! -d "$MAINTENANCE_SCRIPTS_SUBDIR" ]]; then
    echo -e "\e[33m⚠️  Scripts directory $MAINTENANCE_SCRIPTS_SUBDIR not found. Creating it...\e[0m"
    mkdir -p "$MAINTENANCE_SCRIPTS_SUBDIR"
fi

if [[ -d "$MAINTENANCE_SCRIPTS_DIR" ]]; then
    sudo chmod -R +x "$MAINTENANCE_SCRIPTS_DIR"
    if [[ $? -eq 0 ]]; then
        echo -e "\e[32m✅ All scripts in $MAINTENANCE_SCRIPTS_DIR and subfolders are now executable!\e[0m"
    else
        echo -e "\e[31m❌ Failed to set executable permissions for $MAINTENANCE_SCRIPTS_DIR!\e[0m"
        exit 1
    fi
else
    echo -e "\e[33m⚠️  Warning: $MAINTENANCE_SCRIPTS_DIR not found (may not be created yet)\e[0m"
fi

echo -e "\e[32m🎉 Script executable permissions setup complete!\e[0m"
