#!/bin/sh

proxy_menu() {
    local HELP_MODULE_ID="proxy"
    local active

    while true; do
        render_persistent_header

        ui_title "🛡️ Proxy & Tunnel Engine Manager"
        if command -v get_active_engine >/dev/null 2>&1; then
            active=$(get_active_engine)
            if [ "$active" = "none" ]; then
                echo "  🎯 Active Engine : ${GRAY}none${RESET}"
            else
                echo "  🎯 Active Engine : ${GREEN}$(transport_engine_label "$active")${RESET}"
            fi
            echo "  ───────────────────────────────────────────────────────────"
        fi
        echo "  🚀 1) Transport Engines (Passwall, sing-box, Xray, WireGuard, OpenVPN)"
        echo "  🧶 2) Config Manager (Nodes & Subscriptions)"
        echo "  🚦 3) Traffic Routing / Shunt Rules"
        echo "  🎭 4) Routing Profiles"
        echo "  🧼 5) Clean IP Manager"
        ui_nav_footer main

        ui_prompt 5

        case "$UI_CHOICE" in
            1) ui_run proxy_engine_menu "Transport Engine" ;;
            2) ui_run config_manager_menu "Config Manager" ;;
            3) ui_run routing_menu "Routing" ;;
            4) ui_run profile_manager_menu "Profile Manager" ;;
            5) ui_run clean_ip_menu "Clean IP" ;;
            0) return 0 ;;
            *)
                ui_nav_common "$UI_CHOICE" "$HELP_MODULE_ID" && continue
                log_warn "Invalid option!"
                sleep 1
                ;;
        esac
    done
}
