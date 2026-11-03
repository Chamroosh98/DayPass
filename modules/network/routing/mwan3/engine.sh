#!/bin/sh
# ============================================================
# DayPass - mwan3 Core Engine for congfigs & policies
# ============================================================

install_mwan3_deps() {
    local PKGS="mwan3 luci-app-mwan3"

    log_info "Verifying Multi-WAN & LuCI Web Interface packages ..."
    if command -v mwan3 >/dev/null 2>&1 && [ -f /usr/lib/lua/luci/controller/mwan3.lua -o -d /www/luci-static/resources/view/mwan3 ]; then
        log_success "mwan3 and LuCI web panel are already installed."
        return 0
    fi

    log_info "Updating package database ..."
    if command -v pkg_update >/dev/null 2>&1; then
        pkg_update >/dev/null 2>&1 || true
    elif command -v opkg >/dev/null 2>&1; then
        opkg update >/dev/null 2>&1 || true
    elif command -v apk >/dev/null 2>&1; then
        apk update >/dev/null 2>&1 || true
    fi

    log_info "Installing mwan3 and LuCI Web Interface ($PKGS) ..."
    if command -v pkg_install >/dev/null 2>&1; then
        if pkg_install mwan3 && pkg_install luci-app-mwan3; then
            log_success "mwan3 and LuCI Web Interface successfully installed."
            return 0
        fi
    fi
    if command -v opkg >/dev/null 2>&1; then
        if opkg install $PKGS >/dev/null 2>&1; then
            log_success "mwan3 & LuCI Web Panel installed via OPKG."
            return 0
        fi
    fi
    if command -v apk >/dev/null 2>&1; then
        if apk add $PKGS >/dev/null 2>&1; then
            log_success "mwan3 & LuCI Web Panel installed via APK."
            return 0
        fi
    fi

    log_error "Could not install mwan3 or luci-app-mwan3."
    return 1
}

_mwan_clear_links() {
    local sec kind
    uci show mwan3 2>/dev/null | sed -n 's/^mwan3\.\([^=]*\)=\(interface\|member\)$/\1 \2/p' | \
    while read -r sec kind; do
        [ -n "$sec" ] || continue
        uci -q delete "mwan3.$sec"
    done
}

# $1: mode ("balanced" or "failover")
apply_mwan3_mode() {
    local mode="${1:-balanced}"
    local list count iface metric rank member

    log_info "Scanning WAN interfaces ..."
    list=$(mwan_active_ifaces)
    count=0
    for iface in $list; do
        count=$((count + 1))
        metric=$(uci -q get "network.$iface.metric")
        [ -n "$metric" ] || metric="default"
        echo "  🌐 $iface  metric $metric"
    done

    if [ "$count" -eq 0 ]; then
        log_warn "No active WAN interfaces found. Create wan, wan_usb, wwan, or wan_lan2 first."
        return 1
    fi

    log_info "Configuring mwan3 for $count WAN interface(s) with policy: [$mode] ..."

    uci set mwan3.globals=globals
    uci set mwan3.globals.mmx_mask='0x3f00'
    _mwan_clear_links

    for iface in $list; do
        uci set "mwan3.$iface"=interface
        uci set "mwan3.$iface.enabled"='1'
        uci set "mwan3.$iface.family"='ipv4'
        uci -q delete "mwan3.$iface.track_ip"
        uci add_list "mwan3.$iface.track_ip"='1.1.1.1'
        uci add_list "mwan3.$iface.track_ip"='8.8.8.8'
        uci set "mwan3.$iface.reliability"='1'
        uci set "mwan3.$iface.timeout"='2'
        uci set "mwan3.$iface.interval"='5'

        member="${iface}_m"
        uci set "mwan3.$member"=member
        uci set "mwan3.$member.interface"="$iface"
        uci set "mwan3.$member.metric"='1'
        uci set "mwan3.$member.weight"='1'
    done

    uci set mwan3.balanced=policy
    uci -q delete mwan3.balanced.use_member
    for iface in $list; do
        uci add_list mwan3.balanced.use_member="${iface}_m"
    done

    uci set mwan3.failover=policy
    uci -q delete mwan3.failover.use_member
    rank=1
    for iface in $(
        for iface in $list; do
            metric=$(uci -q get "network.$iface.metric")
            case "$metric" in
                ''|*[!0-9]*) metric=1000 ;;
            esac
            printf '%s %s\n' "$metric" "$iface"
        done | sort -n | awk '{ print $2 }'
    ); do
        member="${iface}_fo"
        uci set "mwan3.$member"=member
        uci set "mwan3.$member.interface"="$iface"
        uci set "mwan3.$member.metric"="$rank"
        uci set "mwan3.$member.weight"='1'
        uci add_list mwan3.failover.use_member="$member"
        rank=$((rank + 1))
    done

    uci set mwan3.default_rule_v4=rule
    uci set mwan3.default_rule_v4.dest_ip='0.0.0.0/0'
    uci set mwan3.default_rule_v4.family='ipv4'
    uci set mwan3.default_rule_v4.use_policy="$mode"

    uci commit mwan3 || { log_error "Could not save mwan3."; return 1; }

    if [ -x /etc/init.d/mwan3 ]; then
        /etc/init.d/mwan3 enable >/dev/null 2>&1 || true
        /etc/init.d/mwan3 restart >/dev/null 2>&1 || log_warn "mwan3 did not restart. Install it from option 1 if it is missing."
    else
        log_warn "mwan3 is not installed yet. The config is saved. Use option 1, then apply again."
    fi

    if [ "$mode" = "balanced" ]; then
        log_success "mwan3 balanced policy now shares traffic across $count WAN interface(s)."
    else
        log_success "mwan3 failover policy active. Primary WAN is the one with the lowest metric."
    fi
    return 0
}