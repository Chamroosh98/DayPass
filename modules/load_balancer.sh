#!/bin/sh

# Section 1: Helper - Install Required Drivers, Utilities & mwan3 Packages
install_mwan3_deps()
{
    log_info "Installing Load Balancer & USB Tethering dependencies ..."

    PKGS_OPKG="mwan3 luci-app-mwan3 bmon kmod-usb-net-rndis kmod-usb-net-cdc-ncm kmod-nls-base kmod-usb-core kmod-usb-net kmod-usb-net-cdc-ether kmod-usb2 kmod-usb-net-ipheth usbmuxd libimobiledevice usbutils"
    PKGS_APK="mwan3 luci-app-mwan3 bmon kmod-usb-net-rndis kmod-usb-net-cdc-ncm kmod-nls-base kmod-usb-core kmod-usb-net kmod-usb-net-cdc-ether kmod-usb2 kmod-usb-net-ipheth usbmuxd libimobiledevice usbutils"

    if [ "${PKG_MANAGER:-opkg}" = "apk" ]; then
        apk update >/dev/null 2>&1
        for pkg in $PKGS_APK; do
            apk add "$pkg" >/dev/null 2>&1 || log_warn "Failed or already installed: $pkg"
        done
    else
        opkg update >/dev/null 2>&1
        for pkg in $PKGS_OPKG; do
            opkg install "$pkg" >/dev/null 2>&1 || log_warn "Failed or already installed: $pkg"
        done
    fi

    # Enable usbmuxd autostart daemon for iOS (iPhone) Tethering
    if command -v usbmuxd >/dev/null 2>&1; then
        if ! grep -q "usbmuxd" /etc/rc.local 2>/dev/null; then
            sed -i -e "\$i usbmuxd -v &" /etc/rc.local
        fi
        usbmuxd -v >/dev/null 2>&1 &
    fi

    log_success "Multi-WAN dependencies installed successfully!"
}

# Section 2: Helper - Configure USB Tethering WAN Interface (Android / iPhone)
setup_usb_tethering_interface()
{
    log_info "Setting up USB Tethering WAN Interface (wan_usb) ..."
    
    # Auto-detect USB Network Hardware Device (usb0 / eth1)
    USB_DEV=""
    if ip link show usb0 >/dev/null 2>&1; then
        USB_DEV="usb0"
    elif ip link show eth1 >/dev/null 2>&1; then
        USB_DEV="eth1"
    fi

    if [ -z "$USB_DEV" ]; then
        log_warn "No active USB Tethering device detected (usb0/eth1)!"
        log_warn "Please ensure your phone is connected and USB Tethering is enabled."
        USB_DEV="usb0" # Default fallback device
    fi

    uci set network.wan_usb=interface
    uci set network.wan_usb.proto='dhcp'
    uci set network.wan_usb.device="$USB_DEV"
    uci set network.wan_usb.metric='20' # Dedicated metric for Multi-WAN routing
    
    # Assign interface to Firewall WAN Zone
    uci add_list firewall.@zone[1].network='wan_usb' 2>/dev/null || true

    uci commit network
    uci commit firewall
    log_success "Created WAN interface [wan_usb] bound to physical device $USB_DEV!"
}

