#!/bin/sh
# ============================================================
# DayPass - Passwall Driver: Routing & DNS
# ============================================================

_pw_apply_iran_direct() {
    local pkg="$1" node rule core domains

    if ! node=$(_pw_real_node "$pkg"); then
        log_error "No proxy node is selected in $pkg. Pick a node first."
        return 1
    fi

    core=$(uci -q get "$pkg.$node.type" 2>/dev/null)
    [ -n "$core" ] || core="Xray"
    domains="geosite:category-ir
geosite:ir"

    rule="$PW_SHUNT_RULE_ID"
    uci -q delete "$pkg.$rule"
    uci set "$pkg.$rule=shunt_rules"
    uci set "$pkg.$rule.remarks=DayPass Iran Direct"
    uci set "$pkg.$rule.network=tcp,udp"
    uci set "$pkg.$rule.domain_list=$domains"
    uci set "$pkg.$rule.ip_list=geoip:ir"

    uci -q delete "$pkg.$PW_SHUNT_ID"
    uci set "$pkg.$PW_SHUNT_ID=nodes"
    uci set "$pkg.$PW_SHUNT_ID.remarks=DayPass Iran Direct"
    uci set "$pkg.$PW_SHUNT_ID.type=$core"
    uci set "$pkg.$PW_SHUNT_ID.protocol=_shunt"
    uci set "$pkg.$PW_SHUNT_ID.default_node=$node"
    uci set "$pkg.$PW_SHUNT_ID.$rule=_direct"

    transport_opt_set "$pkg" real_node "$node"

    uci set "$pkg.@global[0].enabled=1"
    _pw_set_global_node "$pkg" "$PW_SHUNT_ID"
    uci set "$pkg.@global[0].tcp_proxy_mode=proxy"
    uci set "$pkg.@global[0].udp_proxy_mode=proxy"
    if [ "$pkg" = "passwall2" ]; then
        uci set "$pkg.@global[0].localhost_proxy=0" 2>/dev/null || true
    fi
    return 0
}

_pw_apply_route_mode() {
    local pkg="$1"

    case "$2" in
        iran_direct)
            _pw_apply_iran_direct "$pkg" || return 1
            ;;
        global_proxy)
            _pw_restore_real_node "$pkg"
            uci set "$pkg.@global[0].enabled=1" 2>/dev/null
            uci set "$pkg.@global[0].tcp_proxy_mode=proxy" 2>/dev/null
            uci set "$pkg.@global[0].udp_proxy_mode=proxy" 2>/dev/null
            ;;
        direct_only)
            _pw_restore_real_node "$pkg"
            uci set "$pkg.@global[0].enabled=0" 2>/dev/null
            uci set "$pkg.@global[0].tcp_proxy_mode=disable" 2>/dev/null
            uci set "$pkg.@global[0].udp_proxy_mode=disable" 2>/dev/null
            ;;
        *) return 1 ;;
    esac

    uci commit "$pkg"
    _pw_reload "$pkg"
    return 0
}

_pw_dns_listen_port() {
    local pkg="$1" raw port
    port=$(_pw_get "$pkg" dns_listen_port 2>/dev/null) || true
    [ -z "$port" ] && port=$(_pw_get "$pkg" dns_port 2>/dev/null) || true
    [ -z "$port" ] && port=$(_pw_get "$pkg" listen_port 2>/dev/null) || true
    if [ -z "$port" ]; then
        raw=$(_pw_get "$pkg" dns_listen 2>/dev/null) || true
        port=$(echo "$raw" | sed -n 's/.*[#:]\([0-9][0-9]*\)$/\1/p')
    fi
    if [ -n "$port" ]; then echo "$port"; return; fi
    if [ "$pkg" = "passwall" ]; then echo "7913"; else echo "15353"; fi
}

_pw_set_v1_dns_mode() {
    local pkg="$1"
    [ "$pkg" = "passwall" ] || return 0
    case "$2" in
        udp|tcp|dns2socks|sing-box|xray) _pw_set "$pkg" "dns_mode" "$2" || true ;;
    esac
}

_pw_dns_core() {
    local pkg="$1" node type=""
    node=$(_pw_real_node "$pkg" 2>/dev/null) && type=$(uci -q get "$pkg.$node.type" 2>/dev/null)
    case "$type" in
        *[Ss]ing*) echo "sing-box" ;;
        *)         echo "xray" ;;
    esac
}

_pw_dns_configure() {
    local pkg="$1"
    local doh="${DNS_DOH_URL:-https://cloudflare-dns.com/dns-query}"
    local remote="${DNS_CF:-1.1.1.1}"

    case "$2" in
        off)
            _pw_set "$pkg" "dns_redirect" "0" || true
            uci commit "$pkg" 2>/dev/null || true
            _pw_reload "$pkg"
            return 0
            ;;
        doh)
            _pw_set "$pkg" "enabled" "1" || true
            _pw_set "$pkg" "dns_redirect" "1" || true
            _pw_set "$pkg" "remote_dns" "$remote" || true
            _pw_set "$pkg" "remote_dns_protocol" "doh" || true
            _pw_set "$pkg" "remote_dns_doh" "$doh" || true
            _pw_set_v1_dns_mode "$pkg" "$(_pw_dns_core "$pkg")"
            ;;
        tunnel)
            _pw_set "$pkg" "enabled" "1" || true
            _pw_set "$pkg" "dns_redirect" "1" || true
            _pw_set "$pkg" "remote_dns" "$remote" || true
            _pw_set "$pkg" "remote_dns_protocol" "tcp" || true
            _pw_set_v1_dns_mode "$pkg" "tcp"
            ;;
        hybrid)
            _pw_set "$pkg" "enabled" "1" || true
            _pw_set "$pkg" "dns_redirect" "1" || true
            _pw_set "$pkg" "direct_dns" "$remote" || true
            _pw_set "$pkg" "direct_dns_protocol" "doh" || true
            _pw_set "$pkg" "direct_dns_doh" "$doh" || true
            _pw_set "$pkg" "remote_dns" "$remote" || true
            _pw_set "$pkg" "remote_dns_protocol" "doh" || true
            _pw_set "$pkg" "remote_dns_doh" "$doh" || true
            _pw_set_v1_dns_mode "$pkg" "$(_pw_dns_core "$pkg")"
            ;;
        *) return 3 ;;
    esac
    uci commit "$pkg" 2>/dev/null || true
    _pw_reload "$pkg"
    return 0
}

# --- Routing Hooks ---
tdrv_passwall2_apply_route_mode() { _pw_apply_route_mode passwall2 "$1"; }
tdrv_passwall2_dns_endpoint()     { echo "127.0.0.1#$(_pw_dns_listen_port passwall2)"; }
tdrv_passwall2_dns_configure()    { _pw_dns_configure passwall2 "$1"; }

tdrv_passwall_apply_route_mode()  { _pw_apply_route_mode passwall "$1"; }
tdrv_passwall_dns_endpoint()      { echo "127.0.0.1#$(_pw_dns_listen_port passwall)"; }
tdrv_passwall_dns_configure()     { _pw_dns_configure passwall "$1"; }