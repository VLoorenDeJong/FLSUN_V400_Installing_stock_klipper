#!/bin/bash
# ============================================
# Install / Repair Python 3.10 Environment
# Speeder Pad – Ubuntu 22.04
# ============================================

echo "--------------------------------------------"
echo "📦 Installing Python 3.10 environment"
echo "--------------------------------------------"

# Remove broken Python 3.9 remnants
echo "🧹 Removing old Python 3.9 packages (if present)..."
sudo apt purge -y python3.9 python3.9-minimal python3.9-venv python3.9-distutils python3.9-lib2to3 python3.9-dev >/dev/null 2>&1

# Remove leftover directories
sudo rm -rf /usr/lib/python3.9 >/dev/null 2>&1
sudo rm -rf /usr/local/lib/python3.9 >/dev/null 2>&1

echo "✔ Python 3.9 removed (or was not present)"

# Install Python 3.10 core packages
echo "📦 Installing Python 3.10 core packages..."
sudo apt update -y
sudo apt install -y python3 python3.10 python3.10-venv python3.10-distutils python3.10-full python3-pip python3-apt python3-distutils

if [ $? -ne 0 ]; then
    echo "❌ Failed to install Python 3.10 packages"
    exit 1
fi

echo "✔ Python 3.10 installed"

# Fix python3 symlink
echo "🔧 Repairing /usr/bin/python3 symlink..."
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1 >/dev/null 2>&1
sudo update-alternatives --set python3 /usr/bin/python3.10 >/dev/null 2>&1

# Verify python3
PYVER=$(python3 --version 2>/dev/null)
if [[ "$PYVER" != *"3.10"* ]]; then
    echo "❌ python3 is not pointing to Python 3.10"
    echo "   Current version: $PYVER"
    exit 1
fi

echo "✔ python3 now points to Python 3.10 ($PYVER)"

# Test venv creation
echo "🧪 Testing virtual environment creation..."
sudo rm -rf /tmp/python_test_env >/dev/null 2>&1
python3 -m venv /tmp/python_test_env >/dev/null 2>&1

if [ ! -f "/tmp/python_test_env/bin/activate" ]; then
    echo "❌ Virtual environment creation failed"
    echo "   Python installation is still broken"
    exit 1
fi

echo "✔ Virtual environment creation works"

# Cleanup test venv
sudo rm -rf /tmp/python_test_env >/dev/null 2>&1

echo "--------------------------------------------"
echo "✅ Python 3.10 environment installed and verified"
echo "--------------------------------------------"
exit 0
