#!/bin/sh
# ============================================================
# DayPass - mwan3 Core Engine for congfigs & policies
# ============================================================

install_mwan3_deps() {
    local PKG_MANAGER="${PKG_MANAGER:-}"
    local PKGS="mwan3 luci-app-mwan3"

    log_info "Verifying Multi-WAN & LuCI Web Interface packages ..."
    if command -v mwan3 >/dev/null 2>&1 && [ -f /usr/lib/lua/luci/controller/mwan3.lua -o -d /www/luci-static/resources/view/mwan3 ]; then
        log_success "mwan3 and LuCI web panel are already installed."
        return 0
    fi

    case "${PKG_MANAGER:-}" in
        apk|opkg) ;;
        '')
            if command -v apk >/dev/null && ! command -v opkg >/dev/null; then
                PKG_MANAGER=apk
            elif command -v opkg >/dev/null && ! command -v apk >/dev/null; then
                PKG_MANAGER=opkg
            else
                log_error "Could not identify a single package manager."; return 1
            fi ;;
        *) log_error "Unsupported package manager."; return 1 ;;
    esac
    command -v pkg_update >/dev/null 2>&1 || return 1
    log_info "Updating package database ..."
    pkg_update || return $?
    log_info "Installing $PKGS ..."
    case "$PKG_MANAGER" in
        apk) apk add mwan3 luci-app-mwan3 || return $? ;;
        opkg) opkg install mwan3 luci-app-mwan3 || return $? ;;
    esac
    log_success "mwan3 and LuCI Web Interface installed."

}

# Private staging must still describe the same committed graph at publication.
_mwan_check_baseline() {
    local pending current
    pending=$(uci changes mwan3) && [ -z "$pending" ] || return 1
    current=$(uci show mwan3) && [ "$current" = "$1" ]
}

# Existing rules can take precedence over a new catch-all. Refuse adoption,
# including installations created by older DayPass versions without markers.
apply_mwan3_mode() (
    local mode="$1" delta config pending list iface member metric rank=0 ordered
    local rule=daypass_default policy="daypass_$1" section
    case "$mode" in balanced|failover) ;; *) return 1 ;; esac
    pending=$(uci changes mwan3) && [ -z "$pending" ] || return 1
    config=$(uci show mwan3) || return 1
    for section in $(printf '%s\n' "$config" | sed -n 's/^mwan3\.\([^.]*\)=\(rule\|policy\|member\)$/\1/p'); do
        [ "$(uci -q get "mwan3.$section.daypass_owner")" = mwan_v1 ] ||
            { log_warn "Existing mwan3 policy graph requires manual integration."; return 1; }
    done
    [ -x /etc/init.d/mwan3 ] || return 1
    list=$(mwan_active_ifaces) && [ -n "$list" ] || return 1
    delta=$(mktemp -d /tmp/daypass_mwan.XXXXXX) || return 1
    trap 'rm -f "$delta/mwan3" "$delta/order"; rmdir "$delta"' EXIT
    for iface in $list; do
        case "$iface" in ''|daypass_*|*[!a-zA-Z0-9_]*) return 1 ;; esac
        metric=$(uci -q get "network.$iface.metric") || metric=1000
        case "$metric" in ''|*[!0-9]*) metric=1000 ;; esac
        printf '%s %s\n' "$metric" "$iface" >> "$delta/order" || return 1
    done
    ordered=$(sort -n "$delta/order") || return 1

    # Only this private delta is written before the single commit.
    mwan_stage_section() {
        local name="$1" type="$2" old
        old=$(uci -q get "mwan3.$name")
        if [ -n "$old" ]; then
            [ "$old" = "$type" ] &&
                [ "$(uci -q get "mwan3.$name.daypass_owner")" = mwan_v1 ] || return 1
        fi
        uci -P "$delta" set "mwan3.$name=$type" &&
            uci -P "$delta" set "mwan3.$name.daypass_owner=mwan_v1"
    }

    mwan_stage_section "$policy" policy && mwan_stage_section "$rule" rule || return 1
    if uci -q get "mwan3.$policy.use_member" >/dev/null; then
        uci -P "$delta" delete "mwan3.$policy.use_member" || return 1
    fi
    while read -r metric iface; do
        if uci -q get "mwan3.$iface" >/dev/null; then
            [ "$(uci -q get "mwan3.$iface")" = interface ] &&
                [ "$(uci -q get "mwan3.$iface.enabled")" = 1 ] || return 1
        else
            mwan_stage_section "$iface" interface &&
                uci -P "$delta" set "mwan3.$iface.enabled=1" &&
                uci -P "$delta" set "mwan3.$iface.family=ipv4" &&
                uci -P "$delta" add_list "mwan3.$iface.track_ip=1.1.1.1" || return 1
        fi
        member="daypass_${mode}_$iface"
        if [ "$mode" = balanced ]; then rank=1; else rank=$((rank+1)); fi
        mwan_stage_section "$member" member &&
            uci -P "$delta" set "mwan3.$member.interface=$iface" &&
            uci -P "$delta" set "mwan3.$member.metric=$rank" &&
            uci -P "$delta" set "mwan3.$member.weight=1" &&
            uci -P "$delta" add_list "mwan3.$policy.use_member=$member" || return 1
    done <<EOF
$ordered
EOF
    uci -P "$delta" set "mwan3.$rule.dest_ip=0.0.0.0/0" &&
        uci -P "$delta" set "mwan3.$rule.family=ipv4" &&
        uci -P "$delta" set "mwan3.$rule.use_policy=$policy" || return 1
    _mwan_check_baseline "$config" ||
        { log_warn "mwan3 configuration changed during staging; apply cancelled."; return 1; }
    uci -P "$delta" commit mwan3 || return 1
    /etc/init.d/mwan3 enable && /etc/init.d/mwan3 restart ||
        { log_error "mwan3 configuration saved; activation incomplete."; return 1; }
    log_info "Applied DayPass $mode configuration. Check live policy in mwan3 status."
)