# Section 3: Helper - Configure Wi-Fi WWAN (Client / Repeater Mode for Hotspot)
setup_wifi_wwan_interface()
{
    render_persistent_header 2>/dev/null || clear
    echo "  📡 Setup Wi-Fi Hotspot WAN (WWAN Repeater Mode)            "
    echo "  ───────────────────────────────────────────────────────────"
    echo "  ${GRAY}ℹ️  NOTE : This connects your router to a phone hotspot or${RESET}"
    echo "  ${GRAY}    external Wi-Fi as an internet source for Load Balancing.${RESET}"
    echo "  ───────────────────────────────────────────────────────────"

    # Detect Available Radios
    RADIOS=$(uci show wireless 2>/dev/null | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1)
    if [ -z "$RADIOS" ]; then
        log_error "No Wi-Fi radio hardware available on this router!"
        return 1
    fi

    # Interactive Radio Selection (2.4GHz vs 5GHz)
    echo "  🔍 Select Wireless Hardware Radio to connect with :"
    r_idx=1
    radio_list=""
    for r in $RADIOS; do
        band=$(uci -q get "wireless.$r.band" || uci -q get "wireless.$r.hwmode" || echo "2.4G/5G")
        echo "     $r_idx) $r ($band)"
        radio_list="$radio_list $r"
        r_idx=$((r_idx + 1))
    done
    echo "  ───────────────────────────────────────────────────────────"
    printf "  Select Radio [1-%d, Default: 1] : " "$((r_idx - 1))"
    read -r r_choice </dev/tty

    # Resolve Chosen Radio
    chosen_radio=""
    cur_idx=1
    for r in $radio_list; do
        if [ "$r_choice" = "$cur_idx" ] || [ -z "$chosen_radio" ]; then
            chosen_radio="$r"
            [ "$r_choice" = "$cur_idx" ] && break
        fi
        cur_idx=$((cur_idx + 1))
    done

    printf "  ✏️ Enter Target Wi-Fi SSID (Hotspot Name) : "
    read -r target_ssid </dev/tty
    if [ -z "$target_ssid" ]; then
        log_error "SSID cannot be empty!"
        return 1
    fi

    printf "  🔑 Enter Target Wi-Fi Password (Leave empty if Open) : "
    read -r target_pass </dev/tty

    # Configure Logical Network Interface for WWAN
    uci set network.wwan=interface
    uci set network.wwan.proto='dhcp'
    uci set network.wwan.metric='30'

    # Ensure Radio is Enabled
    uci set "wireless.$chosen_radio.disabled"='0'

    # Configure Wireless Station (Client Mode) Interface without wiping AP
    IFACE_KEY="wwan_$chosen_radio"
    uci set "wireless.$IFACE_KEY"=wifi-iface
    uci set "wireless.$IFACE_KEY.device"="$chosen_radio"
    uci set "wireless.$IFACE_KEY.mode"='sta'
    uci set "wireless.$IFACE_KEY.network"='wwan'
    uci set "wireless.$IFACE_KEY.ssid"="$target_ssid"
    uci set "wireless.$IFACE_KEY.disabled"='0'

    if [ -n "$target_pass" ]; then
        uci set "wireless.$IFACE_KEY.encryption"='psk2'
        uci set "wireless.$IFACE_KEY.key"="$target_pass"
    else
        uci set "wireless.$IFACE_KEY.encryption"='none'
    fi

    # Assign WWAN interface to Firewall WAN Zone
    uci add_list firewall.@zone[1].network='wwan' 2>/dev/null || true

    uci commit network
    uci commit wireless
    uci commit firewall
    
    log_info "Applying Wireless changes..."
    wifi reload 2>/dev/null || /etc/init.d/network restart >/dev/null 2>&1
    log_success "Wi-Fi WWAN successfully configured on [$chosen_radio] -> Joined [$target_ssid]!"
}

