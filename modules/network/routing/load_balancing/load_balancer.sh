#!/bin/sh
# ============================================================
# DayPass - Dynamic Multi-WAN Load Balancer (mwan3)
# Discovers every WAN (firewall wan zone, plus wan / wan_* /
# wwan), then builds an N-way balanced policy. Echo only on
# menu lines so emoji are not clipped by column widths.
# ============================================================

# $1 interface name. 0 when it is a WAN-style name (not wan6).
mwan_iface_is_wan() {
    case "$1" in
        wan6) return 1 ;;
        wan|wan_*|wwan|wwan_*) return 0 ;;
    esac
    return 1
}

# Record $1 if it is a real IPv4-capable network interface.
# Uses MWAN_SEEN. Prints the name once.
_mwan_note_iface() {
    _mi="$1"
    [ -n "$_mi" ] || return 1
    case " $MWAN_SEEN " in
        *" $_mi "*) return 1 ;;
    esac
    [ "$(uci -q get "network.$_mi")" = "interface" ] || return 1
    case "$(uci -q get "network.$_mi.proto")" in
        dhcpv6) return 1 ;;
    esac
    case "$_mi" in
        wan6) return 1 ;;
    esac
    MWAN_SEEN="$MWAN_SEEN $_mi"
    printf '%s\n' "$_mi"
    return 0
}

# Every WAN interface, one name per line.
# Firewall zone "wan", then any wan / wan_* / wwan interface
# that is not already listed (wan_usb, wan_usb2, wan_lan2, wwan).
mwan_discover_ifaces() {
    local i name nets net iface

    MWAN_SEEN=""
    i=0
    while uci -q get "firewall.@zone[$i]" >/dev/null 2>&1; do
        name=$(uci -q get "firewall.@zone[$i].name")
        if [ "$name" = "wan" ]; then
            nets=$(uci -q get "firewall.@zone[$i].network")
            for net in $nets; do
                _mwan_note_iface "$net" || true
            done
        fi
        i=$((i + 1))
        [ "$i" -gt 64 ] && break
    done

    for iface in $(uci show network 2>/dev/null | sed -n 's/^network\.\([A-Za-z0-9_]*\)=interface$/\1/p'); do
        mwan_iface_is_wan "$iface" || continue
        _mwan_note_iface "$iface" || true
    done
}

# $1 interface. 0 when it is not administratively disabled.
mwan_iface_enabled() {
    [ "$(uci -q get "network.$1.disabled")" != "1" ]
}

# Enabled WAN interfaces only.
mwan_active_ifaces() {
    local iface

    for iface in $(mwan_discover_ifaces); do
        mwan_iface_enabled "$iface" || continue
        printf '%s\n' "$iface"
    done
}

# Install mwan3 with opkg (OpenWrt 24) or apk (OpenWrt 25).
install_mwan3_deps() {
    if command -v pkg_installed >/dev/null 2>&1 && pkg_installed mwan3; then
        log_success "mwan3 is already installed."
        return 0
    fi
    if command -v mwan3 >/dev/null 2>&1 || [ -x /etc/init.d/mwan3 ]; then
        log_success "mwan3 is already installed."
        return 0
    fi

    log_info "Installing mwan3 ..."
    if command -v pkg_update >/dev/null 2>&1; then
        pkg_update >/dev/null 2>&1 || true
    elif command -v opkg >/dev/null 2>&1; then
        opkg update >/dev/null 2>&1 || true
    elif command -v apk >/dev/null 2>&1; then
        apk update >/dev/null 2>&1 || true
    fi

    if command -v pkg_install >/dev/null 2>&1 && pkg_install mwan3; then
        log_success "mwan3 installed."
        return 0
    fi
    if command -v opkg >/dev/null 2>&1 && opkg install mwan3 >/dev/null 2>&1; then
        log_success "mwan3 installed."
        return 0
    fi
    if command -v apk >/dev/null 2>&1 && apk add --allow-untrusted mwan3 >/dev/null 2>&1; then
        log_success "mwan3 installed."
        return 0
    fi

    log_error "Could not install mwan3."
    return 1
}

# Drop previous interface and member sections so a smaller WAN
# set does not leave stale members in the policies.
_mwan_clear_links() {
    local sec kind

    uci show mwan3 2>/dev/null | sed -n 's/^mwan3\.\([^=]*\)=\(interface\|member\)$/\1 \2/p' | \
    while read -r sec kind; do
        [ -n "$sec" ] || continue
        uci -q delete "mwan3.$sec"
    done
}

