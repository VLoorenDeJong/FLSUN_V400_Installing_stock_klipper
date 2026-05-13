#!/usr/bin/env bash
set -e

# =============================================================================
# Fix outdated pip in Python virtual environments
# =============================================================================
# Old pip versions bundled with Debian/Raspbian use toml-0.10.0 to parse
# pyproject.toml files. That library has a parser bug (IndexError in array
# handling) that causes Moonraker/Klipper requirements installation to fail.
# pip >= 21.x switched to tomli which does not have this bug.
# This script upgrades pip inside every known venv so installations succeed.
# =============================================================================

print_status()  { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning() { printf "\033[33m⚠️  %s\033[0m\n" "$1"; }
print_error()   { printf "\033[31m❌ %s\033[0m\n" "$1"; }
print_header()  { printf "\n\033[36m=== %s ===\033[0m\n" "$1"; }

# Resolve actual user home (works under sudo)
TARGET_USER="${SUDO_USER:-}"
if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
    if id pi >/dev/null 2>&1; then
        TARGET_USER="pi"
    else
        TARGET_USER="$(whoami)"
    fi
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

print_header "Upgrade pip in Python Virtual Environments"
print_warning "Old pip uses toml-0.10.0 which has a TOML array parser bug."
print_warning "This causes Moonraker requirements installation to fail."
print_status  "Upgrading pip to fix the issue..."

VENV_DIRS=(
    "${TARGET_HOME}/moonraker-env"
    "${TARGET_HOME}/klipper-env"
    "${TARGET_HOME}/klippy-env"
    "${TARGET_HOME}/mainsail-env"
    "${TARGET_HOME}/KlipperScreen-env"
    "${TARGET_HOME}/crowsnest-env"
    "${TARGET_HOME}/moonraker-telegram-bot-env"
)

any_upgraded=false

for venv in "${VENV_DIRS[@]}"; do
    pip_bin="${venv}/bin/pip"
    if [ -f "$pip_bin" ]; then
        print_status "Upgrading pip in: $venv"
        if sudo -u "$TARGET_USER" "$pip_bin" install --upgrade pip --quiet; then
            new_version=$(sudo -u "$TARGET_USER" "$pip_bin" --version 2>/dev/null | awk '{print $2}')
            print_success "pip upgraded to $new_version in $(basename "$venv")"
            any_upgraded=true
        else
            print_warning "pip upgrade failed in $venv — continuing anyway"
        fi
    fi
done

if [ "$any_upgraded" = false ]; then
    print_warning "No virtual environments found yet (KIAUH hasn't installed anything)."
    print_warning "This script will be useful after Moonraker/Klipper are installed."
fi

print_success "pip venv fix complete."
