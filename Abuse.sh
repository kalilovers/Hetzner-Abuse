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
    IP_LIST=$(curl -s 'https://raw.githubusercontent.com/Kiya6955/Abuse-Defender/main/abuse-ips.ipv4')

    if [ $? -ne 0 ]; then
        echo "Failed to fetch the IP-Ranges list. Please contact @PV_THIS_IS_AMIR"
        exit 1
    fi

    # اضافه کردن هر IP به chain abuse-defender
    for IP in $IP_LIST; do
        iptables -A abuse-defender -d $IP -j DROP
    done

    # ذخیره قوانین در /etc/iptables/rules.v4
    iptables-save > /etc/iptables/rules.v4

    echo "IP-Ranges have been blocked successfully."
}

# اجرای تابع
block_ips
