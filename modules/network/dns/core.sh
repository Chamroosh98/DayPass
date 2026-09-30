#!/bin/sh
# DNS Core — shared paths, active transport engine DNS hooks, dnsmasq apply

DNS_DIR="${DAYPASS_DIR:-/etc/daypass}/dns"
DNS_MODE_FILE="$DNS_DIR/mode"
DNS_DOH_URL="https://cloudflare-dns.com/dns-query"
DNS_CF="1.1.1.1"
DNS_CF2="1.0.0.1"
DNS_GOOGLE="8.8.8.8"

# Active transport engine (see transports/transport_bridge.sh), or "none"
dns_engine() {
    if command -v get_active_engine >/dev/null 2>&1; then
        get_active_engine
    else
        echo "none"
    fi
}

dns_engine_available() {
    local engine
    engine=$(dns_engine)
    [ "$engine" != "none" ] && transport_has_hook "$engine" dns_configure
}

# $1 mode: doh | tunnel | hybrid | off. Returns 3 when the engine lacks that mode.
dns_engine_configure() {
    local engine
    engine=$(dns_engine)
    [ "$engine" = "none" ] && return 3
    transport_call "$engine" dns_configure "$1"
}

# dnsmasq upstream served by the engine (e.g. 127.0.0.1#7913 or a tunnel-routed resolver)
dns_engine_endpoint() {
    local engine
    engine=$(dns_engine)
    [ "$engine" = "none" ] && return 1
    transport_call "$engine" dns_endpoint 2>/dev/null
}

dns_engine_label() {
    local engine
    engine=$(dns_engine)
    if [ "$engine" = "none" ]; then
        echo "none"
    else
        transport_engine_label "$engine"
    fi
}

# Stops engine DNS hijack / tunnel DNS routes
dns_engine_release() {
    dns_engine_available || return 0
    dns_engine_configure off >/dev/null 2>&1 || true
    return 0
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

show_dns_status() {
    local mode upstream
    mode=$(get_dns_mode)

    echo "  🧭 Current DNS Status"
    echo "  ───────────────────────────────────────────────────────────"
    echo "  🫀 Active Mode : ${GREEN}${mode}${RESET}"
    echo "  🛡️  Engine     : ${CYAN}$(dns_engine_label)${RESET}"

    upstream=$(uci -q get dhcp.@dnsmasq[0].server 2>/dev/null | tr '\n' ' ')
    if [ -n "$upstream" ]; then
        echo "  📡 dnsmasq    : ${upstream}"
    else
        echo "  📡 dnsmasq    : ${GRAY}system / WAN resolvers${RESET}"
    fi
    echo "  ───────────────────────────────────────────────────────────"
}
