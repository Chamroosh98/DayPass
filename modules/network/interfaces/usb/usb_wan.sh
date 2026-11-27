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

    if [ -n "${DAYPASS_HOME:-}" ] && [ -f "$DAYPASS_HOME/modules/network/interfaces/usb/deps.sh" ]; then
        printf '%s\n' "$DAYPASS_HOME/modules/network/interfaces/usb"
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

# JSON from `ubus call network.interface.<iface> status`, or empty.
_usb_ubus_iface_json() {
    ubus call "network.interface.$1" status 2>/dev/null || true
}

# 0 when the ubus blob reports the interface up.
_usb_ubus_is_up() {
    printf '%s' "$1" | grep -q '"up"[[:space:]]*:[[:space:]]*true'
}

# First IPv4 default-route metric from a ubus interface status blob.
_usb_ubus_route_metric() {
    local json="$1"
    local m=""

    [ -n "$json" ] || return 1
    if command -v jsonfilter >/dev/null 2>&1; then
        m=$(printf '%s\n' "$json" | jsonfilter -e '@.route[0].metric' 2>/dev/null)
    elif command -v jq >/dev/null 2>&1; then
        m=$(printf '%s\n' "$json" | jq -r '.route[0].metric // empty' 2>/dev/null)
    else
        m=$(printf '%s\n' "$json" | sed -n 's/.*\"metric\": *\([0-9][0-9]*\).*/\1/p' | head -n 1)
    fi
    case "$m" in
        ''|null|*[!0-9]*) return 1 ;;
    esac
    printf '%s\n' "$m"
}

# Suggested explicit metric. Lower wins. Unset and 0 are not usable priorities.
usb_metric_plan() {
    case "$1" in
        wan)      printf '%s\n' "10" ;;
        wan6)     printf '%s\n' "15" ;;
        wan_usb)  printf '%s\n' "20" ;;
        *)        return 1 ;;
    esac
}

# Number to show and to offer in the prompt. Stored value when it is non-zero.
usb_metric_effective() {
    local iface="$1"
    local m plan

    m=$(uci -q get "network.$iface.metric")
    case "$m" in
        ''|0) ;;
        *[!0-9]*) ;;
        *)
            printf '%s\n' "$m"
            return 0
            ;;
    esac
    plan=$(usb_metric_plan "$iface") || plan="20"
    printf '%s\n' "$plan"
}

# Fixed label for the metrics table. "unset" marks a value not written to UCI yet.
usb_metric_column() {
    local iface="$1"
    local m

    m=$(uci -q get "network.$iface.metric")
    case "$m" in
        ''|0)
            printf '%s unset\n' "$(usb_metric_effective "$iface")"
            ;;
        *[!0-9]*)
            printf '%s unset\n' "$(usb_metric_effective "$iface")"
            ;;
        *)
            printf '%s\n' "$m"
            ;;
    esac
}

# Write wan=10, wan6=15, wan_usb=20 when the UCI metric is missing or 0.
# Existing non-zero metrics are left alone.
usb_apply_explicit_metrics() {
    local iface plan current changed=0 activate="" pending

    command -v uci >/dev/null 2>&1 || { log_error "uci is not available."; return 1; }

    pending=$(uci changes network) || return 1
    [ -z "$pending" ] || { log_error "Network already has pending edits."; return 1; }

    for iface in wan wan6 wan_usb; do
        [ "$(uci -q get "network.$iface")" = "interface" ] || continue
        plan=$(usb_metric_plan "$iface") || continue
        current=$(uci -q get "network.$iface.metric")
        case "$current" in
            ''|0) ;;
            *) continue ;;
        esac
        uci set "network.$iface.metric"="$plan" || return 1
        changed=1
        log_info "network.$iface.metric=$plan"
        if [ "$(uci -q get "network.$iface.disabled")" != "1" ]; then
            activate="$activate $iface"
        fi
    done

    if [ "$changed" -eq 0 ]; then
        log_info "Explicit metrics are already set."
        return 0
    fi
    uci commit network || return 1
    for iface in $activate; do
        ifup "$iface" || { log_error "Metrics saved; activation failed for $iface."; return 1; }
    done
    log_success "Suggested metrics written (wan 10, wan6 15, wan_usb 20)."
    return 0
}

