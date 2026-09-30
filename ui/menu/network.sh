#!/bin/sh

# Guest Sub-Menu (Network + QoS)

guest_menu() {
    local HELP_MODULE_ID="network_guest"

    while true; do
        render_persistent_header

        ui_title "👥 Guest Network Management"
        echo "  🍚 1) Setup Guest Network (Interface + Firewall)"
        echo "  🛜 2) Setup Guest WiFi"
        echo "  🛣️ 3) Bandwidth Control (QoS / SQM)"
        echo "  ❌ 4) Remove Guest Network"
        ui_nav_footer

        ui_prompt 4

        case "$UI_CHOICE" in
            1) ui_run setup_guest_network "Guest Network" ;;
            2) ui_run setup_guest_wifi "Guest WiFi" ;;
            3) ui_run guest_qos_menu "Guest QoS"; continue ;;
            4) ui_run remove_guest_network "Guest Network" ;;
            0) return 0 ;;
            *)
                ui_nav_common "$UI_CHOICE" "$HELP_MODULE_ID" && continue
                log_warn "Invalid option!"
                sleep 1
                continue
                ;;
        esac

        ui_pause
    done
}

# Main Network Menu

network_menu() {
    local HELP_MODULE_ID="network"

    while true; do
        render_persistent_header

        ui_title "🌐 Network & Routing Configuration"
        echo "  📡 1) Wi-Fi Access Point (Home WiFi)"
        echo "  👥 2) Guest Network & Bandwidth Control (QoS / SQM)"
        echo "  🏠 3) Change Local Router LAN IP"
        echo "  ⚖️ 4) Multi-WAN Load Balancer (mwan3)"
        echo "  📊 5) Network Info & Speed Monitor"
        echo "  🧭 6) DNS Manager (DNS modes)"
        ui_nav_footer main

        ui_prompt 6

        case "$UI_CHOICE" in
            1) ui_run wifi_ap_menu "WiFi Access Point (AP)" ;;
            2) guest_menu ;;
            3) ui_run change_lan_ip_menu "LAN IP" ;;
            4) ui_run load_balancer_menu "Load Balancer" ;;
            5) ui_run network_info_menu "Network Info" ;;
            6) ui_run dns_menu "DNS" ;;
            0) return 0 ;;
            *)
                ui_nav_common "$UI_CHOICE" "$HELP_MODULE_ID" && continue
                log_warn "Invalid option!"
                sleep 1
                ;;
        esac
    done
}
