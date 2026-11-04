#!/bin/sh
# ============================================================
# DayPass - Wi-Fi AP Status
# ============================================================

_wifi_ap_format_band() {
    case "$1" in
        *5g*|*a*|*ac*|*ax*) printf "5 GHz (802.11 a/ac/ax)" ;;
        *)                  printf "2.4 GHz (802.11 b/g/n)" ;;
    esac
}

show_ap_status() {
    echo "  📶 Current Access Point Status"
    ui_divider

    local found=0 mode ssid disabled device encryption network status band formated_band

    for sec in $(uci show wireless 2>/dev/null | grep "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
        mode=$(uci -q get wireless.$sec.mode)
        [ "$mode" != "ap" ] && continue

        ssid=$(uci -q get wireless.$sec.ssid)
        disabled=$(uci -q get wireless.$sec.disabled || echo "0")
        device=$(uci -q get wireless.$sec.device)
        encryption=$(uci -q get wireless.$sec.encryption)
        network=$(uci -q get wireless.$sec.network)
        band=$(uci -q get wireless.$device.band || uci -q get wireless.$device.hwmode || echo "")
        formated_band=$(_wifi_ap_format_band "$band")

        if [ "$disabled" = "1" ]; then
            status="${GRAY}Disabled${RESET}"
        else
            status="${GREEN}Enabled${RESET}"
        fi

        echo "  • SSID       : ${YELLOW}${ssid}${RESET}"
        echo "  • Radio      : $device ${GRAY}[$formated_band]${RESET}"
        echo "  • Network    : $network"
        echo "  • Encryption : $encryption"
        echo "  • Status     : $status"
        echo
        found=1
    done

    [ "$found" -eq 0 ] && echo "  ${GRAY}No Access Point configured yet!${RESET}"
    ui_divider
}