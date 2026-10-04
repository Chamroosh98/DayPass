#!/bin/sh
# DayPass - Choose one card or the multi-WAN list, then draw it.

# Fetch every active WAN, then draw one card or the list.
net_show_panel() {
    local list count iface dev metric data snap mwan

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
    for iface in $list; do
        dev=$(net_linux_dev "$iface" 2>/dev/null || true)
        metric=$(uci -q get "network.$iface.metric")
        [ -n "$metric" ] || metric="default"
        mwan=$(net_mwan3_state "$iface")
        data=$(net_fetch_iface_ip "$dev" 2>/dev/null || printf '%s\n' "false|||||||")
        printf '%s|%s|%s|%s|%s\n' "$iface" "$dev" "$metric" "$mwan" "$data" >> "$snap"
    done
    net_render_multiwan_ui "$snap"
    rm -f "$snap"
    echo
}
