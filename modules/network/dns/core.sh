#!/bin/sh
# DNS Core — shared paths, Passwall UCI helpers, dnsmasq apply

DNS_DIR="${DAYPASS_DIR:-/etc/daypass}/dns"
DNS_MODE_FILE="$DNS_DIR/mode"
DNS_DOH_URL="https://cloudflare-dns.com/dns-query"
DNS_CF="1.1.1.1"
DNS_CF2="1.0.0.1"
DNS_GOOGLE="8.8.8.8"

dns_pw_pkg() {
    if command -v detect_passwall_version >/dev/null 2>&1; then
        detect_passwall_version
        return
    fi
    if [ -f /etc/config/passwall2 ] || uci -q show passwall2 >/dev/null 2>&1; then
        echo "passwall2"
        return
    fi
    if [ -f /etc/config/passwall ] || uci -q show passwall >/dev/null 2>&1; then
        echo "passwall"
        return
    fi
    echo "none"
}

dns_passwall_available() {
    [ "$(dns_pw_pkg)" != "none" ]
}

get_dns_mode() {
    if [ -f "$DNS_MODE_FILE" ]; then
        cat "$DNS_MODE_FILE"
    else
        echo "system"
    fi
}

set_dns_mode() {
    mkdir -p "$DNS_DIR" 2>/dev/null || {
        log_error "Cannot create DNS state dir [$DNS_DIR]"
        return 1
    }
    echo "$1" > "$DNS_MODE_FILE"
}

dns_restart_dnsmasq() {
    if [ -x /etc/init.d/dnsmasq ]; then
        /etc/init.d/dnsmasq reload >/dev/null 2>&1 || \
            /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
    fi
}

dns_restart_passwall() {
    local pkg
    pkg=$(dns_pw_pkg)
    case "$pkg" in
        passwall2)
            /etc/init.d/passwall2 reload >/dev/null 2>&1 || \
                /etc/init.d/passwall2 restart >/dev/null 2>&1 || true
            ;;
        passwall)
            /etc/init.d/passwall reload >/dev/null 2>&1 || \
                /etc/init.d/passwall restart >/dev/null 2>&1 || true
            ;;
    esac
}

# Set a UCI option on the first matching Passwall section that already exists.
dns_pw_set() {
    local key="$1"
    local val="$2"
    local pkg sect
    pkg=$(dns_pw_pkg)
    [ "$pkg" = "none" ] && return 1

    for sect in global global_dns global_forwarding global_other; do
        if uci -q get "${pkg}.@${sect}[0]" >/dev/null 2>&1; then
            uci set "${pkg}.@${sect}[0].${key}=${val}" 2>/dev/null && return 0
        fi
    done
    uci set "${pkg}.@global[0].${key}=${val}" 2>/dev/null || return 1
}

dns_pw_get() {
    local key="$1"
    local pkg sect val
    pkg=$(dns_pw_pkg)
    [ "$pkg" = "none" ] && return 1

    for sect in global global_dns global_forwarding global_other; do
        val=$(uci -q get "${pkg}.@${sect}[0].${key}" 2>/dev/null) || true
        if [ -n "$val" ]; then
            echo "$val"
            return 0
        fi
    done
    return 1
}

dns_pw_commit() {
    local pkg
    pkg=$(dns_pw_pkg)
    [ "$pkg" = "none" ] && return 1
    uci commit "$pkg" 2>/dev/null || true
}

dns_pw_enable() {
    [ "$(dns_pw_pkg)" = "none" ] && return 1
    dns_pw_set "enabled" "1" || true
}

# Port Passwall listens on for local DNS (dnsmasq upstream).
dns_pw_listen_port() {
    local raw port
    port=$(dns_pw_get dns_listen_port 2>/dev/null) || true
    [ -z "$port" ] && port=$(dns_pw_get dns_port 2>/dev/null) || true
    [ -z "$port" ] && port=$(dns_pw_get listen_port 2>/dev/null) || true
    if [ -z "$port" ]; then
        raw=$(dns_pw_get dns_listen 2>/dev/null) || true
        port=$(echo "$raw" | sed -n 's/.*[#:]\([0-9][0-9]*\)$/\1/p')
    fi
    if [ -n "$port" ]; then
        echo "$port"
        return
    fi
    if [ "$(dns_pw_pkg)" = "passwall" ]; then
        echo "7913"
    else
        echo "15353"
    fi
}

