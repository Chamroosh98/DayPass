#!/bin/sh

# Setup can adopt an existing UCI interface. Neither its name nor the
# installed-driver inventory establishes exclusive ownership or a prior state.
usb_restore_settings() {
    local iface="${USB_WAN_IFACE:-wan_usb}" device

    if device=$(uci -q get "network.$iface.device" 2>/dev/null) ||
        device=$(uci -q get "network.$iface.ifname" 2>/dev/null); then
        printf '  Configured binding: %s → %s\n' "$iface" "$device"
    else
        log_warn "No readable device binding for [$iface]."
    fi
    log_warn "USB restore incomplete: setup has no verified previous binding or exclusive driver ownership record."
    return 1
}
