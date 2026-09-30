#!/bin/sh
# ============================================================
# DayPass - Transport driver : Passwall / Passwall2
# Both apps install their own nftables/iptables interception (interception=self)
# ============================================================

# Returns: passwall2 | passwall | none
detect_passwall_version() {
    if [ -f /etc/config/passwall2 ] || uci -q show passwall2 >/dev/null 2>&1; then
        echo "passwall2"
        return
    fi

    if [ -f /etc/config/passwall ] || uci -q show passwall >/dev/null 2>&1; then
        echo "passwall"
        return
    fi

    if command -v pkg_installed >/dev/null 2>&1; then
        if pkg_installed "luci-app-passwall2" || pkg_installed "passwall2"; then
            echo "passwall2"
            return
        fi
        if pkg_installed "luci-app-passwall" || pkg_installed "passwall"; then
            echo "passwall"
            return
        fi
    fi

    echo "none"
}

_pw_detect() {
    [ -f "/etc/config/$1" ] || uci -q show "$1" >/dev/null 2>&1 || [ -x "/etc/init.d/$1" ]
}

_pw_service() {
    [ -x "/etc/init.d/$1" ] || return 1
    /etc/init.d/"$1" "$2" >/dev/null 2>&1
}

_pw_reload() {
    _pw_service "$1" reload || _pw_service "$1" restart || true
}

# Set a UCI option on the first matching Passwall section that already exists.
_pw_set() {
    local pkg="$1"
    local key="$2"
    local val="$3"
    local sect

    for sect in global global_dns global_forwarding global_other; do
        if uci -q get "${pkg}.@${sect}[0]" >/dev/null 2>&1; then
            uci set "${pkg}.@${sect}[0].${key}=${val}" 2>/dev/null && return 0
        fi
    done
    uci set "${pkg}.@global[0].${key}=${val}" 2>/dev/null || return 1
}

_pw_get() {
    local pkg="$1"
    local key="$2"
    local sect val

    for sect in global global_dns global_forwarding global_other; do
        val=$(uci -q get "${pkg}.@${sect}[0].${key}" 2>/dev/null) || true
        if [ -n "$val" ]; then
            echo "$val"
            return 0
        fi
    done
    return 1
}

_pw_start() {
    uci set "$1.@global[0].enabled=1" 2>/dev/null
    uci commit "$1"
    _pw_service "$1" restart || _pw_service "$1" start
}

_pw_stop() {
    _pw_service "$1" stop
}

_pw_status() {
    local enabled
    enabled=$(uci -q get "$1.@global[0].enabled" 2>/dev/null)

    if nft list table inet "$1" >/dev/null 2>&1 || iptables -t mangle -S 2>/dev/null | grep -qi "$1"; then
        echo "interception active, enabled=${enabled:-0}"
        return 0
    fi
    if pgrep -f "/usr/share/$1/" >/dev/null 2>&1; then
        echo "processes running, enabled=${enabled:-0}"
        return 0
    fi
    echo "enabled=${enabled:-0}"
    return 1
}

_pw_apply_route_mode() {
    local pkg="$1"

    case "$2" in
        iran_direct)
            uci set "$pkg.@global[0].enabled=1" 2>/dev/null
            uci set "$pkg.@global[0].tcp_proxy_mode=gfwlist" 2>/dev/null || \
            uci set "$pkg.@global[0].tcp_proxy_mode=proxy" 2>/dev/null
            [ "$pkg" = "passwall2" ] && uci set "$pkg.@global[0].localhost_proxy=0" 2>/dev/null
            ;;
        global_proxy)
            uci set "$pkg.@global[0].enabled=1" 2>/dev/null
            uci set "$pkg.@global[0].tcp_proxy_mode=proxy" 2>/dev/null
            uci set "$pkg.@global[0].udp_proxy_mode=proxy" 2>/dev/null
            ;;
        direct_only)
            uci set "$pkg.@global[0].enabled=0" 2>/dev/null
            uci set "$pkg.@global[0].tcp_proxy_mode=disable" 2>/dev/null
            ;;
        *)
            return 1
            ;;
    esac

    uci commit "$pkg"
    _pw_reload "$pkg"
    return 0
}

