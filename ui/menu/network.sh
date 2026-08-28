#!/bin/sh
# ------------------------------------------------------------
# Guest Sub-Menu (Network + QoS)
# ------------------------------------------------------------
guest_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear

        echo "  👥 Guest Network Management"
        echo "  ─────────────────────────────────────────────────────────── "
        echo "  🍚 1) Setup Guest Network (Interface + Firewall)"
        echo "  🛜 2) Setup Guest WiFi"
        echo "  🛣️ 3) Bandwidth Control (QoS)"
        echo "  ❌ 4) Remove Guest Network"
        echo "  🚪 0) Back"
        echo "  ─────────────────────────────────────────────────────────── "
        echo

        printf "  ⁉️ Select option [0-4] : "
        read -r choice </dev/tty

        case "$choice" in
            1)
                if command -v setup_guest_network >/dev/null 2>&1; then
                    setup_guest_network
                else
                    log_error "Guest Network module not found!"
                fi
                ;;
            2)
                if command -v setup_guest_wifi >/dev/null 2>&1; then
                    setup_guest_wifi
                else
                    log_error "Guest WiFi function not found!"
                fi
                ;;
            3)
                if command -v guest_qos_menu >/dev/null 2>&1; then
                    guest_qos_menu
                else
                    log_error "Guest QoS module not found!"
                fi
                ;;
            4)
                if command -v remove_guest_network >/dev/null 2>&1; then
                    remove_guest_network
                else
                    log_error "Remove function not found!"
                fi
                ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press [ENTER] to return to main menu ... ${RESET}"
        read -r _ </dev/tty
    done
}

# ------------------------------------------------------------
# Main Network Menu
# ------------------------------------------------------------
network_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear

        echo "  🌐 Network Settings"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  📡 1) Wi-Fi Access Point (Home WiFi)"
        echo "  👥 2) Guest Network & Bandwidth Control"
        echo "  🏠 3) Change Local Router LAN IP"
        echo "  ⚖️ 4) Multi-WAN Load Balancer"
        echo "  📊 5) Network Info & Speed Monitor"
        echo "  🚪 0) Back to Main Menu"
        echo "  ───────────────────────────────────────────────────────────"
        echo

        printf "  ⁉️ Select option [0-5] : "
        read -r choice </dev/tty

        case "$choice" in
            1)
                if command -v wifi_ap_menu >/dev/null 2>&1; then
                    wifi_ap_menu
                else
                    log_error "WiFi Access Point (AP) module not found!"
                    sleep 2
                fi
                ;;
            2)
                guest_menu
                ;;
            3)
                if command -v change_lan_ip_menu >/dev/null 2>&1; then
                    change_lan_ip_menu
                else
                    log_error "LAN IP module not found!"
                    sleep 2
                fi
                ;;
            4)
                if command -v load_balancer_menu >/dev/null 2>&1; then
                    load_balancer_menu
                else
                    log_error "Load Balancer module not found!"
                    sleep 2
                fi
                ;;
            5)
                if command -v network_info_menu >/dev/null 2>&1; then
                    network_info_menu
                else
                    log_error "Network Info module not found!"
                    sleep 2
                fi
                ;;
            0)
                return 0
                ;;
            *)
                log_warn "Invalid option!"
                sleep 1
                ;;
        esac
    done
}