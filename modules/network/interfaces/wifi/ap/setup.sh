#!/bin/sh
# ============================================================
# DayPass - Wi-Fi AP Setup
# ============================================================

setup_wifi_ap() {
    render_persistent_header
    ui_title "📡 Wi-Fi Access Point Configuration"
    echo "  ${GRAY}This module only manages Access Point (home Wi-Fi).${RESET}"
    echo "  ${GRAY}Station / WWAN interfaces will not be modified.${RESET}"
    ui_divider
    echo

    local RADIOS
    RADIOS=$(uci show wireless 2>/dev/null | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1)

    if [ -z "$RADIOS" ]; then
        wifi config 2>/dev/null
        RADIOS=$(uci show wireless 2>/dev/null | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1)
    fi

    if [ -z "$RADIOS" ]; then
        log_error "No wireless radio detected on this device."
        return 1
    fi

    show_ap_status

    local has_ap=0 sec
    for sec in $(uci show wireless | grep "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
        [ "$(uci -q get wireless.$sec.mode)" = "ap" ] && has_ap=1 && break
    done

    if [ "$has_ap" -eq 1 ]; then
        printf "  ⁉️ Existing Access Points found. Reconfigure? [y/N] : "
        read -r reconf </dev/tty
        case "$reconf" in
            y|Y) ;;
            *)
                printf "  ${GRAY}>> Keeping current AP settings.${RESET}\n"
                sleep 1
                return 0
                ;;
        esac
    fi

    echo
    echo "  ⚙️ SSID Naming Strategy :"
    echo "     1) Unified SSID for all bands (Smart Connect)"
    echo "     2) Separate SSID per band (2.4G + 5G)"
    ui_divider
    
    ui_prompt 2
    local ssid_mode="$UI_CHOICE"
    [ -z "$ssid_mode" ] && ssid_mode=1

    local SSID_2G SSID_5G unified

    if [ "$ssid_mode" = "2" ]; then
        printf "  🛜 2.4GHz SSID [DayPass-2.4G] : "
        read -r SSID_2G </dev/tty
        [ -z "$SSID_2G" ] && SSID_2G="DayPass-2.4G"

        printf "  🛜 5GHz SSID [DayPass-5G] : "
        read -r SSID_5G </dev/tty
        [ -z "$SSID_5G" ] && SSID_5G="DayPass-5G"
    else
        printf "  🛜 Unified SSID [DayPass] : "
        read -r unified </dev/tty
        [ -z "$unified" ] && unified="DayPass"
        SSID_2G="$unified"
        SSID_5G="$unified"
    fi

    local password=""
    while true; do
        printf "  🔒 WiFi Password (min 8 characters) : "
        read -r password </dev/tty
        if [ ${#password} -ge 8 ]; then
            break
        fi
        log_error "Password must be at least 8 characters!"
    done

    log_info "Applying Access Point configuration ..."

    local radio band iface
    for radio in $RADIOS; do
        uci set wireless.$radio.disabled='0'
        band=$(uci -q get wireless.$radio.band || uci -q get wireless.$radio.hwmode || echo "")
        iface="ap_${radio}"
        
        uci set wireless.$iface=wifi-iface
        uci set wireless.$iface.device="$radio"
        uci set wireless.$iface.mode='ap'
        uci set wireless.$iface.network='lan'
        uci set wireless.$iface.disabled='0'
        uci set wireless.$iface.encryption='psk2'
        uci set wireless.$iface.key="$password"

        case "$band" in
            *5g*|*a*|*ac*|*ax*) 
                uci set wireless.$iface.ssid="$SSID_5G"
                log_success "Configured 5GHz AP on $radio → $SSID_5G"
                ;;
            *)
                uci set wireless.$iface.ssid="$SSID_2G"
                log_success "Configured 2.4GHz AP on $radio → $SSID_2G"
                ;;
        esac
    done

    uci commit wireless
    wifi reload >/dev/null 2>&1 || /etc/init.d/network restart >/dev/null 2>&1

    echo
    log_success "Access Point configuration completed successfully!"
}