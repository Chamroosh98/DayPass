#!/bin/sh
# ============================================================
# DayPass - Wi-Fi Client Setup (WWAN)
# ============================================================

# $1 radio  $2 ssid  $3 encryption  $4 password
wifi_connect_client() {
    local radio="$1"
    local ssid="$2"
    local enc="$3"
    local pass="$4"

    # Logical interface
    uci set network.wwan=interface
    uci set network.wwan.proto='dhcp'
    uci set network.wwan.metric='30'
    uci commit network

    # Station interface
    uci -q delete wireless.wwan_sta
    uci set wireless.wwan_sta=wifi-iface
    uci set wireless.wwan_sta.device="$radio"
    uci set wireless.wwan_sta.mode='sta'
    uci set wireless.wwan_sta.network='wwan'
    uci set wireless.wwan_sta.ssid="$ssid"
    uci set wireless.wwan_sta.disabled='0'

    if [ "$enc" = "psk" ] && [ -n "$pass" ]; then
        uci set wireless.wwan_sta.encryption='psk2'
        uci set wireless.wwan_sta.key="$pass"
    else
        uci set wireless.wwan_sta.encryption='none'
    fi

    uci commit wireless

    # Firewall
    local zone
    zone=$(uci show firewall | grep "=zone" | while read -r l; do
        s=$(echo "$l" | cut -d'.' -f2 | cut -d'=' -f1)
        [ "$(uci -q get firewall.$s.name)" = "wan" ] && echo "$s" && break
    done)
    if [ -n "$zone" ]; then
        uci -q del_list firewall.$zone.network='wwan'
        uci add_list firewall.$zone.network='wwan'
        uci commit firewall
    fi

    wifi reload >/dev/null 2>&1
    log_success "Wi-Fi WAN connected to [${YELLOW}$ssid${RESET}] on radio [${CYAN}$radio${RESET}]!"
}