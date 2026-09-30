#!/bin/sh
# ============================================================
# DayPass - Transport driver : Xray direct core (/etc/init.d/xray)
# LAN traffic is sent to the core's TPROXY inbound (interception=tproxy)
# ============================================================

_xr_conffile() {
    local f
    f=$(transport_opt_get xray_direct conffile)
    [ -z "$f" ] && f=$(uci -q get xray.config.conffiles 2>/dev/null | awk '{print $1}')
    echo "${f:-/etc/xray/config.json}"
}

_xr_validate() {
    xray run -test -c "$1"
}

# Passwall ships the xray binary as a dependency, so require the standalone service and config
tdrv_xray_direct_detect() {
    [ -x /etc/init.d/xray ] && [ -f "$(_xr_conffile)" ]
}

tdrv_xray_direct_start() {
    uci -q get xray.enabled >/dev/null 2>&1 && {
        uci set xray.enabled.enabled=1
        uci commit xray
    }
    _jcore_service xray restart || _jcore_service xray start
}

tdrv_xray_direct_stop()   { _jcore_service xray stop; }
tdrv_xray_direct_reload() { _jcore_service xray restart; }

tdrv_xray_direct_status() {
    if _jcore_running "/usr/bin/xray"; then
        echo "config $(_xr_conffile)"
        return 0
    fi
    echo "not running"
    return 1
}

tdrv_xray_direct_interception() { echo "tproxy"; }

tdrv_xray_direct_describe() {
    echo "config $(_xr_conffile), tproxy port $(tdrv_xray_direct_tproxy_port 2>/dev/null || echo none)"
}

# dokodemo-door / tunnel inbound with sockopt.tproxy set
tdrv_xray_direct_tproxy_port() {
    local port
    port=$(transport_opt_get xray_direct tproxy_port)
    [ -z "$port" ] && port=$(jq -r '
        first(.inbounds[]? | select((.protocol == "dokodemo-door" or .protocol == "tunnel")
            and ((.streamSettings.sockopt.tproxy // "off") != "off")) | .port) // empty
    ' "$(_xr_conffile)" 2>/dev/null)
    [ -n "$port" ] || return 1
    echo "$port"
}

tdrv_xray_direct_dns_endpoint() {
    local port
    port=$(transport_opt_get xray_direct dns_port)
    [ -z "$port" ] && port=$(jq -r 'first(.inbounds[]? | select(.tag == "dns-in") | .port) // empty' "$(_xr_conffile)" 2>/dev/null)
    [ -n "$port" ] || return 1
    echo "127.0.0.1#$port"
}

tdrv_xray_direct_dns_configure() {
    case "$1" in
        off) return 0 ;;
        doh|tunnel|hybrid) tdrv_xray_direct_dns_endpoint >/dev/null ;;
        *) return 3 ;;
    esac
}

# id|name|protocol|host|port|l4 (vnext / servers / wireguard peers)
tdrv_xray_direct_list_nodes() {
    jq -r '
        .outbounds[]? | select(.tag != null) | . as $o
        | ( (.settings.vnext[]?   | "\($o.tag)|\($o.tag)|\($o.protocol)|\(.address)|\(.port)|tcp"),
            (.settings.servers[]? | "\($o.tag)|\($o.tag)|\($o.protocol)|\(.address)|\(.port)|tcp"),
            (.settings.peers[]?   | select(.endpoint != null)
                | (.endpoint | tostring) as $ep
                | ($ep | split(":")) as $p
                | "\($o.tag)|\($o.tag)|\($o.protocol)|\($p[:-1] | join(":") | ltrimstr("[") | rtrimstr("]"))|\($p[-1])|udp") )
    ' "$(_xr_conffile)" 2>/dev/null | tr -d '\r'
}

# Xray uses the first outbound as the default
tdrv_xray_direct_active_node() {
    jq -r '.outbounds[0].tag // empty' "$(_xr_conffile)" 2>/dev/null
}

tdrv_xray_direct_select_node() {
    local file
    file=$(_xr_conffile)

    jq -e --arg tag "$1" 'any(.outbounds[]?; .tag == $tag)' "$file" >/dev/null 2>&1 || return 1
    _jcore_edit_config "$file" '.outbounds = ([.outbounds[] | select(.tag == $tag)] + [.outbounds[] | select(.tag != $tag)])' \
        "$1" _xr_validate || return 1
    _jcore_service xray restart
}
