#!/bin/bash

set -u

# Suppress confirmation prompts
export DEBIAN_FRONTEND=noninteractive

if [ "$(id -u)" -ne 0 ]; then
    echo -e "\e[31m❌ This script must run as root (use sudo).\e[0m"
    exit 1
fi

iptables_ok() {
    iptables --version >/dev/null 2>&1 && ip6tables --version >/dev/null 2>&1
}

set_iptables_backend() {
    local backend="$1"
    local ok=0

    for bin in iptables ip6tables; do
        local target="/usr/sbin/${bin}-${backend}"
        if [ -x "$target" ]; then
            if ! update-alternatives --set "$bin" "$target" >/dev/null 2>&1; then
                ok=1
            fi
        fi
    done

    return $ok
}

repair_iptables_stack() {
    apt-get install -y -qq iptables >/dev/null 2>&1 || true

    if iptables_ok; then
        return 0
    fi

    set_iptables_backend nft || true
    if iptables_ok; then
        return 0
    fi

    set_iptables_backend legacy || true
    if iptables_ok; then
        return 0
    fi

    apt-get install -y -qq --reinstall iptables >/dev/null 2>&1 || true
    iptables_ok
}

# Install UFW if not present
if ! command -v ufw >/dev/null 2>&1; then
    echo -e "\e[33m⚠️  UFW not found. Installing...\e[0m"
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq ufw >/dev/null 2>&1
    if ! command -v ufw >/dev/null 2>&1; then
        echo -e "\e[31mError: UFW installation failed! Exiting...\e[0m"
        exit 1
    fi
    echo -e "\e[32m✅ UFW installed\e[0m"
fi

if ! iptables_ok; then
    echo -e "\e[33m⚠️  iptables stack looks unhealthy. Attempting repair...\e[0m"
    if repair_iptables_stack; then
        echo -e "\e[32m✅ iptables stack repaired\e[0m"
    else
        echo -e "\e[31mError: Unable to repair iptables stack for UFW\e[0m"
    fi
fi

# Allow SSH connections without asking for confirmation
ufw allow ssh >/dev/null 2>&1 || true

# Enable UFW without requiring user confirmation
if ufw --force enable >/dev/null 2>&1; then
    :
else
    echo -e "\e[31mError: UFW enable failed on first attempt. Retrying after service restart...\e[0m"
fi

# Verify UFW status
if ufw status | grep -q "Status: active"; then
    echo -e "\e[32m✅ UFW setup completed!\e[0m"
else
    echo -e "\e[31mError: UFW failed to start!\e[0m"
    systemctl restart ufw >/dev/null 2>&1 || true

    if ufw status | grep -q "Status: active"; then
        echo -e "\e[32m✅ UFW started successfully after restart!\e[0m"
    else
        echo -e "\e[31mCritical error: UFW is still not running. Diagnostics:\e[0m"
        iptables --version 2>/dev/null || echo "iptables: unavailable"
        ip6tables --version 2>/dev/null || echo "ip6tables: unavailable"
        update-alternatives --display iptables 2>/dev/null || true
        update-alternatives --display ip6tables 2>/dev/null || true
        ufw status verbose 2>/dev/null || true
        exit 1
    fi
fi
