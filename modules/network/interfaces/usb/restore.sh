#!/bin/sh
# ============================================================
# DayPass - Restore / reset USB tethering
# Removes wan_usb from network and firewall, uninstalls USB
# driver packages, unloads tether modules, and restarts
# networking. Safe to source. Never calls exit.
# ============================================================

# 0 only on an explicit yes. Enter is No.
usb_restore_confirm() {
    local answer=""

    printf "  ⁉️ Are you sure you want to restore all USB network configurations to default? [y/N] : "
    if ! read -r answer </dev/tty; then
        return 1
    fi
    case "$answer" in
        y|Y|yes|YES) return 0 ;;
    esac
    return 1
}

# Logical interface name used by USB tethering UCI.
_usb_restore_iface() {
    printf '%s\n' "${USB_WAN_IFACE:-wan_usb}"
}

# Drop wan_usb, its device binding, and its firewall zone membership.
# Returns 0 when the sections are gone, 1 when uci commit fails.
usb_restore_uci() {
    local zone dev iface

    iface=$(_usb_restore_iface)
    command -v uci >/dev/null 2>&1 || return 1

    dev=""
    if [ "$(uci -q get "network.$iface")" = "interface" ]; then
        dev=$(uci -q get "network.$iface.device")
        [ -n "$dev" ] || dev=$(uci -q get "network.$iface.ifname")
        ifdown "$iface" >/dev/null 2>&1 || true
        uci -q delete "network.$iface"
    fi

    if [ -n "$dev" ]; then
        for zone in $(uci -q show network | sed -n "s/^network\.\([^.]*\)=device$/\1/p"); do
            if [ "$(uci -q get "network.$zone.name")" = "$dev" ]; then
                uci -q delete "network.$zone"
            fi
        done
    fi

    uci commit network || return 1

    for zone in $(uci -q show firewall | sed -n "s/^firewall\.\([^.]*\)=zone$/\1/p"); do
        uci -q del_list "firewall.$zone.network=$iface"
    done
    uci commit firewall || return 1
    return 0
}

# Unload USB tethering / modem kernel modules that are still loaded.
usb_restore_unload_modules() {
    local mod

    for mod in rndis_host cdc_ether cdc_ncm cdc_eem cdc_subset ipheth \
        qmi_wwan cdc_mbim huawei_cdc_ncm sierra_net option usb_wwan; do
        lsmod 2>/dev/null | grep -q "^${mod} " || continue
        rmmod "$mod" >/dev/null 2>&1 || true
    done
    return 0
}

# Stop usbmuxd when that service exists.
usb_restore_usb_subsystem() {
    if [ -x /etc/init.d/usbmuxd ]; then
        /etc/init.d/usbmuxd stop >/dev/null 2>&1 || true
    fi
    return 0
}

usb_restore_network() {
    if [ -x /etc/init.d/network ]; then
        /etc/init.d/network restart >/dev/null 2>&1 || return 1
    fi
    return 0
}

_usb_restore_purge_job() {
    if command -v usb_purge_driver_packages >/dev/null 2>&1; then
        usb_purge_driver_packages
        return $?
    fi
    return 0
}

# Asks once, then clears UCI, uninstalls USB drivers, unloads modules,
# and reloads the network / USB subsystem.
# Returns 1 when the user declines or a required step fails.
usb_restore_settings() {
    local purge_ok=0
    local net_ok=0

    usb_restore_confirm || return 1

    if ! usb_restore_uci; then
        log_error "Could not clear USB network configuration."
        return 1
    fi

    usb_restore_unload_modules

    (_usb_restore_purge_job) >/dev/null 2>&1 &
    if command -v ui_spinner >/dev/null 2>&1; then
        ui_spinner $! "Uninstalling USB driver packages..."
    else
        wait $!
    fi
    if [ $? -eq 0 ]; then
        purge_ok=1
    fi

    usb_restore_usb_subsystem

    if usb_restore_network; then
        net_ok=1
    fi

    if [ "$purge_ok" -eq 1 ] && [ "$net_ok" -eq 1 ]; then
        log_success "USB stack reset complete. Drivers uninstalled and network reloaded."
        return 0
    fi
    if [ "$purge_ok" -ne 1 ]; then
        log_warn "Some USB driver packages could not be removed."
    fi
    if [ "$net_ok" -ne 1 ]; then
        log_warn "Configuration was cleared, but the network service did not restart."
    fi
    [ "$purge_ok" -eq 1 ]
}
