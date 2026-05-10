#!/bin/bash

# Suppress confirmation prompts
export DEBIAN_FRONTEND=noninteractive

# Install UFW if not present
if ! command -v ufw &> /dev/null; then
    echo -e "\e[33m⚠️  UFW not found. Installing...\e[0m"
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq ufw >/dev/null 2>&1
    if ! command -v ufw &> /dev/null; then
        echo -e "\e[31mError: UFW installation failed! Exiting...\e[0m"
        exit 1
    fi
    echo -e "\e[32m✅ UFW installed\e[0m"
fi

# Allow SSH connections without asking for confirmation
sudo ufw allow ssh > /dev/null

# Enable UFW without requiring user confirmation
echo "y" | sudo ufw enable > /dev/null

# Verify UFW status
if sudo ufw status | grep -q "Status: active"; then
    echo -e "\e[32m✅ UFW setup completed!\e[0m"
else
    echo -e "\e[31mError: UFW failed to start!\e[0m"
    sudo systemctl restart ufw

    # Re-check status after restart
    if sudo ufw status | grep -q "Status: active"; then
        echo -e "\e[32m✅ UFW started successfully after restart!\e[0m"
    else
        echo -e "\e[31mCritical error: UFW is still not running. Please check manually.\e[0m"
        exit 1
    fi
fi
