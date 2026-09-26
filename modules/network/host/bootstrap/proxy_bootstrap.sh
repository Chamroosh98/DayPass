#!/bin/sh

# Purpose:
#   Offer the user (once, at the very beginning) to route package-manager
#   traffic through a local HTTP proxy, typically delivered via an SSH
#   reverse tunnel. This helps bypass ISP filtering and broken feeds.

# ---------- defaults ----------
PROXY_DEFAULT_PORT="2585"
PROXY_HOST="127.0.0.1"

# ---------- banner ----------
_pb_banner() {
    echo
    echo "  ${CYAN}${RESET}${BOLD}🌐 DayPass — Optional Network Proxy Bootstrap${RESET}"
    echo "  ${CYAN}─────────────────────────────────────────────────────────${RESET}"
    echo "  ${CYAN}${RESET}Routing DayPass traffic through a local proxy helps"
    echo "  ${CYAN}${RESET}avoid ISP filtering and broken package downloads!  "
    echo "  ${CYAN}─────────────────────────────────────────────────────────${RESET}"
    echo
}

# ---------- manual ----------
_pb_manual() {
    render_persistent_header
    echo
    echo "  ${BOLD}${WHITE}📖 Manual Setup${RESET}"
    echo "  ${DIM}──────────────────────────────────────────────────────────${RESET}"
    echo
    echo "  ${BOLD}${CYAN}🪟 Windows users :${RESET}"
    echo "  ${WHITE}1) Open your VPN / proxy client and enable a local${RESET}"
    echo "  ${WHITE}   SOCKS/HTTP listener on port ${YELLOW}[${PROXY_DEFAULT_PORT}]${WHITE}.${RESET}"
    echo "  ${WHITE}2) In Windows Settings → Proxy, set:${RESET}"
    echo "  ${GREEN}   Address : ${PROXY_HOST}${RESET}"
    echo "  ${GREEN}   Port    : ${PROXY_DEFAULT_PORT}${RESET}"
    echo "  ${WHITE}3) Re-run DayPass! it will use that proxy.${RESET}"
    echo
    echo "  ${BOLD}${CYAN}🐧 Linux / macOS users :${RESET}"
    echo "  ${WHITE}Open a reverse SSH tunnel from your machine to the router :${RESET}"
    echo
    echo "  ${YELLOW}        ssh -R ${PROXY_DEFAULT_PORT}:${PROXY_HOST}:<VPN_PORT_ON_PC> root@<ROUTER_IP> -N${RESET}"
    echo
    echo "  ${GRAY}Replace <VPN_PORT_ON_PC> with the local port your VPN${RESET}"
    echo "  ${GRAY}client listens on (e.g. 10810}), and <ROUTER_IP> with${RESET}"
    echo "  ${GRAY}your router address (e.g.192.168.1.1).${RESET}"
    echo
    echo "  ${GRAY}ℹ️  Once the tunnel is up, all package downloads will${RESET}"
    echo "  ${GRAY}flow through ${PROXY_HOST}:${PROXY_DEFAULT_PORT}.${RESET}"
    echo "  ${DIM}──────────────────────────────────────────────────────────${RESET}"
    echo
}

# ---------- detect existing proxy env ----------
_pb_detect_existing() {
    _existing="${http_proxy:-${https_proxy:-${HTTP_PROXY:-${HTTPS_PROXY:-}}}}"
    [ -n "$_existing" ] && echo "$_existing" || echo ""
}

# ---------- apply proxy env ----------
_pb_apply() {
    _port="$1"

    case "$_port" in
        ''|*[!0-9]*)
            echo "${RED}  [x] Invalid port : [${_port}]${RESET}"
            return 1
            ;;
    esac

    if [ "$_port" -lt 1 ] || [ "$_port" -gt 65535 ]; then
        echo "${RED}  [x] Port out of range : [${_port}]${RESET}"
        return 1
    fi

    PROXY_PORT="$_port"
    PROXY_URL="http://${PROXY_HOST}:${PROXY_PORT}"

    export http_proxy="$PROXY_URL"
    export https_proxy="$PROXY_URL"
    export HTTP_PROXY="$PROXY_URL"
    export HTTPS_PROXY="$PROXY_URL"
    export no_proxy="localhost,127.0.0.1,::1"
    export NO_PROXY="$no_proxy"

    echo "${GREEN}  [+] Proxy exported → ${BOLD}${PROXY_URL}${RESET}"
    return 0
}

# Public — interactive offer (NEVER blocks pipeline)
proxy_bootstrap_offer() {
    _existing="$(_pb_detect_existing)"

    # ---- already configured? just confirm ----
    if [ -n "$_existing" ]; then
        echo
        echo "${CYAN}  [i]${RESET} Proxy already configured : ${YELLOW}[${_existing}]${RESET}"
        printf "  Re-configure proxy? ${DIM}[y/N]${RESET} : "
        read -r _ans </dev/tty
        case "$_ans" in
            [yY]|[yY][eE][sS]) ;;   # fall through to setup
            *) return 0 ;;
        esac
    fi

    render_persistent_header
    _pb_banner

    printf "  Route DayPass traffic through a local proxy? ${DIM}[y/N/help]${RESET} : "
    read -r _choice </dev/tty

    case "$_choice" in
        [yY]|[yY][eE][sS])
            ;;  # proceed to port prompt
        [hH]|[hH][eE][lL][pP])
            _pb_manual
            printf "  Continue with proxy setup? ${DIM}[y/N]${RESET} : "
            read -r _c2 </dev/tty
            case "$_c2" in
                [yY]|[yY][eE][sS]) ;;  # proceed
                *)
                    echo "${DIM}  [i] Skipped — continuing without proxy.${RESET}"
                    return 0
                    ;;
            esac
            ;;
        *)
            # empty / n / no / anything else → skip
            echo "${DIM}  [i] Skipped — continuing without proxy.${RESET}"
            return 0
            ;;
    esac

    # ---- ask for port ----
    printf "  Proxy port on router side ${DIM}[default ${PROXY_DEFAULT_PORT}]${RESET} : "
    read -r _port </dev/tty
    [ -z "$_port" ] && _port="$PROXY_DEFAULT_PORT"

    # ---- apply (never fails the caller) ----
    if _pb_apply "$_port"; then
        echo "${GREEN}  [i] All subsequent downloads will use this proxy.${RESET}"
    else
        echo "${YELLOW}  [!] Proxy setup failed — continuing without proxy.${RESET}"
    fi

    return 0
}

# Public — helpers (optional use elsewhere)

proxy_bootstrap_status() {
    _p="$(_pb_detect_existing)"
    if [ -n "$_p" ]; then
        echo "${GREEN}  [+] Proxy active : [${_p}]${RESET}"
    else
        echo "${YELLOW}  [!] No proxy configured.${RESET}"
    fi
}

proxy_bootstrap_clear() {
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
    unset no_proxy NO_PROXY
    unset PROXY_PORT PROXY_URL
    echo "${GREEN}  [+] Proxy environment cleared!${RESET}"
}