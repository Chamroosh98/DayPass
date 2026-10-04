#!/bin/sh
# DayPass - USB tethering dashboard.
# Open two columns: operations on the left, hardware tree on the right.
# The hardware menu prints the shared header and footer.

# $1 interface state (enabled | disabled | absent)
usb_render_left_menu() {
    local state="${1:-absent}"

    echo "  🛠️ Operations"
    echo "  ─────────────"
    echo "  📱 1) Setup USB Tethering"
    echo "  🔀 2) Toggle Interface ($state)"
    echo "  📶 3) Failover & Metrics"
    echo "  📌 4) Install Drivers"
    echo "  ♻️ 5) Restore / Reset USB"
    echo "  📟 6) Modem Mode Switch"
    echo "  🔄 7) Refresh"
    echo "  📊 8) System Resources"
}

# Prints the dashboard. Returns 0.
usb_render_dashboard() {
    local state left right

    state="absent"
    if command -v usb_wan_state >/dev/null 2>&1; then
        state=$(usb_wan_state)
    fi

    left="/tmp/daypass_usbleft.$$"
    right="/tmp/daypass_usbright.$$"
    usb_render_left_menu "$state" > "$left"
    if command -v usb_render_status_tree >/dev/null 2>&1; then
        usb_render_status_tree > "$right"
    else
        echo "  └── 🔌 USB status is not loaded." > "$right"
    fi
    if command -v _net_zip_columns >/dev/null 2>&1; then
        _net_zip_columns "$left" "$right" 38
    else
        cat "$left"
        echo
        cat "$right"
    fi
    rm -f "$left" "$right"
    return 0
}
