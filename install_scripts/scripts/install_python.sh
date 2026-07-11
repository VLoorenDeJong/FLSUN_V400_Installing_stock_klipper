#!/bin/bash
# ============================================
# Install / Repair Python 3.10 Environment
# Speeder Pad – Ubuntu 22.04
# ============================================

# Function to print status messages
print_status() {
    printf "\033[34m🔧 %s\033[0m\n" "$1"
}

# Function to print success messages
print_success() {
    printf "\033[32m✅ %s\033[0m\n" "$1"
}

# Function to print warnings
print_warning() {
    printf "\033[33m⚠️ %s\033[0m\n" "$1"
}

# Function to print errors
print_error() {
    printf "\033[31m❌ %s\033[0m\n" "$1"
}

echo "--------------------------------------------"
print_status "Installing Python 3.10 environment"
echo "--------------------------------------------"

print_status "Removing old Python 3.9 packages..."
sudo apt purge -y python3.9 python3.9-minimal python3.9-venv python3.9-distutils python3.9-lib2to3 python3.9-dev >/dev/null 2>&1
sudo rm -rf /usr/lib/python3.9 >/dev/null 2>&1
sudo rm -rf /usr/local/lib/python3.9 >/dev/null 2>&1
print_success "Python 3.9 removed (or was not present)"

print_status "Updating package lists..."
sudo apt update -y >/dev/null 2>&1
print_success "Package lists updated"

print_status "Installing Python 3.10 packages..."
sudo apt install -y python3 python3.10 python3.10-venv python3.10-distutils python3.10-full python3-pip python3-apt python3-distutils >/dev/null 2>&1
if [ $? -ne 0 ]; then
    print_error "Failed to install Python 3.10 packages"
    exit 1
fi
print_success "Python 3.10 installed"

print_status "Repairing python3 symlink..."
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1 >/dev/null 2>&1
sudo update-alternatives --set python3 /usr/bin/python3.10 >/dev/null 2>&1
print_success "python3 symlink repaired"

PYVER=$(python3 --version 2>/dev/null)
if [[ "$PYVER" != *"3.10"* ]]; then
    print_error "python3 is not pointing to Python 3.10 (current: $PYVER)"
    exit 1
fi
print_success "python3 now points to Python 3.10 ($PYVER)"

print_status "Testing virtual environment creation..."
sudo rm -rf /tmp/python_test_env >/dev/null 2>&1
python3 -m venv /tmp/python_test_env >/dev/null 2>&1

if [ ! -f "/tmp/python_test_env/bin/activate" ]; then
    print_error "Virtual environment creation failed — Python installation still broken"
    exit 1
fi

print_success "Virtual environment creation works"
sudo rm -rf /tmp/python_test_env >/dev/null 2>&1

echo "--------------------------------------------"
print_success "Python 3.10 environment installed and verified"
echo "--------------------------------------------"

exit 0
