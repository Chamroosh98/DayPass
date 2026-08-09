#!/bin/sh
# ============================================================
# DayPass - Guest Network Module
# Creates isolated Guest network with firewall rules & DHCP
# ============================================================

# ------------------------------------------------------------
# Create Guest Network + Firewall + DHCP
# ------------------------------------------------------------
setup_guest_network() {
    log_info "Configuring isolated Guest Network..."

    # 1. Network Interface
    uci set network.guest=interface
    uci set network.guest.proto='static'
    uci set network.guest.ipaddr='192.168.200.1'
    uci set network.guest.netmask='255.255.255.0'
    uci set network.guest.force_link='0'

    # 2. DHCP Server for Guest
    uci set dhcp.guest=dhcp
    uci set dhcp.guest.interface='guest'
    uci set dhcp.guest.start='100'
    uci set dhcp.guest.limit='150'
    uci set dhcp.guest.leasetime='12h'
    uci set dhcp.guest.force='1'

    # 3. Firewall Zone (Isolated)
    uci set firewall.guest=zone
    uci set firewall.guest.name='guest'
    uci set firewall.guest.network='guest'
    uci set firewall.guest.input='REJECT'
    uci set firewall.guest.output='ACCEPT'
    uci set firewall.guest.forward='REJECT'
    uci set firewall.guest.masq='0'

    # 4. Allow Guest -> WAN (Internet only)
    uci set firewall.guest_to_wan=forwarding
    uci set firewall.guest_to_wan.src='guest'
    uci set firewall.guest_to_wan.dest='wan'

    # 5. Essential Rules: DNS + DHCP
    uci set firewall.guest_dns=rule
    uci set firewall.guest_dns.name='Allow-Guest-DNS'
    uci set firewall.guest_dns.src='guest'
    uci set firewall.guest_dns.dest_port='53'
    uci set firewall.guest_dns.proto='tcp udp'
    uci set firewall.guest_dns.target='ACCEPT'

    uci set firewall.guest_dhcp=rule
    uci set firewall.guest_dhcp.name='Allow-Guest-DHCP'
    uci set firewall.guest_dhcp.src='guest'
    uci set firewall.guest_dhcp.dest_port='67-68'
    uci set firewall.guest_dhcp.proto='udp'
    uci set firewall.guest_dhcp.target='ACCEPT'

    # 6. Block Guest from accessing main LAN
    uci set firewall.guest_block_lan=rule
    uci set firewall.guest_block_lan.name='Block-Guest-to-LAN'
    uci set firewall.guest_block_lan.src='guest'
    uci set firewall.guest_block_lan.dest='lan'
    uci set firewall.guest_block_lan.target='REJECT'

    uci commit network
    uci commit dhcp
    uci commit firewall

    /etc/init.d/network reload >/dev/null 2>&1
    /etc/init.d/firewall reload >/dev/null 2>&1
    /etc/init.d/dnsmasq restart >/dev/null 2>&1

    log_success "Guest Network ready → 192.168.200.0/24 (Isolated)"
}

# ------------------------------------------------------------
# Remove Guest Network completely
# ------------------------------------------------------------
remove_guest_network() {
    log_warn "Removing Guest Network configuration..."

    uci -q delete network.guest
    uci -q delete dhcp.guest
    uci -q delete firewall.guest
    uci -q delete firewall.guest_to_wan
    uci -q delete firewall.guest_dns
    uci -q delete firewall.guest_dhcp
    uci -q delete firewall.guest_block_lan

    # Remove related wireless interfaces
    for sec in $(uci show wireless | grep "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
        network=$(uci -q get wireless.$sec.network)
        if [ "$network" = "guest" ]; then
            uci -q delete wireless.$sec
        fi
    done

    uci commit network
    uci commit dhcp
    uci commit firewall
    uci commit wireless

    wifi reload >/dev/null 2>&1
    /etc/init.d/firewall reload >/dev/null 2>&1

    log_success "Guest Network removed."
}

# ------------------------------------------------------------
# Create Guest WiFi (AP on Guest network)
# ------------------------------------------------------------
setup_guest_wifi() {
    render_persistent_header 2>/dev/null || clear

    echo "  👥 Guest WiFi Configuration"
    echo "  ───────────────────────────────────────────────────────────"

    # Make sure guest network exists
    if ! uci -q get network.guest >/dev/null; then
        setup_guest_network
    fi

    local RADIOS
    RADIOS=$(uci show wireless 2>/dev/null | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1)

    if [ -z "$RADIOS" ]; then
        log_error "No wireless radio found!"
        return 1
    fi

    printf "  🛜 Guest SSID [DayPass-Guest] : "
    read -r guest_ssid </dev/tty
    [ -z "$guest_ssid" ] && guest_ssid="DayPass-Guest"

    local guest_pass=""
    while true; do
        printf "  🔒 Guest Password (min 8 chars) : "
        read -r guest_pass </dev/tty
        [ ${#guest_pass} -ge 8 ] && break
        log_error "Password must be at least 8 characters!"
    done

    for radio in $RADIOS; do
        local band
        band=$(uci -q get wireless.$radio.band || echo "")
        local iface="guest_${radio}"

        uci set wireless.$iface=wifi-iface
        uci set wireless.$iface.device="$radio"
        uci set wireless.$iface.mode='ap'
        uci set wireless.$iface.network='guest'
        uci set wireless.$iface.ssid="$guest_ssid"
        uci set wireless.$iface.encryption='psk2'
        uci set wireless.$iface.key="$guest_pass"
        uci set wireless.$iface.isolate='1'
        uci set wireless.$iface.disabled='0'

        log_success "Guest WiFi created on [$radio] → [$guest_ssid]"
    done

    uci commit wireless
    wifi reload >/dev/null 2>&1

    log_success "Guest WiFi is now active!"
}

# ------------------------------------------------------------
# Menu
# ------------------------------------------------------------
guest_network_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear

        echo "  👥 Guest Network Manager"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  1) Setup Guest Network (Interface + Firewall)"
        echo "  2) Setup Guest WiFi"
        echo "  3) Remove Guest Network completely"
        echo "  0) Back"
        echo "  ───────────────────────────────────────────────────────────"
        printf "  ⁉️ Select : "
        read -r choice </dev/tty

        case "$choice" in
            1) setup_guest_network ;;
            2) setup_guest_wifi ;;
            3) remove_guest_network ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press ENTER ...${RESET}"
        read -r _ </dev/tty
    done
}