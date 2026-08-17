#!/bin/sh
# ============================================================
# Orchestrates storage, subscription and Passwall bridge
# ============================================================

config_manager_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear

        local pw_version="unknown"
        if command -v detect_passwall_version >/dev/null 2>&1; then
            pw_version=$(detect_passwall_version)
        fi

        echo "  📦 Config Manager (Nodes & Subscriptions)"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  🛡️ Detected Engine : ${CYAN}$pw_version${RESET}"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  📋 1) List Configs"
        echo "  🤏 2) Add Manual Config"
        echo "  🎲 3) Toggle Enable/Disable Config"
        echo "  💳 4) Add Subscription"
        echo "  🏧 5) List Subscriptions"
        echo "  🔄 6) Update All Subscriptions"
        echo "  🫸 7) Push Config to Passwall"
        echo "  🤜 8) Push All Configs to Passwall"
        echo "  🗑️ 9) Remove Config"
        echo "  🚪 0) Back"
        echo "  ───────────────────────────────────────────────────────────"
        echo

        printf "  ⁉️ Select option [0-9] : "
        read -r choice </dev/tty

        case "$choice" in
            1)
                if command -v list_configs >/dev/null 2>&1; then
                    list_configs
                else
                    log_error "list_configs() not found!"
                fi
                ;;
            2)
                if command -v add_manual_config >/dev/null 2>&1; then
                    add_manual_config
                else
                    log_error "add_manual_config() not found!"
                fi
                ;;
            3)
                if command -v toggle_config >/dev/null 2>&1; then
                    toggle_config
                else
                    log_error "toggle_config() not found!"
                fi
                ;;
            4)
                if command -v add_subscription >/dev/null 2>&1; then
                    add_subscription
                else
                    log_error "add_subscription() not found!"
                fi
                ;;
            5)
                if command -v list_subscriptions >/dev/null 2>&1; then
                    list_subscriptions
                else
                    log_error "list_subscriptions() not found!"
                fi
                ;;
            6)
                if command -v update_all_subscriptions >/dev/null 2>&1; then
                    update_all_subscriptions
                else
                    log_error "update_all_subscriptions() not found!"
                fi
                ;;
            7)
                if command -v list_configs >/dev/null 2>&1; then
                    list_configs
                fi
                printf "  ✊🏻 Enter config name to push : "
                read -r push_name </dev/tty
                if [ -n "$push_name" ] && command -v push_config_to_passwall >/dev/null 2>&1; then
                    push_config_to_passwall "$push_name"
                else
                    log_error "Invalid name or push function not found!"
                fi
                ;;
            8)
                if command -v push_all_to_passwall >/dev/null 2>&1; then
                    push_all_to_passwall
                else
                    log_error "push_all_to_passwall() not found!"
                fi
                ;;
            9)
                if command -v remove_config >/dev/null 2>&1; then
                    remove_config
                else
                    log_error "remove_config() not found!"
                fi
                ;;
            0)
                return 0
                ;;
            *)
                log_warn "Invalid option!"
                ;;
        esac

        printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
        read -r _ </dev/tty
    done
}