#!/usr/bin/env bash

export DEBIAN_FRONTEND=noninteractive

print_status()  { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning() { printf "\033[33m⚠️  %s\033[0m\n" "$1"; }
print_error()   { printf "\033[31m❌ %s\033[0m\n" "$1"; }
print_header()  { printf "\n\033[36m=== %s ===\033[0m\n" "$1"; }

if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must run with sudo/root privileges."
    exit 1
fi

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

# Function to check and fix DPKG locks (calls dedicated script)
check_and_fix_dpkg_lock() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local fix_script="$script_dir/fix_dpkg_lock.sh"
    
    if [ -f "$fix_script" ]; then
        print_status "Checking and fixing DPKG locks..."
        if bash "$fix_script"; then
            print_success "DPKG lock check/fix completed"
            return 0
        else
            print_error "DPKG lock fix failed, continuing anyway..."
            return 1
        fi
    else
        print_warning "fix_dpkg_lock.sh not found, proceeding without DPKG lock check"
        return 1
    fi
}

# Function to diagnose apt/dpkg system health
diagnose_apt_system() {
    print_status "Diagnosing apt/dpkg system health..."
    
    local issues_found=0
    
    # Check network connectivity to Ubuntu repositories
    print_status "Checking network connectivity..."
    if ! timeout 10 curl -s --head http://archive.ubuntu.com/ubuntu/dists/ >/dev/null 2>&1; then
        print_warning "Cannot reach Ubuntu repositories - network issue"
        ((issues_found++))
    fi
    
    # Check for corrupted dpkg status file
    if ! sudo dpkg --audit >/dev/null 2>&1; then
        print_warning "dpkg audit failed - possible corruption"
        ((issues_found++))
    fi
    
    # Check package cache integrity
    if ! sudo apt-get check >/dev/null 2>&1; then
        print_warning "apt-get check failed - dependency issues"
        ((issues_found++))
    fi
    
    # Check for held packages
    local held_packages=$(sudo apt-mark showhold | wc -l)
    if [ "$held_packages" -gt 0 ]; then
        print_warning "$held_packages packages are held"
        ((issues_found++))
    fi
    
    # Check disk space
    local available_space=$(df /var/lib/dpkg | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 100000 ]; then  # Less than ~100MB
        print_warning "Low disk space available: $(($available_space/1024))MB"
        ((issues_found++))
    fi
    
    if [ $issues_found -gt 0 ]; then
        print_warning "Found $issues_found potential issues. Attempting auto-fix..."
        
        # Try to fix common issues
        sudo apt-get clean >/dev/null 2>&1
        sudo apt-get autoclean >/dev/null 2>&1
        sudo apt-get autoremove -y >/dev/null 2>&1
        sudo dpkg --configure -a >/dev/null 2>&1
        
        print_success "Auto-fix completed"
    else
        print_success "apt/dpkg system appears healthy"
    fi
}

print_status "Installing Webmin Web Management Interface..."

# Check if Webmin is already installed and running
if timeout 10 systemctl is-active --quiet webmin 2>/dev/null; then
    print_success "Webmin is already installed and running"
    print_status "Access at: https://$(hostname -I | awk '{print $1}'):10000"
    exit 0
fi

print_status "Setting up official Webmin repository using modern GPG keys..."

# Check and fix DPKG locks before proceeding
check_and_fix_dpkg_lock

# Diagnose overall apt/dpkg system health
diagnose_apt_system

# Install dependencies
print_status "Installing required dependencies..."
if show_progress "📦 Updating package lists" "timeout 600 sudo apt-get update -qq --fix-missing" 3 600; then
    print_success "Package lists updated successfully"
else
    print_warning "apt-get update failed, trying apt update..."
    if show_progress "📦 Updating package lists (alternative method)" "timeout 600 sudo apt update -qq" 3 600; then
        print_success "Package lists updated successfully (alternative method)"
    else
        print_error "Failed to update package lists"
        # Show what went wrong
        print_warning "Debug info:"
        timeout 30 sudo apt-get update --fix-missing 2>&1 | head -20
        exit 1
    fi
fi

if show_progress "�🔧 Installing dependencies" "timeout 300 sudo apt-get install -y -qq --no-install-recommends curl gnupg software-properties-common apt-transport-https ca-certificates" 2 300; then
    print_success "Dependencies installed successfully"
else
    print_warning "Standard installation failed, trying alternative method..."
    # Try with apt instead of apt-get
    if show_progress "🔧 Installing dependencies (alternative method)" "timeout 300 sudo apt install -y -qq --no-install-recommends curl gnupg software-properties-common apt-transport-https ca-certificates" 2 300; then
        print_success "Dependencies installed successfully (alternative method)"
    else
        print_error "Failed to install dependencies"
        # Show what went wrong
        print_warning "Debug info:"
        timeout 30 sudo apt-get install -y --no-install-recommends curl gnupg software-properties-common apt-transport-https ca-certificates 2>&1 | head -20
        exit 1
    fi
