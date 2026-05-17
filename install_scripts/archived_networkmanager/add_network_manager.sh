#!/usr/bin/env bash
set -e

export DEBIAN_FRONTEND=noninteractive

# --- User detection ---
if [ -n "$SUDO_USER" ]; then
	ACTUAL_USER="$SUDO_USER"
	ACTUAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
	ACTUAL_USER=$(whoami)
	ACTUAL_HOME="$HOME"
fi

# --- Inline utility functions ---
show_progress() {
	local message="$1"
	local command="$2"
	local interval="${3:-3}"
	local timeout="${4:-300}"
	printf "\033[34m%s\033[0m\n" "$message"
	eval "$command" &
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
			return 1
		fi
	done
	wait $cmd_pid 2>/dev/null
	local exit_code=$?
	printf "\n"
	return $exit_code
}

print_status()  { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning() { printf "\033[33m⚠️  %s\033[0m\n" "$1"; }
print_error()   { printf "\033[31m❌ %s\033[0m\n" "$1"; }
print_header()  { printf "\n\033[36m=== %s ===\033[0m\n" "$1"; }

# --- Variables ---
readonly NM_CONF_DIR="/etc/NetworkManager/conf.d"
readonly NM_CONF_FILE="${NM_CONF_DIR}/any-user.conf"

# --- Main ---
print_header "Install and Configure NetworkManager"
print_warning "OPTIONAL STEP: NetworkManager is not required on all systems."
print_warning "Installing it disables dhcpcd (the default DHCP client)."
print_warning "This can cause network issues such as losing your internet connection"
