#!/bin/sh
# ============================================================
# DayPass - Wi-Fi WAN (Station / Client Mode)
# Connects the router to an external hotspot for internet
# Does NOT touch any Access Point interfaces
# ============================================================

setup_wifi_wan() {
    render_persistent_header

    echo "  📡 Wi-Fi WAN (Station Mode)"
    ui_divider
    echo "  ${GRAY:-}Connect this router to a phone hotspot or another Wi-Fi${RESET}"
    echo "  ${GRAY:-}network to use it as an internet source (WWAN)!${RESET}"
    ui_divider
    echo

    # List radios
    local radios idx=1 radio_list=""
    radios=$(uci show wireless 2>/dev/null | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1)

    if [ -z "$radios" ]; then
        log_error "No wireless radio found."
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

    command -v wifi_connect_client >/dev/null || { log_error "Load the DayPass Wi-Fi client module."; return 1; }
    if [ -n "$pass" ]; then
        wifi_connect_client "$chosen" "$ssid" psk "$pass"
    else
        wifi_connect_client "$chosen" "$ssid" none ""
    fi
}
