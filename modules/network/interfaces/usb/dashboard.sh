#!/bin/sh
# DayPass - USB tethering operations menu.
# Echo only. The hardware menu prints the shared header and footer.

# $1 interface state (UP | DOWN | DISABLED | absent)
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
    echo "  7) 📡 Network Interfaces State"
    echo "  8) 📈 System Resources"
}

# Prints the operations list. Returns 0.
usb_render_dashboard() {
    local state

    state="absent"
    if command -v usb_wan_state >/dev/null 2>&1; then
        state=$(usb_wan_state)
    fi

    usb_render_operations "$state"
    return 0
}
