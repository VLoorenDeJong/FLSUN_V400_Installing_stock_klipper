#!/bin/bash

set -u

# Suppress confirmation prompts
export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/sbin:/sbin:/usr/bin:/bin:$PATH"

IPTABLES_BIN="/usr/sbin/iptables"
IP6TABLES_BIN="/usr/sbin/ip6tables"
UFW_BIN="/usr/sbin/ufw"

if [ "$(id -u)" -ne 0 ]; then
    echo -e "\e[31m❌ This script must run as root (use sudo).\e[0m"
    exit 1
fi

iptables_ok() {
    "$IPTABLES_BIN" --version >/dev/null 2>&1 && "$IP6TABLES_BIN" --version >/dev/null 2>&1
}

iptables_filter_works() {
    "$IPTABLES_BIN" -t filter -S >/dev/null 2>&1 && "$IP6TABLES_BIN" -t filter -S >/dev/null 2>&1
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

    if iptables_ok && iptables_filter_works; then
        return 0
    fi

    set_iptables_backend nft || true
    if iptables_ok && iptables_filter_works; then
        return 0
    fi

    # Some images still default to legacy; force nft if available as final preference.
    if [ -x /usr/sbin/iptables-nft ] && [ -x /usr/sbin/ip6tables-nft ]; then
        update-alternatives --set iptables /usr/sbin/iptables-nft >/dev/null 2>&1 || true
        update-alternatives --set ip6tables /usr/sbin/ip6tables-nft >/dev/null 2>&1 || true
    fi
    if iptables_ok && iptables_filter_works; then
        return 0
    fi

    set_iptables_backend legacy || true
    if iptables_ok && iptables_filter_works; then
        return 0
    fi

    apt-get install -y -qq --reinstall iptables >/dev/null 2>&1 || true
    iptables_ok && iptables_filter_works
}

force_nft_backend() {
    local changed=0
    if [ -x /usr/sbin/iptables-nft ]; then
        update-alternatives --set iptables /usr/sbin/iptables-nft >/dev/null 2>&1 && changed=1 || true
    fi
    if [ -x /usr/sbin/ip6tables-nft ]; then
        update-alternatives --set ip6tables /usr/sbin/ip6tables-nft >/dev/null 2>&1 && changed=1 || true
    fi
    return $changed
}

# Install UFW if not present
if ! command -v "$UFW_BIN" >/dev/null 2>&1; then
    echo -e "\e[33m⚠️  UFW not found. Installing...\e[0m"
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq ufw >/dev/null 2>&1
    if ! command -v "$UFW_BIN" >/dev/null 2>&1; then
        echo -e "\e[31mError: UFW installation failed! Exiting...\e[0m"
        exit 1
    fi
    echo -e "\e[32m✅ UFW installed\e[0m"
fi

if ! iptables_ok || ! iptables_filter_works; then
    echo -e "\e[33m⚠️  iptables stack looks unhealthy. Attempting repair...\e[0m"
    if repair_iptables_stack; then
        echo -e "\e[32m✅ iptables stack repaired\e[0m"
    else
        echo -e "\e[31mError: Unable to repair iptables stack for UFW\e[0m"
    fi
fi

# On kernels without legacy tables, nft is required for UFW to operate.
force_nft_backend >/dev/null 2>&1 || true

# Allow SSH connections without asking for confirmation
"$UFW_BIN" allow ssh >/dev/null 2>&1 || true

# Enable UFW without requiring user confirmation
if "$UFW_BIN" --force enable >/dev/null 2>&1; then
    :
else
    echo -e "\e[31mError: UFW enable failed on first attempt. Retrying after service restart...\e[0m"
fi

# Verify UFW status
if "$UFW_BIN" status | grep -q "Status: active"; then
    echo -e "\e[32m✅ UFW setup completed!\e[0m"
else
    echo -e "\e[31mError: UFW failed to start!\e[0m"
    # Automatic failover: force nft and retry once before giving up.
    force_nft_backend >/dev/null 2>&1 || true
    "$UFW_BIN" --force reset >/dev/null 2>&1 || true
    "$UFW_BIN" allow ssh >/dev/null 2>&1 || true
    "$UFW_BIN" --force enable >/dev/null 2>&1 || true
    systemctl restart ufw >/dev/null 2>&1 || true

    if "$UFW_BIN" status | grep -q "Status: active"; then
        echo -e "\e[32m✅ UFW started successfully after restart!\e[0m"
    else
        echo -e "\e[31mCritical error: UFW is still not running. Diagnostics:\e[0m"
        "$IPTABLES_BIN" --version 2>/dev/null || echo "iptables: unavailable"
        "$IP6TABLES_BIN" --version 2>/dev/null || echo "ip6tables: unavailable"
        update-alternatives --display iptables 2>/dev/null || true
        update-alternatives --display ip6tables 2>/dev/null || true
        "$UFW_BIN" status verbose 2>/dev/null || true
        echo -e "\e[33m⚠️  Continuing without an active UFW firewall so the installer can finish.\e[0m"
        echo -e "\e[33m💡 UFW can be revisited later if the kernel/firewall stack is fixed.\e[0m"
        exit 0
    fi
fi
