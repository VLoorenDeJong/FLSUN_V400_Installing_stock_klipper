#!/bin/bash

# Define the repo root relative to this script
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Get installer user (unchanged)
INSTALLER_USER=""
if [ -f "/etc/manageserver-installer-user" ]; then
    INSTALLER_USER=$(cat /etc/manageserver-installer-user 2>/dev/null)
fi

if [ -z "$INSTALLER_USER" ]; then
    if [ -n "$SUDO_USER" ]; then
        INSTALLER_USER="$SUDO_USER"
    else
        INSTALLER_USER="$(whoami)"
    fi
fi

# Installer home (still used for other things, but NOT for backup_config)
if [ -n "$INSTALLER_USER" ]; then
    INSTALLER_HOME=$(getent passwd "$INSTALLER_USER" | cut -d: -f6)
else
    INSTALLER_HOME="$HOME"
fi

# FIXED: backup_config is now relative to the repo
BACKUP_CONFIG_DIR="$REPO_DIR/backup_config"

echo -e "\e[34m🔧 Setting executable permissions for scripts...\e[0m"

# Make repo scripts executable
if [[ -d "$REPO_DIR" ]]; then
    sudo chmod -R +x "$REPO_DIR"
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

# FIXED: backup_config relative to repo
if [[ -d "$BACKUP_CONFIG_DIR" ]]; then
    sudo chmod -R +x "$BACKUP_CONFIG_DIR"
    if [[ $? -eq 0 ]]; then
        echo -e "\e[32m✅ All scripts in $BACKUP_CONFIG_DIR are now executable!\e[0m"
    else
        echo -e "\e[31m❌ Failed to set executable permissions for $BACKUP_CONFIG_DIR!\e[0m"
        exit 1
    fi
else
    echo -e "\e[33m⚠️  Warning: $BACKUP_CONFIG_DIR not found (may not be created yet)\e[0m"
fi

# FIXED: maintenance scripts also relative to repo
MAINTENANCE_SCRIPTS_DIR="$BACKUP_CONFIG_DIR/maintenance_scripts"
MAINTENANCE_SCRIPTS_SUBDIR="$MAINTENANCE_SCRIPTS_DIR/scripts"

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
