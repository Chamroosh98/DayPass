#!/bin/sh
# ============================================================
# DayPass - Hardware & USB Tethering Manager
# USB phones (RNDIS / CDC-Ether / NCM / iPhone), USB modems,
# ModeSwitch and WAN failover metrics.
# ============================================================

_hw_metric() {
    if command -v usb_iface_metric_text >/dev/null 2>&1; then
        usb_iface_metric_text "$1"
        return 0
    fi
    uci -q get "network.$1.metric" || echo "0 [default]"
}

show_hardware_status() {
    local devices line dev driver kind state carrier ports iface

    ui_title "🔌 USB Devices"
    devices=$(usb_device_list 2>/dev/null)
    if [ -n "$devices" ]; then
        printf '%s\n' "$devices" | while IFS= read -r line; do
            printf "  • %s\n" "$line"
        done
    else
        echo "  ${GRAY}No USB devices detected.${RESET}"
    fi
    command -v lsusb >/dev/null 2>&1 || echo "  ${GRAY}(lsusb missing, read from sysfs; install the USB profile for usbutils)${RESET}"

    echo
    ui_title "📱 USB Network Interfaces"
    line=$(usb_net_interfaces 2>/dev/null)
    if [ -n "$line" ]; then
        printf '%s\n' "$line" | while IFS='|' read -r dev driver kind; do
            carrier=$(cat "/sys/class/net/$dev/operstate" 2>/dev/null)
            printf "  • %-8s %-14s ${GRAY}%-7s${RESET} link %s\n" "$dev" "$driver" "$kind" "${carrier:-unknown}"
        done
    else
        echo "  ${GRAY}None. Connect the phone and enable USB Tethering on it.${RESET}"
    fi

    ports=$(usb_modem_ports)
    [ -n "$ports" ] && printf "  📟 Modem ports : %s\n" "$ports"

    echo
    ui_title "🧭 WAN Failover (lower metric = preferred)"
    for iface in wan wan_usb wwan; do
        [ "$(uci -q get network.$iface)" = "interface" ] || continue
        if [ "$iface" = "wan_usb" ]; then
            state=$(usb_wan_state)
        elif [ "$(uci -q get network.$iface.disabled)" = "1" ]; then
            state="disabled"
        else
            state="enabled"
        fi
        printf "  • %-8s metric %-8s %s\n" "$iface" "$(_hw_metric "$iface")" "$state"
    done
    usb_wan_exists || echo "  ${GRAY}wan_usb not configured.${RESET}"
    if [ -f /etc/config/mwan3 ]; then
        echo "  ${GRAY}mwan3 is configured; its member metrics decide failover while it runs.${RESET}"
    fi
    ui_divider
}

# Sets HW_DEVICE to a tethering device picked by the user (empty = cancel)
_hw_pick_tether_device() {
    local list count i dev

    HW_DEVICE=""
    list=$(usb_tether_interfaces)
    count=$(printf '%s\n' "$list" | grep -c .)

    if [ "$count" -eq 0 ]; then
        printf "  ${RED}❌ No active USB Network Hardware detected! Please connect your phone/dongle, turn on USB Tethering, and try again.${RESET}\n"
        return 1
    fi

    if [ "$count" -eq 1 ]; then
        HW_DEVICE="$list"
        return 0
    fi

    i=1
    for dev in $list; do
        printf "  %s) %s (%s)\n" "$i" "$dev" "$(usb_net_driver "$dev")"
        i=$((i + 1))
    done
    ui_read "Select device [1-$count]"
    case "$UI_CHOICE" in
        0|'') return 1 ;;
        q|Q) daypass_quit ;;
    esac

    i=1
    for dev in $list; do
        [ "$UI_CHOICE" = "$i" ] && HW_DEVICE="$dev"
        i=$((i + 1))
    done
    [ -n "$HW_DEVICE" ] || { log_warn "Invalid option!"; return 1; }
}

