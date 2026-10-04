#!/bin/sh

# DNS Manager Menu — persistent router DNS (not the temporary opkg recovery fix)

dns_menu() {
    local HELP_MODULE_ID="network_dns"

    while true; do
        render_persistent_header

        echo "  🧭 DNS Manager"
        ui_divider
        show_dns_status
        echo
        echo "  1) System Default (WAN / ISP resolvers)"
        echo "  2) Secure DNS (DoT/DoH when available)"
        echo "  3) DNS through Tunnel (transport engine required)"
        echo "  4) Hybrid (tunnel/DoH first, public fallback)"
        ui_nav_footer
        echo "  ${GRAY}Temporary package-manager DNS recovery stays in Network Checker.${RESET}"
        echo

        ui_prompt 4
        choice="$UI_CHOICE"

        case "$choice" in
            1) apply_dns_mode "system" ;;
            2) apply_dns_mode "secure" ;;
            3) apply_dns_mode "tunnel" ;;
            4) apply_dns_mode "hybrid" ;;
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

        printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
        read -r _ </dev/tty || daypass_quit
    done
}
