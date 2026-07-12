#!/bin/bash

print_status() { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_error()  { printf "\033[31m❌ %s\033[0m\n" "$1"; }

if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must run as root. Use: sudo bash $0"
    exit 1
fi

# Print current IP addresses so the user knows how to reconnect via SSH after reboot
echo ""
echo -e "\e[36m╔══════════════════════════════════════════════════════════════╗\e[0m"
echo -e "\e[36m║              REBOOT IN 15 SECONDS — READ THIS               ║\e[0m"
echo -e "\e[36m╚══════════════════════════════════════════════════════════════╝\e[0m"
echo ""
echo -e "\e[33m⚠️  After reboot, the FLSUN screen UI may not start — this is EXPECTED.\e[0m"
echo -e "\e[33m   Phase 1 upgrades the OS which can disrupt the display software.\e[0m"
echo -e "\e[33m   Phase 2 will install a fresh Klipper stack with a new UI.\e[0m"
echo ""
echo -e "\e[32m✅ SSH is enabled — reconnect via terminal:\e[0m"
echo ""

# Show all non-loopback IPv4 addresses
FOUND_IP=0
while IFS= read -r line; do
    ip=$(echo "$line" | awk '{print $2}' | cut -d/ -f1)
    iface=$(echo "$line" | awk '{print $NF}')
    echo -e "     \e[32mssh flsun@${ip}\e[0m    (interface: ${iface})"
    FOUND_IP=1
done < <(ip -4 addr show scope global | awk '/inet /{print $2, $(NF)}')

if [[ "$FOUND_IP" -eq 0 ]]; then
    echo -e "     \e[33mCould not detect IP. Check your router's DHCP table after reboot.\e[0m"
fi

echo ""
echo -e "\e[33m   After reconnecting via SSH, run Phase 2:\e[0m"
echo -e "     cd $(cd "$(dirname "$0")/.." && pwd)"
echo -e "     sudo bash start_install.sh"
echo ""

print_status "Waiting 15 seconds before rebooting..."
sleep 15
print_status "Rebooting the system..."
systemctl --no-wall reboot 2>/dev/null || reboot
