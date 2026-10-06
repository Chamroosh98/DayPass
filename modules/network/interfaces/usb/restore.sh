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
    ifdown "$iface" >/dev/null 2>&1 || true
    if [ "$(uci -q get "network.$iface")" = "interface" ]; then
        dev=$(uci -q get "network.$iface.device")
        [ -n "$dev" ] || dev=$(uci -q get "network.$iface.ifname")
    fi
    uci -q delete "network.$iface" || true

    if [ -n "$dev" ]; then
        for zone in $(uci -q show network | sed -n "s/^network\.\([^.]*\)=device$/\1/p"); do
            if [ "$(uci -q get "network.$zone.name")" = "$dev" ]; then
                uci -q delete "network.$zone"
            fi
        done
    fi

    uci commit network || return 1
    ifdown "$iface" >/dev/null 2>&1 || true

    for zone in $(uci -q show firewall | sed -n "s/^firewall\.\([^.]*\)=zone$/\1/p"); do
        uci -q del_list "firewall.$zone.network=$iface"
    done
    uci commit firewall || return 1
    return 0
}

# Drop DayPass's package memory so the next menu reads opkg/apk, not a stale hit.
usb_restore_flush_cache() {
    rm -f /tmp/daypass_pkg_cache /tmp/daypass_usb_pkg.log 2>/dev/null || true
    return 0
}

# Unbind tether/modem USB interfaces only. Host controllers and storage stay bound.
usb_restore_unbind_net() {
    local node devpath drv name

    for node in /sys/class/net/usb* /sys/class/net/rndis* /sys/class/usbmisc/cdc-wdm*; do
        [ -e "$node" ] || continue
        devpath=$(readlink -f "$node/device" 2>/dev/null) || continue
        [ -n "$devpath" ] || continue
        drv=$(basename "$(readlink -f "$devpath/driver" 2>/dev/null)" 2>/dev/null)
        case "$drv" in
            rndis_host|cdc_ether|cdc_ncm|cdc_mbim|qmi_wwan|ipheth|huawei_cdc_ncm|cdc_eem|cdc_subset) ;;
            *) continue ;;
        esac
        name=$(basename "$devpath")
        if [ -n "$name" ] && [ -e "/sys/bus/usb/drivers/$drv/unbind" ]; then
            printf '%s\n' "$name" > "/sys/bus/usb/drivers/$drv/unbind" 2>/dev/null || true
        fi
        case "$node" in
            /sys/class/net/*)
                ip link set "$(basename "$node")" down >/dev/null 2>&1 || true
                ;;
        esac
    done
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
    printf '  %s✔ Purged network.wan_usb configuration from UCI.%s\n' "${GREEN:-}" "${RESET:-}"

    usb_restore_unbind_net
    usb_restore_unload_modules
    usb_restore_usb_subsystem

    if command -v ui_spinner >/dev/null 2>&1; then
        (_usb_restore_purge_job) >/dev/null 2>&1 &
        ui_spinner $! "Uninstalling USB driver packages..." && purge_ok=1
    else
        _usb_restore_purge_job && purge_ok=1
    fi

    usb_restore_flush_cache
    printf '  %s✔ Flushed DayPass driver state cache.%s\n' "${GREEN:-}" "${RESET:-}"
    printf '  %s✔ Soft-reset USB network stack and interface bindings.%s\n' "${GREEN:-}" "${RESET:-}"

    if usb_restore_network; then
        net_ok=1
    fi

    if [ "$purge_ok" -eq 1 ]; then
        printf '  %s✅ USB Stack restored to clean baseline state.%s\n' "${GREEN:-}" "${RESET:-}"
        if [ "$net_ok" -ne 1 ]; then
            log_warn "Configuration was cleared, but the network service did not restart."
        fi
        return 0
    fi
    log_warn "Some USB driver packages could not be removed. The drivers menu will show what is still installed."
    [ "$net_ok" -eq 1 ] || log_warn "Configuration was cleared, but the network service did not restart."
    return 1
}
