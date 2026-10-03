#!/bin/sh
# ============================================================
# DayPass - USB WAN network handler
# Loads deps.sh and detect.sh, then binds the detected USB
# device as a WAN interface in /etc/config/network.
# Safe to source. Never calls exit.
# ============================================================

USB_WAN_IFACE="wan_usb"
USB_WAN_DEFAULT_METRIC="20"

# Directory of this file when it is sourced on its own.
# The generated installer already defined the functions, so the
# lookup is skipped in that case.
_usb_module_dir() {
    local dir

    if [ -n "${DAYPASS_USB_DIR:-}" ] && [ -f "$DAYPASS_USB_DIR/deps.sh" ]; then
        printf '%s\n' "$DAYPASS_USB_DIR"
        return 0
    fi

    dir=$(CDPATH= cd -- "$(dirname "$0")" >/dev/null 2>&1 && pwd)
    if [ -n "$dir" ] && [ -f "$dir/deps.sh" ]; then
        printf '%s\n' "$dir"
        return 0
    fi

    for dir in modules/network/interfaces/usb "$(pwd)/modules/network/interfaces/usb"; do
        if [ -f "$dir/deps.sh" ]; then
            printf '%s\n' "$dir"
            return 0
        fi
    done
    return 1
}

# $1 function that proves the module is loaded, $2 filename
_usb_require() {
    local fn="$1"
    local file="$2"
    local dir

    command -v "$fn" >/dev/null 2>&1 && return 0
    dir=$(_usb_module_dir) || return 1
    [ -f "$dir/$file" ] || return 1
    # shellcheck source=/dev/null
    . "$dir/$file"
}

_usb_require ensure_usb_tether_deps deps.sh || true
_usb_require detect_usb_device detect.sh || true

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

# Create or update USB tethering WAN interface.
# Usage: setup_usb_wan [device] [metric]
# Returns 0 when the UCI interface is written, 1 when UCI is unavailable.
setup_usb_wan() {
    local usb_dev="${1:-}"
    local metric="${2:-$USB_WAN_DEFAULT_METRIC}"
    local zone

    log_info "Setting up USB Tethering WAN interface ..."

    if command -v ensure_usb_tether_deps >/dev/null 2>&1; then
        ensure_usb_tether_deps || log_warn "Some USB tethering packages could not be installed."
    else
        log_warn "USB dependency module is not loaded."
    fi

    if [ -z "$usb_dev" ]; then
        if command -v detect_usb_device >/dev/null 2>&1; then
            usb_dev=$(detect_usb_device) || usb_dev=""
        fi
    fi

    if [ -z "$usb_dev" ]; then
        log_warn "No USB tethering device detected."
        log_warn "Connect your phone and enable USB Tethering first."
        usb_dev="usb0"
    else
        log_success "Using USB device : $usb_dev"
    fi

    command -v uci >/dev/null 2>&1 || { log_error "uci is not available."; return 1; }

    uci set network.$USB_WAN_IFACE=interface
    uci set network.$USB_WAN_IFACE.proto='dhcp'
    uci set network.$USB_WAN_IFACE.device="$usb_dev"
    uci set network.$USB_WAN_IFACE.metric="$metric"
    uci -q delete network.$USB_WAN_IFACE.disabled
    uci commit network || return 1

    zone=$(_usb_wan_zone)
    if [ -n "$zone" ]; then
        uci -q del_list firewall.$zone.network="$USB_WAN_IFACE"
        uci add_list firewall.$zone.network="$USB_WAN_IFACE"
        uci commit firewall
        /etc/init.d/firewall reload >/dev/null 2>&1 || true
    else
        log_warn "Firewall zone [wan] not found; add [$USB_WAN_IFACE] to your WAN zone manually."
    fi

    ifup $USB_WAN_IFACE >/dev/null 2>&1 || true
    log_success "USB WAN interface [$USB_WAN_IFACE] is ready (device $usb_dev, metric $metric)!"
    return 0
}

