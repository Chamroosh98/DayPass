#!/bin/sh

proxy_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear

        echo "  🛡️ Proxy & Routing Manager"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  🧶 1) Config Manager (Nodes & Subscriptions)"
        echo "  🚦 2) Traffic Routing / Shunt Rules"
        echo "  ⚖️ 3) Node Load Balancing"
        echo "  🩺 4) Node Health Checker"
        echo "  🎭 5) Routing Profiles"
        echo "  🚪 0) Back to Main Menu"
        echo "  ───────────────────────────────────────────────────────────"
        echo

        printf "  ⁉️ Select option [0-5] : "
        read -r choice </dev/tty

        case "$choice" in
            1)
                if command -v config_manager_menu >/dev/null 2>&1; then
                    config_manager_menu
                else
                    log_error "Config Manager module not found!"
                    sleep 2
                fi
                ;;
            2)
                if command -v routing_menu >/dev/null 2>&1; then
                    routing_menu
                else
                    log_error "Routing module not found!"
                    sleep 2
                fi
                ;;
            3)
                if command -v node_balancer_menu >/dev/null 2>&1; then
                    node_balancer_menu
                else
                    log_error "Node Balancer module not found!"
                    sleep 2
                fi
                ;;
            4)
                if command -v health_checker_menu >/dev/null 2>&1; then
                    health_checker_menu
                else
                    log_error "Health Checker module not found!"
                    sleep 2
                fi
                ;;
            5)
                if command -v profile_manager_menu >/dev/null 2>&1; then
                    profile_manager_menu
                else
                    log_error "Profile Manager module not found!"
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