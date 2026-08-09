#!/bin/sh
# ============================================================
# DayPass - Multi-WAN Load Balancer (mwan3 Orchestrator)
# ============================================================

configure_mwan3_engine() {
    log_info "Configuring mwan3 engine..."

    uci set mwan3.globals=globals
    uci set mwan3.globals.mmx_mask='0x3f00'

    # Interfaces
    for iface in wan wan_usb wwan; do
        uci set mwan3.$iface=interface
        uci set mwan3.$iface.enabled='1'
        uci set mwan3.$iface.family='ipv4'
        uci -q delete mwan3.$iface.track_ip
        uci add_list mwan3.$iface.track_ip='1.1.1.1'
        uci add_list mwan3.$iface.track_ip='8.8.8.8'
        uci set mwan3.$iface.reliability='1'
        uci set mwan3.$iface.timeout='2'
        uci set mwan3.$iface.interval='5'
    done

    # Members with different metrics & weights
    uci set mwan3.wan_m=member
    uci set mwan3.wan_m.interface='wan'
    uci set mwan3.wan_m.metric='1'
    uci set mwan3.wan_m.weight='5'

    uci set mwan3.usb_m=member
    uci set mwan3.usb_m.interface='wan_usb'
    uci set mwan3.usb_m.metric='2'
    uci set mwan3.usb_m.weight='4'

    uci set mwan3.wwan_m=member
    uci set mwan3.wwan_m.interface='wwan'
    uci set mwan3.wwan_m.metric='3'
    uci set mwan3.wwan_m.weight='3'

    # Policies
    uci set mwan3.balanced=policy
    uci -q delete mwan3.balanced.use_member
    uci add_list mwan3.balanced.use_member='wan_m'
    uci add_list mwan3.balanced.use_member='usb_m'
    uci add_list mwan3.balanced.use_member='wwan_m'

    uci set mwan3.failover=policy
    uci -q delete mwan3.failover.use_member
    uci add_list mwan3.failover.use_member='wan_m'
    uci add_list mwan3.failover.use_member='usb_m'
    uci add_list mwan3.failover.use_member='wwan_m'

    # Default rule
    uci set mwan3.default_rule_v4=rule
    uci set mwan3.default_rule_v4.dest_ip='0.0.0.0/0'
    uci set mwan3.default_rule_v4.family='ipv4'
    uci set mwan3.default_rule_v4.use_policy='balanced'

    uci commit mwan3
    /etc/init.d/mwan3 enable >/dev/null 2>&1
    /etc/init.d/mwan3 restart >/dev/null 2>&1

    log_success "mwan3 engine configured (Balanced + Failover)."
}

load_balancer_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear
        echo "  ⚖️  Multi-WAN Load Balancer"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  1) Install Dependencies"
        echo "  2) Setup USB Tethering WAN"
        echo "  3) Setup Wi-Fi Hotspot WAN"
        echo "  4) Apply mwan3 Load Balancing"
        echo "  5) Show mwan3 Status"
        echo "  0) Back"
        echo "  ───────────────────────────────────────────────────────────"
        printf "  ⁉️ Select : "
        read -r c </dev/tty

        case "$c" in
            1) install_mwan3_deps 2>/dev/null || log_warn "Dependency installer not found." ;;
            2) setup_usb_wan 2>/dev/null || log_warn "USB module not loaded." ;;
            3) setup_wifi_wan 2>/dev/null || log_warn "Wi-Fi WAN module not loaded." ;;
            4) configure_mwan3_engine ;;
            5) command -v mwan3 >/dev/null && mwan3 status || log_error "mwan3 not installed." ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        echo
        printf "\n  ${GRAY}Press ENTER ...${RESET}"
        read -r _ </dev/tty
    done
}