# Port Passwall listens on for local DNS (dnsmasq upstream).
_pw_dns_listen_port() {
    local pkg="$1"
    local raw port

    port=$(_pw_get "$pkg" dns_listen_port 2>/dev/null) || true
    [ -z "$port" ] && port=$(_pw_get "$pkg" dns_port 2>/dev/null) || true
    [ -z "$port" ] && port=$(_pw_get "$pkg" listen_port 2>/dev/null) || true
    if [ -z "$port" ]; then
        raw=$(_pw_get "$pkg" dns_listen 2>/dev/null) || true
        port=$(echo "$raw" | sed -n 's/.*[#:]\([0-9][0-9]*\)$/\1/p')
    fi
    if [ -n "$port" ]; then
        echo "$port"
        return
    fi
    if [ "$pkg" = "passwall" ]; then
        echo "7913"
    else
        echo "15353"
    fi
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
            _pw_set "$pkg" "dns_doh" "$doh" || true
            _pw_set "$pkg" "v2ray_dns_mode" "doh" || true
            _pw_set "$pkg" "dns_mode" "doh" || true
            ;;
        tunnel)
            _pw_set "$pkg" "enabled" "1" || true
            _pw_set "$pkg" "dns_redirect" "1" || true
            _pw_set "$pkg" "remote_dns" "$remote" || true
            _pw_set "$pkg" "remote_dns_protocol" "tcp" || true
            _pw_set "$pkg" "v2ray_dns_mode" "tcp" || true
            _pw_set "$pkg" "dns_mode" "tcp" || true
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
            _pw_set "$pkg" "dns_doh" "$doh" || true
            _pw_set "$pkg" "v2ray_dns_mode" "doh" || true
            _pw_set "$pkg" "dns_mode" "doh" || true
            ;;
        *)
            return 3
            ;;
    esac

    uci commit "$pkg" 2>/dev/null || true
    _pw_reload "$pkg"
    return 0
}

# id|name|protocol|host|port|l4
_pw_list_nodes() {
    local pkg="$1"
    local sect name proto host port l4

    for sect in $(uci -q show "$pkg" 2>/dev/null | sed -n "s/^$pkg\.\([^.]*\)=nodes$/\1/p"); do
        host=$(uci -q get "$pkg.$sect.address")
        [ -n "$host" ] || continue
        port=$(uci -q get "$pkg.$sect.port")
        name=$(uci -q get "$pkg.$sect.remarks" | tr '|' '/')
        proto=$(uci -q get "$pkg.$sect.protocol")
        [ -z "$proto" ] && proto=$(uci -q get "$pkg.$sect.type")
        case "$proto" in
            hysteria*|tuic|wireguard|WireGuard) l4="udp" ;;
            *) l4="tcp" ;;
        esac
        printf '%s|%s|%s|%s|%s|%s\n' "$sect" "${name:-$sect}" "${proto:-unknown}" "$host" "$port" "$l4"
    done
}

_pw_active_node() {
    uci -q get "$1.@global[0].node" 2>/dev/null || uci -q get "$1.@global[0].tcp_node" 2>/dev/null
}

_pw_select_node() {
    local pkg="$1"
    local sect="$2"

    [ "$(uci -q get "$pkg.$sect" 2>/dev/null)" = "nodes" ] || return 1

    uci set "$pkg.@global[0].node=$sect"
    uci -q get "$pkg.@global[0].tcp_node" >/dev/null 2>&1 && uci set "$pkg.@global[0].tcp_node=$sect"
    uci commit "$pkg"
    _pw_reload "$pkg"
}

_pw_node_exists() {
    uci show "$1" 2>/dev/null | grep -q "remarks='$2'"
}

