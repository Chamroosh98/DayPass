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

# $1 JSON object  $2 field: up | l3 | device | metric | ip4 | ip6
_ns_json_str() {
    local json="$1"
    local field="$2"
    local out=""

    [ -n "$json" ] || return 1
    if command -v jq >/dev/null 2>&1; then
        case "$field" in
            up)     out=$(printf '%s\n' "$json" | jq -r '.up // empty' 2>/dev/null) ;;
            l3)     out=$(printf '%s\n' "$json" | jq -r '.l3_device // empty' 2>/dev/null) ;;
            device) out=$(printf '%s\n' "$json" | jq -r '.device // empty' 2>/dev/null) ;;
            metric) out=$(printf '%s\n' "$json" | jq -r '.metric // empty' 2>/dev/null) ;;
            ip4)    out=$(printf '%s\n' "$json" | jq -r '.["ipv4-address"][0].address // empty' 2>/dev/null) ;;
            ip6)    out=$(printf '%s\n' "$json" | jq -r '.["ipv6-address"][0].address // empty' 2>/dev/null) ;;
        esac
    elif command -v jsonfilter >/dev/null 2>&1; then
        case "$field" in
            up)     out=$(printf '%s\n' "$json" | jsonfilter -e '@.up' 2>/dev/null) ;;
            l3)     out=$(printf '%s\n' "$json" | jsonfilter -e '@.l3_device' 2>/dev/null) ;;
            device) out=$(printf '%s\n' "$json" | jsonfilter -e '@.device' 2>/dev/null) ;;
            metric) out=$(printf '%s\n' "$json" | jsonfilter -e '@.metric' 2>/dev/null) ;;
            ip4)    out=$(printf '%s\n' "$json" | jsonfilter -e '@["ipv4-address"][0].address' 2>/dev/null) ;;
            ip6)    out=$(printf '%s\n' "$json" | jsonfilter -e '@["ipv6-address"][0].address' 2>/dev/null) ;;
        esac
    fi
    case "$out" in
        ''|null) return 1 ;;
    esac
    printf '%s\n' "$out"
}

# Space-separated "dev:metric" pairs from `ip route show default`.
_NS_ROUTES=""

_ns_load_routes() {
    local line dev metric

    _NS_ROUTES=""
    while IFS= read -r line; do
        case "$line" in
            default*) ;;
            *) continue ;;
        esac
        dev=""
        metric=""
        set -- $line
        while [ $# -gt 0 ]; do
            case "$1" in
                dev)    shift; dev="${1:-}" ;;
                metric) shift; metric="${1:-}" ;;
            esac
            [ $# -gt 0 ] && shift
        done
        [ -n "$dev" ] || continue
        [ -n "$metric" ] || metric="0"
        _NS_ROUTES="$_NS_ROUTES $dev:$metric"
    done <<EOF
$(ip route show default 2>/dev/null)
EOF
    _NS_ROUTES=${_NS_ROUTES# }
}

# 0 when $1 (linux device) carries a default route. Prints its route metric.
_ns_route_metric() {
    local dev="$1"
    local pair name m

    [ -n "$dev" ] || return 1
    for pair in $_NS_ROUTES; do
        name="${pair%%:*}"
        m="${pair#*:}"
        if [ "$name" = "$dev" ]; then
            printf '%s\n' "$m"
            return 0
        fi
    done
    return 1
}

# mwan3 interface names reported online, one per line.
_ns_mwan_online() {
    local line name

    command -v mwan3 >/dev/null 2>&1 || return 1
    mwan3 status 2>/dev/null | while IFS= read -r line; do
        case "$line" in
            *' is online'*)
                name=${line%% is online*}
                name=${name##* }
                [ -n "$name" ] && printf '%s\n' "$name"
                ;;
        esac
    done
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
    local proto device disabled metric json l3 up ip ip6 status_line icon rmetric

    proto=$(uci -q get "network.$iface.proto")
    [ -n "$proto" ] || proto="—"

    device=$(uci -q get "network.$iface.device")
    [ -n "$device" ] || device=$(uci -q get "network.$iface.ifname")

    disabled=$(uci -q get "network.$iface.disabled")
    metric=$(uci -q get "network.$iface.metric")

    json=$(_ns_ubus_iface "$iface")
    l3=$(_ns_json_str "$json" l3) || l3=""
    [ -n "$device" ] || device=$(_ns_json_str "$json" device) || device=""
    [ -n "$l3" ] || l3="$device"
    [ -n "$device" ] || device="—"

    if [ -z "$metric" ]; then
        metric=$(_ns_json_str "$json" metric) || metric=""
        case "$metric" in
            ''|null) metric="0 [default]" ;;
            *)       metric="$metric [default]" ;;
        esac
    fi

    up=$(_ns_json_str "$json" up) || up=""
    ip=$(_ns_json_str "$json" ip4) || ip=""
    ip6=$(_ns_json_str "$json" ip6) || ip6=""
    [ -n "$ip" ] || ip="$ip6"
    [ -n "$ip" ] || ip="—"

    if [ "$disabled" = "1" ]; then
        status_line="${YELLOW}⚠️ DISABLED${RESET}"
    elif [ "$up" = "true" ]; then
        status_line="${GREEN}🟢 UP${RESET}"
    else
        status_line="${RED}🔴 DOWN${RESET}"
    fi

    icon=$(_ns_iface_icon "$iface")
    echo "  $icon $iface ($device)"
    if command -v ui_divider >/dev/null 2>&1; then
        ui_divider
    fi
    echo "  Protocol   : $proto | $ip"
    echo "  Status     : $status_line"
    echo "  Metric     : $metric"
    if rmetric=$(_ns_route_metric "$l3") || rmetric=$(_ns_route_metric "$device"); then
        echo "  Traffic    : ${GREEN}[🚀 Active / Routing Traffic]${RESET}"
    fi
}

