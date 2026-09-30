#!/bin/sh
# ============================================================
# Orchestrates storage, subscription and the transport bridge
# ============================================================

config_manager_menu() {
    local HELP_MODULE_ID="proxy_config_manager"

    while true; do
        render_persistent_header

        local engine_label="unknown"
        if command -v get_active_engine >/dev/null 2>&1; then
            engine_label=$(transport_engine_label "$(get_active_engine)")
        fi

        echo "  📦 Config Manager (Nodes & Subscriptions)"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  🛡️ Detected Engine : ${CYAN}$engine_label${RESET}"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  📋 1) List Configs"
        echo "  🤏 2) Add Manual Config"
        echo "  🎲 3) Toggle Enable/Disable Config"
        echo "  💳 4) Add Subscription"
        echo "  🏧 5) List Subscriptions"
        echo "  🔄 6) Update All Subscriptions"
        echo "  🫸 7) Push Config to Active Engine"
        echo "  🤜 8) Push All Configs to Active Engine"
        echo "  🗑️ 9) Remove Config"
        ui_nav_footer

        ui_prompt 9
        choice="$UI_CHOICE"

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
                if [ -n "$push_name" ] && command -v transport_push_config >/dev/null 2>&1; then
                    transport_push_config "$push_name"
                else
                    log_error "Invalid name or push function not found!"
                fi
                ;;
            8)
                if command -v transport_push_all >/dev/null 2>&1; then
                    transport_push_all
                else
                    log_error "transport_push_all() not found!"
                fi
                ;;
            9)
                if command -v remove_config >/dev/null 2>&1; then
                    remove_config
                else
                    log_error "remove_config() not found!"
                fi
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
            0)
                return 0
                ;;
            *)
                log_warn "Invalid option!"
                ;;
        esac

        printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
        read -r _ </dev/tty || daypass_quit
    done
}