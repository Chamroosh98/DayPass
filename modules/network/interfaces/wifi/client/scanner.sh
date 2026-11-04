#!/bin/sh
# ============================================================
# DayPass - Wi-Fi Scanner (Client Mode)
# ============================================================

# $1 radio device (e.g., radio0)
wifi_scan_networks() {
    local radio="$1"
    local scan_file="/tmp/daypass_wifi_scan.txt"
    
    # Ensure iwinfo is installed
    if ! command -v iwinfo >/dev/null 2>&1; then
        log_error "iwinfo is required for scanning Wi-Fi networks."
        return 1
    fi

    # Trigger scan and parse SSID and Signal
    iwinfo "$radio" scan 2>/dev/null | awk '
        /^Cell/ { signal=""; ssid="" }
        /ESSID:/ { 
            match($0, /ESSID: "(.*)"/, arr); 
            ssid=arr[1]; 
            if(ssid == "unknown") ssid=""
        }
        /Signal:/ { 
            match($0, /Signal: (-[0-9]+) dBm/, arr); 
            signal=arr[1] 
        }
        /Encryption:/ {
            encryption="none"
            if ($0 !~ /none/) encryption="psk"
            
            if (ssid != "") {
                print ssid "|" signal "|" encryption
            }
        }
    ' | sort -t '|' -k2 -nr | awk -F '|' '!seen[$1]++' > "$scan_file"
    
    if [ ! -s "$scan_file" ]; then
        return 1
    fi
    return 0
}