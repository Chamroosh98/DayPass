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

# ------------------------------------------------------------
# Sections DayPass owns inside the Passwall config
# ------------------------------------------------------------
PW_SHUNT_ID="daypass_shunt"
PW_SHUNT_RULE_ID="daypass_ir_rule"
PW_BALANCER_ID="daypass_balancer"
PW_SUBSCRIBE_GROUP="DayPass"

# Node ids DayPass generates itself; these never point at a real server
_pw_is_synthetic_node() {
    case "$1" in
        "$PW_SHUNT_ID"|"$PW_BALANCER_ID") return 0 ;;
    esac
    return 1
}

_pw_node_ids() {
    uci -q show "$1" 2>/dev/null | sed -n "s/^$1\.\([^.]*\)=nodes$/\1/p"
}

_pw_is_node() {
    [ "$(uci -q get "$1.$2" 2>/dev/null)" = "nodes" ]
}

_pw_node_id_by_remarks() {
    local pkg="$1"
    local want="$2"
    local sect

    [ -n "$want" ] || return 1
    for sect in $(_pw_node_ids "$pkg"); do
        if [ "$(uci -q get "$pkg.$sect.remarks" 2>/dev/null)" = "$want" ]; then
            echo "$sect"
            return 0
        fi
    done
    return 1
}

# Prints the real server node the user picked. When @global[0].node points at
# one of DayPass's synthetic nodes, the real one is recovered from it.
_pw_real_node() {
    local pkg="$1"
    local cur cand

    cur=$(uci -q get "$pkg.@global[0].node" 2>/dev/null)
    [ -z "$cur" ] && cur=$(uci -q get "$pkg.@global[0].tcp_node" 2>/dev/null)
    if [ -n "$cur" ] && ! _pw_is_synthetic_node "$cur" && _pw_is_node "$pkg" "$cur"; then
        echo "$cur"
        return 0
    fi

    for cand in \
        "$(uci -q get "$pkg.$PW_SHUNT_ID.default_node" 2>/dev/null)" \
        "$(transport_opt_get "$pkg" real_node)" \
        "$(uci -q get "$pkg.$PW_BALANCER_ID.fallback_node" 2>/dev/null)" \
        "$(uci -q get "$pkg.$PW_BALANCER_ID.balancing_node" 2>/dev/null | cut -d' ' -f1)"
    do
        if [ -n "$cand" ] && ! _pw_is_synthetic_node "$cand" && _pw_is_node "$pkg" "$cand"; then
            echo "$cand"
            return 0
        fi
    done
    return 1
}

# Points Passwall at a node id (v2 uses 'node', v1 uses tcp_node / udp_node)
_pw_set_global_node() {
    local pkg="$1"
    local id="$2"
    local udp

    uci set "$pkg.@global[0].node=$id"
    if uci -q get "$pkg.@global[0].tcp_node" >/dev/null 2>&1; then
        uci set "$pkg.@global[0].tcp_node=$id"
    fi

    udp=$(uci -q get "$pkg.@global[0].udp_node" 2>/dev/null)
    case "$udp" in
        ''|nil|tcp) ;;   # unset, disabled or "same as TCP": leave the user's choice
        *) uci set "$pkg.@global[0].udp_node=$id" ;;
    esac
}

