#!/usr/bin/env bash
set -e

export DEBIAN_FRONTEND=noninteractive

# --- Inline utility functions ---
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

print_status()  { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning() { printf "\033[33m⚠️  %s\033[0m\n" "$1"; }
print_error()   { printf "\033[31m❌ %s\033[0m\n" "$1"; }
print_header()  { printf "\n\033[36m=== %s ===\033[0m\n" "$1"; }

# --- Variables ---
readonly INSTALLER_URL="https://raw.githubusercontent.com/Guilouz/Klipper-Flsun-Speeder-Pad/main/Downloads/sp_installer2.sh"
readonly STATE_DIR="/var/lib/linuxsetups"
readonly STATE_FILE="${STATE_DIR}/flsun_speeder_pad_installer2.done"
FORCE_RUN="${FORCE_RUN_FL_SP_INSTALLER2:-0}"

# --- Validation ---
if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must run with sudo/root privileges."
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    show_progress "📦 Installing curl" "apt-get install -y -qq curl"
fi

TARGET_USER="${SUDO_USER:-}"
if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
    if id pi >/dev/null 2>&1; then
        TARGET_USER="pi"
    else
        TARGET_USER="$(whoami)"
    fi
fi

TARGET_DIR="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_SCRIPT="${TARGET_DIR}/sp_installer2.sh"

if [ -z "$TARGET_DIR" ]; then
    print_error "Could not determine home directory for user: $TARGET_USER"
    exit 1
fi

if [ ! -d "$TARGET_DIR" ]; then
    print_error "Target directory does not exist: $TARGET_DIR"
    print_warning "This script expects the Speeder Pad / pi user environment."
    exit 1
fi

if [ -f "$STATE_FILE" ] && [ "$FORCE_RUN" != "1" ]; then
    print_warning "Speeder Pad installer 2 already executed. Skipping."
    print_warning "To force rerun: sudo env FORCE_RUN_FL_SP_INSTALLER2=1 bash $0"
    exit 0
fi

# --- Main ---
print_header "Flsun Speeder Pad — sp_installer2"

# ---------------------------------------------------------
# NEW: Fallback logic for sp_installer2.sh
# ---------------------------------------------------------

# Resolve repo root relative to this script
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FALLBACK_INSTALLER="${REPO_ROOT}/install_scripts/scripts/FallbackCopiedScripts/sp_installer2.sh"

print_status "📥 Downloading sp_installer2.sh"

if curl -fsSL "$INSTALLER_URL" -o "$TARGET_SCRIPT"; then
    print_success "Downloaded to $TARGET_SCRIPT"
else
    print_warning "Remote installer unavailable, using fallback instead."
    print_status "Fallback: $FALLBACK_INSTALLER"

    if [ -f "$FALLBACK_INSTALLER" ]; then
        cp "$FALLBACK_INSTALLER" "$TARGET_SCRIPT"
        print_success "Fallback installer copied to $TARGET_SCRIPT"
    else
        print_error "Fallback installer not found at: $FALLBACK_INSTALLER"
        exit 1
    fi
fi

chmod +x "$TARGET_SCRIPT"

print_status "Running sp_installer2.sh..."
bash "$TARGET_SCRIPT"

mkdir -p "$STATE_DIR"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$STATE_FILE"

print_success "sp_installer2 completed successfully."
