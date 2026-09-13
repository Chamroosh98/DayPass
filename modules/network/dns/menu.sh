#!/bin/sh

# DNS Manager Menu — persistent router DNS (not the temporary opkg recovery fix)

dns_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear

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

        printf "  ⁉️ Select option [0-4] : "
        read -r choice </dev/tty

        case "$choice" in
            1) apply_dns_mode "system" ;;
            2) apply_dns_mode "secure" ;;
            3) apply_dns_mode "tunnel" ;;
            4) apply_dns_mode "hybrid" ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
        read -r _ </dev/tty
    done
}