# Numeric metric for display. A missing or zero UCI metric shows the planned value.
usb_iface_metric_text() {
    usb_metric_effective "$1"
}

# UP | DOWN | DISABLED | absent  — live netifd/ubus, not a static UCI label.
usb_wan_state() {
    local json

    usb_wan_exists || { echo "absent"; return 0; }
    if [ "$(uci -q get network.$USB_WAN_IFACE.disabled)" = "1" ]; then
        echo "DISABLED"
        return 0
    fi
    json=$(_usb_ubus_iface_json "$USB_WAN_IFACE")
    if _usb_ubus_is_up "$json"; then
        echo "UP"
        return 0
    fi
    echo "DOWN"
}

usb_wan_binding_active() {
    local json up device
    json=$(_usb_ubus_iface_json "$USB_WAN_IFACE")
    up=$(jsonfilter -s "$json" -e '@.up') || return 1
    device=$(jsonfilter -s "$json" -e '@.device') || return 1
    [ -n "$1" ] && [ "$up" = true ] && [ "$device" = "$1" ]
}

# Create or update USB tethering WAN interface.
# Usage: setup_usb_wan [device] [metric]
# Returns success only after netifd confirms the selected binding is up.
setup_usb_wan() {
    local usb_dev="${1:-}"
    local metric="${2:-$USB_WAN_DEFAULT_METRIC}"
    local zone stored_dev section pending

    if command -v ensure_usb_tether_deps >/dev/null 2>&1; then
        ensure_usb_tether_deps || return $?
    else
        log_error "USB dependency module is not loaded."
        return 1
    fi

    if [ -n "$usb_dev" ] && [ ! -e "/sys/class/net/$usb_dev" ]; then
        log_error "Selected USB device is unavailable."; return 1
    fi
    if [ -z "$usb_dev" ]; then
        if command -v usb_active_net_dev >/dev/null 2>&1; then
            usb_dev=$(usb_active_net_dev) || usb_dev=""
        elif command -v detect_usb_device >/dev/null 2>&1; then
            usb_dev=$(detect_usb_device) || usb_dev=""
        fi
    fi
    if [ -z "$usb_dev" ] || [ ! -e "/sys/class/net/$usb_dev" ]; then
        printf "  ${RED}❌ No active USB Network Hardware detected! Please connect your phone/dongle, turn on USB Tethering, and try again.${RESET}\n"
        return 1
    fi

    printf '  %s✔ Using USB device : %s%s\n' "$GREEN" "$usb_dev" "$RESET"

    command -v uci >/dev/null 2>&1 || { log_error "uci is not available."; return 1; }

    for section in network firewall; do
        pending=$(uci changes "$section") || return 1
        [ -z "$pending" ] || { log_error "$section has pending edits."; return 1; }
    done
    zone=$(_usb_wan_zone)
    [ -n "$zone" ] && [ "$(uci -q get "firewall.$zone")" = zone ] ||
        { log_error "WAN firewall zone unavailable."; return 1; }
    section=$(uci -q get "network.$USB_WAN_IFACE")
    if [ -n "$section" ]; then
        stored_dev=$(uci -q get "network.$USB_WAN_IFACE.device" ||
            uci -q get "network.$USB_WAN_IFACE.ifname")
        [ "$section" = interface ] && [ "$stored_dev" = "$usb_dev" ] &&
            [ "$(uci -q get "network.$USB_WAN_IFACE.proto")" = dhcp ] ||
            { log_error "Existing USB WAN binding is incompatible."; return 1; }
        [ "$(uci -q get "network.$USB_WAN_IFACE.disabled")" != 1 ] ||
            { log_warn "USB WAN is disabled."; return 1; }
    else
        uci set "network.$USB_WAN_IFACE=interface" &&
            uci set "network.$USB_WAN_IFACE.proto=dhcp" &&
            uci set "network.$USB_WAN_IFACE.device=$usb_dev" || return 1
    fi
    uci set "network.$USB_WAN_IFACE.metric=$metric" && uci commit network || return 1

    case " $(uci -q get "firewall.$zone.network") " in
        *" $USB_WAN_IFACE "*) ;;
        *) uci add_list "firewall.$zone.network=$USB_WAN_IFACE" &&
            uci commit firewall || return 1 ;;
    esac
    /etc/init.d/firewall reload || return 1
    ifup "$USB_WAN_IFACE" || return 1
    usb_wan_binding_active "$usb_dev" ||
        { log_warn "USB WAN saved; active binding to $usb_dev is unconfirmed."; return 1; }
    log_success "USB Tethering WAN interface [$USB_WAN_IFACE] is active and configured."
    return 0
}

