#!/bin/sh
# ============================================================
# DayPass - Wi-Fi WAN (Station / Client Mode)
# Connects the router to an external hotspot for internet
# Does NOT touch any Access Point interfaces
# ============================================================

setup_wifi_wan() {
    render_persistent_header 2>/dev/null || clear

    echo "  📡 Wi-Fi WAN (Station Mode)"
    echo "  ───────────────────────────────────────────────────────────"
    echo "  ${GRAY} Connect this router to a phone hotspot or another Wi-Fi ${RESET}"
    echo "  ${GRAY} network to use it as an internet source (WWAN). ${RESET}"
    echo "  ───────────────────────────────────────────────────────────"
    echo

    # List radios
    local radios idx=1 radio_list=""
    radios=$(uci show wireless 2>/dev/null | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1)

    if [ -z "$radios" ]; then
        log_error "No wireless radio found!"
        return 1
    fi

    echo "  📻 Available Radios :"
    for r in $radios; do
        band=$(uci -q get wireless.$r.band || uci -q get wireless.$r.hwmode || echo "unknown")
        echo "     $idx) $r ($band)"
        radio_list="$radio_list $r"
        idx=$((idx + 1))
    done
    echo

    printf "  📋 Select radio [1] : "
    read -r choice </dev/tty
    [ -z "$choice" ] && choice=1

    local chosen="" i=1
    for r in $radio_list; do
        [ "$i" -eq "$choice" ] && chosen="$r" && break
        i=$((i + 1))
    done
    [ -z "$chosen" ] && chosen=$(echo $radio_list | awk '{print $1}')

    printf "  📶 Hotspot SSID : "
    read -r ssid </dev/tty
    [ -z "$ssid" ] && { log_error "SSID is required!"; return 1; }

    printf "  🔒 Password (leave empty if open) : "
    read -r pass </dev/tty

    # Logical interface
    uci set network.wwan=interface
    uci set network.wwan.proto='dhcp'
    uci set network.wwan.metric='30'
    uci commit network

    # Station interface (never touches AP)
    uci set wireless.wwan_sta=wifi-iface
    uci set wireless.wwan_sta.device="$chosen"
    uci set wireless.wwan_sta.mode='sta'
    uci set wireless.wwan_sta.network='wwan'
    uci set wireless.wwan_sta.ssid="$ssid"
    uci set wireless.wwan_sta.disabled='0'

    if [ -n "$pass" ]; then
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
    log_success "Wi-Fi WAN connected to [$ssid] on radio [$chosen]!"
}