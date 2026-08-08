#!/bin/sh

setup_guest_firewall_and_network()
{
    log_info "Configuring Isolated Guest Network Zone..."

    # 1. Create Guest Network Interface
    uci set network.guest=interface
    uci set network.guest.proto='static'
    uci set network.guest.ipaddr='192.168.200.1'
    uci set network.guest.netmask='255.255.255.0'

    # 2. Setup DHCP for Guest Zone
    uci set dhcp.guest=dhcp
    uci set dhcp.guest.interface='guest'
    uci set dhcp.guest.start='100'
    uci set dhcp.guest.limit='150'
    uci set dhcp.guest.leasetime='12h'

    # 3. Setup Firewall Zone (Isolate from LAN, allow WAN/Internet & DNS/DHCP)
    uci set firewall.guest=zone
    uci set firewall.guest.name='guest'
    uci set firewall.guest.network='guest'
    uci set firewall.guest.input='REJECT'
    uci set firewall.guest.output='ACCEPT'
    uci set firewall.guest.forward='REJECT'

    # Allow Forwarding to WAN
    uci set firewall.guest_forward_wan=forwarding
    uci set firewall.guest_forward_wan.src='guest'
    uci set firewall.guest_forward_wan.dest='wan'

    # Allow DNS & DHCP Requests
    uci set firewall.guest_dns=rule
    uci set firewall.guest_dns.name='Allow Guest DNS'
    uci set firewall.guest_dns.src='guest'
    uci set firewall.guest_dns.dest_port='53'
    uci set firewall.guest_dns.proto='tcpudp'
    uci set firewall.guest_dns.target='ACCEPT'

    uci set firewall.guest_dhcp=rule
    uci set firewall.guest_dhcp.name='Allow Guest DHCP'
    uci set firewall.guest_dhcp.src='guest'
    uci set firewall.guest_dhcp.dest_port='67-68'
    uci set firewall.guest_dhcp.proto='udp'
    uci set firewall.guest_dhcp.target='ACCEPT'

    uci commit network
    uci commit dhcp
    uci commit firewall
    /etc/init.d/network restart >/dev/null 2>&1
    /etc/init.d/firewall restart >/dev/null 2>&1
}

