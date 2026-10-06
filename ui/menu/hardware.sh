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

# UCI interface names, one per line. Skips loopback.
_hw_toggle_ifaces() {
    local iface

    uci -q show network 2>/dev/null | sed -n 's/^network\.\([A-Za-z0-9_]*\)=interface$/\1/p' | while IFS= read -r iface; do
        case "$iface" in
            loopback|lo) continue ;;
        esac
        printf '%s\n' "$iface"
    done
}

# UP when netifd reports the interface up, otherwise DOWN.
_hw_iface_oper() {
    local iface="$1"
    local json=""

    json=$(ubus call "network.interface.$iface" status 2>/dev/null || true)
    if printf '%s' "$json" | grep -q '"up"[[:space:]]*:[[:space:]]*true'; then
        printf '%s\n' "UP"
        return 0
    fi
    if command -v ifstatus >/dev/null 2>&1; then
        json=$(ifstatus "$iface" 2>/dev/null || true)
        if printf '%s' "$json" | grep -q '"up"[[:space:]]*:[[:space:]]*true'; then
            printf '%s\n' "UP"
            return 0
        fi
    fi
    printf '%s\n' "DOWN"
}

_hw_toggle_apply() {
    local iface="$1"
    local disabled oper

    [ "$(uci -q get "network.$iface")" = "interface" ] || return 1
    disabled=$(uci -q get "network.$iface.disabled")
    oper=$(_hw_iface_oper "$iface")

    if [ "$disabled" != "1" ] && [ "$oper" = "UP" ]; then
        ifdown "$iface" >/dev/null 2>&1 || true
        uci set "network.$iface.disabled"="1"
        uci commit network || return 1
        printf '  %s⚠️ Interface [%s] disabled and brought DOWN.%s\n' "$YELLOW" "$iface" "$RESET"
        return 0
    fi

    uci set "network.$iface.disabled"="0"
    uci commit network || return 1
    ifup "$iface" >/dev/null 2>&1 || true
    printf '  %s✅ Interface [%s] enabled and brought UP.%s\n' "$GREEN" "$iface" "$RESET"
}

hardware_toggle_tethering() {
    local list count i iface uci_st oper choice

    while true; do
        if command -v render_persistent_header >/dev/null 2>&1; then
            render_persistent_header
        fi
        if command -v ui_title >/dev/null 2>&1; then
            ui_title "🔀 Toggle Interface Status"
        else
            echo "  🔀 Toggle Interface Status"
            command -v ui_divider >/dev/null 2>&1 && ui_divider
        fi

        list=$(_hw_toggle_ifaces)
        count=0
        if [ -z "$list" ]; then
            echo "  No network interfaces found."
        else
            printf '  %s  %-12s  %-14s  %s\n' " # " "Interface" "UCI" "Oper"
            command -v ui_divider >/dev/null 2>&1 && ui_divider
            i=1
            for iface in $list; do
                count=$i
                if [ "$(uci -q get "network.$iface.disabled")" = "1" ]; then
                    uci_st="[Disabled]"
                else
                    uci_st="[Enabled]"
                fi
                oper=$(_hw_iface_oper "$iface")
                if [ "$oper" = "UP" ]; then
                    printf '  %2d) %-12s  %-14s  %s[UP]%s\n' "$i" "$iface" "$uci_st" "$GREEN" "$RESET"
                else
                    printf '  %2d) %-12s  %-14s  %s[DOWN]%s\n' "$i" "$iface" "$uci_st" "$RED" "$RESET"
                fi
                i=$((i + 1))
            done
        fi
        echo
        echo "  0) Back to Menu"
        echo
        if command -v ui_read >/dev/null 2>&1; then
            ui_read "Select interface"
        else
            printf '  Select interface : '
            read -r UI_CHOICE </dev/tty || return 0
        fi

        case "$UI_CHOICE" in
            0|'') return 0 ;;
            q|Q)
                command -v daypass_quit >/dev/null 2>&1 && daypass_quit
                return 0
                ;;
            h|H)
                command -v ui_show_help >/dev/null 2>&1 && ui_show_help "hardware"
                continue
                ;;
        esac

        case "$UI_CHOICE" in
            *[!0-9]*) log_warn "Invalid option!"; continue ;;
        esac
        [ "$UI_CHOICE" -ge 1 ] && [ "$UI_CHOICE" -le "$count" ] || {
            log_warn "Invalid option!"
            continue
        }

        i=1
        iface=""
        for choice in $list; do
            [ "$i" = "$UI_CHOICE" ] && iface="$choice"
            i=$((i + 1))
        done
        [ -n "$iface" ] || continue
        _hw_toggle_apply "$iface" || log_error "Could not toggle [$iface]."
    done
}

hardware_failover_menu() {
    if command -v usb_metric_menu >/dev/null 2>&1; then
        usb_metric_menu
        return 0
    fi
    log_error "USB metric module not found!"
    return 1
}

# $1 binary name  $2 package name
# Returns 0 when the binary is already on PATH or pkg_install just provided it.
# Other modules can call this before a feature that needs an optional tool.
ensure_binary() {
    local bin="$1"
    local pkg="$2"

    [ -n "$bin" ] || return 1
    command -v "$bin" >/dev/null 2>&1 && return 0
    [ -n "$pkg" ] || return 1
    if ! command -v pkg_install >/dev/null 2>&1; then
        log_error "Package installer is not available."
        return 1
    fi
    log_info "Installing [$pkg] ..."
    pkg_install "$pkg" || return 1
    command -v "$bin" >/dev/null 2>&1
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
        ensure_binary usb_modeswitch usb-modeswitch \
            || ensure_binary usb-modeswitch usb-modeswitch \
            || {
                log_warn "usb-modeswitch could not be installed."
                return 1
            }
        bin=$(_hw_modeswitch_bin) || bin=""
    fi
    if [ -z "$bin" ]; then
        log_warn "usb-modeswitch is installed but its binary was not found."
        return 1
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
            7) ui_run network_interfaces_state "Network Interfaces State"; continue ;;
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
