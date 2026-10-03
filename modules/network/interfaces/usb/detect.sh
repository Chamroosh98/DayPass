#!/bin/sh
# ============================================================
# DayPass - USB network interface detection
# Scans /sys/class/net and dmesg. Safe to source. Never calls exit.
# ============================================================

# Kernel driver bound to a network device. Returns 1 when not USB-backed.
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
    printf '%s\n' "${path##*/}"
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
        printf '%s|%s|%s\n' "$dev" "$driver" "$kind"
    done
}

# Tethering devices from sysfs, one per line. Returns 1 when none exist.
usb_tether_interfaces() {
    local dev

    dev=$(usb_net_interfaces | awk -F'|' '$3 == "tether" { print $1 }')
    [ -n "$dev" ] || return 1
    printf '%s\n' "$dev"
    return 0
}

# Interface names dmesg registered under a USB network driver.
# Returns 1 when dmesg has no usable USB net device.
usb_dmesg_interfaces() {
    local line word out=""

    while IFS= read -r line; do
        case "$line" in
            *rndis_host*|*cdc_ether*|*cdc_ncm*|*cdc_eem*|*ipheth*) ;;
            *) continue ;;
        esac
        for word in $line; do
            word="${word%%:*}"
            word="${word%%,*}"
            case "$word" in
                usb[0-9]*|eth[0-9]*|rndis[0-9]*|enx*)
                    [ -e "/sys/class/net/$word" ] || continue
                    case " $out " in
                        *" $word "*) ;;
                        *) out="$out $word" ;;
                    esac
                    ;;
            esac
        done
    done <<EOF
$(dmesg 2>/dev/null)
EOF

    out=${out# }
    [ -n "$out" ] || return 1
    for word in $out; do
        printf '%s\n' "$word"
    done
    return 0
}

# First tethering device: sysfs, then dmesg, then well-known names.
# Prints the name and returns 0, or returns 1 when nothing is present.
detect_usb_device() {
    local dev

    dev=$(usb_tether_interfaces 2>/dev/null | head -n 1)
    if [ -n "$dev" ]; then
        printf '%s\n' "$dev"
        return 0
    fi

    dev=$(usb_dmesg_interfaces 2>/dev/null | head -n 1)
    if [ -n "$dev" ]; then
        printf '%s\n' "$dev"
        return 0
    fi

    for dev in usb0 usb1 rndis0; do
        if [ -e "/sys/class/net/$dev" ]; then
            printf '%s\n' "$dev"
            return 0
        fi
    done

    return 1
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
        printf '%s:%s %s\n' "$vid" "$pid" "${name# }"
    done
}

# Modem control / serial ports (QMI, MBIM, AT)
usb_modem_ports() {
    ls /dev/cdc-wdm* /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | tr '\n' ' '
}
