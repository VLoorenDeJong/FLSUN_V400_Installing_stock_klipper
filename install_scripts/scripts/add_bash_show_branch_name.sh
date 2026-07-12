#!/usr/bin/env bash
set -e

print_status() { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning() { printf "\033[33m⚠️ %s\033[0m\n" "$1"; }
print_error() { printf "\033[31m❌ %s\033[0m\n" "$1"; }

# Get the actual user who called sudo (not root)
if [ -n "$SUDO_USER" ]; then
    ACTUAL_USER="$SUDO_USER"
    ACTUAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    ACTUAL_USER=$(whoami)
    ACTUAL_HOME="$HOME"
fi

print_status "Setting up Git branch display for user: $ACTUAL_USER"
print_status "User home directory: $ACTUAL_HOME"

# Function: Get Git branch
get_git_branch() {
    local branch
    if branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null); then
        echo "$branch"
    else
        echo ""
    fi
}

# Function: Get OS ID and Version separately
get_os_info() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID $VERSION_ID"
    else
        echo "unknown unknown"
    fi
}


# --- Prompt logic to be appended to ~/.bashrc ---
PROMPT_BRANCH_FUNC='get_git_branch() {
    local branch
    if branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null); then
        echo "$branch"
    else
        echo ""
    fi
}
update_prompt() {
    local branch=$(get_git_branch)
    if [[ -n "$branch" ]]; then
        branch_display="\[\e[35m\]${branch}\[\e[0m\] → "
    else
        branch_display=""
    fi
    PS1="\[\e[1;32m\]\u\[\e[0m\]:${branch_display}\[\e[1;34m\]\W\[\e[0m\] \$ "
}
export PROMPT_COMMAND=update_prompt
if [[ -n "$PS1" ]]; then update_prompt; fi'

# Idempotently add to user's ~/.bashrc
USER_BASHRC="$ACTUAL_HOME/.bashrc"

# Enhanced detection - check for multiple indicators
HAS_GIT_PROMPT=false

if [ -f "$USER_BASHRC" ]; then
    # Check for any of our git prompt indicators
    if grep -q "PROMPT_COMMAND=update_prompt" "$USER_BASHRC" 2>/dev/null || \
       grep -q "Git branch in prompt" "$USER_BASHRC" 2>/dev/null || \
       grep -q "get_git_branch()" "$USER_BASHRC" 2>/dev/null; then
        HAS_GIT_PROMPT=true
    fi
fi

if [ "$HAS_GIT_PROMPT" = false ]; then
    print_status "Adding Git branch prompt to $USER_BASHRC"
    echo "# --- Git branch in prompt ---" >> "$USER_BASHRC"
    echo "$PROMPT_BRANCH_FUNC" >> "$USER_BASHRC"

    # Set proper ownership for the bashrc file
    chown "$ACTUAL_USER:$(id -gn "$ACTUAL_USER")" "$USER_BASHRC" 2>/dev/null || true

    print_success "Git branch prompt added to user's bashrc."
else
    print_warning "Git branch prompt already exists in user's bashrc."

    # Check if the existing prompt has the display issue and fix it
    if grep -q "PS1=.*\[\\\e\[1;32m\].*\[\\\e\[0m\].*\[\\\e\[1;34m\].*\[\\\e\[0m\].*branch_display.*\[\\\e\[0m\]" "$USER_BASHRC" 2>/dev/null; then
        print_status "Detected broken prompt formatting, fixing..."

        # Create a backup
        cp "$USER_BASHRC" "$USER_BASHRC.backup.$(date +%Y%m%d_%H%M%S)"

        # Remove the old broken prompt section
        sed -i '/# --- Git branch in prompt ---/,/^if \[\[ -n "\$PS1" \]\]; then update_prompt; fi$/d' "$USER_BASHRC"

        # Add the fixed version
        echo "# --- Git branch in prompt ---" >> "$USER_BASHRC"
        echo "$PROMPT_BRANCH_FUNC" >> "$USER_BASHRC"

        # Set proper ownership
        chown "$ACTUAL_USER:$(id -gn "$ACTUAL_USER")" "$USER_BASHRC" 2>/dev/null || true

        print_success "Fixed broken Git branch prompt formatting."
    else
        print_success "No changes needed - Git branch prompt is already configured."
    fi
fi

# Test if we can source the bashrc (only if running interactively as the actual user and changes were made)
if [[ -n "$PS1" ]] && [[ "$(whoami)" == "$ACTUAL_USER" ]] && [ "$HAS_GIT_PROMPT" = false ]; then
    print_status "Sourcing bashrc for current session..."
    source "$USER_BASHRC"
fi

if [ "$HAS_GIT_PROMPT" = false ]; then
    print_success "Bash prompt will now show Git branch in new terminals for user: $ACTUAL_USER"
    print_warning "Open a new terminal or run 'source ~/.bashrc' to see the changes"
    print_warning "Navigate to a Git repository folder to see the branch name in the prompt"
else
    print_success "Git branch prompt is already configured for user: $ACTUAL_USER"
    print_warning "If you had display issues, they should now be fixed"
    print_warning "Run 'source ~/.bashrc' or open a new terminal to apply any fixes"
    print_warning "Navigate to a Git repository folder to see the branch name in the prompt"
fi
