#!/bin/sh
# ============================================================
# DayPass - Wi-Fi AP Menu
# ============================================================

wifi_ap_menu() {
    local HELP_MODULE_ID="network_wifi_ap"

    while true; do
        render_persistent_header
        ui_title "📡 Wi-Fi Access Point Manager"
        
        echo "  👀 1) Show current AP status"
        echo "  🛜 2) Create / Update Access Point (AP)"
        
        ui_nav_footer
        ui_prompt 2
        
        case "$UI_CHOICE" in
            1)
                show_ap_status
                ui_pause
                ;;
            2)
                setup_wifi_ap
                ui_pause
                ;;
            q|Q) daypass_quit ;;
            h|H) ui_show_help "$HELP_MODULE_ID"; continue ;;
            0) return 0 ;;
            *) log_warn "Invalid option!"; continue ;;
        esac
    done
}