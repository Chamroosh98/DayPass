#!/bin/sh
# ============================================================
# DayPass - Wi-Fi Client Setup (WWAN)
# ============================================================

wifi_connect_client() {
    local radio="$1"
    local ssid="$2"
    local enc="$3"
    local pass="$4"
    
    # Sanitizing the SSID for use in system naming
    local safe_name
    safe_name=$(echo "$ssid" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')
    [ -n "$safe_name" ] || safe_name="client"
    
    # Requirement for network interface names to begin with the prefix wan_
    local net_name="wan_${safe_name}"
    local iface_name="sta_${safe_name}"

    # 1. Create a network interface with the prefix wan_
    uci set "network.$net_name=interface"
    uci set "network.$net_name.proto"='dhcp'
    uci set "network.$net_name.metric"='30'
    uci commit network

    # 2. Creating a Wireless Interface
    uci -q delete "wireless.$iface_name"
    uci set "wireless.$iface_name=wifi-iface"
    uci set "wireless.$iface_name.device"="$radio"
    uci set "wireless.$iface_name.mode"='sta'
    uci set "wireless.$iface_name.network"="$net_name"
    uci set "wireless.$iface_name.ssid"="$ssid"
    uci set "wireless.$iface_name.disabled"='0'

    if [ "$enc" = "psk" ] && [ -n "$pass" ]; then
        uci set "wireless.$iface_name.encryption"='psk2'
        uci set "wireless.$iface_name.key"="$pass"
    else
        uci set "wireless.$iface_name.encryption"='none'
    fi

    uci commit wireless

    # 3. Adding to the Firewall (WAN Zone)
    local zone
    zone=$(uci show firewall | grep "=zone" | while read -r l; do
        s=$(echo "$l" | cut -d'.' -f2 | cut -d'=' -f1)
        [ "$(uci -q get firewall.$s.name)" = "wan" ] && echo "$s" && break
    done)

    if [ -n "$zone" ]; then
        uci -q add_list "firewall.$zone.network"="$net_name"
        uci commit firewall
        /etc/init.d/firewall restart >/dev/null 2>&1 || true
    fi

    # 4. Reload Wireless Settings
    wifi reload >/dev/null 2>&1
    log_success "Wi-Fi WAN connected to [${YELLOW}$ssid${RESET}] using network [${CYAN}$net_name${RESET}]!"
}