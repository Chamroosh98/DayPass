#!/bin/sh
# ============================================================
# DayPass - Wi-Fi Scanner (Client Mode)
# ============================================================

wifi_scan_networks() {
    local radio="$1"
    local scan_file="/tmp/daypass_wifi_scan.txt"
    local target_iface=""

    : > "$scan_file"

    # Find a valid interface on the radio for the iwinfo scan command
    target_iface=$(iwinfo 2>/dev/null | grep -B 2 "$radio" | head -n 1 | cut -d' ' -f1)
    [ -n "$target_iface" ] || target_iface=$(iwinfo 2>/dev/null | grep "^phy" | head -n 1 | cut -d' ' -f1)
    [ -n "$target_iface" ] || target_iface="phy1-sta0"

    # Execute scan
    iwinfo "$target_iface" scan 2>/dev/null > "/tmp/wifi_raw_scan.txt" || \
    iwinfo "$radio" scan 2>/dev/null > "/tmp/wifi_raw_scan.txt" || true

    if [ -s "/tmp/wifi_raw_scan.txt" ]; then
        awk '
            BEGIN { ssid=""; signal="" }
            /Cell [0-9]+/ { ssid=""; signal="" }
            /ESSID:/ { 
                match($0, /ESSID: "(.*)"/, arr); 
                ssid=arr[1]; 
            }
            /Signal:/ { 
                match($0, /Signal: (-?[0-9]+) dBm/, arr); 
                signal=arr[1] 
            }
            /Encryption:/ {
                enc="none"
                if ($0 !~ /none/) enc="psk"
                if (ssid != "" && ssid != "unknown") {
                    print ssid "|" (signal=="" ? "0" : signal) "|" enc
                }
            }
        ' "/tmp/wifi_raw_scan.txt" | sort -t '|' -k2 -nr | awk -F '|' '!seen[$1]++' > "$scan_file"
    fi

    rm -f "/tmp/wifi_raw_scan.txt"
    [ -s "$scan_file" ] && return 0
    return 1
}