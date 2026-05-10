#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

if ! dpkg -s openssh-server &> /dev/null; then
    timeout 180 sudo apt-get update -qq --fix-missing
    timeout 300 sudo apt-get install -y -qq --no-install-recommends openssh-server
fi

if ! systemctl is-active --quiet ssh; then
    sudo systemctl enable ssh >/dev/null 2>&1
    sudo systemctl start ssh >/dev/null 2>&1
fi

if command -v ufw &> /dev/null && sudo ufw status | grep -q "Status: active"; then
    if ! sudo ufw status numbered | grep -qE "^.*ALLOW.*22"; then
        echo "y" | sudo ufw allow 22/tcp > /dev/null
    fi
fi

echo -e "\e[32m✅ SSH installation and configuration complete\e[0m"
