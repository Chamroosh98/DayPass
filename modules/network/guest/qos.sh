#!/bin/sh
# ============================================================
# DayPass - Guest QoS / Bandwidth Control
# Supports both Simple (tc) and Advanced (SQM) modes
# ============================================================

# ------------------------------------------------------------
# Simple Bandwidth Limit using tc (HTB)
# ------------------------------------------------------------
setup_simple_qos() {
    log_info "Setting up Simple QoS with tc ..."

    # Check if guest interface exists
    if ! uci -q get network.guest >/dev/null; then
        log_error "Guest network not found. Please setup Guest Network first!"
        return 1
    fi

    printf "  📥 Download limit for Guests (Mbps) [e.g. 10] : "
    read -r dl_limit </dev/tty
    [ -z "$dl_limit" ] && dl_limit=10

    printf "  📤 Upload limit for Guests (Mbps) [e.g. 5] : "
    read -r ul_limit </dev/tty
    [ -z "$ul_limit" ] && ul_limit=5

    # Convert to kbps
    local dl_kbit=$((dl_limit * 1000))
    local ul_kbit=$((ul_limit * 1000))

    # Install tc if needed
    if ! command -v tc >/dev/null 2>&1; then
        if [ "${PKG_MANAGER:-opkg}" = "apk" ]; then
            apk add kmod-sched tc >/dev/null 2>&1
        else
            opkg update >/dev/null 2>&1
            opkg install kmod-sched tc >/dev/null 2>&1
        fi
    fi

    # Apply tc rules on guest interface (after it comes up)
    cat > /etc/guest_qos.sh << EOF
#!/bin/sh
# DayPass Guest Simple QoS
IFACE="br-guest"
[ -d /sys/class/net/\$IFACE ] || IFACE="guest"

tc qdisc del dev \$IFACE root 2>/dev/null
tc qdisc del dev \$IFACE ingress 2>/dev/null

# Download limit (ingress)
tc qdisc add dev \$IFACE handle ffff: ingress
tc filter add dev \$IFACE parent ffff: protocol ip prio 1 \\
    u32 match ip src 0.0.0.0/0 police rate ${dl_kbit}kbit burst 100k drop

# Upload limit (egress)
tc qdisc add dev \$IFACE root handle 1: htb default 10
tc class add dev \$IFACE parent 1: classid 1:1 htb rate ${ul_kbit}kbit
tc class add dev \$IFACE parent 1:1 classid 1:10 htb rate ${ul_kbit}kbit ceil ${ul_kbit}kbit
tc qdisc add dev \$IFACE parent 1:10 handle 10: sfq perturb 10
EOF

    chmod +x /etc/guest_qos.sh

    # Run now
    /etc/guest_qos.sh

    # Make persistent
    if ! grep -q "guest_qos.sh" /etc/rc.local 2>/dev/null; then
        sed -i -e '$i /etc/guest_qos.sh &' /etc/rc.local
    fi

    log_success "Simple QoS applied → Download: ${dl_limit}Mbps | Upload: ${ul_limit}Mbps"
}

# ------------------------------------------------------------
# Advanced QoS using SQM (Recommended)
# ------------------------------------------------------------
setup_sqm_qos() {
    log_info "Setting up Advanced QoS with SQM ..."

    if ! uci -q get network.guest >/dev/null; then
        log_error "Guest network not found. Please setup Guest Network first!"
        return 1
    fi

    # Install SQM if needed
    if [ "${PKG_MANAGER:-opkg}" = "apk" ]; then
        apk add sqm-scripts >/dev/null 2>&1 || true
    else
        opkg update >/dev/null 2>&1
        opkg install sqm-scripts luci-app-sqm >/dev/null 2>&1 || true
    fi

    printf "  📥 Download limit for Guests (Mbps) [e.g. 15] : "
    read -r dl_limit </dev/tty
    [ -z "$dl_limit" ] && dl_limit=15

    printf "  📤 Upload limit for Guests (Mbps) [e.g. 5] : "
    read -r ul_limit </dev/tty
    [ -z "$ul_limit" ] && ul_limit=5

    local dl_kbit=$((dl_limit * 1000))
    local ul_kbit=$((ul_limit * 1000))

    # Configure SQM on guest interface
    uci set sqm.guest=queue
    uci set sqm.guest.enabled='1'
    uci set sqm.guest.interface='guest'
    uci set sqm.guest.download="$dl_kbit"
    uci set sqm.guest.upload="$ul_kbit"
    uci set sqm.guest.qdisc='cake'
    uci set sqm.guest.script='piece_of_cake.qos'
    uci set sqm.guest.linklayer='none'

    uci commit sqm
    /etc/init.d/sqm enable >/dev/null 2>&1
    /etc/init.d/sqm restart >/dev/null 2>&1

    log_success "SQM QoS applied → Download: ${dl_limit}Mbps | Upload: ${ul_limit}Mbps (Cake)"
}

# ------------------------------------------------------------
# Remove all Guest QoS
# ------------------------------------------------------------
remove_guest_qos() {
    log_info "Removing Guest QoS rules ..."

    # Remove simple tc
    rm -f /etc/guest_qos.sh
    sed -i '/guest_qos.sh/d' /etc/rc.local 2>/dev/null

    # Remove SQM config
    uci -q delete sqm.guest
    uci commit sqm
    /etc/init.d/sqm restart >/dev/null 2>&1

    # Clear tc rules
    for iface in br-guest guest; do
        tc qdisc del dev $iface root 2>/dev/null
        tc qdisc del dev $iface ingress 2>/dev/null
    done

    log_success "Guest QoS removed!"
}

# ------------------------------------------------------------
# Menu
# ------------------------------------------------------------
guest_qos_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear

        echo "  🚦 Guest Bandwidth Control (QoS)"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  1) Simple Limit (tc) - Lightweight"
        echo "  2) Advanced Limit (SQM + Cake) - Better quality"
        echo "  3) Remove all Guest QoS"
        echo "  0) Back"
        echo "  ───────────────────────────────────────────────────────────"
        printf "  ⁉️ Select : "
        read -r choice </dev/tty

        case "$choice" in
            1) setup_simple_qos ;;
            2) setup_sqm_qos ;;
            3) remove_guest_qos ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press ENTER ...${RESET}"
        read -r _ </dev/tty
    done
}