# Default routes and, when mwan3 is balancing, every online WAN.
_ns_render_active() {
    local pair dev metric iface l3 json policy online n=0 balancing=0

    echo
    echo "  🚀 Active Traffic"
    if command -v ui_divider >/dev/null 2>&1; then
        ui_divider
    fi

    policy=$(uci -q get mwan3.default_rule_v4.use_policy)
    online=$(_ns_mwan_online 2>/dev/null)
    n=0
    for iface in $online; do
        n=$((n + 1))
    done
    if [ "$policy" = "balanced" ] && [ "$n" -ge 2 ]; then
        balancing=1
    fi

    n=0
    for pair in $_NS_ROUTES; do
        n=$((n + 1))
    done
    if [ "$n" -ge 2 ]; then
        balancing=1
    fi

    if [ "$balancing" -eq 1 ]; then
        echo "  Load balancing is active across:"
    elif [ "$n" -eq 0 ] && [ -z "$online" ]; then
        echo "  ${GRAY}No default route.${RESET}"
        return 0
    else
        echo "  Outbound traffic:"
    fi

    for pair in $_NS_ROUTES; do
        dev="${pair%%:*}"
        metric="${pair#*:}"
        iface=""
        for iface in $(_ns_uci_ifaces); do
            json=$(_ns_ubus_iface "$iface")
            l3=$(_ns_json_str "$json" l3) || l3=""
            [ -n "$l3" ] || l3=$(uci -q get "network.$iface.device")
            [ -n "$l3" ] || l3=$(uci -q get "network.$iface.ifname")
            [ "$l3" = "$dev" ] && break
            iface=""
        done
        [ -n "$iface" ] || iface="$dev"
        printf "    %s %-12s dev %-8s metric %-4s ${GREEN}[🚀 Active / Routing Traffic]${RESET}\n" \
            "$(_ns_iface_icon "$iface")" "$iface" "$dev" "$metric"
    done

    if [ "$policy" = "balanced" ] && [ -n "$online" ]; then
        echo "  mwan3 policy [balanced]:"
        for iface in $online; do
            metric=$(uci -q get "network.$iface.metric")
            [ -n "$metric" ] || metric="0 [default]"
            printf "    %s %-12s online  metric %s\n" \
                "$(_ns_iface_icon "$iface")" "$iface" "$metric"
        done
    fi
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
    _ns_load_routes

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

    _ns_render_active

    echo
    printf "  ${GRAY}Press [Enter] to return to main menu ...${RESET}"
    read -r _ </dev/tty || true
}
