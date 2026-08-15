#!/bin/sh
# ============================================================
# DayPass - Traffic Routing / Shunt Rules
# Applies real routing rules to Passwall1 & Passwall2
# ============================================================

# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------
PROXY_DIR="/etc/daypass/proxy"
ROUTING_DIR="$PROXY_DIR/routing"
mkdir -p "$ROUTING_DIR"

# ------------------------------------------------------------
# Detect Passwall version
# ------------------------------------------------------------
get_pw_version() {
    if command -v detect_passwall_version >/dev/null 2>&1; then
        detect_passwall_version
    else
        if [ -f /etc/config/passwall2 ] || uci -q show passwall2 >/dev/null 2>&1; then
            echo "passwall2"
        elif [ -f /etc/config/passwall ] || uci -q show passwall >/dev/null 2>&1; then
            echo "passwall"
        else
            echo "none"
        fi
    fi
}

# ------------------------------------------------------------
# Show current routing status
# ------------------------------------------------------------
show_routing_status() {
    echo "  🚦 Current Routing Status"
    echo "  ───────────────────────────────────────────────────────────"

    if [ -f "$ROUTING_DIR/current_mode" ]; then
        mode=$(cat "$ROUTING_DIR/current_mode")
        echo "  🫀 Active Mode : ${GREEN}$mode${RESET}"
    else
        echo "  🫀 Active Mode : ${GRAY}Not configured${RESET}"
    fi

    local pw_ver
    pw_ver=$(get_pw_version)
    echo "  🛡️  Passwall    : ${CYAN}$pw_ver${RESET}"
    echo "  ───────────────────────────────────────────────────────────"
}

# ------------------------------------------------------------
# Apply Iran Direct + Foreign Proxy
# ------------------------------------------------------------
apply_iran_direct() {
    local pw_ver
    pw_ver=$(get_pw_version)

    if [ "$pw_ver" = "none" ]; then
        log_error "No Passwall installed. Cannot apply routing rules."
        return 1
    fi

    log_info "Applying mode : Iran Direct + Foreign Proxy ..."

    case "$pw_ver" in
        passwall2)
            uci set passwall2.@global[0].enabled='1' 2>/dev/null
            uci set passwall2.@global[0].tcp_proxy_mode='gfwlist' 2>/dev/null || \
            uci set passwall2.@global[0].tcp_proxy_mode='proxy' 2>/dev/null
            uci set passwall2.@global[0].localhost_proxy='0' 2>/dev/null
            uci commit passwall2
            /etc/init.d/passwall2 reload >/dev/null 2>&1 || true
            ;;
        passwall)
            uci set passwall.@global[0].enabled='1' 2>/dev/null
            uci set passwall.@global[0].tcp_proxy_mode='gfwlist' 2>/dev/null || \
            uci set passwall.@global[0].tcp_proxy_mode='proxy' 2>/dev/null
            uci commit passwall
            /etc/init.d/passwall reload >/dev/null 2>&1 || true
            ;;
    esac

    echo "iran_direct" > "$ROUTING_DIR/current_mode"

    cat > "$ROUTING_DIR/iran_direct.rules" << EOF
# DayPass Routing Rule - Iran Direct
# 1. Iranian domains & IPs → Direct
# 2. Everything else → Proxy
EOF

    log_success "Mode [🦁☀️ IRAN Direct] applied to $pw_ver!"
}

# ------------------------------------------------------------
# Global Proxy (All traffic through proxy)
# ------------------------------------------------------------
apply_global_proxy() {
    local pw_ver
    pw_ver=$(get_pw_version)

    if [ "$pw_ver" = "none" ]; then
        log_error "No Passwall installed."
        return 1
    fi

    log_info "Applying mode : Global Proxy ..."

    case "$pw_ver" in
        passwall2)
            uci set passwall2.@global[0].enabled='1' 2>/dev/null
            uci set passwall2.@global[0].tcp_proxy_mode='proxy' 2>/dev/null
            uci set passwall2.@global[0].udp_proxy_mode='proxy' 2>/dev/null
            uci commit passwall2
            /etc/init.d/passwall2 reload >/dev/null 2>&1 || true
            ;;
        passwall)
            uci set passwall.@global[0].enabled='1' 2>/dev/null
            uci set passwall.@global[0].tcp_proxy_mode='proxy' 2>/dev/null
            uci set passwall.@global[0].udp_proxy_mode='proxy' 2>/dev/null
            uci commit passwall
            /etc/init.d/passwall reload >/dev/null 2>&1 || true
            ;;
    esac

    echo "global_proxy" > "$ROUTING_DIR/current_mode"

    cat > "$ROUTING_DIR/global_proxy.rules" << EOF
# DayPass Routing Rule - Global Proxy
# All traffic → Proxy
EOF

    log_success "Mode [🌏 Global Proxy] applied to $pw_ver!"
}

# ------------------------------------------------------------
# Direct Only (No Proxy)
# ------------------------------------------------------------
apply_direct_only() {
    local pw_ver
    pw_ver=$(get_pw_version)

    if [ "$pw_ver" = "none" ]; then
        log_error "No Passwall installed."
        return 1
    fi

    log_info "Applying mode : Direct Only ..."

    case "$pw_ver" in
        passwall2)
            uci set passwall2.@global[0].enabled='0' 2>/dev/null
            uci set passwall2.@global[0].tcp_proxy_mode='disable' 2>/dev/null
            uci commit passwall2
            /etc/init.d/passwall2 reload >/dev/null 2>&1 || true
            ;;
        passwall)
            uci set passwall.@global[0].enabled='0' 2>/dev/null
            uci set passwall.@global[0].tcp_proxy_mode='disable' 2>/dev/null
            uci commit passwall
            /etc/init.d/passwall reload >/dev/null 2>&1 || true
            ;;
    esac

    echo "direct_only" > "$ROUTING_DIR/current_mode"

    cat > "$ROUTING_DIR/direct_only.rules" << EOF
# DayPass Routing Rule - Direct Only
# All traffic → Direct (Proxy disabled)
EOF

    log_success "Mode [🎯 Direct Only] applied. Proxy disabled!"
}

# ------------------------------------------------------------
# Main Routing Menu
# ------------------------------------------------------------
routing_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear

        echo "  🚦 Traffic Routing / Shunt Rules"
        echo "  ───────────────────────────────────────────────────────────"
        show_routing_status
        echo
        echo "  👑 1) Iran Direct + Foreign Proxy   (Recommended)"
        echo "  🌏 2) Global Proxy                  (All traffic via proxy)"
        echo "  🎯 3) Direct Only                   (Disable proxy)"
        echo "  👀 4) Show current rules"
        echo "  🚪 0) Back"
        echo "  ───────────────────────────────────────────────────────────"
        echo

        printf "  ⁉️ Select option [0-4] : "
        read -r choice </dev/tty

        case "$choice" in
            1) apply_iran_direct ;;
            2) apply_global_proxy ;;
            3) apply_direct_only ;;
            4)
                echo
                if [ -f "$ROUTING_DIR/current_mode" ]; then
                    mode=$(cat "$ROUTING_DIR/current_mode")
                    echo "  ⭡ Current mode : $mode"
                    echo
                    cat "$ROUTING_DIR/${mode}.rules" 2>/dev/null || echo "  No detailed rules file."
                else
                    echo "  💅🏻 No routing mode configured yet!"
                fi
                ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
        read -r _ </dev/tty
    done
}