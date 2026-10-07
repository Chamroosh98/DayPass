#!/bin/sh
# DayPass - WAN interface discovery for the network info screen.

# $1 interface name. 0 when the name is a WAN (not wan6).
_net_name_is_wan() {
    case "$1" in
        wan6) return 1 ;;
        wan|wan_*|wwan|wwan_*) return 0 ;;
    esac
    return 1
}

# Record $1 once when it is an enabled IPv4 network interface.
_net_note_iface() {
    _ni="$1"
    [ -n "$_ni" ] || return 1
    case " $NET_SEEN " in
        *" $_ni "*) return 1 ;;
    esac
    [ "$(uci -q get "network.$_ni")" = "interface" ] || return 1
    [ "$(uci -q get "network.$_ni.disabled")" = "1" ] && return 1
    case "$(uci -q get "network.$_ni.proto")" in
        dhcpv6) return 1 ;;
    esac
    case "$_ni" in
        wan6) return 1 ;;
    esac
    NET_SEEN="$NET_SEEN $_ni"
    printf '%s\n' "$_ni"
    return 0
}

# Enabled WAN interfaces, one name per line.
# Firewall zone "wan", then wan / wan_* / wwan (wan_usb, wan_usb2, wan_lan2).
net_get_active_ifaces() {
    local i name nets net iface

    if command -v mwan_discover_ifaces >/dev/null 2>&1; then
        for iface in $(mwan_discover_ifaces); do
            [ "$(uci -q get "network.$iface.disabled")" = "1" ] && continue
            case "$(uci -q get "network.$iface.proto")" in
                dhcpv6) continue ;;
            esac
            printf '%s\n' "$iface"
        done
        return 0
    fi

    NET_SEEN=""
    i=0
    while uci -q get "firewall.@zone[$i]" >/dev/null 2>&1; do
        name=$(uci -q get "firewall.@zone[$i].name")
        if [ "$name" = "wan" ]; then
            nets=$(uci -q get "firewall.@zone[$i].network")
            for net in $nets; do
                _net_note_iface "$net" || true
            done
        fi
        i=$((i + 1))
        [ "$i" -gt 64 ] && break
    done

    for iface in $(uci show network 2>/dev/null | sed -n 's/^network\.\([A-Za-z0-9_]*\)=interface$/\1/p'); do
        _net_name_is_wan "$iface" || continue
        _net_note_iface "$iface" || true
    done
}

# Linux device for a UCI interface (pppoe l3 device, else UCI device).
# Prints the name. Returns 1 when none is known.
net_linux_dev() {
    local iface="$1"
    local dev=""

    if command -v ubus >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        dev=$(ubus call "network.interface.$iface" status 2>/dev/null | jq -r '.l3_device // .device // empty' 2>/dev/null)
    fi
    if [ -z "$dev" ] || [ "$dev" = "null" ]; then
        dev=$(uci -q get "network.$iface.device")
    fi
    if [ -z "$dev" ]; then
        dev=$(uci -q get "network.$iface.ifname")
    fi
    dev=${dev%% *}
    case "$dev" in
        ""|@*) return 1 ;;
    esac
    printf '%s\n' "$dev"
    return 0
}

# online / offline / unknown / n/a
net_mwan3_state() {
    local iface="$1"
    local line=""

    if ! command -v mwan3 >/dev/null 2>&1; then
        printf '%s\n' "n/a"
        return 0
    fi
    line=$(mwan3 status 2>/dev/null | grep -i "interface ${iface} is" | head -n 1)
    case "$line" in
        *[Oo]nline*) printf '%s\n' "online" ;;
        *[Oo]ffline*|*[Dd]own*) printf '%s\n' "offline" ;;
        *) printf '%s\n' "unknown" ;;
    esac
}
