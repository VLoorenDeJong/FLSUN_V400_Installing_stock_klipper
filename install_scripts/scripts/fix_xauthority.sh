#!/bin/bash

print_status()  { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning() { printf "\033[33m⚠️  %s\033[0m\n" "$1"; }
print_error()   { printf "\033[31m❌ %s\033[0m\n" "$1"; }

print_status "Checking for Xauthority file issues..."

# Function to check if Xauthority issue exists
check_xauth_issue() {
    # Check if xauth command fails due to missing .Xauthority file
    if command -v xauth >/dev/null 2>&1; then
        if xauth list >/dev/null 2>&1; then
            return 1  # No issue
        else
            # Check if the error is specifically about missing .Xauthority file
            local error_output=$(xauth list 2>&1)
            if echo "$error_output" | grep -q "does not exist"; then
                return 0  # Issue exists
            else
                return 1  # Different issue or no issue
            fi
        fi
    else
        print_warning "xauth command not found. Skipping Xauthority check."
        return 1  # No xauth, so no issue to fix
    fi
}

# Test for Xauthority issue
if ! check_xauth_issue; then
    print_success "No Xauthority file issues detected."
    exit 0
else
    print_warning "Xauthority file issue detected. Attempting to fix..."
fi

# Get the current user information
CURRENT_USER="$(whoami)"
USER_HOME="$HOME"

# Fallback if HOME is not set
if [ -z "$USER_HOME" ]; then
    USER_HOME="/home/$CURRENT_USER"
fi

# If running as root, try to detect the actual user
if [ "$CURRENT_USER" = "root" ] && [ -n "$SUDO_USER" ]; then
    ACTUAL_USER="$SUDO_USER"
    USER_HOME="/home/$ACTUAL_USER"
    print_warning "Running as root, detected actual user: $ACTUAL_USER"
else
    ACTUAL_USER="$CURRENT_USER"
fi

XAUTH_FILE="$USER_HOME/.Xauthority"

print_status "Step 1: Checking Xauthority file location..."
print_warning "User: $ACTUAL_USER"
print_warning "Home directory: $USER_HOME"
print_warning "Xauthority file: $XAUTH_FILE"

# Step 1: Remove corrupted or problematic Xauthority file if it exists but is corrupted
if [ -f "$XAUTH_FILE" ]; then
    print_warning "Xauthority file exists but may be corrupted. Backing up and removing..."

    # Create backup with timestamp
    BACKUP_FILE="${XAUTH_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

    if cp "$XAUTH_FILE" "$BACKUP_FILE" 2>/dev/null; then
        print_success "Backup created successfully:"
        printf "\033[36m   📁 %s\033[0m\n" "$BACKUP_FILE"

        # Create a log file for the user to reference later
        LOG_FILE="$USER_HOME/.xauthority_fix.log"
        {
            echo "=============================================="
            echo "Xauthority Fix Log - $(date)"
            echo "=============================================="
            echo "User: $ACTUAL_USER"
            echo "Original file: $XAUTH_FILE"
            echo "Backup created: $BACKUP_FILE"
            echo "Fix applied: $(date)"
            echo ""
            echo "To restore backup if needed:"
            echo "cp '$BACKUP_FILE' '$XAUTH_FILE'"
            echo "=============================================="
            echo ""
        } >> "$LOG_FILE"

        print_success "Log saved to: $LOG_FILE"
    else
        print_error "Failed to create backup, but continuing with fix..."
    fi

    rm -f "$XAUTH_FILE"
else
    print_warning "Xauthority file does not exist at $XAUTH_FILE"
fi

# Step 2: Create new Xauthority file
print_status "Step 2: Creating new Xauthority file..."

# Create the file with proper permissions
touch "$XAUTH_FILE"
chmod 600 "$XAUTH_FILE"

# Ensure correct ownership
if [ "$CURRENT_USER" = "root" ] && [ -n "$ACTUAL_USER" ]; then
    # Running as root, set ownership to actual user
    chown "$ACTUAL_USER:$(id -gn "$ACTUAL_USER" 2>/dev/null || echo "$ACTUAL_USER")" "$XAUTH_FILE" 2>/dev/null || true
    print_success "Set ownership to $ACTUAL_USER"
else
    # Running as normal user, ensure correct ownership
    if [ "$(stat -c %U "$XAUTH_FILE" 2>/dev/null)" != "$ACTUAL_USER" ]; then
        chown "$ACTUAL_USER:$(id -gn "$ACTUAL_USER" 2>/dev/null || id -gn)" "$XAUTH_FILE" 2>/dev/null || true
    fi
fi

print_success "Created new Xauthority file: $XAUTH_FILE"

# Update log file with completion status
if [ -f "$USER_HOME/.xauthority_fix.log" ]; then
    {
        echo "Fix completed: $(date)"
        echo "New file created: $XAUTH_FILE"
        echo "File permissions: 600 (read/write for owner only)"
        echo "File owner: $ACTUAL_USER"
        echo ""
    } >> "$USER_HOME/.xauthority_fix.log"
fi

# Step 3: Set up basic X11 authorization if DISPLAY is set
if [ -n "$DISPLAY" ]; then
    print_status "Step 3: Setting up X11 authorization for DISPLAY=$DISPLAY..."

    # Try to add current display
    if xauth add "$DISPLAY" . "$(mcookie)" 2>/dev/null; then
        print_success "Added X11 authorization for current display."
    else
        print_warning "Could not add X11 authorization automatically."
    fi
else
    print_warning "DISPLAY not set. Skipping X11 authorization setup."
fi

# Step 4: Test if fix worked
print_status "Step 4: Testing if fix worked..."
if xauth list >/dev/null 2>&1; then
    print_success "Success! Xauthority file issue has been resolved."
    print_success "X11 applications should now work properly."
else
    # Check what the error is now
    error_output=$(xauth list 2>&1)
    if echo "$error_output" | grep -q "does not exist"; then
        print_error "Xauthority file issue persists."
        exit 1
    else
        print_success "Xauthority file created successfully."
        print_warning "Note: X11 authorization may need to be set up when you start a graphical session."
    fi
fi

print_status "Additional notes:"
print_warning "   - User: $ACTUAL_USER"
print_warning "   - If you're using SSH X11 forwarding, reconnect your SSH session"
print_warning "   - For graphical applications, you may need to restart your desktop session"
print_warning "   - File location: $XAUTH_FILE"

# Show log file location for future reference
if [ -f "$USER_HOME/.xauthority_fix.log" ]; then
    print_success "For future reference, backup and fix details saved to:"
    printf "\033[36m   📁 %s\033[0m\n" "$USER_HOME/.xauthority_fix.log"
    print_warning "   - View with: cat ~/.xauthority_fix.log"
    print_warning "   - This log persists after reboot"
fi
