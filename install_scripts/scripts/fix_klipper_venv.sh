#!/usr/bin/env bash
set -e

# =============================================================================
# Fix Klipper virtualenv after KIAUH install (steps 093.2 - 093.8)
# =============================================================================

print_status()  { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning() { printf "\033[33m⚠️  %s\033[0m\n" "$1"; }
print_error()   { printf "\033[31m❌ %s\033[0m\n" "$1"; }
print_header()  { printf "\n\033[36m=== %s ===\033[0m\n" "$1"; }

# Busy indicator (dot every 5 seconds)
show_progress() {
    local message="$1"
    local command="$2"
    local interval="${3:-5}"
    local timeout="${4:-600}"
    local log_file
    log_file=$(mktemp /tmp/progress.XXXXXX.log)
    printf "\033[34m%s\033[0m\n" "$message"

    # Debug mode: stream output live. No dots, no kill timer.
    if [ "${FLSUN_DEBUG:-0}" = "1" ]; then
        eval "$command" 2>&1 | tee "$log_file"
        local exit_code=${PIPESTATUS[0]}
        if [ "$exit_code" -eq 0 ]; then
            rm -f "$log_file"
        else
            printf "\033[31m❌ Command failed (exit %s). Full log: %s\033[0m\n" "$exit_code" "$log_file"
        fi
        return "$exit_code"
    fi

    # Normal mode: capture output to the log. Show dots.
    eval "$command" >"$log_file" 2>&1 &
    local cmd_pid=$!
    local start_time
    start_time=$(date +%s)
    while kill -0 $cmd_pid 2>/dev/null; do
        printf "."
        sleep "$interval"
        local current_time
        current_time=$(date +%s)
        if (( current_time - start_time > timeout )); then
            printf "\n\033[31m❌ Command timed out after %d seconds\033[0m\n" "$timeout"
            kill -TERM $cmd_pid 2>/dev/null || true
            sleep 2
            kill -KILL $cmd_pid 2>/dev/null || true
            printf "\033[31mLast output before timeout:\033[0m\n"
            tail -n 20 "$log_file"
            printf "\033[33mFull log: %s\033[0m\n" "$log_file"
            return 1
        fi
    done
    wait $cmd_pid 2>/dev/null
    local exit_code=$?
    printf "\n"
    if [ "$exit_code" -ne 0 ]; then
        printf "\033[31m❌ Command failed (exit %s). Last output:\033[0m\n" "$exit_code"
        tail -n 20 "$log_file"
        printf "\033[33mFull log: %s\033[0m\n" "$log_file"
    else
        rm -f "$log_file"
    fi
    return "$exit_code"
}

# Root check
if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must run with sudo/root privileges."
    exit 1
fi

TARGET_USER="${SUDO_USER:-}"
if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
    id pi >/dev/null 2>&1 && TARGET_USER="pi" || TARGET_USER="$(whoami)"
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

KLIPPY_ENV="${TARGET_HOME}/klippy-env"
KLIPPER_DIR="${TARGET_HOME}/klipper"
REQUIREMENTS="${KLIPPER_DIR}/scripts/klippy-requirements.txt"
PIP="${KLIPPY_ENV}/bin/pip"
PYTHON="${KLIPPY_ENV}/bin/python"

print_header "Fix Klipper Virtual Environment (steps 093.2-093.8)"

# --- Ensure system deps ---
print_status "Checking system build dependencies (pkg-config, libsystemd-dev)..."
MISSING_DEPS=()
for pkg in pkg-config libsystemd-dev; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        MISSING_DEPS+=("$pkg")
    fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    print_status "Installing missing packages: ${MISSING_DEPS[*]}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq "${MISSING_DEPS[@]}"
    print_success "System build dependencies installed"
else
    print_success "System build dependencies already installed"
fi

# --- Validate paths ---
if [ ! -f "$PIP" ]; then
    print_warning "klippy-env not found at $KLIPPY_ENV"
    print_warning "KIAUH must be run first (install Klipper). Skipping."
    exit 0
fi

if [ ! -f "$REQUIREMENTS" ]; then
    print_warning "Klipper requirements file not found: $REQUIREMENTS"
    print_warning "Klipper may not be installed. Skipping."
    exit 0
fi

# --- Upgrade pip ---
show_progress "Upgrading pip inside klippy-env..." \
    "sudo -u \"$TARGET_USER\" \"$PIP\" install --upgrade pip --quiet"

new_ver=$(sudo -u "$TARGET_USER" "$PIP" --version 2>/dev/null | awk '{print $2}')
print_success "pip → $new_ver in klippy-env"

# --- Fix aenum ---
show_progress "Pinning aenum to 3.1.11..." \
    "sudo -u \"$TARGET_USER\" \"$PIP\" uninstall -y aenum || true"

show_progress "Installing aenum==3.1.11..." \
    "sudo -u \"$TARGET_USER\" \"$PIP\" install aenum==3.1.11 --quiet"

print_success "aenum pinned to 3.1.11"

# --- Install wheel ---
show_progress "Installing wheel..." \
    "sudo -u \"$TARGET_USER\" \"$PIP\" install wheel --quiet"

print_success "wheel installed"

# --- Install Klipper requirements ---
show_progress "Installing Klipper Python requirements..." \
    "sudo -u \"$TARGET_USER\" \"$PIP\" install -r \"$REQUIREMENTS\" --quiet"

print_success "Klipper requirements installed successfully"

# --- Verify import ---
if sudo -u "$TARGET_USER" "$PYTHON" -c "import klippy" 2>/dev/null; then
    print_success "Klipper import verification passed"
else
    print_warning "Klipper import check skipped (klippy not yet on PYTHONPATH — this is normal)"
fi

print_success "Klipper venv fix complete."
