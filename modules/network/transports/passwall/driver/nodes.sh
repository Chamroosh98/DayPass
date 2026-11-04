#!/bin/sh
# ============================================================
# DayPass - Passwall Driver: Nodes Management
# ============================================================

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
    local pkg="$1" want="$2" sect
    [ -n "$want" ] || return 1
    for sect in $(_pw_node_ids "$pkg"); do
        if [ "$(uci -q get "$pkg.$sect.remarks" 2>/dev/null)" = "$want" ]; then
            echo "$sect"; return 0
        fi
    done
    return 1
}

_pw_real_node() {
    local pkg="$1" cur cand
    cur=$(uci -q get "$pkg.@global[0].node" 2>/dev/null)
    [ -z "$cur" ] && cur=$(uci -q get "$pkg.@global[0].tcp_node" 2>/dev/null)
    if [ -n "$cur" ] && ! _pw_is_synthetic_node "$cur" && _pw_is_node "$pkg" "$cur"; then
        echo "$cur"; return 0
    fi

    for cand in \
        "$(uci -q get "$pkg.$PW_SHUNT_ID.default_node" 2>/dev/null)" \
        "$(transport_opt_get "$pkg" real_node)" \
        "$(uci -q get "$pkg.$PW_BALANCER_ID.fallback_node" 2>/dev/null)" \
        "$(uci -q get "$pkg.$PW_BALANCER_ID.balancing_node" 2>/dev/null | cut -d' ' -f1)"
    do
        if [ -n "$cand" ] && ! _pw_is_synthetic_node "$cand" && _pw_is_node "$pkg" "$cand"; then
            echo "$cand"; return 0
        fi
    done
    return 1
}

_pw_set_global_node() {
    local pkg="$1" id="$2" udp
    uci set "$pkg.@global[0].node=$id"
    if uci -q get "$pkg.@global[0].tcp_node" >/dev/null 2>&1; then
        uci set "$pkg.@global[0].tcp_node=$id"
    fi
    udp=$(uci -q get "$pkg.@global[0].udp_node" 2>/dev/null)
    case "$udp" in
        ''|nil|tcp) ;;
        *) uci set "$pkg.@global[0].udp_node=$id" ;;
    esac
}

_pw_restore_real_node() {
    local pkg="$1" cur real
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

_pw_list_nodes() {
    local pkg="$1" sect name proto host port l4
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
    local pkg="$1" sect="$2" cur
    _pw_is_node "$pkg" "$sect" || return 1
    cur=$(uci -q get "$pkg.@global[0].node" 2>/dev/null)
    [ -z "$cur" ] && cur=$(uci -q get "$pkg.@global[0].tcp_node" 2>/dev/null)

    if [ "$cur" = "$PW_SHUNT_ID" ]; then
        uci set "$pkg.$PW_SHUNT_ID.default_node=$sect"
        transport_opt_set "$pkg" real_node "$sect"
    else
        _pw_set_global_node "$pkg" "$sect"
    fi
    uci commit "$pkg"
    _pw_reload "$pkg"
}

_pw_node_exists() {
    uci show "$1" 2>/dev/null | grep -qF "remarks='$2'"
}

_pw_push_node() {
    local pkg="$1" file="$2" conf_name="$3" share_link script label remarks existing before after new count
    share_link=$(jq -r '.share_link // empty' "$file" 2>/dev/null)
    if [ -z "$share_link" ]; then log_error "No share_link in config: [$conf_name]"; return 1; fi

    script="/usr/share/$pkg/subscribe.lua"
    if [ ! -f "$script" ]; then log_error "Importer missing: [$script]"; return 1; fi
    if ! command -v lua >/dev/null 2>&1; then log_error "lua is required!"; return 1; fi

    if [ "$pkg" = "passwall2" ]; then label="Passwall2"; else label="Passwall1"; fi
    remarks=""
    existing=""
    if parse_share_link "$share_link"; then
        remarks="$PARSED_REMARKS"
        existing=$(_pw_node_id_by_remarks "$pkg" "$remarks") || existing=""
    else
        log_warn "Could not read link of [$conf_name]; letting $label name the node."
    fi

    log_info "Importing node into $label -> [${remarks:-$conf_name}]"
    before=$(_pw_node_ids "$pkg")
    printf '%s\n' "$share_link" > /tmp/links.conf
    lua "$script" add "$PW_SUBSCRIBE_GROUP" >/dev/null 2>&1
    rm -f /tmp/links.conf
    after=$(_pw_node_ids "$pkg")

    if [ -z "$before" ]; then new="$after"; else new=$(printf '%s\n' "$after" | grep -vxF -- "$before"); fi
    new=$(printf '%s\n' "$new" | sed '/^$/d')

    count=0
    [ -n "$new" ] && count=$(printf '%s\n' "$new" | grep -c .)
    if [ "$count" -eq 0 ]; then
        if [ -n "$existing" ]; then uci commit "$pkg"; log_success "$label refreshed [$remarks] ($existing)"; return 0; fi
        log_error "$label did not accept the share link."
        return 1
    fi

    if [ "$count" -gt 1 ]; then log_info "$label created $count nodes."
    elif [ -n "$existing" ] && [ "$new" != "$existing" ]; then
        case "$existing" in
            *[!A-Za-z0-9_]*) log_warn "Node id [$existing] cannot be reused." ;;
            *) uci -q delete "$pkg.$existing"; if uci rename "$pkg.$new=$existing" 2>/dev/null; then new="$existing"; else log_warn "Could not reuse node id [$existing]."; fi ;;
        esac
    fi
    uci commit "$pkg"
    if [ -n "$existing" ]; then log_success "Node [$remarks] updated in $label ($(printf '%s' "$new" | tr '\n' ' '))"
    else log_success "Node [${remarks:-$conf_name}] added to $label ($(printf '%s' "$new" | tr '\n' ' '))"
    fi
    return 0
}

_pw_cleanup() {
    uci -q get "$1.daypass_balancer" >/dev/null 2>&1 || return 0
    uci -q delete "$1.daypass_balancer"
    uci commit "$1"
}

# --- Nodes Hooks ---
tdrv_passwall2_list_nodes()  { _pw_list_nodes passwall2; }
tdrv_passwall2_active_node() { _pw_active_node passwall2; }
tdrv_passwall2_select_node() { _pw_select_node passwall2 "$1"; }
tdrv_passwall2_push_node()   { _pw_push_node passwall2 "$1" "$2"; }
tdrv_passwall2_cleanup()     { _pw_cleanup passwall2; }

tdrv_passwall_list_nodes()   { _pw_list_nodes passwall; }
tdrv_passwall_active_node()  { _pw_active_node passwall; }
tdrv_passwall_select_node()  { _pw_select_node passwall "$1"; }
tdrv_passwall_push_node()    { _pw_push_node passwall "$1" "$2"; }
tdrv_passwall_cleanup()      { _pw_cleanup passwall; }