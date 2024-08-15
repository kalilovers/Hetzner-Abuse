#!/bin/bash

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

# اجرای تابع
block_ips
