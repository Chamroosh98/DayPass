#!/bin/sh
# ============================================================
# DayPass - Transport driver : WireGuard (netifd proto wireguard)
# LAN traffic is policy-routed into the tunnel (interception=tunnel)
# ============================================================

# Logical interface: saved setting, else the first proto=wireguard interface
_wg_network() {
    local net sect

    net=$(transport_opt_get wireguard network)
    if [ -n "$net" ] && [ "$(uci -q get "network.$net.proto")" = "wireguard" ]; then
        echo "$net"
        return 0
    fi

    for sect in $(uci -q show network 2>/dev/null | sed -n "s/^network\.\([^.]*\)\.proto='wireguard'$/\1/p"); do
        echo "$sect"
        return 0
    done
    return 1
}

_wg_peers() {
    uci -q show network 2>/dev/null | sed -n "s/^network\.\([^.]*\)=wireguard_$1$/\1/p"
}

tdrv_wireguard_detect() {
    command -v wg >/dev/null 2>&1 && _wg_network >/dev/null
}

tdrv_wireguard_start() {
    local net
    net=$(_wg_network) || return 1
    ifup "$net" >/dev/null 2>&1
}

tdrv_wireguard_stop() {
    local net
    net=$(_wg_network) || return 1
    ifdown "$net" >/dev/null 2>&1
}

tdrv_wireguard_status() {
    local net handshake
    net=$(_wg_network) || return 1

    if wg show "$net" >/dev/null 2>&1; then
        handshake=$(wg show "$net" latest-handshakes 2>/dev/null | awk '$2 > 0 {n++} END {print n+0}')
        echo "interface $net, peers with handshake: $handshake"
        return 0
    fi
    echo "interface $net down"
    return 1
}

tdrv_wireguard_reload() {
    local net
    net=$(_wg_network) || return 1
    ifup "$net" >/dev/null 2>&1
}

tdrv_wireguard_interception() { echo "tunnel"; }
tdrv_wireguard_tunnel_device() { _wg_network; }
tdrv_wireguard_tunnel_network() { _wg_network; }
tdrv_wireguard_describe() { echo "interface $(_wg_network 2>/dev/null || echo none)"; }

tdrv_wireguard_dns_endpoint() {
    local resolver
    resolver=$(transport_opt_get wireguard dns_resolver)
    [ -n "$resolver" ] || return 1
    echo "$resolver"
}

# DNS goes to a public resolver that is host-routed through the tunnel
tdrv_wireguard_dns_configure() {
    case "$1" in
        off)           transport_tunnel_dns_route wireguard "" ;;
        tunnel|hybrid) transport_tunnel_dns_route wireguard "${DNS_CF:-1.1.1.1}" ;;
        *)             return 3 ;;
    esac
}

# id|name|protocol|host|port|l4 (one line per peer with an endpoint)
tdrv_wireguard_list_nodes() {
    local net sect host port name
    net=$(_wg_network) || return 1

    for sect in $(_wg_peers "$net"); do
        host=$(uci -q get "network.$sect.endpoint_host")
        [ -n "$host" ] || continue
        port=$(uci -q get "network.$sect.endpoint_port")
        name=$(uci -q get "network.$sect.description" | tr '|' '/')
        printf '%s|%s|wireguard|%s|%s|udp\n' "$sect" "${name:-$sect}" "$host" "${port:-51820}"
    done
}

tdrv_wireguard_active_node() {
    local net sect
    net=$(_wg_network) || return 1

    for sect in $(_wg_peers "$net"); do
        [ -n "$(uci -q get "network.$sect.endpoint_host")" ] || continue
        [ "$(uci -q get "network.$sect.disabled")" = "1" ] && continue
        echo "$sect"
        return 0
    done
    return 1
}

# Enables the chosen endpoint peer and disables the other endpoint peers of the interface
tdrv_wireguard_select_node() {
    local target="$1"
    local net sect found=0
    net=$(_wg_network) || return 1

    for sect in $(_wg_peers "$net"); do
        [ -n "$(uci -q get "network.$sect.endpoint_host")" ] || continue
        if [ "$sect" = "$target" ]; then
            uci -q delete "network.$sect.disabled"
            found=1
        else
            uci set "network.$sect.disabled=1"
        fi
    done

    if [ "$found" -eq 0 ]; then
        uci revert network 2>/dev/null
        return 1
    fi

    uci commit network
    ifup "$net" >/dev/null 2>&1
}
