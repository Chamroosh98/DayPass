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
    ui_divider

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
    ui_divider
}

# ------------------------------------------------------------
# Main Setup Function
# ------------------------------------------------------------
wifi_ap_menu() {
    local HELP_MODULE_ID="network_wifi_ap"

    while true; do
        render_persistent_header

        echo "  📡 Wi-Fi Access Point Manager"
        ui_divider
        echo "  👀 1) Show current AP status"
        echo "  🛜 2) Create / Update Access Point (AP)"
        ui_nav_footer
        ui_prompt 2
        choice="$UI_CHOICE"

        case "$choice" in
            1)
                show_ap_status
                printf "  ${GRAY:-}Press [Enter] to continue ... ${RESET:-}\n"
                read -r _ </dev/tty || daypass_quit
                ;;
            2)
                command -v setup_wifi_ap >/dev/null || { echo "Open Wi-Fi setup from the DayPass CLI."; return 1; }
                setup_wifi_ap
                printf "  ${GRAY:-}Press [Enter] to continue ... ${RESET:-}\n"
                read -r _ </dev/tty || daypass_quit
                ;;
            q|Q) daypass_quit ;;
            h|H)
                if command -v show_help >/dev/null 2>&1; then
                    show_help "$HELP_MODULE_ID"
                else
                    log_warn "Help module not loaded!"
                    sleep 1
                fi
                continue
                ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac
    done
}

# Allow direct execution
case "$0" in
    *wifi_ap.sh)
        command -v ui_prompt >/dev/null 2>&1 || { echo "Run this menu from DayPass (install.sh)."; exit 1; }
        wifi_ap_menu
        ;;
esac