#!/bin/sh

# DNS Manager Menu — persistent router DNS (not the temporary opkg recovery fix)

dns_menu() {
    local HELP_MODULE_ID="network_dns"

    while true; do
        render_persistent_header

        echo "  🧭 DNS Manager"
        echo "  ───────────────────────────────────────────────────────────"
        show_dns_status
        echo
        echo "  1) System Default (WAN / ISP resolvers)"
        echo "  2) Secure DNS (DoT/DoH when available)"
        echo "  3) DNS through Tunnel (Passwall required)"
        echo "  4) Hybrid (tunnel/DoH first, public fallback)"
        echo "  0) Back"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  ${GRAY}Temporary package-manager DNS recovery stays in Network Checker.${RESET}"
        echo

        printf "  ⁉️ Select option [0-4] or [h] Help : "
        read -r choice </dev/tty

        case "$choice" in
            1) apply_dns_mode "system" ;;
            2) apply_dns_mode "secure" ;;
            3) apply_dns_mode "tunnel" ;;
            4) apply_dns_mode "hybrid" ;;
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
        read -r _ </dev/tty
    done
}