# Build mwan3 for every enabled WAN. Balanced uses weight 1 on
# every member. Failover orders members by network metric.
configure_mwan3_engine() {
    local list count iface metric rank member

    log_info "Scanning WAN interfaces ..."
    list=$(mwan_active_ifaces)
    count=0
    for iface in $list; do
        count=$((count + 1))
        metric=$(uci -q get "network.$iface.metric")
        [ -n "$metric" ] || metric="default"
        echo "  🌐 $iface  metric $metric"
    done

    if [ "$count" -eq 0 ]; then
        log_warn "No active WAN interfaces found. Create wan, wan_usb, wwan, or wan_lan2 first."
        return 1
    fi

    log_info "Configuring mwan3 for $count WAN interface(s) ..."

    uci set mwan3.globals=globals
    uci set mwan3.globals.mmx_mask='0x3f00'
    _mwan_clear_links

    for iface in $list; do
        uci set "mwan3.$iface"=interface
        uci set "mwan3.$iface.enabled"='1'
        uci set "mwan3.$iface.family"='ipv4'
        uci -q delete "mwan3.$iface.track_ip"
        uci add_list "mwan3.$iface.track_ip"='1.1.1.1'
        uci add_list "mwan3.$iface.track_ip"='8.8.8.8'
        uci set "mwan3.$iface.reliability"='1'
        uci set "mwan3.$iface.timeout"='2'
        uci set "mwan3.$iface.interval"='5'

        member="${iface}_m"
        uci set "mwan3.$member"=member
        uci set "mwan3.$member.interface"="$iface"
        uci set "mwan3.$member.metric"='1'
        uci set "mwan3.$member.weight"='1'
    done

    uci set mwan3.balanced=policy
    uci -q delete mwan3.balanced.use_member
    for iface in $list; do
        uci add_list mwan3.balanced.use_member="${iface}_m"
    done

    uci set mwan3.failover=policy
    uci -q delete mwan3.failover.use_member
    rank=1
    for iface in $(
        for iface in $list; do
            metric=$(uci -q get "network.$iface.metric")
            case "$metric" in
                ''|*[!0-9]*) metric=1000 ;;
            esac
            printf '%s %s\n' "$metric" "$iface"
        done | sort -n | awk '{ print $2 }'
    ); do
        member="${iface}_fo"
        uci set "mwan3.$member"=member
        uci set "mwan3.$member.interface"="$iface"
        uci set "mwan3.$member.metric"="$rank"
        uci set "mwan3.$member.weight"='1'
        uci add_list mwan3.failover.use_member="$member"
        rank=$((rank + 1))
    done

    uci set mwan3.default_rule_v4=rule
    uci set mwan3.default_rule_v4.dest_ip='0.0.0.0/0'
    uci set mwan3.default_rule_v4.family='ipv4'
    uci set mwan3.default_rule_v4.use_policy='balanced'

    uci commit mwan3 || { log_error "Could not save mwan3."; return 1; }

    if [ -x /etc/init.d/mwan3 ]; then
        /etc/init.d/mwan3 enable >/dev/null 2>&1 || true
        /etc/init.d/mwan3 restart >/dev/null 2>&1 || log_warn "mwan3 did not restart. Install it from option 1 if it is missing."
    else
        log_warn "mwan3 is not installed yet. The config is saved. Use option 1, then apply again."
    fi

    log_success "mwan3 balanced policy now shares traffic across $count WAN interface(s)."
    return 0
}

# View and set network.<iface>.metric for every discovered WAN.
mwan_metric_menu() {
    local list count i iface metric current

    while true; do
        if command -v render_persistent_header >/dev/null 2>&1; then
            render_persistent_header
        fi
        echo "  🧭 WAN Metrics"
        echo "  A lower metric is preferred."
        echo
        list=$(mwan_discover_ifaces)
        count=0
        i=1
        if [ -n "$list" ]; then
            for iface in $list; do
                metric=$(uci -q get "network.$iface.metric")
                [ -n "$metric" ] || metric="default"
                if mwan_iface_enabled "$iface"; then
                    echo "  $i) $iface  metric $metric  enabled"
                else
                    echo "  $i) $iface  metric $metric  disabled"
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

        current=$(uci -q get "network.$iface.metric")
        if command -v ui_read >/dev/null 2>&1; then
            ui_read "Metric for $iface [${current:-20}]"
        else
            printf '  Metric for %s : ' "$iface"
            read -r UI_CHOICE </dev/tty || return 0
        fi
        case "$UI_CHOICE" in
            0|'') continue ;;
            q|Q)
                command -v daypass_quit >/dev/null 2>&1 && daypass_quit
                return 0
                ;;
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

load_balancer_menu() {
    local HELP_MODULE_ID="network_multiwan"
    local iface metric

    while true; do
        render_persistent_header
        echo "  ⚖️ Multi-WAN Load Balancer"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  🌐 Detected WAN interfaces"
        if mwan_discover_ifaces >/dev/null 2>&1; then
            metric=""
            for iface in $(mwan_discover_ifaces); do
                metric=$(uci -q get "network.$iface.metric")
                [ -n "$metric" ] || metric="default"
                echo "     $iface  metric $metric"
                metric="x"
            done
            [ -n "$metric" ] || echo "     none"
        else
            echo "     none"
        fi
        echo
        echo "  📌 1) Install Dependencies"
        echo "  📲 2) Setup USB Tethering WAN"
        echo "  📶 3) Setup Wi-Fi Hotspot WAN"
        echo "  ⚖️ 4) Apply Dynamic Load Balancing"
        echo "  👀 5) Show mwan3 Status"
        echo "  🧭 6) WAN Metrics"
        ui_nav_footer
        ui_prompt 6
        c="$UI_CHOICE"

        case "$c" in
            1) install_mwan3_deps || true ;;
            2) setup_usb_wan 2>/dev/null || log_warn "USB module not loaded." ;;
            3) setup_wifi_wan 2>/dev/null || log_warn "Wi-Fi WAN module not loaded." ;;
            4) configure_mwan3_engine || true ;;
            5) command -v mwan3 >/dev/null 2>&1 && mwan3 status || log_error "mwan3 not installed!" ;;
            6) mwan_metric_menu; continue ;;
            q|Q) daypass_quit ;;
            h|H)
                if command -v show_help >/dev/null 2>&1; then
                    show_help "$HELP_MODULE_ID"
                else
                    log_warn "Help module not loaded!"
                    sleep 1
                fi
                continue
                ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        echo
        echo "  ${GRAY:-}Press [Enter] to continue ...${RESET:-}"
        read -r _ </dev/tty || daypass_quit
    done
}