dns_https_proxy_port() {
    local port
    port=$(uci -q get https-dns-proxy.@https-dns-proxy[0].listen_port 2>/dev/null) || true
    if [ -n "$port" ]; then
        echo "$port"
        return 0
    fi
    if [ -f /etc/config/https-dns-proxy ]; then
        echo "5053"
        return 0
    fi
    return 1
}

dns_stubby_port() {
    if command -v stubby >/dev/null 2>&1 || [ -f /etc/stubby/stubby.yml ]; then
        echo "5453"
        return 0
    fi
    return 1
}

dns_dnsmasq_reset() {
    uci -q delete dhcp.@dnsmasq[0].noresolv
    uci -q delete dhcp.@dnsmasq[0].server
    uci -q delete dhcp.@dnsmasq[0].strictorder
}

dns_dnsmasq_forward_only() {
    local addr
    dns_dnsmasq_reset
    uci set dhcp.@dnsmasq[0].noresolv='1'
    for addr in "$@"; do
        [ -n "$addr" ] && uci add_list dhcp.@dnsmasq[0].server="$addr"
    done
}

dns_dnsmasq_commit() {
    uci commit dhcp 2>/dev/null || true
    dns_restart_dnsmasq
}

dns_configure_passwall_doh() {
    dns_passwall_available || return 1
    dns_pw_enable
    dns_pw_set "dns_redirect" "1" || true
    dns_pw_set "remote_dns" "$DNS_CF" || true
    dns_pw_set "remote_dns_protocol" "doh" || true
    dns_pw_set "remote_dns_doh" "$DNS_DOH_URL" || true
    dns_pw_set "dns_doh" "$DNS_DOH_URL" || true
    dns_pw_set "v2ray_dns_mode" "doh" || true
    dns_pw_set "dns_mode" "doh" || true
    dns_pw_commit
    dns_restart_passwall
}

dns_configure_passwall_tunnel() {
    dns_passwall_available || return 1
    dns_pw_enable
    dns_pw_set "dns_redirect" "1" || true
    dns_pw_set "remote_dns" "$DNS_CF" || true
    dns_pw_set "remote_dns_protocol" "tcp" || true
    dns_pw_set "v2ray_dns_mode" "tcp" || true
    dns_pw_set "dns_mode" "tcp" || true
    dns_pw_commit
    dns_restart_passwall
}

dns_configure_passwall_hybrid() {
    dns_passwall_available || return 1
    dns_pw_enable
    dns_pw_set "dns_redirect" "1" || true
    dns_pw_set "direct_dns" "$DNS_CF" || true
    dns_pw_set "direct_dns_protocol" "doh" || true
    dns_pw_set "direct_dns_doh" "$DNS_DOH_URL" || true
    dns_pw_set "remote_dns" "$DNS_CF" || true
    dns_pw_set "remote_dns_protocol" "doh" || true
    dns_pw_set "remote_dns_doh" "$DNS_DOH_URL" || true
    dns_pw_set "dns_doh" "$DNS_DOH_URL" || true
    dns_pw_set "v2ray_dns_mode" "doh" || true
    dns_pw_set "dns_mode" "doh" || true
    dns_pw_commit
    dns_restart_passwall
}

dns_disable_passwall_hijack() {
    dns_passwall_available || return 0
    dns_pw_set "dns_redirect" "0" || true
    dns_pw_commit
    dns_restart_passwall
}

show_dns_status() {
    local mode pkg upstream
    mode=$(get_dns_mode)
    pkg=$(dns_pw_pkg)

    echo "  🧭 Current DNS Status"
    echo "  ───────────────────────────────────────────────────────────"
    echo "  🫀 Active Mode : ${GREEN}${mode}${RESET}"
    echo "  🛡️  Passwall   : ${CYAN}${pkg}${RESET}"

    upstream=$(uci -q get dhcp.@dnsmasq[0].server 2>/dev/null | tr '\n' ' ')
    if [ -n "$upstream" ]; then
        echo "  📡 dnsmasq    : ${upstream}"
    else
        echo "  📡 dnsmasq    : ${GRAY}system / WAN resolvers${RESET}"
    fi
    echo "  ───────────────────────────────────────────────────────────"
}
