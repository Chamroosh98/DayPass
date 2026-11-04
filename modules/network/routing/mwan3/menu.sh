#!/bin/sh
# ============================================================
# DayPass - Multi-WAN Menu
# ============================================================

load_balancer_menu() {
    local HELP_MODULE_ID="network_multiwan"
    local iface metric list icon padded_iface

    while true; do
        render_persistent_header
        ui_title "⚖️ Multi-WAN Load Balancer"
        
        list=$(mwan_active_ifaces 2>/dev/null)
        if [ -z "$list" ]; then
            printf "  ${GRAY}  No active WAN interfaces detected.${RESET}\n"
        else
            printf "  ${BOLD}${CYAN}📊 Active WAN Overview :${RESET}\n"
            for iface in $list; do
                metric=$(uci -q get "network.$iface.metric")
                [ -n "$metric" ] || metric="default"
                icon=$(_mwan_metric_icon "$iface" 2>/dev/null || echo "🌐")
                
                padded_iface="$iface"
                while [ "${#padded_iface}" -lt 14 ]; do padded_iface="$padded_iface "; done
                
                printf "    %s %s ${GRAY}»${RESET} Metric: ${YELLOW}%-4s${RESET}\n" "$icon" "$padded_iface" "$metric"
            done
        fi
        
        echo "------------------------------------------------------------"

        echo "  📌 1) Install Dependencies"
        echo "  📲 2) Setup USB Tethering WAN"
        echo "  📶 3) Setup Wi-Fi Hotspot WAN"
        echo "  ⚖️ 4) Apply Load Balancing (Use all WANs together)"
        echo "  🛡️ 5) Apply Strict Failover (Backup WANs only)"
        echo "  👀 6) Show mwan3 Status"
        echo "  🧭 7) WAN Metrics"
        ui_nav_footer
        
        ui_prompt 7
        c="$UI_CHOICE"

        case "$c" in
            1) install_mwan3_deps || true ;;
            2) setup_usb_wan 2>/dev/null || log_warn "USB module not loaded." ;;
            3) wifi_client_menu 2>/dev/null || log_warn "Wi-Fi WAN module not loaded." ;;
            4) apply_mwan3_mode "balanced" || true ;;
            5) apply_mwan3_mode "failover" || true ;;
            6) command -v mwan3 >/dev/null 2>&1 && mwan3 status || log_error "mwan3 not installed!" ;;
            7) mwan_metric_menu; continue ;;
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

        echo
        echo "  ${GRAY:-}Press [Enter] to continue ...${RESET:-}"
        read -r _ </dev/tty || daypass_quit
    done
}