# Usage: usb_wan_set_enabled 1|0
usb_wan_set_enabled() {
    usb_wan_exists || { log_warn "USB WAN [$USB_WAN_IFACE] is not configured."; return 1; }

    if [ "$1" = "1" ]; then
        uci -q delete network.$USB_WAN_IFACE.disabled
        uci commit network || return 1
        ifup "$USB_WAN_IFACE" >/dev/null 2>&1 || true
        ubus call "network.interface.$USB_WAN_IFACE" up >/dev/null 2>&1 || true
        log_success "USB WAN [$USB_WAN_IFACE] enabled ($(usb_wan_state))."
    else
        ifdown "$USB_WAN_IFACE" >/dev/null 2>&1 || true
        ubus call "network.interface.$USB_WAN_IFACE" down >/dev/null 2>&1 || true
        uci set network.$USB_WAN_IFACE.disabled='1'
        uci commit network || return 1
        log_success "USB WAN [$USB_WAN_IFACE] disabled ($(usb_wan_state))."
    fi
    return 0
}

# One-line hardware, interface, and failover summaries for the status card.
usb_status_hardware() {
    local line dev driver kind label

    line=$(usb_net_interfaces 2>/dev/null | head -n 1)
    if [ -n "$line" ]; then
        IFS='|' read -r dev driver kind <<EOF
$line
EOF
        if command -v usb_net_kind_label >/dev/null 2>&1; then
            label=$(usb_net_kind_label "$driver")
        else
            label="$driver"
        fi
        printf '%s✔ %s (%s)%s\n' "$GREEN" "$label" "$dev" "$RESET"
        return 0
    fi
    dev=$(usb_active_net_dev 2>/dev/null || true)
    if [ -n "$dev" ]; then
        printf '%s✔ USB-net (%s)%s\n' "$GREEN" "$dev" "$RESET"
        return 0
    fi
    if command -v usb_mtp_waiting >/dev/null 2>&1 && usb_mtp_waiting; then
        printf '%s❌ Not Connected (phone in MTP mode)%s\n' "$RED" "$RESET"
        return 0
    fi
    printf '%s❌ Not Connected%s\n' "$RED" "$RESET"
}

usb_status_interface() {
    local state

    if command -v usb_wan_exists >/dev/null 2>&1 && usb_wan_exists; then
        state=$(usb_wan_state)
        case "$state" in
            UP)       printf '%s🟢 UP%s\n' "$GREEN" "$RESET" ;;
            DISABLED) printf '%s⚠️ DISABLED%s\n' "$YELLOW" "$RESET" ;;
            *)        printf '%s🔴 DOWN%s\n' "$RED" "$RESET" ;;
        esac
        return 0
    fi
    printf '%s🔴 DOWN%s\n' "$RED" "$RESET"
}