hardware_setup_tethering() {
    if ! command -v usb_net_hardware_present >/dev/null 2>&1 || ! usb_net_hardware_present; then
        printf "  ${RED}❌ No active USB Network Hardware detected! Please connect your phone/dongle, turn on USB Tethering, and try again.${RESET}\n"
        return 1
    fi

    if command -v usb_mtp_waiting >/dev/null 2>&1 && usb_mtp_waiting; then
        log_warn "Phone is in MTP mode. Enable USB Tethering on the phone first."
        return 1
    fi

    _hw_pick_tether_device || return 1

    ui_read "Route metric [${USB_WAN_DEFAULT_METRIC}]"
    case "$UI_CHOICE" in
        q|Q) daypass_quit ;;
        '') UI_CHOICE="$USB_WAN_DEFAULT_METRIC" ;;
        *[!0-9]*) log_warn "Invalid metric!"; return 0 ;;
    esac

    setup_usb_wan "$HW_DEVICE" "$UI_CHOICE"
}

hardware_toggle_tethering() {
    case "$(usb_wan_state)" in
        DISABLED) usb_wan_set_enabled 1 ;;
        UP|DOWN)  usb_wan_set_enabled 0 ;;
        *)        log_warn "USB WAN is not configured. Use option 2 first." ;;
    esac
}

hardware_failover_menu() {
    if command -v usb_metric_menu >/dev/null 2>&1; then
        usb_metric_menu
        return 0
    fi
    log_error "USB metric module not found!"
    return 1
}

_hw_modeswitch_bin() {
    if command -v usb_modeswitch >/dev/null 2>&1; then
        printf '%s\n' "usb_modeswitch"
        return 0
    fi
    if command -v usb-modeswitch >/dev/null 2>&1; then
        printf '%s\n' "usb-modeswitch"
        return 0
    fi
    return 1
}

hardware_modeswitch() {
    local bin path devpath rc=1

    bin=$(_hw_modeswitch_bin) || bin=""
    if [ -z "$bin" ]; then
        log_warn "usb-modeswitch not found. Run [opkg install usb-modeswitch] or install USB drivers from option 1."
        return 0
    fi

    ui_read "Switch connected USB modems out of storage mode? [y/N]"
    case "$UI_CHOICE" in
        y|Y) ;;
        q|Q) daypass_quit ;;
        *) return 0 ;;
    esac

    if command -v usb_modeswitch_dispatcher >/dev/null 2>&1; then
        for path in /sys/bus/usb/devices/*; do
            [ -e "$path/idVendor" ] || continue
            devpath=$(readlink -f "$path" 2>/dev/null)
            [ -n "$devpath" ] || continue
            DEVPATH="${devpath#/sys}" usb_modeswitch_dispatcher --switch-mode >/dev/null 2>&1 && rc=0
        done
    else
        "$bin" >/dev/null 2>&1 && rc=0
    fi
    if [ "$rc" -eq 0 ]; then
        log_success "ModeSwitch sent. Re-check status in a few seconds."
    else
        log_warn "No USB device needed a mode switch, or the switch did not apply."
    fi
}

hardware_remove_tethering() {
    ui_read "Remove wan_usb? [y/N]"
    case "$UI_CHOICE" in
        y|Y) remove_usb_wan ;;
        q|Q) daypass_quit ;;
    esac
}

hardware_menu() {
    local HELP_MODULE_ID="hardware"

    if ! command -v usb_net_interfaces >/dev/null 2>&1; then
        log_error "USB WAN module not found!"
        sleep 2
        return 1
    fi

    while true; do
        render_persistent_header
        if command -v usb_render_dashboard >/dev/null 2>&1; then
            usb_render_dashboard
        else
            show_hardware_status
        fi
        ui_nav_footer main
        ui_read "Select option"

        case "$UI_CHOICE" in
            1) ui_run usb_driver_menu "USB Drivers"; continue ;;
            2) hardware_setup_tethering ;;
            3) hardware_failover_menu; continue ;;
            4) hardware_toggle_tethering ;;
            5)
                if command -v usb_restore_settings >/dev/null 2>&1; then
                    usb_restore_settings || true
                else
                    hardware_remove_tethering
                fi
                ;;
            6) hardware_modeswitch ;;
            7) continue ;;
            8) ui_run show_system_resources_menu "System Resources"; continue ;;
            0) return 0 ;;
            *)
                ui_nav_common "$UI_CHOICE" "$HELP_MODULE_ID" && continue
                log_warn "Invalid option!"
                sleep 1
                continue
                ;;
        esac

        ui_pause
    done
}
