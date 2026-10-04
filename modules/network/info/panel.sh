#!/bin/sh
# DayPass - Collect WAN lookups, then draw the open two-column screen.
# The menu prints the global header and footer. This file does not.

# Fetch every active WAN into $1 (snapshot path). $2 is the interface count.
_net_fill_snapshot() {
    local snap="$1" count="$2" list="$3"
    local iface dev metric mwan data _net_pids _net_pid

    : > "$snap"
    [ "$count" -gt 0 ] || return 0

    if [ "$count" -le 1 ]; then
        iface=$(printf '%s\n' "$list" | head -n 1)
        dev=$(net_linux_dev "$iface" 2>/dev/null || true)
        metric=$(uci -q get "network.$iface.metric")
        [ -n "$metric" ] || metric="default"
        mwan=$(net_mwan3_state "$iface")
        data=$(net_fetch_iface_ip "$dev" 2>/dev/null || printf '%s\n' "false|||||||")
        printf '%s|%s|%s|%s|%s\n' "$iface" "$dev" "$metric" "$mwan" "$data" >> "$snap"
        return 0
    fi

    _net_pids=""
    for iface in $list; do
        dev=$(net_linux_dev "$iface" 2>/dev/null || true)
        metric=$(uci -q get "network.$iface.metric")
        [ -n "$metric" ] || metric="default"
        mwan=$(net_mwan3_state "$iface")
        printf '%s|%s|%s\n' "$dev" "$metric" "$mwan" > "/tmp/daypass_netsnap.$$.$iface.meta"
        net_fetch_iface_ip "$dev" > "/tmp/daypass_netsnap.$$.$iface" 2>/dev/null &
        _net_pids="$_net_pids $!"
    done
    for _net_pid in $_net_pids; do
        wait "$_net_pid" 2>/dev/null || true
    done
    for iface in $list; do
        IFS='|' read -r dev metric mwan <<EOF
$(cat "/tmp/daypass_netsnap.$$.$iface.meta" 2>/dev/null)
EOF
        data=$(cat "/tmp/daypass_netsnap.$$.$iface" 2>/dev/null)
        [ -n "$data" ] || data="false|||||||"
        printf '%s|%s|%s|%s|%s\n' "$iface" "$dev" "$metric" "$mwan" "$data" >> "$snap"
        rm -f "/tmp/daypass_netsnap.$$.$iface" "/tmp/daypass_netsnap.$$.$iface.meta"
    done
}

# Fetch every active WAN, then draw operations beside the tree.
net_show_panel() {
    local list count iface snap

    snap="/tmp/daypass_netsnap.$$"
    : > "$snap"

    if ! command -v curl >/dev/null 2>&1; then
        net_render_columns "$snap" 0 "curl is required for interface queries."
        rm -f "$snap"
        return 0
    fi
    if ! command -v jq >/dev/null 2>&1; then
        net_render_columns "$snap" 0 "jq is required to read provider details."
        rm -f "$snap"
        return 0
    fi

    list=$(net_get_active_ifaces)
    count=0
    for iface in $list; do
        count=$((count + 1))
    done

    _net_fill_snapshot "$snap" "$count" "$list"
    net_render_columns "$snap" "$count"
    rm -f "$snap"
}
