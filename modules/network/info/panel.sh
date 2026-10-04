#!/bin/sh
# DayPass - Choose one card or the multi-WAN list, then draw it.

# Fetch every active WAN, then draw one card or the list.
net_show_panel() {
    local list count iface dev metric data snap mwan _net_pids _net_pid

    if command -v render_persistent_header >/dev/null 2>&1; then
        render_persistent_header
    fi

    if ! command -v curl >/dev/null 2>&1; then
        echo "  🌐 Network Diagnostics"
        echo "  curl is required for interface queries."
        echo
        return 0
    fi
    if ! command -v jq >/dev/null 2>&1; then
        echo "  🌐 Network Diagnostics"
        echo "  jq is required to read provider details."
        echo
        return 0
    fi

    list=$(net_get_active_ifaces)
    count=0
    for iface in $list; do
        count=$((count + 1))
    done

    if [ "$count" -le 1 ]; then
        iface=$(printf '%s\n' "$list" | head -n 1)
        [ -n "$iface" ] || iface="wan"
        dev=$(net_linux_dev "$iface" 2>/dev/null || true)
        metric=$(uci -q get "network.$iface.metric")
        data=$(net_fetch_iface_ip "$dev" 2>/dev/null || printf '%s\n' "false|||||||")
        net_render_standalone_ui "$iface" "$dev" "$metric" "$data"
        echo
        return 0
    fi

    snap="/tmp/daypass_netsnap.$$"
    : > "$snap"
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
    done
    net_render_multiwan_ui "$snap"
    rm -f "$snap"
    for iface in $list; do
        rm -f "/tmp/daypass_netsnap.$$.$iface" "/tmp/daypass_netsnap.$$.$iface.meta"
    done
    echo
}