# Moves @global[0].node off a synthetic node back onto the real one
_pw_restore_real_node() {
    local pkg="$1"
    local cur real

    cur=$(uci -q get "$pkg.@global[0].node" 2>/dev/null)
    [ -z "$cur" ] && cur=$(uci -q get "$pkg.@global[0].tcp_node" 2>/dev/null)
    _pw_is_synthetic_node "$cur" || return 0

    if real=$(_pw_real_node "$pkg"); then
        _pw_set_global_node "$pkg" "$real"
        return 0
    fi

    log_warn "Could not work out which real node to restore in $pkg; pick one from its node list."
    return 1
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

# Iran-direct routing the way Passwall really does it: a _shunt node that sends
# Iranian domains / IPs straight out and everything else to the chosen node.
# tcp_proxy_mode / udp_proxy_mode only accept "disable" or "proxy".
_pw_apply_iran_direct() {
    local pkg="$1"
    local node rule core domains

    if ! node=$(_pw_real_node "$pkg"); then
        log_error "No proxy node is selected in $pkg. Pick a node first (Transport Engines -> Show Nodes, or Config Manager)."
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
    # Per-rule option: the shunt_rules section id carries the target
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

# dns_mode exists on Passwall v1 only and accepts udp / tcp / dns2socks /
# sing-box / xray - never "doh". Passwall2 has no dns_mode, no v2ray_dns_mode
# and no dns_doh at all; there the DoH URL lives in remote_dns_doh.
_pw_set_v1_dns_mode() {
    local pkg="$1"

    [ "$pkg" = "passwall" ] || return 0
    case "$2" in
        udp|tcp|dns2socks|sing-box|xray) _pw_set "$pkg" "dns_mode" "$2" || true ;;
    esac
}

# Core that resolves DoH on Passwall v1, following the active node's own core
_pw_dns_core() {
    local pkg="$1"
    local node type=""

    node=$(_pw_real_node "$pkg" 2>/dev/null) && \
        type=$(uci -q get "$pkg.$node.type" 2>/dev/null)

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

# Reports the real server node, resolving through the Iran-direct shunt
_pw_active_node() {
    local cur

    cur=$(uci -q get "$1.@global[0].node" 2>/dev/null)
    [ -z "$cur" ] && cur=$(uci -q get "$1.@global[0].tcp_node" 2>/dev/null)

    if [ "$cur" = "$PW_SHUNT_ID" ]; then
        uci -q get "$1.$PW_SHUNT_ID.default_node" 2>/dev/null
        return 0
    fi

    [ -n "$cur" ] && echo "$cur"
}

_pw_select_node() {
    local pkg="$1"
    local sect="$2"
    local cur

    _pw_is_node "$pkg" "$sect" || return 1

    cur=$(uci -q get "$pkg.@global[0].node" 2>/dev/null)
    [ -z "$cur" ] && cur=$(uci -q get "$pkg.@global[0].tcp_node" 2>/dev/null)

    if [ "$cur" = "$PW_SHUNT_ID" ]; then
        # Iran-direct routing is active: retarget the shunt so its direct rules survive
        uci set "$pkg.$PW_SHUNT_ID.default_node=$sect"
        transport_opt_set "$pkg" real_node "$sect"
    else
        _pw_set_global_node "$pkg" "$sect"
    fi

    uci commit "$pkg"
    _pw_reload "$pkg"
}

# remarks may contain regex metacharacters, so match them literally
_pw_node_exists() {
    uci show "$1" 2>/dev/null | grep -qF "remarks='$2'"
}

# Imports a share link with Passwall's own parser (/usr/share/<pkg>/subscribe.lua),
# which is the only way Reality (pbk/sid/spx), ssr, hysteria, hysteria2, tuic,
# anytls and naive nodes get built with every field Passwall expects.
# $1 pkg, $2 config file, $3 config name
_pw_push_node() {
    local pkg="$1"
    local file="$2"
    local conf_name="$3"
    local share_link script label remarks existing before after new count

    share_link=$(jq -r '.share_link // empty' "$file" 2>/dev/null)
    if [ -z "$share_link" ]; then
        log_error "No share_link in config: [$conf_name]"
        return 1
    fi

    script="/usr/share/$pkg/subscribe.lua"
    if [ ! -f "$script" ]; then
        log_error "Passwall's own link importer is missing: [$script]"
        return 1
    fi
    if ! command -v lua >/dev/null 2>&1; then
        log_error "lua is required to import share links into $pkg!"
        return 1
    fi

    if [ "$pkg" = "passwall2" ]; then
        label="Passwall2"
    else
        label="Passwall1"
    fi

    remarks=""
    existing=""
    if parse_share_link "$share_link"; then
        remarks="$PARSED_REMARKS"
        existing=$(_pw_node_id_by_remarks "$pkg" "$remarks") || existing=""
    else
        log_warn "Could not read the share link of [$conf_name]; letting $label name the node."
    fi

    log_info "Importing node into $label -> [${remarks:-$conf_name}]"

    before=$(_pw_node_ids "$pkg")

    printf '%s\n' "$share_link" > /tmp/links.conf
    lua "$script" add "$PW_SUBSCRIBE_GROUP" >/dev/null 2>&1
    rm -f /tmp/links.conf

    after=$(_pw_node_ids "$pkg")

    if [ -z "$before" ]; then
        # busybox grep with an empty pattern list matches nothing, so the very
        # first imported node has to be handled without a diff.
        new="$after"
    else
        new=$(printf '%s\n' "$after" | grep -vxF -- "$before")
    fi
    new=$(printf '%s\n' "$new" | sed '/^$/d')

    count=0
    [ -n "$new" ] && count=$(printf '%s\n' "$new" | grep -c .)

    if [ "$count" -eq 0 ]; then
        if [ -n "$existing" ]; then
            uci commit "$pkg"
            log_success "$label refreshed the existing node [$remarks] ($existing)"
            return 0
        fi
        log_error "$label did not accept the share link of [$conf_name]."
        return 1
    fi

    if [ "$count" -gt 1 ]; then
        log_info "$label created $count nodes from this link."
    elif [ -n "$existing" ] && [ "$new" != "$existing" ]; then
        # Reuse the old section id so @global[0].node, the shunt's default_node
        # and the balancer's saved ids keep pointing at this node.
        case "$existing" in
            *[!A-Za-z0-9_]*)
                log_warn "Node id [$existing] cannot be reused; [$remarks] now lives in [$new]."
                ;;
            *)
                uci -q delete "$pkg.$existing"
                if uci rename "$pkg.$new=$existing" 2>/dev/null; then
                    new="$existing"
                else
                    log_warn "Could not reuse node id [$existing]; [$remarks] now lives in [$new]."
                fi
                ;;
        esac
    fi

    uci commit "$pkg"

    if [ -n "$existing" ]; then
        log_success "Node [$remarks] updated in $label ($(printf '%s' "$new" | tr '\n' ' '))"
    else
        log_success "Node [${remarks:-$conf_name}] added to $label ($(printf '%s' "$new" | tr '\n' ' '))"
    fi
    return 0
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
