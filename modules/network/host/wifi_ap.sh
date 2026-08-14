#!/bin/sh
# ============================================================
# DayPass - Wi-Fi Access Point Module
# Manages Home Wi-Fi (AP Mode only)
# Never touches Station / WWAN interfaces
# ============================================================

# ------------------------------------------------------------
# Show current Access Point status
# ------------------------------------------------------------
show_ap_status() {
    echo "  📶 Current Access Point Status"
    echo "  ───────────────────────────────────────────────────────────"

    local found=0
    for sec in $(uci show wireless 2>/dev/null | grep "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
        mode=$(uci -q get wireless.$sec.mode)
        [ "$mode" != "ap" ] && continue

        ssid=$(uci -q get wireless.$sec.ssid)
        disabled=$(uci -q get wireless.$sec.disabled || echo "0")
        device=$(uci -q get wireless.$sec.device)
        encryption=$(uci -q get wireless.$sec.encryption)
        network=$(uci -q get wireless.$sec.network)

        if [ "$disabled" = "1" ]; then
            status="${GRAY}Disabled${RESET}"
        else
            status="${GREEN}Enabled${RESET}"
        fi

        echo "  • SSID       : ${YELLOW}${ssid}${RESET}"
        echo "  • Device     : $device"
        echo "  • Network    : $network"
        echo "  • Encryption : $encryption"
        echo "  • Status     : $status"
        echo
        found=1
    done

    [ "$found" -eq 0 ] && echo "  ${GRAY}No Access Point configured yet!${RESET}"
    echo "  ───────────────────────────────────────────────────────────"
}

# ------------------------------------------------------------
# Main Setup Function
# ------------------------------------------------------------
setup_wifi_ap() {
    render_persistent_header 2>/dev/null || clear

    echo "  📡 Wi-Fi Access Point Configuration"
    echo "  ───────────────────────────────────────────────────────────"
    echo "  ${GRAY}This module only manages Access Point (home Wi-Fi).${RESET}"
    echo "  ${GRAY}Station / WWAN interfaces will not be modified.${RESET}"
    echo "  ───────────────────────────────────────────────────────────"
    echo

    # Detect radios
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

    # Check if any AP already exists
    local has_ap=0
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

    # SSID Strategy
    echo
    echo "  ⚙️ SSID Naming Strategy :"
    echo "     1) Unified SSID for all bands (Smart Connect)"
    echo "     2) Separate SSID per band (2.4G + 5G)"
    echo "  ───────────────────────────────────────────────────────────"
    printf "  ⁉️ Select [1/2] (default: 1) : "
    read -r ssid_mode </dev/tty
    [ -z "$ssid_mode" ] && ssid_mode=1

    local SSID_2G SSID_5G

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

    # Password
    local password=""
    while true; do
        printf "  🔒 WiFi Password (min 8 characters) : "
        read -r password </dev/tty
        if [ ${#password} -ge 8 ]; then
            break
        fi
        log_error "Password must be at least 8 characters!"
    done

    # Apply configuration to all radios
    log_info "Applying Access Point configuration ..."

    for radio in $RADIOS; do
        uci set wireless.$radio.disabled='0'

        local band
        band=$(uci -q get wireless.$radio.band || uci -q get wireless.$radio.hwmode || echo "")

        local iface="ap_${radio}"
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

# ------------------------------------------------------------
# Main Menu
# ------------------------------------------------------------
wifi_ap_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear

        echo "  📡 Wi-Fi Access Point Manager"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  👀 1) Show current AP status"
        echo "  🛜 2) Create / Update Access Point (AP)"
        echo "  🚪 0) Back"
        echo "  ───────────────────────────────────────────────────────────"
        printf "  ⁉️ Select option [0-2] : "
        read -r choice </dev/tty

        case "$choice" in
            1)
                show_ap_status
                printf "  ${GRAY:-}Press [Enter] to continue ... ${RESET:-}\n"
                read -r _ </dev/tty
                ;;
            2)
                setup_wifi_ap
                printf "  ${GRAY:-}Press [Enter] to continue ... ${RESET:-}\n"
                read -r _ </dev/tty
                ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac
    done
}

# Allow direct execution
case "$0" in
    *wifi_ap.sh)
        wifi_ap_menu
        ;;
esac