# $1 pkg, $2 config file, $3 config name
_pw_push_node() {
    local pkg="$1"
    local file="$2"
    local conf_name="$3"
    local share_link protocol remarks section label

    share_link=$(jq -r '.share_link // empty' "$file")
    protocol=$(jq -r '.protocol // empty' "$file")

    if [ -z "$share_link" ]; then
        log_error "No share_link in config: [$conf_name]"
        return 1
    fi

    if ! parse_share_link "$share_link"; then
        log_warn "Could not fully parse share link for [$conf_name]. Adding with limited info."
    fi

    remarks="${PARSED_REMARKS:-$conf_name}"
    if [ "$pkg" = "passwall2" ]; then
        label="Passwall2"
    else
        label="Passwall1"
    fi

    # Skip duplicate
    if _pw_node_exists "$pkg" "$remarks"; then
        log_warn "Node [$remarks] already exists in $pkg. Skipped."
        return 0
    fi

    log_info "Adding node to $label → [$remarks]"

    section=$(uci add "$pkg" nodes 2>/dev/null)
    if [ -z "$section" ]; then
        log_error "Failed to create node section in $label"
        return 1
    fi

    uci set "$pkg.$section.remarks=$remarks"
    uci set "$pkg.$section.type=${PARSED_PROTOCOL:-$protocol}"
    [ -n "$PARSED_ADDRESS" ]  && uci set "$pkg.$section.address=$PARSED_ADDRESS"
    [ -n "$PARSED_PORT" ]     && uci set "$pkg.$section.port=$PARSED_PORT"
    [ -n "$PARSED_UUID" ]     && uci set "$pkg.$section.uuid=$PARSED_UUID"
    [ -n "$PARSED_PASSWORD" ] && uci set "$pkg.$section.password=$PARSED_PASSWORD"
    [ -n "$PARSED_NETWORK" ]  && uci set "$pkg.$section.transport=$PARSED_NETWORK"
    [ -n "$PARSED_SECURITY" ] && uci set "$pkg.$section.tls=$PARSED_SECURITY"
    [ -n "$PARSED_SNI" ]      && uci set "$pkg.$section.tls_serverName=$PARSED_SNI"
    if [ "$pkg" = "passwall2" ]; then
        [ -n "$PARSED_FLOW" ]        && uci set "$pkg.$section.flow=$PARSED_FLOW"
        [ -n "$PARSED_FP" ]          && uci set "$pkg.$section.fingerprint=$PARSED_FP"
        [ -n "$PARSED_PATH" ]        && uci set "$pkg.$section.ws_path=$PARSED_PATH"
        [ -n "$PARSED_HOST_HEADER" ] && uci set "$pkg.$section.ws_host=$PARSED_HOST_HEADER"
    fi
    uci set "$pkg.$section.share_link=$share_link"
    uci set "$pkg.$section.enabled=1"

    uci commit "$pkg"
    log_success "Node [$remarks] added to $label ($section)"
}

# Removes the unused daypass_balancer section written by older DayPass releases
_pw_cleanup() {
    uci -q get "$1.daypass_balancer" >/dev/null 2>&1 || return 0
    uci -q delete "$1.daypass_balancer"
    uci commit "$1"
}

# ------------------------------------------------------------
# Hook table
# ------------------------------------------------------------
tdrv_passwall2_detect()           { _pw_detect passwall2; }
tdrv_passwall2_start()            { _pw_start passwall2; }
tdrv_passwall2_stop()             { _pw_stop passwall2; }
tdrv_passwall2_status()           { _pw_status passwall2; }
tdrv_passwall2_reload()           { _pw_reload passwall2; }
tdrv_passwall2_interception()     { echo "self"; }
tdrv_passwall2_apply_route_mode() { _pw_apply_route_mode passwall2 "$1"; }
tdrv_passwall2_dns_endpoint()     { echo "127.0.0.1#$(_pw_dns_listen_port passwall2)"; }
tdrv_passwall2_dns_configure()    { _pw_dns_configure passwall2 "$1"; }
tdrv_passwall2_list_nodes()       { _pw_list_nodes passwall2; }
tdrv_passwall2_active_node()      { _pw_active_node passwall2; }
tdrv_passwall2_select_node()      { _pw_select_node passwall2 "$1"; }
tdrv_passwall2_push_node()        { _pw_push_node passwall2 "$1" "$2"; }
tdrv_passwall2_cleanup()          { _pw_cleanup passwall2; }
tdrv_passwall2_describe()         { echo "config /etc/config/passwall2, DNS port $(_pw_dns_listen_port passwall2)"; }

tdrv_passwall_detect()            { _pw_detect passwall; }
tdrv_passwall_start()             { _pw_start passwall; }
tdrv_passwall_stop()              { _pw_stop passwall; }
tdrv_passwall_status()            { _pw_status passwall; }
tdrv_passwall_reload()            { _pw_reload passwall; }
tdrv_passwall_interception()      { echo "self"; }
tdrv_passwall_apply_route_mode()  { _pw_apply_route_mode passwall "$1"; }
tdrv_passwall_dns_endpoint()      { echo "127.0.0.1#$(_pw_dns_listen_port passwall)"; }
tdrv_passwall_dns_configure()     { _pw_dns_configure passwall "$1"; }
tdrv_passwall_list_nodes()        { _pw_list_nodes passwall; }
tdrv_passwall_active_node()       { _pw_active_node passwall; }
tdrv_passwall_select_node()       { _pw_select_node passwall "$1"; }
tdrv_passwall_push_node()         { _pw_push_node passwall "$1" "$2"; }
tdrv_passwall_cleanup()           { _pw_cleanup passwall; }
tdrv_passwall_describe()          { echo "config /etc/config/passwall, DNS port $(_pw_dns_listen_port passwall)"; }
