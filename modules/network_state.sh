#!/bin/sh
# ============================================================
# DayPass - Network Interfaces State
# Full-screen listing of every UCI network interface with
# live ubus status. Safe to source. Never calls exit.
# ============================================================

# Cached JSON from `ubus call network.interface show` (or dump).
_NS_UBUS=""

_ns_load_ubus() {
    _NS_UBUS=$(ubus call network.interface show 2>/dev/null)
    case "$_NS_UBUS" in
        *'"interface"'*) return 0 ;;
    esac
    _NS_UBUS=$(ubus call network.interface dump 2>/dev/null)
    case "$_NS_UBUS" in
        *'"interface"'*) return 0 ;;
    esac
    _NS_UBUS=""
    return 1
}

# UCI logical interface names, one per line. Skips loopback.
_ns_uci_ifaces() {
    local iface

    uci -q show network 2>/dev/null | sed -n 's/^network\.\([A-Za-z0-9_]*\)=interface$/\1/p' | while IFS= read -r iface; do
        case "$iface" in
            loopback|lo) continue ;;
        esac
        printf '%s\n' "$iface"
    done
}

# JSON object for one logical interface from the cached dump, or empty.
_ns_ubus_iface() {
    local name="$1"

    [ -n "$_NS_UBUS" ] || return 1
    if command -v jq >/dev/null 2>&1; then
        printf '%s\n' "$_NS_UBUS" | jq -c --arg n "$name" '.interface[]? | select(.interface == $n)' 2>/dev/null
        return 0
    fi
    if command -v jsonfilter >/dev/null 2>&1; then
        printf '%s\n' "$_NS_UBUS" | jsonfilter -e "@.interface[@.interface='$name']" 2>/dev/null
        return 0
    fi
    return 1
}

_ns_json_str() {
    local json="$1"
    local expr="$2"

    [ -n "$json" ] || return 1
    if command -v jq >/dev/null 2>&1; then
        printf '%s\n' "$json" | jq -r "$expr" 2>/dev/null
        return 0
    fi
    return 1
}

_ns_iface_icon() {
    case "$1" in
        lan|lan_*)    printf '%s\n' "🏠" ;;
        wan_usb*)     printf '%s\n' "📱" ;;
        wwan*)        printf '%s\n' "📶" ;;
        wan6*)        printf '%s\n' "🌐" ;;
        wan|wan_*)    printf '%s\n' "🔌" ;;
        *)            printf '%s\n' "🔗" ;;
    esac
}

# Prints one stacked card for $1 (UCI interface name).
_ns_render_iface() {
    local iface="$1"
    local proto device disabled metric json l3 up ip ip6 status_line icon

    proto=$(uci -q get "network.$iface.proto")
    [ -n "$proto" ] || proto="—"

    device=$(uci -q get "network.$iface.device")
    [ -n "$device" ] || device=$(uci -q get "network.$iface.ifname")

    disabled=$(uci -q get "network.$iface.disabled")
    metric=$(uci -q get "network.$iface.metric")

    json=$(_ns_ubus_iface "$iface")
    l3=$(_ns_json_str "$json" '.["l3_device"] // .device // empty')
    [ -n "$device" ] || device="$l3"
    [ -n "$device" ] || device="—"

    if [ -z "$metric" ]; then
        metric=$(_ns_json_str "$json" '.metric // empty')
        case "$metric" in
            ''|null) metric="0 [default]" ;;
            *)       metric="$metric [default]" ;;
        esac
    fi

    up=$(_ns_json_str "$json" '.up')
    ip=$(_ns_json_str "$json" '.["ipv4-address"][0].address // empty')
    ip6=$(_ns_json_str "$json" '.["ipv6-address"][0].address // empty')
    case "$ip" in ''|null) ip="" ;; esac
    case "$ip6" in ''|null) ip6="" ;; esac
    [ -n "$ip" ] || ip="$ip6"

    if [ "$disabled" = "1" ]; then
        status_line="${YELLOW}⚠️ DISABLED${RESET}"
    elif [ "$up" = "true" ]; then
        if [ -n "$ip" ]; then
            status_line="${GREEN}🟢 UP${RESET}  ($ip)"
        else
            status_line="${GREEN}🟢 UP${RESET}"
        fi
    else
        status_line="${RED}🔴 DOWN${RESET}"
    fi

    icon=$(_ns_iface_icon "$iface")
    echo "  $icon $iface"
    if command -v ui_divider >/dev/null 2>&1; then
        ui_divider
    fi
    echo "  Device     : $device"
    echo "  Protocol   : $proto"
    echo "  Status     : $status_line"
    echo "  Metric     : $metric"
}

# Full-screen interface list. Enter returns to the caller.
network_interfaces_state() {
    local iface first=1

    if command -v render_persistent_header >/dev/null 2>&1; then
        render_persistent_header
    fi
    if command -v ui_title >/dev/null 2>&1; then
        ui_title "📡 Network Interfaces State"
    else
        echo "  📡 Network Interfaces State"
        command -v ui_divider >/dev/null 2>&1 && ui_divider
    fi

    _ns_load_ubus || true

    for iface in $(_ns_uci_ifaces); do
        [ -n "$iface" ] || continue
        if [ "$first" -eq 0 ]; then
            echo
        fi
        first=0
        _ns_render_iface "$iface"
    done

    if [ "$first" -eq 1 ]; then
        echo "  ${GRAY}No network interfaces found in UCI.${RESET}"
    fi

    echo
    printf "  ${GRAY}Press [Enter] to return to main menu ...${RESET}"
    read -r _ </dev/tty || true
}
