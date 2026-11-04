#!/bin/sh
# ============================================================
# DayPass - Passwall Driver: Core & Service Management
# ============================================================

# Sections DayPass owns inside the Passwall config
PW_SHUNT_ID="daypass_shunt"
PW_SHUNT_RULE_ID="daypass_ir_rule"
PW_BALANCER_ID="daypass_balancer"
PW_SUBSCRIBE_GROUP="DayPass"

detect_passwall_version() {
    if [ -f /etc/config/passwall2 ] || uci -q show passwall2 >/dev/null 2>&1; then
        echo "passwall2"; return
    fi
    if [ -f /etc/config/passwall ] || uci -q show passwall >/dev/null 2>&1; then
        echo "passwall"; return
    fi
    if command -v pkg_installed >/dev/null 2>&1; then
        if pkg_installed "luci-app-passwall2" || pkg_installed "passwall2"; then echo "passwall2"; return; fi
        if pkg_installed "luci-app-passwall" || pkg_installed "passwall"; then echo "passwall"; return; fi
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

_pw_set() {
    local pkg="$1" key="$2" val="$3" sect
    for sect in global global_dns global_forwarding global_other; do
        if uci -q get "${pkg}.@${sect}[0]" >/dev/null 2>&1; then
            uci set "${pkg}.@${sect}[0].${key}=${val}" 2>/dev/null && return 0
        fi
    done
    uci set "${pkg}.@global[0].${key}=${val}" 2>/dev/null || return 1
}

_pw_get() {
    local pkg="$1" key="$2" sect val
    for sect in global global_dns global_forwarding global_other; do
        val=$(uci -q get "${pkg}.@${sect}[0].${key}" 2>/dev/null) || true
        if [ -n "$val" ]; then echo "$val"; return 0; fi
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

# --- Core Hooks ---
tdrv_passwall2_detect()       { _pw_detect passwall2; }
tdrv_passwall2_start()        { _pw_start passwall2; }
tdrv_passwall2_stop()         { _pw_stop passwall2; }
tdrv_passwall2_status()       { _pw_status passwall2; }
tdrv_passwall2_reload()       { _pw_reload passwall2; }
tdrv_passwall2_interception() { echo "self"; }
tdrv_passwall2_describe()     { echo "config /etc/config/passwall2, DNS port $(_pw_dns_listen_port passwall2)"; }

tdrv_passwall_detect()        { _pw_detect passwall; }
tdrv_passwall_start()         { _pw_start passwall; }
tdrv_passwall_stop()          { _pw_stop passwall; }
tdrv_passwall_status()        { _pw_status passwall; }
tdrv_passwall_reload()        { _pw_reload passwall; }
tdrv_passwall_interception()  { echo "self"; }
tdrv_passwall_describe()      { echo "config /etc/config/passwall, DNS port $(_pw_dns_listen_port passwall)"; }