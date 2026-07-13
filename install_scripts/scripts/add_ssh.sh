#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

print_status()  { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning() { printf "\033[33m⚠️  %s\033[0m\n" "$1"; }
print_error()   { printf "\033[31m❌ %s\033[0m\n" "$1"; }

# Inline show_progress function (always used)
show_progress() {
    local message="$1"
    local command="$2"
    local interval="${3:-5}"
    local timeout="${4:-600}"
    printf "\033[34m%s\033[0m\n" "$message"
    eval "$command" &
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
            return 1
        fi
    done
    wait $cmd_pid 2>/dev/null
    local exit_code=$?
    printf "\n"
    return $exit_code
}

if ! dpkg -s openssh-server &> /dev/null; then
    show_progress "📦 Updating package lists" "apt-get update -qq --fix-missing" 3 180
    show_progress "🔐 Installing openssh-server" "apt-get install -y -qq --no-install-recommends openssh-server" 3 300
fi

if ! systemctl is-active --quiet ssh; then
    systemctl enable ssh >/dev/null 2>&1
    systemctl start ssh >/dev/null 2>&1
fi

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    if ! ufw status numbered 2>/dev/null | grep -qE "^.*ALLOW.*22"; then
        ufw allow 22/tcp >/dev/null 2>&1
    fi
fi

print_success "SSH installation and configuration complete"
