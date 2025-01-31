#!/bin/bash
# Exit on error
set -e

# Function to log messages with color
log() {
    local COLOR_RESET='\033[0m'
    local COLOR_RED='\033[0;31m'
    local COLOR_GREEN='\033[0;32m'
    local COLOR_YELLOW='\033[0;33m'
    local COLOR_BLUE='\033[0;34m'

    case $1 in
        ERROR*)
            echo -e "${COLOR_RED}[$(date +'%Y-%m-%d %H:%M:%S')] $1${COLOR_RESET}"
            ;;
        SUCCESS*)
            echo -e "${COLOR_GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${COLOR_RESET}"
            ;;
        INFO*)
            echo -e "${COLOR_BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${COLOR_RESET}"
            ;;
        WARNING*)
            echo -e "${COLOR_YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] $1${COLOR_RESET}"
            ;;
        *)
            echo -e "${COLOR_RESET}[$(date +'%Y-%m-%d %H:%M:%S')] $1${COLOR_RESET}"
            ;;
    esac
}

# Function to check root privileges
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log "ERROR: This script must be run as root"
        exit 1
    fi
}

# Install required packages
install_packages() {
    log "INFO: Installing required packages..."
    DEBIAN_FRONTEND=noninteractive apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y needrestart iptables iptables-persistent curl unattended-upgrades
}

# Configure system settings
configure_system() {
    log "INFO: Configuring system settings..."

    # Ensure directories and files exist
    sudo mkdir -p /etc/apt/apt.conf.d
    sudo touch /etc/apt/apt.conf.d/50unattended-upgrades

    # Reinstall unattended-upgrades
    sudo apt install --reinstall unattended-upgrades

    # Configure needrestart
    sed -i 's/^#\$nrconf{restart} =.*/$nrconf{restart} = '\''a'\'';/' /etc/needrestart/needrestart.conf || true
    
    # Configure dpkg
    echo 'DPkg::Options { "--force-confdef"; "--force-confold"; }' > /etc/apt/apt.conf.d/99mydebconf || true
    
    # Configure unattended upgrades
    sed -i 's/^\/\/Unattended-Upgrade::Automatic-Reboot/Unattended-Upgrade::Automatic-Reboot/' /etc/apt/apt.conf.d/50unattended-upgrades || true
}

# Function to block IPs
block_ips() {
    log "INFO: Starting IP blocking procedure..."
    
    # Create or flush abuse-defender chain
    iptables -N abuse-defender 2>/dev/null || iptables -F abuse-defender
    
    # Ensure abuse-defender is linked to OUTPUT chain
    iptables -C OUTPUT -j abuse-defender 2>/dev/null || iptables -I OUTPUT -j abuse-defender
    
    # Fetch IP list
    local ip_list
    ip_list=$(curl -s --retry 3 --retry-delay 5 'https://raw.githubusercontent.com/Salarvand-Education/Hetzner-Abuse/main/ips.txt')
    
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to fetch the IP list"
        return 1
    fi
    
    if [ -z "$ip_list" ]; then
        log "ERROR: Empty IP list received"
        return 1
    fi
    
    # Process IP list
    while IFS= read -r ip; do
        if [[ -n "$ip" && ! "$ip" =~ ^[[:space:]]*# && ! "$ip" =~ : && "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
            iptables -A abuse-defender -d "$ip" -j DROP
        fi
    done <<< "$ip_list"
    
    # Save rules
    iptables-save > /etc/iptables/rules.v4
    
    log "SUCCESS: IP blocking completed successfully"
}

# Function to setup automatic updates
setup_update() {
    log "INFO: Setting up automatic updates..."
    
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
    
    log "SUCCESS: Auto-update configured to run every 6 hours"
}

# Main menu function with colored output
show_menu() {
    local COLOR_RESET='\033[0m'
    local COLOR_BLUE='\033[0;34m'
    local COLOR_GREEN='\033[0;32m'
    local COLOR_RED='\033[0;31m'

    while true; do
        clear
        echo -e "${COLOR_BLUE}=== IP Blocking Management Tool ===${COLOR_RESET}"
        echo -e "${COLOR_BLUE}1.${COLOR_RESET} ${COLOR_GREEN}Block IPs now${COLOR_RESET}"
        echo -e "${COLOR_BLUE}2.${COLOR_RESET} ${COLOR_GREEN}Setup automatic updates${COLOR_RESET}"
        echo -e "${COLOR_BLUE}3.${COLOR_RESET} ${COLOR_GREEN}Exit${COLOR_RESET}"
        echo
        read -p "Please select an option (1-3): " choice
        
        case $choice in
            1) 
                block_ips ;;
            2) 
                setup_update ;;
            3) 
                log "INFO: Exiting..."; 
                exit 0 ;;
            *) 
                log "WARNING: Invalid option. Please try again."; 
                sleep 2 ;;
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