# Section 4: Helper - Configure mwan3 Engine Rules & Load Balancing Policy
configure_mwan3_engine()
{
    log_info "Configuring mwan3 Load Balancing & Failover Rules ..."

    # Initialize Global mwan3 Parameters
    uci set mwan3.globals=globals
    uci set mwan3.globals.mmx_mask='0x3f00'

    # 1. Primary Ethernet WAN Interface Tracking
    uci set mwan3.wan=interface
    uci set mwan3.wan.enabled='1'
    uci set mwan3.wan.family='ipv4'
    uci set mwan3.wan.track_ip=''
    uci add_list mwan3.wan.track_ip='1.1.1.1'
    uci add_list mwan3.wan.track_ip='8.8.8.8'
    uci set mwan3.wan.reliability='1'
    uci set mwan3.wan.count='1'
    uci set mwan3.wan.timeout='2'

    # 2. USB Tethering WAN Interface Tracking
    uci set mwan3.wan_usb=interface
    uci set mwan3.wan_usb.enabled='1'
    uci set mwan3.wan_usb.family='ipv4'
    uci set mwan3.wan_usb.track_ip=''
    uci add_list mwan3.wan_usb.track_ip='1.0.0.1'
    uci add_list mwan3.wan_usb.track_ip='8.8.4.4'
    uci set mwan3.wan_usb.reliability='1'
    uci set mwan3.wan_usb.count='1'
    uci set mwan3.wan_usb.timeout='2'

    # 3. Wi-Fi WWAN Interface Tracking
    uci set mwan3.wwan=interface
    uci set mwan3.wwan.enabled='1'
    uci set mwan3.wwan.family='ipv4'
    uci set mwan3.wwan.track_ip=''
    uci add_list mwan3.wwan.track_ip='9.9.9.9'
    uci set mwan3.wwan.reliability='1'
    uci set mwan3.wwan.count='1'
    uci set mwan3.wwan.timeout='2'

    # Define Policy Members (Weights & Metrics)
    uci set mwan3.wan_m1=member
    uci set mwan3.wan_m1.interface='wan'
    uci set mwan3.wan_m1.metric='1'
    uci set mwan3.wan_m1.weight='3'

    uci set mwan3.usb_m1=member
    uci set mwan3.usb_m1.interface='wan_usb'
    uci set mwan3.usb_m1.metric='1'
    uci set mwan3.usb_m1.weight='3'

    uci set mwan3.wwan_m1=member
    uci set mwan3.wwan_m1.interface='wwan'
    uci set mwan3.wwan_m1.metric='1'
    uci set mwan3.wwan_m1.weight='2'

    # Create Combined Balanced Policy
    uci set mwan3.balanced=policy
    uci set mwan3.balanced.use_member=''
    uci add_list mwan3.balanced.use_member='wan_m1'
    uci add_list mwan3.balanced.use_member='usb_m1'
    uci add_list mwan3.balanced.use_member='wwan_m1'

    # Apply Balanced Policy to Default Routing Rule
    uci set mwan3.default_rule=rule
    uci set mwan3.default_rule.dest_ip='0.0.0.0/0'
    uci set mwan3.default_rule.use_policy='balanced'

    uci commit mwan3
    /etc/init.d/mwan3 enable >/dev/null 2>&1
    /etc/init.d/mwan3 restart >/dev/null 2>&1
    log_success "mwan3 Engine successfully configured and service restarted!"
}

# Section 5: Main Load Balancer Interactive Menu Engine
load_balancer_menu()
{
    render_persistent_header 2>/dev/null || clear

    echo "  ⚖️ Multi-WAN Load Balancer Setup (mwan3)                 "
    echo "  ───────────────────────────────────────────────────────────"
    echo "  1) 📦 Install Dependencies (mwan3, USB Drivers, Utilities) "
    echo "  2) 📱 Configure USB Tethering WAN (Android / iPhone)      "
    echo "  3) 📡 Configure Wi-Fi Hotspot WAN (WWAN Client Mode)      "
    echo "  4) ⚡ Auto-Setup Combined Load Balancing (Balanced Policy)"
    echo "  5) 📊 Show Live WAN Status & Monitor                       "
    echo "  ───────────────────────────────────────────────────────────"
    echo

    printf "  ⁉️ Select option [1-5] : "
    read -r choice </dev/tty

    case "$choice" in
        1)
            install_mwan3_deps
            ;;
        2)
            setup_usb_tethering_interface
            ;;
        3)
            setup_wifi_wwan_interface
            ;;
        4)
            configure_mwan3_engine
            ;;
        5)
            if command -v mwan3 >/dev/null 2>&1; then
                mwan3 status
            else
                log_error "mwan3 package is not installed!"
            fi
            ;;
        *)
            log_warn "Invalid choice!"
            ;;
    esac

    echo
    printf "  ${GRAY}Press [ENTER] to return to menu ...${RESET}"
    read -r _ </dev/tty
}