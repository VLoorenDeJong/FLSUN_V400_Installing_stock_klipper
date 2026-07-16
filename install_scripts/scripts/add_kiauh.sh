#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

print_status()  { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_error()   { printf "\033[31m❌ %s\033[0m\n" "$1"; }

# Inline show_progress function (always used)
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

KIAUH_REPO_URL="https://github.com/dw-0/kiauh.git"
FORCE_REINSTALL="${FORCE_REINSTALL_KIAUH:-0}"
# Pin to a specific tag/branch/commit by setting KIAUH_TAG.
# Empty = latest master/main. Example: KIAUH_TAG=v5.3.0
KIAUH_TAG="${KIAUH_TAG:-}"

if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must run with sudo/root privileges."
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
    print_error "Could not determine home directory for user: $TARGET_USER"
    exit 1
fi

KIAUH_DIR="${TARGET_HOME}/kiauh"

if ! command -v git >/dev/null 2>&1; then
    show_progress "📦 Installing git" "apt-get update -qq && apt-get install -y -qq git" 3 600
fi

# If KIAUH already exists and this is not a forced reinstall, do a safe update.
if [ -d "$KIAUH_DIR/.git" ] && [ "$FORCE_REINSTALL" != "1" ]; then
    print_status "Existing KIAUH clone found, updating instead of reinstalling"
    git -C "$KIAUH_DIR" fetch --all --prune
    if [ -n "$KIAUH_TAG" ]; then
        print_status "Checking out KIAUH tag/version: $KIAUH_TAG"
        git -C "$KIAUH_DIR" checkout "$KIAUH_TAG"
    else
        git -C "$KIAUH_DIR" reset --hard origin/master || git -C "$KIAUH_DIR" reset --hard origin/main
    fi
    git -C "$KIAUH_DIR" clean -fd
    chown -R "$TARGET_USER":"$TARGET_USER" "$KIAUH_DIR"
    print_success "KIAUH updated successfully"
    exit 0
fi

print_status "Removing existing KIAUH directory: $KIAUH_DIR"
rm -rf "$KIAUH_DIR"

print_status "Cloning KIAUH into: $KIAUH_DIR"
git clone "$KIAUH_REPO_URL" "$KIAUH_DIR"

if [ -n "$KIAUH_TAG" ]; then
    print_status "Checking out KIAUH tag/version: $KIAUH_TAG"
    git -C "$KIAUH_DIR" checkout "$KIAUH_TAG"
fi

print_status "Fixing ownership for user: $TARGET_USER"
chown -R "$TARGET_USER":"$TARGET_USER" "$KIAUH_DIR"

print_success "KIAUH re-cloned successfully"
