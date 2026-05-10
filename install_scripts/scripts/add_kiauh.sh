#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

KIAUH_REPO_URL="https://github.com/dw-0/kiauh.git"
FORCE_REINSTALL="${FORCE_REINSTALL_KIAUH:-0}"

if [ "$(id -u)" -ne 0 ]; then
    echo -e "\e[31m❌ This script must run with sudo/root privileges.\e[0m"
    exit 1
fi

# Prefer the original sudo user. Fall back to pi, then root.
TARGET_USER="${SUDO_USER:-}"
if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
    if id pi >/dev/null 2>&1; then
        TARGET_USER="pi"
    else
        TARGET_USER="root"
    fi
fi

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
if [ -z "$TARGET_HOME" ]; then
    echo -e "\e[31m❌ Could not determine home directory for user: $TARGET_USER\e[0m"
    exit 1
fi

KIAUH_DIR="${TARGET_HOME}/kiauh"

if ! command -v git >/dev/null 2>&1; then
    echo -e "\e[34m🔧 Installing git\e[0m"
    apt-get update -qq
    apt-get install -y -qq git
fi

# If KIAUH already exists and this is not a forced reinstall, do a safe update.
if [ -d "$KIAUH_DIR/.git" ] && [ "$FORCE_REINSTALL" != "1" ]; then
    echo -e "\e[34m🔄 Existing KIAUH clone found, updating instead of reinstalling\e[0m"
    git -C "$KIAUH_DIR" fetch --all --prune
    git -C "$KIAUH_DIR" reset --hard origin/master || git -C "$KIAUH_DIR" reset --hard origin/main
    git -C "$KIAUH_DIR" clean -fd
    chown -R "$TARGET_USER":"$TARGET_USER" "$KIAUH_DIR"
    echo -e "\e[32m✅ KIAUH updated successfully\e[0m"
    exit 0
fi

echo -e "\e[34m🧹 Removing existing KIAUH directory: $KIAUH_DIR\e[0m"
rm -rf "$KIAUH_DIR"

echo -e "\e[34m📥 Cloning KIAUH into: $KIAUH_DIR\e[0m"
git clone "$KIAUH_REPO_URL" "$KIAUH_DIR"

echo -e "\e[34m🔐 Fixing ownership for user: $TARGET_USER\e[0m"
chown -R "$TARGET_USER":"$TARGET_USER" "$KIAUH_DIR"

echo -e "\e[32m✅ KIAUH re-cloned successfully\e[0m"