# Usage: usb_wan_set_enabled 1|0
usb_wan_set_enabled() {
    usb_wan_exists || { log_warn "USB WAN [$USB_WAN_IFACE] is not configured."; return 1; }

    if [ "$1" = "1" ]; then
        uci -q delete network.$USB_WAN_IFACE.disabled
        uci commit network || return 1
        ifup $USB_WAN_IFACE >/dev/null 2>&1 || true
        log_success "USB WAN [$USB_WAN_IFACE] enabled."
    else
        ifdown $USB_WAN_IFACE >/dev/null 2>&1 || true
        uci set network.$USB_WAN_IFACE.disabled='1'
        uci commit network || return 1
        log_success "USB WAN [$USB_WAN_IFACE] disabled."
    fi
    return 0
}

# WAN-like UCI interfaces, one name per line.
usb_metric_ifaces() {
    local iface

    uci show network 2>/dev/null | sed -n 's/^network\.\([A-Za-z0-9_]*\)=interface$/\1/p' | while IFS= read -r iface; do
        case "$iface" in
            wan*|wwan*) printf '%s\n' "$iface" ;;
        esac
    done
}

# Interactive metric editor. Lower metric is preferred. Never calls exit.
usb_metric_menu() {
    local list count i iface metric current

    while true; do
        if command -v render_persistent_header >/dev/null 2>&1; then
            render_persistent_header
        fi
        echo "  WAN metrics"
        echo "  Lower metric is preferred."
        echo
        list=$(usb_metric_ifaces)
        count=0
        if [ -n "$list" ]; then
            i=1
            for iface in $list; do
                metric=$(uci -q get "network.$iface.metric")
                [ -n "$metric" ] || metric="default"
                if [ "$(uci -q get "network.$iface.disabled")" = "1" ]; then
                    printf "  %s) %-12s metric %-8s disabled\n" "$i" "$iface" "$metric"
                else
                    printf "  %s) %-12s metric %-8s enabled\n" "$i" "$iface" "$metric"
                fi
                i=$((i + 1))
                count=$((count + 1))
            done
        else
            echo "  No WAN interfaces found."
        fi
        if command -v ui_nav_footer >/dev/null 2>&1; then
            ui_nav_footer
        fi
        if command -v ui_read >/dev/null 2>&1; then
            ui_read "Select option"
        else
            printf "  Select option : "
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
        [ "$UI_CHOICE" -ge 1 ] && [ "$UI_CHOICE" -le "$count" ] || { log_warn "Invalid option!"; continue; }

        i=1
        iface=""
        for iface in $list; do
            [ "$i" = "$UI_CHOICE" ] && break
            i=$((i + 1))
        done

        current=$(uci -q get "network.$iface.metric")
        if command -v ui_read >/dev/null 2>&1; then
            ui_read "Metric for $iface [${current:-20}]"
        else
            printf "  Metric for %s : " "$iface"
            read -r UI_CHOICE </dev/tty || return 0
        fi
        case "$UI_CHOICE" in
            0|'') continue ;;
            q|Q)
                command -v daypass_quit >/dev/null 2>&1 && daypass_quit
                return 0
                ;;
            '') UI_CHOICE="${current:-20}" ;;
        esac
        usb_wan_set_metric "$iface" "$UI_CHOICE" || true
        command -v ui_pause >/dev/null 2>&1 && ui_pause
    done
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
    uci commit network || return 1
    if [ "$(uci -q get network.$iface.disabled)" != "1" ]; then
        ifup "$iface" >/dev/null 2>&1 || true
    fi
    log_success "Metric of [$iface] set to $metric."
    return 0
}

remove_usb_wan() {
    local zone

    usb_wan_exists || { log_warn "USB WAN [$USB_WAN_IFACE] is not configured."; return 0; }

    ifdown $USB_WAN_IFACE >/dev/null 2>&1 || true
    uci -q delete network.$USB_WAN_IFACE
    uci commit network || return 1

    zone=$(_usb_wan_zone)
    if [ -n "$zone" ]; then
        uci -q del_list firewall.$zone.network="$USB_WAN_IFACE"
        uci commit firewall || true
        /etc/init.d/firewall reload >/dev/null 2>&1 || true
    fi
    log_success "USB WAN [$USB_WAN_IFACE] removed."
    return 0
}
