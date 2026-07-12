#!/bin/bash

print_status()  { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning() { printf "\033[33m⚠️  %s\033[0m\n" "$1"; }
print_error()   { printf "\033[31m❌ %s\033[0m\n" "$1"; }

# Define the repo root relative to this script
# BASH_SOURCE[0] is .../install_scripts/scripts/set_scripts_executable.sh,
# so we need two levels up (scripts -> install_scripts -> repo root).
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

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

print_status "Setting executable permissions for scripts..."

# Make repo scripts executable
if [[ -d "$REPO_DIR" ]]; then
    sudo chmod -R +x "$REPO_DIR"
    if [[ $? -eq 0 ]]; then
        print_success "All scripts in $REPO_DIR are now executable!"
    else
        print_error "Failed to set executable permissions for $REPO_DIR!"
        exit 1
    fi
else
    print_error "Error: $REPO_DIR not found!"
    exit 1
fi

# FIXED: backup_config relative to repo
if [[ -d "$BACKUP_CONFIG_DIR" ]]; then
    sudo chmod -R +x "$BACKUP_CONFIG_DIR"
    if [[ $? -eq 0 ]]; then
        print_success "All scripts in $BACKUP_CONFIG_DIR are now executable!"
    else
        print_error "Failed to set executable permissions for $BACKUP_CONFIG_DIR!"
        exit 1
    fi
else
    print_warning "Warning: $BACKUP_CONFIG_DIR not found (may not be created yet)"
fi

print_success "Script executable permissions setup complete!"
