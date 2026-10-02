#!/bin/sh
# ============================================================
# DayPass - USB WAN Module
# Handles Android / iPhone USB Tethering and USB modem detection
# ============================================================

USB_WAN_IFACE="wan_usb"
USB_WAN_DEFAULT_METRIC="20"

# Kernel driver bound to a network device, empty when not USB-backed
usb_net_driver() {
    local dev="$1"
    local path

    path=$(readlink -f "/sys/class/net/$dev/device" 2>/dev/null)
    case "$path" in
        */usb*) ;;
        *) return 1 ;;
    esac

    path=$(readlink -f "/sys/class/net/$dev/device/driver" 2>/dev/null)
    [ -n "$path" ] || return 1
    echo "${path##*/}"
}

# Lines: device|driver|kind   (kind: tether | modem | usbnet)
usb_net_interfaces() {
    local path dev driver kind

    for path in /sys/class/net/*; do
        [ -e "$path" ] || continue
        dev="${path##*/}"
        driver=$(usb_net_driver "$dev") || continue

        case "$driver" in
            rndis_host|cdc_ether|cdc_ncm|cdc_eem|cdc_subset|ipheth) kind="tether" ;;
            qmi_wwan|cdc_mbim|huawei_cdc_ncm|sierra_net)            kind="modem" ;;
            *)                                                        kind="usbnet" ;;
        esac
        echo "$dev|$driver|$kind"
    done
}

# Tethering devices only, one per line
usb_tether_interfaces() {
    usb_net_interfaces | awk -F'|' '$3 == "tether" { print $1 }'
}

# First tethering device (legacy API used by setup_usb_wan)
detect_usb_device() {
    local dev

    dev=$(usb_tether_interfaces | head -n 1)
    if [ -z "$dev" ]; then
        # Name-based fallback for kernels without a driver link
        for dev in usb0 usb1 rndis0; do
            if [ -e "/sys/class/net/$dev" ]; then
                echo "$dev"
                return 0
            fi
        done
        echo ""
        return 1
    fi
    echo "$dev"
}

# Lines: "vid:pid name" for every non-hub USB device
usb_device_list() {
    local d vid pid name

    if command -v lsusb >/dev/null 2>&1; then
        lsusb 2>/dev/null | grep -v "1d6b:" | sed 's/^Bus [0-9]* Device [0-9]*: ID //'
        return 0
    fi

    for d in /sys/bus/usb/devices/*; do
        [ -f "$d/idVendor" ] || continue
        vid=$(cat "$d/idVendor")
        [ "$vid" = "1d6b" ] && continue
        pid=$(cat "$d/idProduct" 2>/dev/null)
        name="$(cat "$d/manufacturer" 2>/dev/null) $(cat "$d/product" 2>/dev/null)"
        echo "$vid:$pid ${name# }"
    done
}

# Modem control / serial ports (QMI, MBIM, AT)
usb_modem_ports() {
    ls /dev/cdc-wdm* /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | tr '\n' ' '
}

_usb_wan_zone() {
    uci -q show firewall | sed -n "s/^firewall\.\([^.]*\)\.name='wan'$/\1/p" | head -n 1
}

usb_wan_exists() {
    [ "$(uci -q get network.$USB_WAN_IFACE)" = "interface" ]
}

# enabled | disabled | absent
usb_wan_state() {
    usb_wan_exists || { echo "absent"; return 0; }
    if [ "$(uci -q get network.$USB_WAN_IFACE.disabled)" = "1" ]; then
        echo "disabled"
    else
        echo "enabled"
    fi
}

# Create or update USB tethering WAN interface
# Usage: setup_usb_wan [device] [metric]
setup_usb_wan() {
    local usb_dev="${1:-}"
    local metric="${2:-$USB_WAN_DEFAULT_METRIC}"
    local zone

    log_info "Setting up USB Tethering WAN interface ..."

    if command -v ensure_usb_tether_kmods >/dev/null 2>&1; then
        ensure_usb_tether_kmods || true
    fi

    if [ -z "$usb_dev" ]; then
        usb_dev=$(detect_usb_device)
    fi

    if [ -z "$usb_dev" ]; then
        log_warn "No USB tethering device detected."
        log_warn "Connect your phone and enable USB Tethering first."
        usb_dev="usb0"
    else
        log_success "Using USB device : $usb_dev"
    fi

    uci set network.$USB_WAN_IFACE=interface
    uci set network.$USB_WAN_IFACE.proto='dhcp'
    uci set network.$USB_WAN_IFACE.device="$usb_dev"
    uci set network.$USB_WAN_IFACE.metric="$metric"
    uci -q delete network.$USB_WAN_IFACE.disabled
    uci commit network

    zone=$(_usb_wan_zone)
    if [ -n "$zone" ]; then
        uci -q del_list firewall.$zone.network="$USB_WAN_IFACE"
        uci add_list firewall.$zone.network="$USB_WAN_IFACE"
        uci commit firewall
        /etc/init.d/firewall reload >/dev/null 2>&1
    else
        log_warn "Firewall zone [wan] not found; add [$USB_WAN_IFACE] to your WAN zone manually."
    fi

    ifup $USB_WAN_IFACE >/dev/null 2>&1 || true
    log_success "USB WAN interface [$USB_WAN_IFACE] is ready (device $usb_dev, metric $metric)!"
}

# Usage: usb_wan_set_enabled 1|0
usb_wan_set_enabled() {
    usb_wan_exists || { log_warn "USB WAN [$USB_WAN_IFACE] is not configured."; return 1; }

    if [ "$1" = "1" ]; then
        uci -q delete network.$USB_WAN_IFACE.disabled
        uci commit network
        ifup $USB_WAN_IFACE >/dev/null 2>&1 || true
        log_success "USB WAN [$USB_WAN_IFACE] enabled."
    else
        ifdown $USB_WAN_IFACE >/dev/null 2>&1 || true
        uci set network.$USB_WAN_IFACE.disabled='1'
        uci commit network
        log_success "USB WAN [$USB_WAN_IFACE] disabled."
    fi
}

# Usage: usb_wan_set_metric <interface> <metric>
usb_wan_set_metric() {
    local iface="$1"
    local metric="$2"

    case "$metric" in
        ''|*[!0-9]*) log_error "Invalid metric [$metric]!"; return 1 ;;
    esac
    [ "$(uci -q get network.$iface)" = "interface" ] || { log_error "Interface [$iface] not found!"; return 1; }

    uci set network.$iface.metric="$metric"
    uci commit network
    if [ "$(uci -q get network.$iface.disabled)" != "1" ]; then
        ifup "$iface" >/dev/null 2>&1 || true
    fi
    log_success "Metric of [$iface] set to $metric."
}

remove_usb_wan() {
    local zone

    usb_wan_exists || { log_warn "USB WAN [$USB_WAN_IFACE] is not configured."; return 0; }

    ifdown $USB_WAN_IFACE >/dev/null 2>&1 || true
    uci -q delete network.$USB_WAN_IFACE
    uci commit network

    zone=$(_usb_wan_zone)
    if [ -n "$zone" ]; then
        uci -q del_list firewall.$zone.network="$USB_WAN_IFACE"
        uci commit firewall
        /etc/init.d/firewall reload >/dev/null 2>&1
    fi
    log_success "USB WAN [$USB_WAN_IFACE] removed."
}