usb_status_metrics() {
    local out="" iface metric icon frag

    if ! command -v usb_metric_ifaces >/dev/null 2>&1; then
        printf '%s\n' "none"
        return 0
    fi
    for iface in $(usb_metric_ifaces 2>/dev/null | head -n 6); do
        metric=$(usb_iface_metric_text "$iface")
        if command -v _net_iface_icon >/dev/null 2>&1; then
            icon=$(_net_iface_icon "$iface")
        else
            case "$iface" in
                wan6*)    icon="🌐" ;;
                wan_usb*) icon="📱" ;;
                wwan*)    icon="📶" ;;
                *)        icon="🔌" ;;
            esac
        fi
        case "$metric" in
            *" unset")
                metric="${metric% unset}"
                metric="${metric% }"
                frag="$icon $iface ($metric) unset"
                ;;
            *)
                frag="$icon $iface ($metric)"
                ;;
        esac
        if [ -n "$out" ]; then
            out="$out  │  $frag"
        else
            out="$frag"
        fi
    done
    [ -n "$out" ] || out="none"
    printf '%s\n' "$out"
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
    local list count i iface metric current state last

    while true; do
        if command -v render_persistent_header >/dev/null 2>&1; then
            render_persistent_header
        fi
        echo "  ⚖️ WAN Metrics & Failover Configuration"
        echo "  💡 Note: Lower metric values are preferred by the routing engine."
        echo
        list=$(usb_metric_ifaces)
        count=0
        for iface in $list; do
            count=$((count + 1))
        done
        if [ "$count" -eq 0 ]; then
            echo "  No WAN interfaces found."
        else
            i=1
            for iface in $list; do
                metric=$(usb_metric_column "$iface")
                if [ "$(uci -q get "network.$iface.disabled")" = "1" ]; then
                    state="disabled"
                else
                    state="enabled"
                fi
                if [ "$i" -eq "$count" ]; then
                    last=1
                else
                    last=0
                fi
                if command -v mwan_render_metric_row >/dev/null 2>&1; then
                    mwan_render_metric_row "$i" "$iface" "$metric" "$state" "$last"
                else
                    echo "  $i) $iface  metric $metric  $state"
                fi
                i=$((i + 1))
            done
        fi
        if command -v ui_nav_footer >/dev/null 2>&1; then
            echo "  a) Write suggested metrics (wan 10, wan6 15, wan_usb 20)"
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
            a|A)
                if command -v usb_apply_explicit_metrics >/dev/null 2>&1; then
                    usb_apply_explicit_metrics || true
                fi
                continue
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

        current=$(usb_metric_effective "$iface")
        if command -v ui_read >/dev/null 2>&1; then
            ui_read "Metric for $iface [${current}]"
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
            a|A)
                usb_apply_explicit_metrics || true
                command -v ui_pause >/dev/null 2>&1 && ui_pause
                continue
                ;;
            '') UI_CHOICE="$current" ;;
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
        0) log_error "Metric must be greater than 0. Suggested: wan 10, wan6 15, wan_usb 20."; return 1 ;;
    esac
    [ "$(uci -q get network.$iface)" = "interface" ] || { log_error "Interface [$iface] not found!"; return 1; }

    uci set network.$iface.metric="$metric" || return 1
    uci commit network || return 1
    if [ "$(uci -q get network.$iface.disabled)" != "1" ]; then
        ifup "$iface" >/dev/null 2>&1 || { log_error "Metric saved; interface activation failed."; return 1; }
    fi
    log_success "Configured metric of [$iface] set to $metric."
    return 0
}

# Compatibility entry for older callers; apply the same ownership guard.
remove_usb_wan() {
    if command -v usb_restore_settings >/dev/null 2>&1; then
        usb_restore_settings
    else
        log_error "USB restore unavailable; ownership cannot be verified."
        return 1
    fi
}
