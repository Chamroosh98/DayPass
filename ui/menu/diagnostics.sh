#!/bin/sh
# ============================================================
# DayPass - Node Balancer & Health Diagnostics
# ============================================================

diagnostics_menu() {
    local HELP_MODULE_ID="diagnostics"

    while true; do
        render_persistent_header

        ui_title "⚖️ Node Balancer & Health Diagnostics"
        if command -v show_balancer_status >/dev/null 2>&1; then
            show_balancer_status
        fi
        echo
        echo "  🧶 1) Node Balancer (select nodes, Active/Standby mode)"
        echo "  🏓 2) Probe Selected Nodes"
        echo "  🔥 3) Probe & Auto-Switch Now"
        echo "  🩺 4) Node Health Checker"
        echo "  🌍 5) Internet Connectivity Check"
        ui_nav_footer main

        ui_prompt 5

        case "$UI_CHOICE" in
            1) ui_run node_balancer_menu "Node Balancer"; continue ;;
            2) ui_run probe_selected_nodes "Node Balancer" ;;
            3) ui_run apply_balancer "Node Balancer" ;;
            4) ui_run health_checker_menu "Health Checker"; continue ;;
            5) ui_run network_check "Connectivity Check"; continue ;;
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
