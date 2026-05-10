#!/bin/bash

# Suppress confirmation prompts
export DEBIAN_FRONTEND=noninteractive

# Check if UFW is installed, else exit
if ! command -v ufw &> /dev/null; then
    echo -e "\e[31mError: UFW is not installed! Exiting...\e[0m"
    exit 1
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
