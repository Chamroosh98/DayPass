#!/bin/sh
# ============================================================
# DayPass - USB WAN Module
# Handles Android / iPhone USB Tethering interface
# ============================================================

# Detect active USB tethering network device
detect_usb_device() {
    for dev in usb0 usb1 rndis0 eth1 eth2; do
        if ip link show "$dev" >/dev/null 2>&1; then
            echo "$dev"
            return 0
        fi
    done
    echo ""
}

# Create or update USB tethering WAN interface
setup_usb_wan() {
    log_info "Setting up USB Tethering WAN interface ..."

    local usb_dev
    usb_dev=$(detect_usb_device)

    if [ -z "$usb_dev" ]; then
        log_warn "No USB tethering device detected!"
        log_warn "Connect your phone and enable USB Tethering first!"
        usb_dev="usb0"
    else
        log_success "Detected USB device : $usb_dev"
    fi

    uci set network.wan_usb=interface
    uci set network.wan_usb.proto='dhcp'
    uci set network.wan_usb.device="$usb_dev"
    uci set network.wan_usb.metric='20'
    uci commit network

    # Add to firewall wan zone safely
    local zone
    zone=$(uci show firewall | grep "=zone" | while read -r l; do
        s=$(echo "$l" | cut -d'.' -f2 | cut -d'=' -f1)
        [ "$(uci -q get firewall.$s.name)" = "wan" ] && echo "$s" && break
    done)

    if [ -n "$zone" ]; then
        uci -q del_list firewall.$zone.network='wan_usb'
        uci add_list firewall.$zone.network='wan_usb'
        uci commit firewall
    fi

    ifup wan_usb >/dev/null 2>&1 || true
    log_success "USB WAN interface [wan_usb] is ready!"
}