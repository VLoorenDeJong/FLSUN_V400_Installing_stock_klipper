#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

if ! dpkg -s openssh-server &> /dev/null; then
    timeout 180 apt-get update -qq --fix-missing
    timeout 300 apt-get install -y -qq --no-install-recommends openssh-server
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

echo -e "\e[32m✅ SSH installation and configuration complete\e[0m"
