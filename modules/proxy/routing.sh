#!/bin/sh
# ============================================================
# DayPass - Traffic Routing / Shunt Rules
# ============================================================

# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------
PROXY_DIR="/etc/daypass/proxy"
ROUTING_DIR="$PROXY_DIR/routing"
mkdir -p "$ROUTING_DIR"

# ------------------------------------------------------------
# Show current routing mode
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

    echo "  ───────────────────────────────────────────────────────────"
}

# ------------------------------------------------------------
# Apply Iran Direct + Foreign Proxy (Most Common)
# ------------------------------------------------------------
apply_iran_direct() {
    log_info "Applying mode : Iran Direct + Foreign Proxy ..."

    # This is a high-level rule. Actual implementation depends on
    # whether user uses Passwall, Passwall2, or raw Xray/Sing-box.
    # For now we save the preference and give instructions.

    echo "iran_direct" > "$ROUTING_DIR/current_mode"

    cat > "$ROUTING_DIR/iran_direct.rules" << EOF
# DayPass Routing Rule - Iran Direct
# 1. Iranian domains & IPs → Direct
# 2. Everything else → Proxy
EOF

    log_success "Mode [🦁☀️ IRAN Direct] saved!"
    log_info "Note : You need to apply this rule inside Passwall/Passwall2 or Xray config!"
}

# ------------------------------------------------------------
# Global Proxy (All traffic through proxy)
# ------------------------------------------------------------
apply_global_proxy() {
    log_info "Applying mode : Global Proxy ..."

    echo "global_proxy" > "$ROUTING_DIR/current_mode"

    cat > "$ROUTING_DIR/global_proxy.rules" << EOF
# DayPass Routing Rule - Global Proxy
# All traffic → Proxy
EOF

    log_success "Mode [🌏 Global Proxy] saved!"
}

# ------------------------------------------------------------
# Direct Only (No Proxy)
# ------------------------------------------------------------
apply_direct_only() {
    log_info "Applying mode : Direct Only ..."

    echo "direct_only" > "$ROUTING_DIR/current_mode"

    cat > "$ROUTING_DIR/direct_only.rules" << EOF
# DayPass Routing Rule - Direct Only
# All traffic → Direct (Proxy disabled)
EOF

    log_success "Mode [🎯 Direct Only] saved!"
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
                    echo "  🫴🏻 Current mode : $mode"
                    echo
                    cat "$ROUTING_DIR/${mode}.rules" 2>/dev/null || echo "  No detailed rules file."
                else
                    echo "  💅🏻 No routing mode configured yet!"
                fi
                ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press [Enter] to continue ... ${RESET}"
        read -r _ </dev/tty
    done
}