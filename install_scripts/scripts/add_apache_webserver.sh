#!/usr/bin/env bash
set -e

export DEBIAN_FRONTEND=noninteractive

# Source shared utilities (safe - no breaking changes)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/shared_utilities.sh" ]; then
    source "$SCRIPT_DIR/shared_utilities.sh"
else
    # Fallback to inline functions if shared file not found (maintains compatibility)
    echo "Warning: shared_utilities.sh not found, using inline functions"
fi

# Function to check and fix DPKG locks (calls dedicated script)
check_and_fix_dpkg_lock() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local fix_script="$script_dir/fix_dpkg_lock.sh"
    
    if [ -f "$fix_script" ]; then
        echo -e "\e[34m🔧 Checking and fixing DPKG locks...\e[0m"
        if bash "$fix_script"; then
            echo -e "\e[32m✅ DPKG lock check/fix completed\e[0m"
            return 0
        else
            echo -e "\e[31m❌ DPKG lock fix failed, continuing anyway...\e[0m"
            return 1
        fi
    else
        echo -e "\e[33m⚠️  fix_dpkg_lock.sh not found, proceeding without DPKG lock check\e[0m"
        return 1
    fi
}

echo ""
echo -e "\e[34m🔍 Checking Apache installation...\e[0m"
echo ""

# Check if Apache is already installed
if dpkg -s apache2 &> /dev/null; then
    echo -e "\e[32m✅ Apache is already installed.\e[0m"
else
    echo -e "\e[34m🛠️ Installing Apache...\e[0m"
    
    # Check and fix DPKG locks before proceeding
    check_and_fix_dpkg_lock
    
    if show_progress "📦 Updating package lists" "sudo apt-get update -qq >/dev/null 2>&1"; then
        if show_progress "🔄 Installing Apache2 package" "sudo apt-get install -y -qq apache2 >/dev/null 2>&1"; then
            echo -e "\e[32m✅ Apache installed successfully.\e[0m"
        else
            echo -e "\e[31m❌ Apache installation failed.\e[0m"
            exit 1
        fi
    else
        echo -e "\e[31m❌ Package update failed.\e[0m"
        exit 1
    fi
fi

echo -e "\e[34m🔧 Checking Apache service status...\e[0m"

# Enable and start Apache service if not running
if ! systemctl is-active --quiet apache2; then
    if show_progress "🚀 Starting and enabling Apache service" "sudo systemctl enable apache2 >/dev/null 2>&1 && sudo systemctl start apache2 >/dev/null 2>&1"; then
        echo -e "\e[32m✅ Apache service started successfully.\e[0m"
    else
        echo -e "\e[31m❌ Failed to start Apache service.\e[0m"
        exit 1
    fi
else
    echo -e "\e[32m✅ Apache service is already running.\e[0m"
fi

echo -e "\e[34m🛡️ Configuring firewall...\e[0m"

# Allow Apache through firewall if UFW is active
if command -v ufw &> /dev/null && sudo ufw status | grep -q "Status: active"; then
    if sudo ufw status numbered | grep -qE "^.*ALLOW.*(Apache|80|443)"; then
        echo -e "\e[32m✅ Apache is already allowed through UFW.\e[0m"
    else
        echo -e "\e[34m🔥 Allowing Apache through UFW...\e[0m"
        sudo ufw allow 'Apache' >/dev/null 2>&1
        echo -e "\e[32m✅ Apache allowed through firewall.\e[0m"
    fi
else
    echo -e "\e[33m⚠️ UFW not active or not installed. Skipping firewall configuration.\e[0m"
fi

echo -e "\e[34m🧪 Testing Apache configuration...\e[0m"

# Test Apache configuration
if sudo apachectl configtest &> /dev/null; then
    echo -e "\e[32m✅ Apache configuration is valid.\e[0m"
else
    echo -e "\e[33m⚠️ Apache configuration test failed. Please check manually.\e[0m"
fi

echo -e "\e[34m📁 Setting up web directory...\e[0m"

# Create /var/www folder and set permissions if needed
if [ ! -d "/var/www" ]; then
    sudo mkdir -p /var/www >/dev/null 2>&1
    sudo chmod 755 /var/www >/dev/null 2>&1
    echo -e "\e[32m✅ Apache www folder created with proper permissions.\e[0m"
elif [ "$(stat -c %a /var/www)" != "755" ]; then
    sudo chmod 755 /var/www >/dev/null 2>&1
    echo -e "\e[32m✅ Apache www folder permissions updated.\e[0m"
else
    echo -e "\e[32m✅ Apache www folder already exists with correct permissions.\e[0m"
fi

echo ""
echo -e "\e[32m✅ Apache installation and configuration complete\e[0m"
echo ""