#!/bin/sh
# ============================================================
# DayPass - Wi-Fi Scanner (Client Mode)
# ============================================================

wifi_scan_networks() {
    local radio="$1"
    local scan_file="/tmp/daypass_wifi_scan.txt"
    local target_iface=""
    
    : > "$scan_file"

    # 1. Extract radio index (e.g., "radio1" -> "1")
    local rad_idx
    rad_idx=$(echo "$radio" | tr -dc '0-9')

    # 2. Get ALL active wireless interfaces on the system
    local all_ifaces
    all_ifaces=$(iwinfo 2>/dev/null | awk '/^[a-zA-Z0-9_-]+/ {print $1}')

    # 3. Match the interface that belongs to our PHY (e.g., phy1*, wlan1*)
    for iface in $all_ifaces; do
        if echo "$iface" | grep -qE "^(phy|wlan|ath|ra)${rad_idx}"; then
            target_iface="$iface"
            break
        fi
    done

    # 4. Fallback: If no direct match, use the first available wireless interface
    if [ -z "$target_iface" ]; then
        target_iface=$(echo "$all_ifaces" | head -n 1)
    fi

    # 5. Execute scan on the correctly identified interface
    if [ -n "$target_iface" ]; then
        iwinfo "$target_iface" scan 2>/dev/null > "/tmp/wifi_raw_scan.txt"
    fi

    # 6. Parse Results
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