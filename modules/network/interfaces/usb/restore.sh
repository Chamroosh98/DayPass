#!/bin/sh
# ============================================================
# DayPass - Restore / reset USB tethering
# Removes wan_usb from network and firewall, restarts the
# network service, and can uninstall the USB driver packages.
# Safe to source. Never calls exit.
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

# Drop wan_usb, its device binding, and its firewall zone membership.
# Returns 0 when the sections are gone, 1 when uci commit fails.
usb_restore_uci() {
    local zone dev

    dev=""
    if [ "$(uci -q get network.wan_usb)" = "interface" ]; then
        dev=$(uci -q get network.wan_usb.device)
        ifdown wan_usb >/dev/null 2>&1 || true
        uci -q delete network.wan_usb
    fi

    if [ -n "$dev" ]; then
        for zone in $(uci -q show network | sed -n "s/^network\.\([^.]*\)=device$/\1/p"); do
            if [ "$(uci -q get network.$zone.name)" = "$dev" ]; then
                uci -q delete network.$zone
            fi
        done
    fi

    uci commit network || return 1

    for zone in $(uci -q show firewall | sed -n "s/^firewall\.\([^.]*\)=zone$/\1/p"); do
        uci -q del_list firewall.$zone.network="wan_usb"
    done
    uci commit firewall || return 1
    return 0
}

usb_restore_network() {
    if [ -x /etc/init.d/network ]; then
        /etc/init.d/network restart >/dev/null 2>&1 || return 1
    fi
    return 0
}

# Asks, then removes UCI state and restarts networking.
# A second prompt optionally uninstalls the driver packages.
# Returns 1 when the user declines or a step fails.
usb_restore_settings() {
    local answer=""

    usb_restore_confirm || return 1

    if ! usb_restore_uci; then
        log_error "Could not clear USB network configuration."
        return 1
    fi

    if usb_restore_network; then
        log_success "USB network configuration restored. Network service restarted."
    else
        log_warn "Configuration was cleared, but the network service did not restart."
    fi

    printf "  ⁉️ Uninstall USB tethering and modem drivers to free flash space? [y/N] : "
    if ! read -r answer </dev/tty; then
        return 0
    fi
    case "$answer" in
        y|Y|yes|YES) ;;
        *) return 0 ;;
    esac

    if command -v usb_purge_driver_packages >/dev/null 2>&1 && usb_purge_driver_packages; then
        log_success "USB driver packages removed."
        return 0
    fi
    log_warn "Some USB driver packages could not be removed."
    return 1
}
