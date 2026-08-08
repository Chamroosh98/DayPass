#!/bin/sh

install_mwan3_deps()
{
    log_info "Installing Load Balancer & USB Tethering dependencies..."

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

    # Enable usbmuxd autostart for iOS Tethering
    if command -v usbmuxd >/dev/null 2>&1; then
        if ! grep -q "usbmuxd" /etc/rc.local 2>/dev/null; then
            sed -i -e "\$i usbmuxd -v &" /etc/rc.local
        fi
        usbmuxd -v >/dev/null 2>&1 &
    fi

    log_success "Dependencies installed successfully!"
}

setup_usb_tethering_interface()
{
    log_info "Setting up USB Tethering WAN Interface (wan_usb)..."
    
    # Check for usb0 device
    USB_DEV=""
    if ip link show usb0 >/dev/null 2>&1; then
        USB_DEV="usb0"
    elif ip link show eth1 >/dev/null 2>&1; then
        USB_DEV="eth1"
    fi

    if [ -z "$USB_DEV" ]; then
        log_warn "No USB Tethering device detected (usb0/eth1)!"
        log_warn "Make sure your Android/iPhone USB Tethering is enabled."
        USB_DEV="usb0" # Fallback assign
    fi

    uci set network.wan_usb=interface
    uci set network.wan_usb.proto='dhcp'
    uci set network.wan_usb.device="$USB_DEV"
    uci set network.wan_usb.metric='20' # Higher metric for secondary WAN
    
    # Firewalld Zone Setup
    uci add_list firewall.@zone[1].network='wan_usb' 2>/dev/null || true

    uci commit network
    uci commit firewall
    log_success "Created interface [wan_usb] attached to $USB_DEV"
}

setup_wifi_wwan_interface()
{
    render_persistent_header 2>/dev/null || clear
    echo "    📡 Setup Wi-Fi Repeater / Hotspot (WWAN)                  "
    echo "  ───────────────────────────────────────────────────────────"

    RADIO=$(uci show wireless 2>/dev/null | grep "=wifi-device" | head -n1 | cut -d'.' -f2 | cut -d'=' -f1)
    if [ -z "$RADIO" ]; then
        log_error "No Wi-Fi radio hardware available for Wireless WAN!"
        return 1
    fi

    printf "  ✏️ Enter Target Wi-Fi SSID (Hotspot Name): "
    read -r target_ssid </dev/tty
    [ -z "$target_ssid" ] && return 1

    printf "  🔑 Enter Target Wi-Fi Password: "
    read -r target_pass </dev/tty

    # Setup Wireless Station (Client)
    uci set network.wwan=interface
    uci set network.wwan.proto='dhcp'
    uci set network.wwan.metric='30'

    IFACE_KEY="sta_$RADIO"
    uci set wireless.$IFACE_KEY=wifi-iface
    uci set wireless.$IFACE_KEY.device="$RADIO"
    uci set wireless.$IFACE_KEY.mode='sta'
    uci set wireless.$IFACE_KEY.network='wwan'
    uci set wireless.$IFACE_KEY.ssid="$target_ssid"
    if [ -n "$target_pass" ]; then
        uci set wireless.$IFACE_KEY.encryption='psk2'
        uci set wireless.$IFACE_KEY.key="$target_pass"
    else
        uci set wireless.$IFACE_KEY.encryption='none'
    fi

    uci add_list firewall.@zone[1].network='wwan' 2>/dev/null || true

    uci commit network
    uci commit wireless
    uci commit firewall
    wifi reload 2>/dev/null || /etc/init.d/network restart
    log_success "Wi-Fi WWAN interface configured to join [$target_ssid]!"
}

configure_mwan3_engine()
{
    log_info "Configuring mwan3 Load Balancing & Failover Rules..."

    # Enable mwan3 global
    uci set mwan3.globals=globals
    uci set mwan3.globals.mmx_mask='0x3f00'

    # 1. Primary Ethernet WAN
    uci set mwan3.wan=interface
    uci set mwan3.wan.enabled='1'
    uci set mwan3.wan.family='ipv4'
    uci add_list mwan3.wan.track_ip='1.1.1.1'
    uci add_list mwan3.wan.track_ip='8.8.8.8'
    uci set mwan3.wan.reliability='1'
    uci set mwan3.wan.count='1'
    uci set mwan3.wan.timeout='2'

    # 2. USB WAN
    uci set mwan3.wan_usb=interface
    uci set mwan3.wan_usb.enabled='1'
    uci set mwan3.wan_usb.family='ipv4'
    uci add_list mwan3.wan_usb.track_ip='1.0.0.1'
    uci add_list mwan3.wan_usb.track_ip='8.8.4.4'
    uci set mwan3.wan_usb.reliability='1'
    uci set mwan3.wan_usb.count='1'
    uci set mwan3.wan_usb.timeout='2'

    # 3. WWAN (Wi-Fi)
    uci set mwan3.wwan=interface
    uci set mwan3.wwan.enabled='1'
    uci set mwan3.wwan.family='ipv4'
    uci add_list mwan3.wwan.track_ip='9.9.9.9'
    uci set mwan3.wwan.reliability='1'

    # Define Members (Weights)
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
    uci add_list mwan3.balanced.use_member='wan_m1'
    uci add_list mwan3.balanced.use_member='usb_m1'
    uci add_list mwan3.balanced.use_member='wwan_m1'

    # Apply Policy to Default Rule
    uci set mwan3.default_rule=rule
    uci set mwan3.default_rule.dest_ip='0.0.0.0/0'
    uci set mwan3.default_rule.use_policy='balanced'

    uci commit mwan3
    /etc/init.d/mwan3 enable
    /etc/init.d/mwan3 restart
    log_success "mwan3 Engine successfully configured and started!"
}

load_balancer_menu()
{
    render_persistent_header 2>/dev/null || clear

    echo "    ⚖️ Multi-WAN Load Balancer Setup (mwan3)                 "
    echo "  ───────────────────────────────────────────────────────────"
    echo "    1) 📦 Install Dependencies (mwan3, USB Tethering drivers) "
    echo "    2) 📱 Configure USB Tethering WAN (Android / iPhone)      "
    echo "    3) 📡 Configure Wi-Fi Hotspot WAN (WWAN Client Mode)      "
    echo "    4) ⚡ Auto-Setup Combined Load Balancing (Balanced Policy)"
    echo "    5) 📊 Show Live WAN Status & Monitor                       "
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
                log_error "mwan3 is not installed!"
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