#!/bin/sh
# ============================================================
# DayPass - mwan3 Metric Configuration
# ============================================================

_mwan_metric_icon() {
    case "$1" in
        wan6*)    printf '%s\n' "🌐" ;;
        wan_usb*) printf '%s\n' "📱" ;;
        wwan*)    printf '%s\n' "📶" ;;
        wan|wan_*) printf '%s\n' "🔌" ;;
        *)        printf '%s\n' "🌐" ;;
    esac
}

mwan_render_metric_row() {
    local i="$1" iface="$2" metric="$3" state="$4" last="$5"
    local icon name branch st metric_str

    icon=$(_mwan_metric_icon "$iface")
    name="$iface"
    while [ "${#name}" -lt 12 ]; do
        name="$name "
    done
    if [ "$last" = "1" ]; then
        branch="└──"
    else
        branch="├──"
    fi
    case "$state" in
        enabled) st="🟢 enabled" ;;
        *)       st="🔴 disabled" ;;
    esac
    metric_str=$(printf 'Metric: %s' "$metric")
    printf '  %s) %s %s %s %-22s | Status: %s\n' "$i" "$icon" "$name" "$branch" "$metric_str" "$st"
}

mwan_metric_menu() {
    local list count i iface metric current state last

    while true; do
        if command -v render_persistent_header >/dev/null 2>&1; then
            render_persistent_header
        fi
        ui_title "⚖️ WAN Metrics & Failover Configuration"
        echo "  💡 Note: Lower metric values are preferred by the routing engine."
        echo
        list=$(mwan_discover_ifaces)
        count=0
        for iface in $list; do
            count=$((count + 1))
        done
        if [ "$count" -eq 0 ]; then
            echo "  No WAN interfaces found."
        else
            i=1
            for iface in $list; do
                if command -v usb_metric_column >/dev/null 2>&1; then
                    metric=$(usb_metric_column "$iface")
                else
                    metric=$(uci -q get "network.$iface.metric")
                    [ -n "$metric" ] && [ "$metric" != "0" ] || metric="unset"
                fi
                if mwan_iface_enabled "$iface"; then
                    state="enabled"
                else
                    state="disabled"
                fi
                if [ "$i" -eq "$count" ]; then
                    last=1
                else
                    last=0
                fi
                mwan_render_metric_row "$i" "$iface" "$metric" "$state" "$last"
                i=$((i + 1))
            done
        fi
        if command -v ui_nav_footer >/dev/null 2>&1; then
            echo "  a) Write suggested metrics (wan 10, wan6 15, wan_usb 20)"
            ui_nav_footer
        fi
        if command -v ui_prompt >/dev/null 2>&1; then
            ui_prompt "$count"
        else
            printf '  Select option : '
            read -r UI_CHOICE </dev/tty || return 0
        fi

        case "$UI_CHOICE" in
            0|'') return 0 ;;
            q|Q)
                command -v daypass_quit >/dev/null 2>&1 && daypass_quit
                return 0
                ;;
            h|H)
                command -v ui_show_help >/dev/null 2>&1 && ui_show_help "network_multiwan"
                continue
                ;;
            a|A)
                if command -v usb_apply_explicit_metrics >/dev/null 2>&1; then
                    usb_apply_explicit_metrics || true
                fi
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
        for iface in $list; do
            [ "$i" = "$UI_CHOICE" ] && break
            i=$((i + 1))
        done

        if command -v usb_metric_effective >/dev/null 2>&1; then
            current=$(usb_metric_effective "$iface")
        else
            current=$(uci -q get "network.$iface.metric")
            [ -n "$current" ] && [ "$current" != "0" ] || current="20"
        fi
        
        printf '  Metric for %s [%s] : ' "$iface" "$current"
        read -r UI_CHOICE </dev/tty || return 0
        
        case "$UI_CHOICE" in
            0|'') continue ;;
            q|Q)
                command -v daypass_quit >/dev/null 2>&1 && daypass_quit
                return 0
                ;;
            '') UI_CHOICE="$current" ;;
        esac
        if command -v usb_wan_set_metric >/dev/null 2>&1; then
            usb_wan_set_metric "$iface" "$UI_CHOICE" || true
        else
            case "$UI_CHOICE" in
                ''|*[!0-9]*) log_error "Invalid metric [$UI_CHOICE]!"; continue ;;
            esac
            uci set "network.$iface.metric"="$UI_CHOICE"
            uci commit network || { log_error "Could not save the metric."; continue; }
            if [ "$(uci -q get "network.$iface.disabled")" != "1" ]; then
                ifup "$iface" >/dev/null 2>&1 || true
            fi
            log_success "Metric of [$iface] set to $UI_CHOICE."
        fi
        command -v ui_pause >/dev/null 2>&1 && ui_pause
    done
}