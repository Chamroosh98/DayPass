#!/bin/sh
# ============================================================
# DayPass - Transport driver : OpenVPN (/etc/config/openvpn instances)
# LAN traffic is policy-routed into the tun device (interception=tunnel)
# ============================================================

_ovpn_sections() {
    uci -q show openvpn 2>/dev/null | sed -n "s/^openvpn\.\([^.]*\)=openvpn$/\1/p"
}

_ovpn_enabled() {
    [ "$(uci -q get "openvpn.$1.enabled")" = "1" ] || [ "$(uci -q get "openvpn.$1.enable")" = "1" ]
}

# Prints "host port proto" for an instance (inline remote option or .ovpn file)
_ovpn_remote() {
    local sect="$1"
    local remote proto conf

    remote=$(uci -q get "openvpn.$sect.remote" 2>/dev/null | head -n 1)
    proto=$(uci -q get "openvpn.$sect.proto" 2>/dev/null)
    conf=$(uci -q get "openvpn.$sect.config" 2>/dev/null)

    if [ -z "$remote" ] && [ -n "$conf" ] && [ -f "$conf" ]; then
        remote=$(sed -n 's/^[[:space:]]*remote[[:space:]]\{1,\}//p' "$conf" | head -n 1)
        [ -z "$proto" ] && proto=$(sed -n 's/^[[:space:]]*proto[[:space:]]\{1,\}\([a-z0-9-]*\).*/\1/p' "$conf" | head -n 1)
    fi

    [ -n "$remote" ] || return 1
    set -- $remote
    [ -n "$3" ] && proto="$3"
    echo "$1 ${2:-1194} ${proto:-udp}"
}

tdrv_openvpn_detect() {
    [ -x /etc/init.d/openvpn ] && [ -n "$(_ovpn_sections)" ]
}

tdrv_openvpn_start()  { /etc/init.d/openvpn start >/dev/null 2>&1; }
tdrv_openvpn_stop()   { /etc/init.d/openvpn stop >/dev/null 2>&1; }
tdrv_openvpn_reload() { /etc/init.d/openvpn reload >/dev/null 2>&1 || /etc/init.d/openvpn restart >/dev/null 2>&1; }

tdrv_openvpn_status() {
    local dev
    dev=$(tdrv_openvpn_tunnel_device)

    if pgrep openvpn >/dev/null 2>&1; then
        if ip link show "$dev" >/dev/null 2>&1; then
            echo "device $dev up"
        else
            echo "process running, device $dev missing"
        fi
        return 0
    fi
    echo "not running"
    return 1
}

tdrv_openvpn_interception() { echo "tunnel"; }
tdrv_openvpn_describe() { echo "device $(tdrv_openvpn_tunnel_device), instances $(_ovpn_sections | wc -l | tr -d ' ')"; }

tdrv_openvpn_tunnel_device() {
    transport_opt_get openvpn device tun0
}

tdrv_openvpn_tunnel_network() {
    local net
    net=$(transport_opt_get openvpn network)
    [ -n "$net" ] && [ -n "$(uci -q get "network.$net")" ] || return 1
    echo "$net"
}

tdrv_openvpn_dns_endpoint() {
    local resolver
    resolver=$(transport_opt_get openvpn dns_resolver)
    [ -n "$resolver" ] || return 1
    echo "$resolver"
}

tdrv_openvpn_dns_configure() {
    case "$1" in
        off)           transport_tunnel_dns_route openvpn "" ;;
        tunnel|hybrid) transport_tunnel_dns_route openvpn "${DNS_CF:-1.1.1.1}" ;;
        *)             return 3 ;;
    esac
}

# id|name|protocol|host|port|l4
tdrv_openvpn_list_nodes() {
    local sect remote l4

    for sect in $(_ovpn_sections); do
        remote=$(_ovpn_remote "$sect") || continue
        set -- $remote
        case "$3" in
            tcp*) l4="tcp" ;;
            *)    l4="udp" ;;
        esac
        printf '%s|%s|openvpn-%s|%s|%s|%s\n' "$sect" "$sect" "$3" "$1" "$2" "$l4"
    done
}

tdrv_openvpn_active_node() {
    local sect
    for sect in $(_ovpn_sections); do
        _ovpn_enabled "$sect" && { echo "$sect"; return 0; }
    done
    return 1
}

# Enables exactly one instance and restarts OpenVPN
tdrv_openvpn_select_node() {
    local target="$1"
    local sect

    [ "$(uci -q get "openvpn.$target" 2>/dev/null)" = "openvpn" ] || return 1

    for sect in $(_ovpn_sections); do
        _ovpn_remote "$sect" >/dev/null || continue
        if [ "$sect" = "$target" ]; then
            uci set "openvpn.$sect.enabled=1"
        else
            uci set "openvpn.$sect.enabled=0"
            uci -q delete "openvpn.$sect.enable"
        fi
    done

    uci commit openvpn
    /etc/init.d/openvpn restart >/dev/null 2>&1
}
