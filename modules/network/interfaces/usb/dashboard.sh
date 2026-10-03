#!/bin/sh
# ============================================================
# DayPass - USB tethering dashboard
# Status block, then the operations menu. Echo only, so
# multi-byte emoji are not clipped by printf column widths.
# Safe to source. Never calls exit.
# ============================================================

# Prints the dashboard. Returns 0.
usb_render_dashboard() {
    local line state shown metric muted

    muted="${COLOR_MUTED:-${GRAY:-\033[90m}}"
    state="absent"
    if command -v usb_wan_state >/dev/null 2>&1; then
        state=$(usb_wan_state)
    fi

    echo "  📌 System & Network Status"
    echo "  ${muted}───────────────────────────────────────────────────────────${RESET}"

    echo "  🔌 USB hardware"
    line=$(usb_device_list 2>/dev/null | head -n 3)
    if [ -z "$line" ]; then
        echo "     none"
    else
        printf '%s\n' "$line" | while IFS= read -r line; do
            [ -n "$line" ] || continue
            echo "     $line"
        done
    fi

    if command -v usb_mtp_waiting >/dev/null 2>&1 && usb_mtp_waiting; then
        echo "  📶 Phone is in MTP mode. Enable USB Tethering on the phone."
    fi

    echo "  📱 Interfaces"
    line=$(usb_net_interfaces 2>/dev/null | head -n 4)
    if [ -z "$line" ]; then
        echo "     none"
    else
        printf '%s\n' "$line" | while IFS='|' read -r dev driver kind; do
            [ -n "$dev" ] || continue
            echo "     $dev  $driver  $kind"
        done
    fi

    echo "  ⚖️ WAN metrics"
    shown=0
    if command -v usb_metric_ifaces >/dev/null 2>&1; then
        for line in $(usb_metric_ifaces); do
            metric=$(uci -q get "network.$line.metric")
            [ -n "$metric" ] || metric="-"
            echo "     $line  metric $metric"
            shown=$((shown + 1))
            [ "$shown" -ge 6 ] && break
        done
    fi
    [ "$shown" -gt 0 ] || echo "     none"

    echo
    echo "  🛠️ Operations"
    echo "  ${muted}───────────────────────────────────────────────────────────${RESET}"
    echo "  📱 1) Setup USB Tethering"
    echo "  🔀 2) Toggle Interface ($state)"
    echo "  📶 3) Failover & Metrics"
    echo "  📌 4) Install Drivers"
    echo "  🧹 5) Restore / Reset USB"
    echo "  📟 6) Modem Mode Switch"
    echo "  🔄 7) Refresh"
    echo "  📊 8) System Resources"
    return 0
}
