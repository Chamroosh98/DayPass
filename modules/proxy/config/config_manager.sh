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
        echo "  Detected Engine : ${CYAN}$pw_version${RESET}"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  📋 1) List Configs"
        echo "  🤏 2) Add Manual Config"
        echo "  🫰 3) Add Subscription"
        echo "  🔄 4) Update All Subscriptions"
        echo "  🫸🏻 5) Push Config to Passwall"
        echo "  🤜🏻 6) Push All Configs to Passwall"
        echo "  🗑️ 7) Remove Config"
        echo "  🚪 0) Back"
        echo "  ───────────────────────────────────────────────────────────"
        echo

        printf "  ⁉️ Select option [0-7] : "
        read -r choice </dev/tty

        case "$choice" in
            1) list_configs ;;
            2) add_manual_config ;;
            3) add_subscription ;;
            4) update_all_subscriptions ;;
            5)
                list_configs
                printf "  Enter config name to push : "
                read -r push_name </dev/tty
                [ -n "$push_name" ] && push_config_to_passwall "$push_name"
                ;;
            6) push_all_to_passwall ;;
            7) remove_config ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press [Enter] to continue ... ${RESET}"
        read -r _ </dev/tty
    done
}