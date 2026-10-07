#!/bin/sh
# DayPass - Live download/upload rate on the first active WAN device.

net_monitor_live_speed() {
    local iface="" dev="" rx_prev tx_prev rx_now tx_now rx_speed tx_speed rx_fmt tx_fmt

    for iface in $(net_get_active_ifaces); do
        dev=$(net_linux_dev "$iface" 2>/dev/null || true)
        [ -n "$dev" ] && [ -d "/sys/class/net/$dev" ] && break
        dev=""
    done
    if [ -z "$dev" ]; then
        dev=$(ip route show default 2>/dev/null | awk '/default/ { print $5; exit }')
    fi
    if [ -z "$dev" ] || [ ! -d "/sys/class/net/$dev" ]; then
        echo "  📊 No WAN device to monitor."
        return 1
    fi

    echo
    echo "  📊 Live speed on $dev"
    echo "  Press Ctrl+C to stop."
    echo

    rx_prev=$(cat "/sys/class/net/$dev/statistics/rx_bytes" 2>/dev/null || echo 0)
    tx_prev=$(cat "/sys/class/net/$dev/statistics/tx_bytes" 2>/dev/null || echo 0)
    trap 'echo ""; trap - INT; return 0' INT

    while true; do
        sleep 1
        rx_now=$(cat "/sys/class/net/$dev/statistics/rx_bytes" 2>/dev/null || echo 0)
        tx_now=$(cat "/sys/class/net/$dev/statistics/tx_bytes" 2>/dev/null || echo 0)
        rx_speed=$(( (rx_now - rx_prev) / 1024 ))
        tx_speed=$(( (tx_now - tx_prev) / 1024 ))
        [ "$rx_speed" -lt 0 ] && rx_speed=0
        [ "$tx_speed" -lt 0 ] && tx_speed=0

        if [ "$rx_speed" -gt 1024 ]; then
            rx_fmt=$(awk "BEGIN { printf \"%.2f MB/s\", $rx_speed/1024 }")
        else
            rx_fmt="${rx_speed} KB/s"
        fi
        if [ "$tx_speed" -gt 1024 ]; then
            tx_fmt=$(awk "BEGIN { printf \"%.2f MB/s\", $tx_speed/1024 }")
        else
            tx_fmt="${tx_speed} KB/s"
        fi

        printf '\r  📥 Down: %s    📤 Up: %s   ' "$rx_fmt" "$tx_fmt"
        rx_prev=$rx_now
        tx_prev=$tx_now
    done
}