wifi_menu()
{
    render_persistent_header 2>/dev/null || clear

    echo "   🛜 Advanced WiFi & Guest Network Setup                    "
    echo "  ───────────────────────────────────────────────────────────"

    RADIOS=""
    if [ -f /etc/config/wireless ]; then
        RADIOS=$(uci show wireless | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1)
    fi

    if [ -z "$RADIOS" ]; then
        wifi config 2>/dev/null
        RADIOS=$(uci show wireless 2>/dev/null | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1)
    fi

    if [ -z "$RADIOS" ]; then
        log_error "No wireless hardware detected!"
        sleep 2
        return 1
    fi

    # UX Improvement: Ask SSID Strategy
    echo "  ⚙️ How do you want to configure your Main WiFi SSIDs?"
    echo "   1) Single SSID for All Bands (Smart Connect / Unified Name)"
    echo "   2) Custom SSID per Band (e.g., Home_2.4G and Home_5G)"
    echo "  ───────────────────────────────────────────────────────────"
    printf "  Select Option [1/2] : "
    read -r ssid_mode </dev/tty

    MAIN_SSID_2G=""
    MAIN_SSID_5G=""
    
    if [ "$ssid_mode" = "2" ]; then
        printf "  ✏️ Enter 2.4GHz SSID Name [Default: DayPass-2.4G]: "
        read -r MAIN_SSID_2G </dev/tty
        [ -z "$MAIN_SSID_2G" ] && MAIN_SSID_2G="DayPass-2.4G"

        printf "  ✏️ Enter 5GHz SSID Name [Default: DayPass-5G]: "
        read -r MAIN_SSID_5G </dev/tty
        [ -z "$MAIN_SSID_5G" ] && MAIN_SSID_5G="DayPass-5G"
    else
        printf "  ✏️ Enter Unified SSID Name [Default: DayPass-WiFi]: "
        read -r unified_ssid </dev/tty
        [ -z "$unified_ssid" ] && unified_ssid="DayPass-WiFi"
        MAIN_SSID_2G="$unified_ssid"
        MAIN_SSID_5G="$unified_ssid"
    fi

    while true; do
        printf "  🔑 Enter Main WiFi Password (Min 8 chars) : "
        read -r user_pass </dev/tty
        if [ ${#user_pass} -ge 8 ]; then
            break
        else
            log_error "Password must be at least 8 characters long!"
        fi
    done

    # Configure Main WiFi
    idx=0
    for radio in $RADIOS; do
        uci set "wireless.$radio.disabled"='0'
        band=$(uci -q get "wireless.$radio.band" || uci -q get "wireless.$radio.hwmode" || echo "")

        IFACE_KEY="default_$radio"
        if ! uci -q get "wireless.$IFACE_KEY" >/dev/null; then
            IFACE_KEY="wifinet${idx}"
            uci set "wireless.$IFACE_KEY"=wifi-iface
            uci set "wireless.$IFACE_KEY.device"="$radio"
            uci set "wireless.$IFACE_KEY.mode"='ap'
            uci set "wireless.$IFACE_KEY.network"='lan'
        fi

        # Assign SSID based on Band
        case "$band" in
            *5g*|*a*|*ac*|*ax*) CHOSEN_SSID="$MAIN_SSID_5G" ;;
            *)                  CHOSEN_SSID="$MAIN_SSID_2G" ;;
        esac

        uci set "wireless.$IFACE_KEY.ssid"="$CHOSEN_SSID"
        uci set "wireless.$IFACE_KEY.encryption"='psk2'
        uci set "wireless.$IFACE_KEY.key"="$user_pass"
        uci set "wireless.$IFACE_KEY.disabled"='0'

        log_success "Configured Main WiFi [$radio] -> $CHOSEN_SSID"
        idx=$((idx + 1))
    done

    # Ask for Guest WiFi
    echo
    echo "  ───────────────────────────────────────────────────────────"
    printf "  👥 Do you want to enable an Isolated Guest WiFi Network? [y/N] : "
    read -r enable_guest </dev/tty

    case "$enable_guest" in
        y|Y)
            setup_guest_firewall_and_network

            printf "  ✏️ Enter Guest WiFi SSID [Default: DayPass-Guest]: "
            read -r guest_ssid </dev/tty
            [ -z "$guest_ssid" ] && guest_ssid="DayPass-Guest"

            while true; do
                printf "  🔑 Enter Guest WiFi Password (Min 8 chars) : "
                read -r guest_pass </dev/tty
                if [ ${#guest_pass} -ge 8 ]; then
                    break
                else
                    log_error "Guest Password must be at least 8 characters long!"
                fi
            done

            for radio in $RADIOS; do
                band=$(uci -q get "wireless.$radio.band" || uci -q get "wireless.$radio.hwmode" || echo "")
                GUEST_IFACE="guest_$radio"

                # Differentiate Guest SSID per band if using custom mode
                CURR_GUEST_SSID="$guest_ssid"
                if [ "$ssid_mode" = "2" ]; then
                    case "$band" in
                        *5g*|*a*|*ac*|*ax*) CURR_GUEST_SSID="${guest_ssid}_5G" ;;
                        *)                  CURR_GUEST_SSID="${guest_ssid}_2.4G" ;;
                    esac
                fi

                uci set "wireless.$GUEST_IFACE"=wifi-iface
                uci set "wireless.$GUEST_IFACE.device"="$radio"
                uci set "wireless.$GUEST_IFACE.mode"='ap'
                uci set "wireless.$GUEST_IFACE.network"='guest'
                uci set "wireless.$GUEST_IFACE.ssid"="$CURR_GUEST_SSID"
                uci set "wireless.$GUEST_IFACE.encryption"='psk2'
                uci set "wireless.$GUEST_IFACE.key"="$guest_pass"
                uci set "wireless.$GUEST_IFACE.isolate"='1' # Prevent client-to-client traffic
                uci set "wireless.$GUEST_IFACE.disabled"='0'

                log_success "Configured Guest WiFi [$radio] -> $CURR_GUEST_SSID"
            done
            ;;
        *)
            log_info "Guest WiFi setup skipped."
            ;;
    esac

    uci commit wireless
    wifi reload 2>/dev/null || /etc/init.d/network restart

    echo
    log_success "WiFi Settings Applied Successfully!"
    echo
    printf "  ${GRAY}Press [ENTER] to continue ...${RESET}"
    read -r _ </dev/tty
}