fi

# Function to use official Webmin repository setup
setup_official_webmin_repo() {
    print_status "Using official Webmin repository setup script..."
    
    # Download and run the official Webmin repository setup script
    cd /tmp
    if show_progress "📥 Downloading official repository setup script" "curl --max-time 30 -fsSL https://raw.githubusercontent.com/webmin/webmin/master/webmin-setup-repo.sh -o webmin-setup-repo.sh" 2 60; then
        print_status "Downloaded official Webmin repository setup script"
        
        # Run the official setup script with force flag to avoid prompts
        if show_progress "⚙️ Configuring official Webmin repository" "bash webmin-setup-repo.sh --force"; then
            print_success "Official Webmin repository configured successfully"
            rm -f webmin-setup-repo.sh
            return 0
        else
            print_warning "Official repository setup failed, trying manual setup..."
            rm -f webmin-setup-repo.sh
            return 1
        fi
    else
        print_warning "Could not download official setup script, trying manual setup..."
        return 1
    fi
}

# Function to manually setup Webmin repository (fallback)
setup_manual_webmin_repo() {
    print_status "Setting up Webmin repository manually with modern keys..."
    
    # Clean up any existing repositories
    sudo rm -f /etc/apt/sources.list.d/webmin*.list >/dev/null 2>&1
    sudo rm -f /usr/share/keyrings/webmin*.gpg >/dev/null 2>&1
    
    # Download the modern Webmin developers key (post-DSA-1024)
    print_status "Adding modern Webmin developers GPG key..."
    if show_progress "🔑 Downloading and installing GPG key" "curl --max-time 30 -fsSL https://download.webmin.com/developers-key.asc | gpg --dearmor | sudo tee /usr/share/keyrings/webmin-developers.gpg" 2 60; then
        print_success "Modern Webmin developers key added successfully"
        
        # Add the official Webmin repository with modern newkey path
        print_status "Adding modern Webmin repository..."
        echo "deb [signed-by=/usr/share/keyrings/webmin-developers.gpg] https://download.webmin.com/download/newkey/repository stable contrib" | sudo tee /etc/apt/sources.list.d/webmin.list >/dev/null
        
        return 0
    else
        print_error "Failed to add modern Webmin developers key"
        return 1
    fi
}

# Function for Snap installation (alternative)
install_webmin_snap() {
    print_status "Attempting Snap installation as alternative..."
    if command -v snap >/dev/null 2>&1; then
        if sudo snap install webmin --classic >/dev/null 2>&1; then
            print_success "Webmin installed via Snap"
            print_status "Access Webmin at: https://$(hostname -I | awk '{print $1}'):10000"
            print_status "Login with your system username and password"
            print_warning "Note: Snap version may have slightly different features"
            return 0
        else
            print_error "Snap installation also failed"
            return 1
        fi
    else
        print_warning "Snap not available on this system"
        return 1
    fi
}

# Function for direct .deb installation (alternative)
install_webmin_deb() {
    print_status "Attempting direct .deb installation..."
    cd /tmp
    if show_progress "📥 Downloading Webmin .deb package" "wget --timeout=30 -q https://download.webmin.com/download/deb/webmin-current.deb" 2 60; then
        if show_progress "📦 Installing Webmin from .deb package" "sudo dpkg -i webmin-current.deb"; then
            # Fix any dependency issues
            timeout 120 sudo apt-get install -f -y -qq --fix-missing >/dev/null 2>&1
            rm -f webmin-current.deb
            print_success "Webmin installed via direct .deb package"
            return 0
        else
            rm -f webmin-current.deb
            print_error "Direct .deb installation failed"
            return 1
        fi
    else
        print_error "Could not download Webmin .deb package"
        return 1
    fi
}

# Try official repository setup first
if setup_official_webmin_repo; then
    print_status "Repository setup successful, proceeding with installation..."
elif setup_manual_webmin_repo; then
    print_status "Manual repository setup successful, proceeding with installation..."
else
    print_warning "Repository setup failed, trying alternative installation methods..."
    
    # Try Snap first, then direct .deb as fallbacks
    if install_webmin_snap; then
        exit 0
    elif install_webmin_deb; then
        # Skip the rest since we've already installed via .deb
        print_status "Configuring firewall for Webmin..."
        if command -v ufw &> /dev/null && sudo ufw status | grep -q "Status: active"; then
            if ! sudo ufw status numbered | grep -q "10000"; then
                sudo ufw allow 10000 >/dev/null 2>&1
            fi
        fi
        print_success "Webmin installation complete"
        print_status "Access Webmin at: https://$(hostname -I | awk '{print $1}'):10000"
        print_status "Login with your system username and password"
        exit 0
    else
        print_error "All installation methods failed"
        print_status "Manual installation options:"
        print_status "1. Download from: https://download.webmin.com/download/deb/webmin-current.deb"
        print_status "2. Try: curl -o setup-repos.sh https://raw.githubusercontent.com/webmin/webmin/master/webmin-setup-repo.sh && sudo sh setup-repos.sh"
        exit 0
    fi
