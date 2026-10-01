#!/bin/sh

# Purpose:
#   Ask (once, before package work) how the router should reach
#   OpenWrt feeds: local HTTP proxy, Cloudflare Worker mirror, or direct.

# ---------- banner ----------
_nb_banner() {
    echo
    echo "  ${CYAN}${RESET}${BOLD}🌐 Network Bootstrap Wizard${RESET}"
    echo "  ${CYAN}─────────────────────────────────────────────────────────${RESET}"
    echo "  ${CYAN}${RESET}Choose how DayPass should reach package mirrors"
    echo "  ${CYAN}${RESET}before updating or installing software.          "
    echo "  ${CYAN}─────────────────────────────────────────────────────────${RESET}"
    echo
}

_nb_menu() {
    echo "  ${WHITE}🔌 1)${RESET} Configure Local HTTP/HTTPS Proxy"
    echo "  ${WHITE}☁️ 2)${RESET} Use Cloudflare Worker Mirror"
    echo "  ${WHITE}➡️ 3)${RESET} Proceed with Direct Connection ${DIM}(default)${RESET}"
    echo
    echo "  ${DIM}─────────────────────────────────────────────────────────${RESET}"
    echo
}

# Public — interactive dispatcher (NEVER blocks / fails the pipeline)
network_bootstrap_offer() {
    local _choice

    render_persistent_header
    _nb_banner
    _nb_menu

    printf "  How should package downloads be prepared? ${DIM}[1-3]${RESET} : "
    read -r _choice </dev/tty

    case "$_choice" in
        1)
            render_persistent_header
            _pb_banner
            proxy_bootstrap_setup
            ;;
        2)
            worker_bootstrap_offer
            ;;
        3|"")
            echo "${DIM}  [i] Direct connection — official OpenWrt endpoints unchanged.${RESET}"
            ;;
        *)
            echo "${YELLOW}  [!] Unknown choice — continuing with a direct connection.${RESET}"
            ;;
    esac

    return 0
}
