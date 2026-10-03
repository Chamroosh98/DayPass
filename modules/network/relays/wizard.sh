#!/bin/sh

# Purpose:
#   Reach OpenWrt feeds through a local HTTP proxy, a Cloudflare Worker
#   mirror, or a direct connection. Startup skips this wizard when a
#   custom feed host or http_proxy is already set. The main menu can
#   open it later, and asks before overwriting that configuration.

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

# Official OpenWrt feed host. Anything else in the feed files is a custom mirror.
_BS_UPSTREAM_HOST="downloads.openwrt.org"

# $1 feed file. Prints the first non-official host.
_bs_custom_host_from() {
    _bs_file="$1"
    [ -f "$_bs_file" ] || return 1

    while IFS= read -r _bs_line || [ -n "$_bs_line" ]; do
        case "$_bs_line" in
            ''|'#'*) continue ;;
        esac
        case "$_bs_line" in
            *://*) ;;
            *) continue ;;
        esac
        _bs_host="${_bs_line#*://}"
        _bs_host="${_bs_host%%/*}"
        _bs_host="${_bs_host%% *}"
        case "$_bs_host" in
            ''|"$_BS_UPSTREAM_HOST") continue ;;
        esac
        printf '%s' "$_bs_host"
        return 0
    done < "$_bs_file"
    return 1
}

# Sets BOOTSTRAP_ACTIVE_URL (shown on skip) and BOOTSTRAP_ACTIVE_HOST (shown on overwrite).
bootstrap_detect_active() {
    BOOTSTRAP_ACTIVE_URL=""
    BOOTSTRAP_ACTIVE_HOST=""

    for _bs_feed in /etc/opkg/distfeeds.conf /etc/apk/repositories; do
        if _bs_host="$(_bs_custom_host_from "$_bs_feed")"; then
            BOOTSTRAP_ACTIVE_HOST="$_bs_host"
            BOOTSTRAP_ACTIVE_URL="https://${_bs_host}"
            return 0
        fi
    done

    _bs_proxy="${http_proxy:-${https_proxy:-${HTTP_PROXY:-${HTTPS_PROXY:-}}}}"
    if [ -n "$_bs_proxy" ]; then
        BOOTSTRAP_ACTIVE_URL="$_bs_proxy"
        _bs_host="${_bs_proxy#*://}"
        BOOTSTRAP_ACTIVE_HOST="${_bs_host%%/*}"
        return 0
    fi

    return 1
}

# Startup: skip the wizard when a mirror or proxy is already in place.
network_bootstrap_startup() {
    if bootstrap_detect_active; then
        BOOTSTRAP_SKIP_NOTICE="[+] Active package mirror detected: [${BOOTSTRAP_ACTIVE_URL}] -> Bypassing Bootstrap Wizard."
        return 0
    fi
    network_bootstrap_offer
    return 0
}

# Main-menu entry. Confirms before replacing a mirror or proxy that already works.
network_bootstrap_from_menu() {
    local _answer=""

    if bootstrap_detect_active; then
        render_persistent_header
        printf '  %s[!] Active configuration found: [%s]%s\n' "$YELLOW" "$BOOTSTRAP_ACTIVE_HOST" "$RESET"
        printf '  %s⁉️ Overwrite existing mirror settings?%s %s[y/N]%s : ' "$YELLOW" "$RESET" "$GRAY" "$RESET"
        if ! read -r _answer </dev/tty; then
            return 0
        fi
        case "$_answer" in
            y|Y) ;;
            *)
                printf '  %s[i] Current mirror kept.%s\n' "$GRAY" "$RESET"
                sleep 1
                return 0
                ;;
        esac
    fi

    network_bootstrap_offer
    return 0
}

# Public — interactive dispatcher (NEVER blocks / fails the pipeline)
network_bootstrap_offer() {
    local _choice

    while true; do
        render_persistent_header
        _nb_banner
        _nb_menu
        if command -v ui_nav_footer >/dev/null 2>&1; then
            ui_nav_footer
        fi
        printf "  How should package downloads be prepared? [1-3] : "
        if ! read -r _choice </dev/tty; then
            return 0
        fi

        case "$_choice" in
            h|H)
                if command -v ui_show_help >/dev/null 2>&1; then
                    ui_show_help "bootstrap_wizard"
                fi
                continue
                ;;
            q|Q)
                command -v daypass_quit >/dev/null 2>&1 && daypass_quit
                return 0
                ;;
            0)
                return 0
                ;;
        esac
        break
    done

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