fi

print_status "Updating package lists with new repository..."
if ! show_progress "📦 Updating package lists with Webmin repository" "timeout 600 sudo apt-get update -qq --fix-missing" 3 600; then
    print_warning "Package list update failed, but continuing with installation attempt..."
fi

print_status "Installing Webmin package..."
print_status "Webmin is a large package - this may take several minutes..."

# Try repository installation first with longer timeout
if show_progress "🌐 Installing Webmin from repository" "timeout 1800 sudo apt-get install -y -qq --no-install-recommends webmin" 5 1800; then
    print_success "Webmin installed successfully via repository"
    # Skip to configuration since repository installation succeeded
    print_status "Proceeding with Webmin configuration..."
else
    print_warning "Repository installation timed out or failed, trying alternative methods..."

    # Try alternative installation methods only if repository failed
    if install_webmin_snap; then
        print_success "Webmin installed via Snap"
        print_status "Proceeding with Webmin configuration..."
    elif install_webmin_deb; then
        print_success "Webmin installed via direct .deb"
        print_status "Proceeding with Webmin configuration..."
    else
        print_error "All installation methods failed"
        exit 1
    fi
fi

print_status "Configuring Webmin service..."

# Ensure Webmin service is enabled and started
if ! timeout 10 systemctl is-enabled --quiet webmin 2>/dev/null; then
    if timeout 30 sudo systemctl enable webmin >/dev/null 2>&1; then
        print_success "Webmin service enabled"
    else
        print_warning "Failed to enable Webmin service"
    fi
fi

if ! timeout 10 systemctl is-active --quiet webmin 2>/dev/null; then
    if timeout 30 sudo systemctl start webmin >/dev/null 2>&1; then
        print_success "Webmin service started"
    else
        print_warning "Failed to start Webmin service"
    fi
fi

print_status "Configuring firewall for Webmin..."

# Allow Webmin through firewall if UFW is active
if command -v ufw &> /dev/null && sudo ufw status | grep -q "Status: active"; then
    if ! sudo ufw status numbered | grep -q "10000"; then
        sudo ufw allow 10000 >/dev/null 2>&1
        print_success "Firewall rule added for Webmin (port 10000)"
    fi
fi

print_status "Verifying Webmin installation..."

# Give Webmin a moment to start
sleep 2

# Verify Webmin is running
if timeout 10 systemctl is-active --quiet webmin 2>/dev/null; then
    print_success "Webmin installation and configuration complete"
    
    # Configure dark mode as default
    print_status "Configuring Webmin dark mode..."
    if [ -d "/etc/webmin" ]; then
        # Set dark theme in global config
        echo "theme=authentic-theme" | sudo tee -a /etc/webmin/config >/dev/null 2>&1
        echo "preroot=authentic-theme" | sudo tee -a /etc/webmin/config >/dev/null 2>&1
        
        # Create/update the authentic theme config for dark mode
        sudo mkdir -p /etc/webmin/authentic-theme >/dev/null 2>&1
        echo "settings_background_color=dark" | sudo tee /etc/webmin/authentic-theme/settings >/dev/null 2>&1
        echo "settings_theme_mode=dark" | sudo tee -a /etc/webmin/authentic-theme/settings >/dev/null 2>&1
        echo "settings_side_slider_enabled=1" | sudo tee -a /etc/webmin/authentic-theme/settings >/dev/null 2>&1
        
        # Restart Webmin to apply theme changes
        print_status "Applying theme changes..."
        if timeout 30 sudo systemctl restart webmin >/dev/null 2>&1; then
            sleep 2
            
            if timeout 10 systemctl is-active --quiet webmin 2>/dev/null; then
                print_success "Dark mode configured successfully"
            else
                print_warning "Theme configuration may need manual adjustment"
            fi
        else
            print_warning "Failed to restart Webmin for theme changes"
        fi
    fi
    
    print_status "Access Webmin at: https://$(hostname -I | awk '{print $1}'):10000"
    print_status "Login with your system username and password"
    print_status "Accept the self-signed SSL certificate when prompted"
    print_status "Dark mode has been pre-configured"
    print_status "Configure additional settings through the web interface"
else
    print_warning "Webmin service may need manual start: sudo systemctl start webmin"
    print_status "Once started, access at: https://$(hostname -I | awk '{print $1}'):10000"
fi
