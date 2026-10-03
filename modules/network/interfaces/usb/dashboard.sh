#!/bin/sh
# ============================================================
# DayPass - USB tethering dashboard
# Two columns: status on the left, actions on the right.
# Safe to source. Never calls exit.
# ============================================================

_usb_dash_repeat() {
    _ud_n="$1"
    _ud_ch="$2"
    while [ "$_ud_n" -gt 0 ]; do
        printf '%s' "$_ud_ch"
        _ud_n=$((_ud_n - 1))
    done
}

_usb_dash_left() {
    local line shown=0

    printf '%s\n' "System & Network"
    printf '%s\n' "USB hardware"
    line=$(usb_device_list 2>/dev/null | head -n 2)
    if [ -z "$line" ]; then
        printf '%s\n' "  none"
    else
        printf '%s\n' "$line" | while IFS= read -r line; do
            [ -n "$line" ] || continue
            printf '  %s\n' "$line"
        done
    fi

    if command -v usb_mtp_waiting >/dev/null 2>&1 && usb_mtp_waiting; then
        printf '%s\n' "MTP mode: enable tethering"
    fi

    printf '%s\n' "Interfaces"
    line=$(usb_net_interfaces 2>/dev/null | head -n 3)
    if [ -z "$line" ]; then
        printf '%s\n' "  none"
    else
        printf '%s\n' "$line" | while IFS='|' read -r dev driver kind; do
            [ -n "$dev" ] || continue
            printf '  %s %s %s\n' "$dev" "$driver" "$kind"
        done
    fi

    printf '%s\n' "WAN metrics"
    shown=0
    if command -v usb_metric_ifaces >/dev/null 2>&1; then
        for line in $(usb_metric_ifaces); do
            _ud_m=$(uci -q get "network.$line.metric")
            [ -n "$_ud_m" ] || _ud_m="-"
            printf '  %-10s %s\n' "$line" "$_ud_m"
            shown=$((shown + 1))
            [ "$shown" -ge 4 ] && break
        done
    fi
    [ "$shown" -gt 0 ] || printf '%s\n' "  none"
}

_usb_dash_right() {
    local state="absent"

    if command -v usb_wan_state >/dev/null 2>&1; then
        state=$(usb_wan_state)
    fi
    printf '%s\n' "Operations"
    printf '%s\n' "1) Setup USB Tethering"
    printf '%s\n' "2) Toggle ($state)"
    printf '%s\n' "3) Failover & Metrics"
    printf '%s\n' "4) Install Drivers"
    printf '%s\n' "5) Restore / Reset USB"
    printf '%s\n' "6) Modem Mode Switch"
    printf '%s\n' "7) Refresh"
    printf '%s\n' "8) System Resources"
    printf '%s\n' ""
    printf '%s\n' "@0) Back / Skip"
    printf '%s\n' "@q) Quit DayPass"
    printf '%s\n' "@h) Help"
}

# Prints the dashboard. Returns 0.
usb_render_dashboard() {
    local muted leftf rightf nL nR n i left right

    muted="${COLOR_MUTED:-${GRAY:-\033[90m}}"
    leftf="/tmp/daypass_usb_l.$$"
    rightf="/tmp/daypass_usb_r.$$"
    _usb_dash_left > "$leftf"
    _usb_dash_right > "$rightf"

    nL=$(wc -l < "$leftf" | tr -d ' ')
    nR=$(wc -l < "$rightf" | tr -d ' ')
    n="$nL"
    [ "$nR" -gt "$n" ] && n="$nR"

    printf '  %s┌' "$muted"
    _usb_dash_repeat 36 "─"
    printf '┬'
    _usb_dash_repeat 38 "─"
    printf '┐%s\n' "$RESET"

    i=1
    while [ "$i" -le "$n" ]; do
        left=$(sed -n "${i}p" "$leftf")
        right=$(sed -n "${i}p" "$rightf")
        case "$right" in
            @*)
                printf '  %s│%s %-34.34s %s│%s %-36.36s %s│%s\n' \
                    "$muted" "$RESET" "$left" "$muted" "$muted" "${right#@}" "$muted" "$RESET"
                ;;
            *)
                printf '  %s│%s %-34.34s %s│%s %-36.36s %s│%s\n' \
                    "$muted" "$RESET" "$left" "$muted" "$RESET" "$right" "$muted" "$RESET"
                ;;
        esac
        i=$((i + 1))
    done

    printf '  %s└' "$muted"
    _usb_dash_repeat 36 "─"
    printf '┴'
    _usb_dash_repeat 38 "─"
    printf '┘%s\n' "$RESET"

    rm -f "$leftf" "$rightf"
    return 0
}
