#!/bin/sh
# DayPass - USB tethering dashboard.
# Status card, then operations. Echo only. The hardware menu
# prints the shared header and footer.

# $1 interface state (enabled | disabled | absent)
usb_render_operations() {
    local state="${1:-absent}"

    echo "  🛠️ Operations"
    ui_divider
    echo "  1) 📌 Install Drivers (RNDIS / CDC-Ether / NCM)"
    echo "  2) 📱 Setup USB Tethering"
    echo "  3) 📶 Failover & Metrics Configuration"
    echo "  4) 🔀 Toggle Interface Status ($state)"
    echo "  5) ♻️ Restore / Reset USB Stack"
    echo "  6) 📟 Modem Mode Switch"
    echo "  7) 🔄 Refresh"
    echo "  8) 📈 System Resources"
}

# Prints the dashboard. Returns 0.
usb_render_dashboard() {
    local state

    state="absent"
    if command -v usb_wan_state >/dev/null 2>&1; then
        state=$(usb_wan_state)
    fi

    if command -v usb_render_status_card >/dev/null 2>&1; then
        usb_render_status_card
    else
        echo "  📡 USB & Network Status"
        ui_divider
        echo "  🔌 Hardware  : unavailable"
        echo "  📱 Interface : unavailable"
        echo "  ⚖️ Metrics   : none"
    fi
    echo
    usb_render_operations "$state"
    return 0
}
