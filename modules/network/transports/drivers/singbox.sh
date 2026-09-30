#!/bin/sh
# ============================================================
# DayPass - Transport driver : sing-box direct core (/etc/init.d/sing-box)
# LAN traffic is sent to the core's tproxy inbound (interception=tproxy)
# ============================================================

_sb_conffile() {
    local f
    f=$(transport_opt_get singbox conffile)
    [ -z "$f" ] && f=$(uci -q get sing-box.main.conffile 2>/dev/null)
    echo "${f:-/etc/sing-box/config.json}"
}

# Passwall ships the sing-box binary as a dependency, so require the standalone service and config
tdrv_singbox_detect() {
    [ -x /etc/init.d/sing-box ] && [ -f "$(_sb_conffile)" ]
}

tdrv_singbox_start() {
    uci -q get sing-box.main >/dev/null 2>&1 && {
        uci set sing-box.main.enabled=1
        uci commit sing-box
    }
    _jcore_service sing-box restart || _jcore_service sing-box start
}

tdrv_singbox_stop()   { _jcore_service sing-box stop; }
tdrv_singbox_reload() { _jcore_service sing-box restart; }

tdrv_singbox_status() {
    if _jcore_running "sing-box run"; then
        echo "config $(_sb_conffile)"
        return 0
    fi
    echo "not running"
    return 1
}

tdrv_singbox_interception() { echo "tproxy"; }

tdrv_singbox_describe() {
    echo "config $(_sb_conffile), tproxy port $(tdrv_singbox_tproxy_port 2>/dev/null || echo none)"
}

tdrv_singbox_tproxy_port() {
    local port
    port=$(transport_opt_get singbox tproxy_port)
    [ -z "$port" ] && port=$(jq -r 'first(.inbounds[]? | select(.type == "tproxy") | .listen_port) // empty' "$(_sb_conffile)" 2>/dev/null)
    [ -n "$port" ] || return 1
    echo "$port"
}

# DNS inbound: saved dns_port, else an inbound tagged "dns-in"
tdrv_singbox_dns_endpoint() {
    local port
    port=$(transport_opt_get singbox dns_port)
    [ -z "$port" ] && port=$(jq -r 'first(.inbounds[]? | select(.tag == "dns-in") | .listen_port) // empty' "$(_sb_conffile)" 2>/dev/null)
    [ -n "$port" ] || return 1
    echo "127.0.0.1#$port"
}

tdrv_singbox_dns_configure() {
    case "$1" in
        off) return 0 ;;
        doh|tunnel|hybrid) tdrv_singbox_dns_endpoint >/dev/null ;;
        *) return 3 ;;
    esac
}

# id|name|protocol|host|port|l4 (outbounds with a server, plus WireGuard endpoint peers)
tdrv_singbox_list_nodes() {
    jq -r '
        def l4: if (.type // "") | IN("hysteria", "hysteria2", "tuic", "wireguard") then "udp" else "tcp" end;
        (.outbounds[]? | select(.server != null and .tag != null)
            | "\(.tag)|\(.tag)|\(.type // "unknown")|\(.server)|\(.server_port // "")|\(l4)"),
        (.endpoints[]? | select(.tag != null) | . as $e | .peers[]? | select(.address != null)
            | "\($e.tag)|\($e.tag)|\($e.type // "wireguard")|\(.address)|\(.port // "")|udp")
    ' "$(_sb_conffile)" 2>/dev/null | tr -d '\r'
}

tdrv_singbox_active_node() {
    jq -r '.route.final // first(.outbounds[]? | select(.server != null) | .tag) // empty' "$(_sb_conffile)" 2>/dev/null
}

# Makes the chosen outbound the route default (route.final)
tdrv_singbox_select_node() {
    local file
    file=$(_sb_conffile)

    jq -e --arg tag "$1" 'any((.outbounds[]?, .endpoints[]?); .tag == $tag)' "$file" >/dev/null 2>&1 || return 1
    _jcore_edit_config "$file" '.route = ((.route // {}) + {final: $tag})' "$1" sing-box check -c || return 1
    _jcore_service sing-box restart
}
