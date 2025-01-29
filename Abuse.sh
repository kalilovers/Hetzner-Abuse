#!/bin/bash

# نصب پکیج needrestart
sudo apt-get install -y needrestart

# تنظیمات مربوط به needrestart و unattended-upgrades
sudo sed -i 's/^#\$nrconf{restart} =.*/$nrconf{restart} = '\''a'\'';/' /etc/needrestart/needrestart.conf
echo 'DPkg::Options { "--force-confdef"; "--force-confold"; }' | sudo tee /etc/apt/apt.conf.d/99mydebconf > /dev/null
sudo sed -i 's/^\/\/Unattended-Upgrade::Automatic-Reboot/Unattended-Upgrade::Automatic-Reboot/' /etc/apt/apt.conf.d/50unattended-upgrades

function block_ips {
    clear
    # بررسی نصب بودن iptables
    if ! command -v iptables &> /dev/null; then
        apt-get update
        apt-get install -y iptables
    fi
    # بررسی نصب بودن iptables-persistent برای ذخیره‌سازی قوانین
    if ! dpkg -s iptables-persistent &> /dev/null; then
        apt-get update
        apt-get install -y iptables-persistent
    fi

    # ایجاد chain جدید به نام abuse-defender در صورت عدم وجود
    if ! iptables -L abuse-defender -n >/dev/null 2>&1; then
        iptables -N abuse-defender
    fi

    # پیوستن abuse-defender به chain خروجی
    if ! iptables -L OUTPUT -n | grep -q "abuse-defender"; then
        iptables -I OUTPUT -j abuse-defender
    fi

    # پاک کردن قوانین قبلی
    iptables -F abuse-defender

    # دریافت لیست IPها
    IP_LIST=$(curl -s 'https://raw.githubusercontent.com/Salarvand-Education/Hetzner-Abuse/main/ips.txt')

    if [ $? -ne 0 ]; then
        echo "Failed to fetch the IP-Ranges list. Please check the URL."
        exit 1
    fi

    if [ -z "$IP_LIST" ]; then
        echo "The IP list is empty. No IPs were fetched."
        exit 1
    fi

    # اضافه کردن هر IP به chain abuse-defender
    while IFS= read -r IP; do
        # حذف خطوط خالی و خطوط نادرست
        if [[ ! -z "$IP" && ! "$IP" =~ ^\s*# && ! "$IP" =~ : ]]; then
            iptables -A abuse-defender -d $IP -j DROP
        fi
    done <<< "$IP_LIST"

    # ذخیره قوانین در /etc/iptables/rules.v4
    iptables-save > /etc/iptables/rules.v4

    echo "IP-Ranges have been blocked successfully."
}

function setup_update {
    cat <<EOF >/root/Update.sh
#!/bin/bash
iptables -F abuse-defender
IP_LIST=\$(curl -s 'https://raw.githubusercontent.com/Salarvand-Education/Hetzner-Abuse/main/ips.txt')
for IP in \$IP_LIST; do
    iptables -A abuse-defender -d \$IP -j DROP
done
iptables-save > /etc/iptables/rules.v4
EOF
    chmod +x /root/Update.sh
    
    crontab -l 2>/dev/null | grep -v "/root/Update.sh" | crontab -
    (crontab -l 2>/dev/null; echo "0 */6 * * * /root/Update.sh") | crontab -
    echo "Auto-update cron job has been set up to run every 6 hours."
}

function show_menu {
    clear
    echo "1. Block IPs now"
    echo "2. Setup update"
    echo "3. Exit"
    echo -n "Please select an option: "
    read choice

    case \$choice in
        1) block_ips;;
        2) setup_update;;
        3) exit 0;;
        *) echo "Invalid option, please try again"; sleep 2; show_menu;;
    esac
}

# نمایش منو
show_menu
