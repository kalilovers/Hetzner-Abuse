#!/bin/bash

# Exit on error
set -e

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check root privileges
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log "Error: This script must be run as root"
        exit 1
    fi
}

# Install required packages
install_packages() {
    log "Installing required packages..."
    DEBIAN_FRONTEND=noninteractive apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y needrestart iptables iptables-persistent curl
}

# Configure system settings
configure_system() {
    log "Configuring system settings..."
    
    # Configure needrestart
    sed -i 's/^#\$nrconf{restart} =.*/$nrconf{restart} = '\''a'\'';/' /etc/needrestart/needrestart.conf
    
    # Configure dpkg
    echo 'DPkg::Options { "--force-confdef"; "--force-confold"; }' > /etc/apt/apt.conf.d/99mydebconf
    
    # Configure unattended upgrades
    sed -i 's/^\/\/Unattended-Upgrade::Automatic-Reboot/Unattended-Upgrade::Automatic-Reboot/' /etc/apt/apt.conf.d/50unattended-upgrades
}

# Function to block IPs
block_ips() {
    log "Starting IP blocking procedure..."
    
    # Create or flush abuse-defender chain
    iptables -N abuse-defender 2>/dev/null || iptables -F abuse-defender
    
    # Ensure abuse-defender is linked to OUTPUT chain
    iptables -C OUTPUT -j abuse-defender 2>/dev/null || iptables -I OUTPUT -j abuse-defender
    
    # Fetch IP list
    local ip_list
    ip_list=$(curl -s --retry 3 --retry-delay 5 'https://raw.githubusercontent.com/Salarvand-Education/Hetzner-Abuse/main/ips.txt')
    
    if [ $? -ne 0 ]; then
        log "Error: Failed to fetch the IP list"
        return 1
    fi
    
    if [ -z "$ip_list" ]; then
        log "Error: Empty IP list received"
        return 1
    }
    
    # Process IP list
    while IFS= read -r ip; do
        if [[ -n "$ip" && ! "$ip" =~ ^[[:space:]]*# && ! "$ip" =~ : && "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
            iptables -A abuse-defender -d "$ip" -j DROP
        fi
    done <<< "$ip_list"
    
    # Save rules
    iptables-save > /etc/iptables/rules.v4
    
    log "IP blocking completed successfully"
}

# Function to setup automatic updates
setup_update() {
    log "Setting up automatic updates..."
    
    # Create update script
    cat > /root/Update.sh <<'EOF'
#!/bin/bash
set -e
exec 1> >(logger -s -t $(basename $0)) 2>&1

iptables -F abuse-defender
IP_LIST=$(curl -s --retry 3 'https://raw.githubusercontent.com/Salarvand-Education/Hetzner-Abuse/main/ips.txt')

if [ -n "$IP_LIST" ]; then
    while IFS= read -r IP; do
        if [[ -n "$IP" && ! "$IP" =~ ^[[:space:]]*# && ! "$IP" =~ : && "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
            iptables -A abuse-defender -d "$IP" -j DROP
        fi
    done <<< "$IP_LIST"
    iptables-save > /etc/iptables/rules.v4
fi
EOF
    
    chmod +x /root/Update.sh
    
    # Setup cron job
    (crontab -l 2>/dev/null | grep -v "/root/Update.sh"; echo "0 */6 * * * /root/Update.sh") | sort - | uniq - | crontab -
    
    log "Auto-update configured to run every 6 hours"
}

# Main menu function
show_menu() {
    while true; do
        clear
        echo "=== IP Blocking Management Tool ==="
        echo "1. Block IPs now"
        echo "2. Setup automatic updates"
        echo "3. Exit"
        echo
        read -p "Please select an option (1-3): " choice
        
        case $choice in
            1) block_ips ;;
            2) setup_update ;;
            3) log "Exiting..."; exit 0 ;;
            *) log "Invalid option. Please try again."; sleep 2 ;;
        esac
    done
}

# Main execution
main() {
    check_root
    install_packages
    configure_system
    show_menu
}

# Start script
main
