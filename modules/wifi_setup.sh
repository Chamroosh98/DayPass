#!/bin/sh

# Section 1: Helper - Setup Guest Firewall Zone, Network Subnet & DHCP Server
setup_guest_firewall_and_network()
{
    log_info "Configuring Isolated Guest Network Zone..."

    # Create Isolated Guest Network Interface (Subnet: 192.168.200.1/24)
    uci set network.guest=interface
    uci set network.guest.proto='static'
    uci set network.guest.ipaddr='192.168.200.1'
    uci set network.guest.netmask='255.255.255.0'

    # Setup Dedicated DHCP Pool for Guest Subnet
    uci set dhcp.guest=dhcp
    uci set dhcp.guest.interface='guest'
    uci set dhcp.guest.start='100'
    uci set dhcp.guest.limit='150'
    uci set dhcp.guest.leasetime='12h'

    # Setup Isolated Firewall Zone (Deny access to router LAN, allow Internet WAN)
    uci set firewall.guest=zone
    uci set firewall.guest.name='guest'
    uci set firewall.guest.network='guest'
    uci set firewall.guest.input='REJECT'
    uci set firewall.guest.output='ACCEPT'
    uci set firewall.guest.forward='REJECT'

    # Forwarding Rule: Guest Zone -> WAN Only
    uci set firewall.guest_forward_wan=forwarding
    uci set firewall.guest_forward_wan.src='guest'
    uci set firewall.guest_forward_wan.dest='wan'

    # Firewall Rule: Allow Essential DNS Resolution
    uci set firewall.guest_dns=rule
    uci set firewall.guest_dns.name='Allow Guest DNS'
    uci set firewall.guest_dns.src='guest'
    uci set firewall.guest_dns.dest_port='53'
    uci set firewall.guest_dns.proto='tcpudp'
    uci set firewall.guest_dns.target='ACCEPT'

    # Firewall Rule: Allow Essential DHCP Requests
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

# Section 2: Helper - Inspect Current WiFi Configuration and Active SSIDs
inspect_existing_wifi()
{
    echo "  🔍 Current WiFi Status & Detected SSIDs:"
    has_active_ap=0

    for radio in $1; do
        band=$(uci -q get "wireless.$radio.band" || uci -q get "wireless.$radio.hwmode" || echo "2.4G/5G")
        disabled=$(uci -q get "wireless.$radio.disabled" || echo "1")
        
        # Find active Access Point SSIDs on this radio
        existing_ssids=""
        for iface in $(uci show wireless | grep "\.device='$radio'" | cut -d'.' -f2); do
            mode=$(uci -q get "wireless.$iface.mode" || echo "")
            if [ "$mode" = "ap" ]; then
                ssid=$(uci -q get "wireless.$iface.ssid" || echo "Unassigned")
                iface_disabled=$(uci -q get "wireless.$iface.disabled" || echo "0")
                if [ "$iface_disabled" = "0" ]; then
                    existing_ssids="${existing_ssids:+$existing_ssids, }$ssid"
                fi
            fi
        done

        if [ "$disabled" = "0" ] && [ -n "$existing_ssids" ]; then
            printf "     ├─ 📻 Radio [${CYAN}%s${RESET}] (%s): ${GREEN}ACTIVE${RESET} (SSID: ${YELLOW}%s${RESET})\n" "$radio" "$band" "$existing_ssids"
            has_active_ap=1
        else
            printf "     ├─ 📻 Radio [${CYAN}%s${RESET}] (%s): ${GRAY}DISABLED / NOT CONFIGURED${RESET}\n" "$radio" "$band"
        fi
    done
    
    echo "  ───────────────────────────────────────────────────────────"
    return $has_active_ap
}

# Section 3: Main WiFi Interactive Setup Engine
wifi_menu()
{
    render_persistent_header 2>/dev/null || clear

    echo "  🛜 Local Access Point (AP) & Guest Network Setup          "
    echo "  ───────────────────────────────────────────────────────────"
    echo "  ${GRAY}ℹ️  NOTE: This menu configures the WiFi network broadcasted${RESET}"
    echo "  ${GRAY}    by THIS router for your phones/laptops to connect to.${RESET}"
    echo "  ${GRAY}    To connect this router to ANOTHER WiFi/Hotspot for internet,${RESET}"
    echo "  ${GRAY}    use Option 5 (Multi-WAN Load Balancer) instead.${RESET}"
    echo "  ───────────────────────────────────────────────────────────"

    # Detect Wireless Radios
    RADIOS=""
    if [ -f /etc/config/wireless ]; then
        RADIOS=$(uci show wireless | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1)
    fi

    if [ -z "$RADIOS" ]; then
        wifi config 2>/dev/null
        RADIOS=$(uci show wireless 2>/dev/null | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1)
    fi

    if [ -z "$RADIOS" ]; then
        log_error "No wireless hardware detected on this router!"
        sleep 2
        return 1
    fi

    # Inspect current WiFi Status
    inspect_existing_wifi "$RADIOS"
    has_existing=$?

    # Offer option to skip if already configured
    if [ "$has_existing" -eq 1 ]; then
        printf "  ⁉️ Existing WiFi SSIDs detected. Do you want to reconfigure? [y/N] : "
        read -r reconf </dev/tty
        case "$reconf" in
            y|Y) ;;
            *)
                printf "  ${GRAY}>> Keeping current WiFi settings. Skipping Main WiFi setup ...${RESET}\n"
                sleep 1
                goto_guest_check=1
                ;;
        esac
    fi

    # Execute Main WiFi Setup if not skipped
    if [ "${goto_guest_check:-0}" -ne 1 ]; then
        echo
        echo "  ⚙️ Select SSID Naming Strategy :"
        echo "     1) Single Unified SSID for All Bands (Smart Connect)"
        echo "     2) Separate SSID per Band (e.g., Home_2.4G & Home_5G)"
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
            printf "  ✏️ Enter Unified SSID Name [Default: DayPass]: "
            read -r unified_ssid </dev/tty
            [ -z "$unified_ssid" ] && unified_ssid="DayPass"
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

        # Configure Main WiFi Access Points
        log_info "Applying Main Access Point (AP) settings..."
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

            # Determine appropriate SSID based on radio band
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
        uci commit wireless
    fi

    # Section 4: Optional Isolated Guest Network Configuration
    echo
    echo "  ───────────────────────────────────────────────────────────"
    printf "  👥 Do you want to configure/update Isolated Guest WiFi? [y/N] : "
    read -r enable_guest </dev/tty

    case "$enable_guest" in
        y|Y)
            setup_guest_firewall_and_network

            printf "  ✏️ Enter Guest WiFi SSID [Default: DayPass-Guest] : "
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

                # Differentiate Guest SSID if custom band naming selected
                CURR_GUEST_SSID="$guest_ssid"
                if [ "${ssid_mode:-1}" = "2" ]; then
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
                uci set "wireless.$GUEST_IFACE.isolate"='1' # Block client-to-client traffic
                uci set "wireless.$GUEST_IFACE.disabled"='0'

                log_success "Configured Guest WiFi [$radio] -> $CURR_GUEST_SSID"
            done
            uci commit wireless
            ;;
        *)
            printf "  ${GRAY}>> Guest WiFi setup skipped.${RESET}\n"
            ;;
    esac

    # Section 5: Reload Subsystems
    log_info "Reloading Wireless Network Subsystem ..."
    wifi reload 2>/dev/null || /etc/init.d/network restart >/dev/null 2>&1

    echo
    log_success "WiFi Subsystem Successfully Synchronized!"
    echo
    printf "  ${GRAY}Press [ENTER] to continue ...${RESET}"
    read -r _ </dev/tty
}