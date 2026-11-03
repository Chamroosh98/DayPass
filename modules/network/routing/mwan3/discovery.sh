#!/bin/sh
# ============================================================
# DayPass - mwan3 WAN Discovery (Detection whole Internets)
# ============================================================

mwan_iface_is_wan() {
    case "$1" in
        wan6) return 1 ;;
        wan|wan_*|wwan|wwan_*) return 0 ;;
    esac
    return 1
}

_mwan_note_iface() {
    _mi="$1"
    [ -n "$_mi" ] || return 1
    case " $MWAN_SEEN " in
        *" $_mi "*) return 1 ;;
    esac
    [ "$(uci -q get "network.$_mi")" = "interface" ] || return 1
    case "$(uci -q get "network.$_mi.proto")" in
        dhcpv6) return 1 ;;
    esac
    case "$_mi" in
        wan6) return 1 ;;
    esac
    MWAN_SEEN="$MWAN_SEEN $_mi"
    printf '%s\n' "$_mi"
    return 0
}

mwan_discover_ifaces() {
    local i name nets net iface

    MWAN_SEEN=""
    i=0
    while uci -q get "firewall.@zone[$i]" >/dev/null 2>&1; do
        name=$(uci -q get "firewall.@zone[$i].name")
        if [ "$name" = "wan" ]; then
            nets=$(uci -q get "firewall.@zone[$i].network")
            for net in $nets; do
                _mwan_note_iface "$net" || true
            done
        fi
        i=$((i + 1))
        [ "$i" -gt 64 ] && break
    done

    for iface in $(uci show network 2>/dev/null | sed -n 's/^network\.\([A-Za-z0-9_]*\)=interface$/\1/p'); do
        mwan_iface_is_wan "$iface" || continue
        _mwan_note_iface "$iface" || true
    done
}

mwan_iface_enabled() {
    [ "$(uci -q get "network.$1.disabled")" != "1" ]
}

mwan_active_ifaces() {
    local iface
    for iface in $(mwan_discover_ifaces); do
        mwan_iface_enabled "$iface" || continue
        printf '%s\n' "$iface"
    done
}