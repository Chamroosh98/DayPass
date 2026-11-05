#!/bin/sh
# ============================================================
# DayPass - Wi-Fi Scanner (Client Mode)
# ============================================================

wifi_scan_networks() {
    local radio="$1"
    local scan_file="/tmp/daypass_wifi_scan.txt"
    local target_iface=""
    local dummy_created=0
    
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

    # 4. Create a dummy interface if no interface exists on this radio
    if [ -z "$target_iface" ]; then
        log_info "No active interface found on $radio. Creating a temporary scanner..."
        
        # Create a temporary interface in UCI
        uci -q delete wireless.daypass_scanner
        uci set wireless.daypass_scanner=wifi-iface
        uci set wireless.daypass_scanner.device="$radio"
        uci set wireless.daypass_scanner.network="lan"
        uci set wireless.daypass_scanner.mode="sta"
        uci set wireless.daypass_scanner.ssid="daypass_temp_scan"
        uci set wireless.daypass_scanner.disabled="0"
        uci commit wireless
        
        # Reload wireless to apply changes and spawn the physical interface
        wifi reload "$radio" >/dev/null 2>&1
        sleep 3 # Wait for the interface to come up
        
        # Re-read interfaces
        all_ifaces=$(iwinfo 2>/dev/null | awk '/^[a-zA-Z0-9_-]+/ {print $1}')
        for iface in $all_ifaces; do
            if echo "$iface" | grep -qE "^(phy|wlan|ath|ra)${rad_idx}"; then
                target_iface="$iface"
                dummy_created=1
                break
            fi
        done
    fi

    # 5. Execute scan on the correctly identified interface
    if [ -n "$target_iface" ]; then
        # Try scanning with iwinfo, fallback to iw on failure
        iwinfo "$target_iface" scan 2>/dev/null > "/tmp/wifi_raw_scan.txt"
        if [ ! -s "/tmp/wifi_raw_scan.txt" ] && command -v iw >/dev/null 2>&1; then
           iw dev "$target_iface" scan 2>/dev/null > "/tmp/wifi_raw_scan.txt"
        fi
    else
         # Abort if no interface is found even after creating a dummy one
         rm -f "/tmp/wifi_raw_scan.txt"
         return 1
    fi

    # 6. Parse Results
    if [ -s "/tmp/wifi_raw_scan.txt" ]; then
        awk '
            BEGIN { ssid=""; signal="" }
            /Cell [0-9]+/ || /^BSS / { ssid=""; signal="" }
            /ESSID:/ || /SSID:/ { 
                match($0, /(ESSID|SSID): "(.*)"/, arr); 
                if (arr[2] != "") ssid=arr[2]; 
            }
            /Signal:/ || /signal:/ { 
                match($0, /(Signal|signal): (-?[0-9.]+) dBm/, arr); 
                signal=arr[2];
                # Convert decimal values (from iw output) to integer
                sub(/\..*/, "", signal);
            }
            /Encryption:/ || /RSN:/ || /WPA:/ {
                enc="none"
                if ($0 !~ /none/) enc="psk"
                if (ssid != "" && ssid != "unknown" && ssid != "\\x00") {
                    print ssid "|" (signal=="" ? "0" : signal) "|" enc
                    ssid=""; # Prevent duplicate printing in iw output
                }
            }
        ' "/tmp/wifi_raw_scan.txt" | sort -t '|' -k2 -nr | awk -F '|' '!seen[$1]++' > "$scan_file"
    fi

    # 7. Cleanup dummy interface if we created one
    if [ "$dummy_created" -eq 1 ]; then
        uci -q delete wireless.daypass_scanner
        uci commit wireless
        wifi reload "$radio" >/dev/null 2>&1
    fi

    rm -f "/tmp/wifi_raw_scan.txt"
    [ -s "$scan_file" ] && return 0
    return 1
}