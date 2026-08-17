#!/bin/sh
# ============================================================
# DayPass - Node Load Balancing
# Selects nodes + mode and tries to apply settings to Passwall
# ============================================================

# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------
PROXY_DIR="/etc/daypass/proxy"
CONFIG_DIR="$PROXY_DIR/configs"
BALANCER_DIR="$PROXY_DIR/balancer"
mkdir -p "$BALANCER_DIR"

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
# Show current balancer status
# ------------------------------------------------------------
show_balancer_status() {
    echo "  ⚖️  Current Node Balancer Status"
    echo "  ───────────────────────────────────────────────────────────"

    if [ -f "$BALANCER_DIR/mode" ]; then
        mode=$(cat "$BALANCER_DIR/mode")
        echo "  🫀 Active Mode  : ${GREEN}$mode${RESET}"
    else
        echo "  🫀 Active Mode  : ${GRAY}Disabled${RESET}"
    fi

    if [ -f "$BALANCER_DIR/nodes.list" ]; then
        count=$(wc -l < "$BALANCER_DIR/nodes.list" 2>/dev/null || echo 0)
        echo "  🧠 Active Nodes : $count"
        if [ "$count" -gt 0 ]; then
            echo "  📋 Nodes        : ${GRAY}$(tr '\n' ' ' < "$BALANCER_DIR/nodes.list")${RESET}"
        fi
    else
        echo "  🧠 Active Nodes : 0"
    fi

    local pw_ver
    pw_ver=$(get_pw_version)
    echo "  🛡️  Passwall     : ${CYAN}$pw_ver${RESET}"
    echo "  ───────────────────────────────────────────────────────────"
}

# ------------------------------------------------------------
# Select nodes for balancing
# ------------------------------------------------------------
select_nodes() {
    echo
    echo "  📋 Available Configs :"
    echo "  ───────────────────────────────────────────────────────────"

    local configs=""
    local i=1
    for file in "$CONFIG_DIR"/*.json; do
        [ -f "$file" ] || continue

        name=$(basename "$file" .json)
        protocol=$(jq -r '.protocol // "unknown"' "$file" 2>/dev/null)
        enabled=$(jq -r '.enabled // true' "$file" 2>/dev/null)

        if [ "$enabled" = "false" ]; then
            echo "  $i) $name  ${GRAY}($protocol) [DISABLED]${RESET}"
        else
            echo "  $i) $name  ${GRAY}($protocol)${RESET}"
        fi

        configs="$configs $name"
        i=$((i + 1))
    done

    if [ "$i" -eq 1 ]; then
        log_warn "No configs found. Add some configs first!"
        return 1
    fi

    echo "  ───────────────────────────────────────────────────────────"
    printf "  🧶 Enter node numbers to include (e.g. 1 3 4) : "
    read -r selected </dev/tty

    if [ -z "$selected" ]; then
        log_warn "No selection entered!"
        return 1
    fi

    > "$BALANCER_DIR/nodes.list"

    local idx=1
    local added=0
    for name in $configs; do
        for num in $selected; do
            if [ "$num" = "$idx" ]; then
                enabled=$(jq -r '.enabled // true' "$CONFIG_DIR/${name}.json" 2>/dev/null)
                if [ "$enabled" = "false" ]; then
                    log_warn "Skipped disabled node: [$name]"
                else
                    echo "$name" >> "$BALANCER_DIR/nodes.list"
                    log_success "Added : [$name]"
                    added=$((added + 1))
                fi
            fi
        done
        idx=$((idx + 1))
    done

    if [ "$added" -eq 0 ]; then
        log_warn "No valid nodes selected!"
    else
        log_success "[$added] node(s) selected for balancing!"
    fi
}

# ------------------------------------------------------------
# Set balancing mode
# ------------------------------------------------------------
set_balancer_mode() {
    echo
    echo "  ⚖️  Select Load Balancing Mode :"
    echo "  ───────────────────────────────────────────────────────────"
    echo "  ⏳ 1) Round-Robin      (distribute equally)"
    echo "  🏓 2) Least Ping       (prefer lowest latency)"
    echo "  👨‍👩‍👧‍👦 3) Failover         (use next only if previous fails)"
    echo "  🤹 4) Random"
    echo "  ───────────────────────────────────────────────────────────"
    printf "  ⁉️ Select mode [1-4] : "
    read -r mode_choice </dev/tty

    case "$mode_choice" in
        1) mode="round-robin" ;;
        2) mode="least-ping" ;;
        3) mode="failover" ;;
        4) mode="random" ;;
        *) log_warn "Invalid mode!"; return 1 ;;
    esac

    echo "$mode" > "$BALANCER_DIR/mode"
    log_success "Balancer mode set to : [$mode]"
}

# ------------------------------------------------------------
# Apply balancer settings to Passwall (best-effort)
# ------------------------------------------------------------
apply_balancer() {
    local pw_ver
    pw_ver=$(get_pw_version)

    if [ "$pw_ver" = "none" ]; then
        log_error "No Passwall installed. Cannot apply balancer."
        return 1
    fi

    if [ ! -f "$BALANCER_DIR/mode" ]; then
        log_warn "No balancer mode selected yet."
        return 1
    fi

    if [ ! -f "$BALANCER_DIR/nodes.list" ] || [ ! -s "$BALANCER_DIR/nodes.list" ]; then
        log_warn "No nodes selected for balancing."
        return 1
    fi

    local mode
    mode=$(cat "$BALANCER_DIR/mode")

    log_info "Applying balancer [$mode] to $pw_ver ..."

    case "$pw_ver" in
        passwall2)
            uci set passwall2.@global[0].enabled='1' 2>/dev/null
            uci -q delete passwall2.daypass_balancer
            uci set passwall2.daypass_balancer=global
            uci set passwall2.daypass_balancer.mode="$mode"
            uci set passwall2.daypass_balancer.nodes="$(tr '\n' ' ' < "$BALANCER_DIR/nodes.list")"
            uci commit passwall2
            /etc/init.d/passwall2 reload >/dev/null 2>&1 || true
            ;;
        passwall)
            uci set passwall.@global[0].enabled='1' 2>/dev/null
            uci -q delete passwall.daypass_balancer
            uci set passwall.daypass_balancer=global
            uci set passwall.daypass_balancer.mode="$mode"
            uci set passwall.daypass_balancer.nodes="$(tr '\n' ' ' < "$BALANCER_DIR/nodes.list")"
            uci commit passwall
            /etc/init.d/passwall reload >/dev/null 2>&1 || true
            ;;
    esac

    log_success "Balancer settings saved and service reloaded."
    log_info "Note: Full traffic distribution depends on Passwall version capabilities."
}

# ------------------------------------------------------------
# Disable balancer
# ------------------------------------------------------------
disable_balancer() {
    rm -f "$BALANCER_DIR/mode"
    rm -f "$BALANCER_DIR/nodes.list"

    local pw_ver
    pw_ver=$(get_pw_version)

    case "$pw_ver" in
        passwall2)
            uci -q delete passwall2.daypass_balancer
            uci commit passwall2
            /etc/init.d/passwall2 reload >/dev/null 2>&1 || true
            ;;
        passwall)
            uci -q delete passwall.daypass_balancer
            uci commit passwall
            /etc/init.d/passwall reload >/dev/null 2>&1 || true
            ;;
    esac

    log_success "Node Balancer disabled!"
}

# ------------------------------------------------------------
# Main Menu
# ------------------------------------------------------------
node_balancer_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear

        echo "  🧶 Node Load Balancing"
        echo "  ───────────────────────────────────────────────────────────"
        show_balancer_status
        echo
        echo "  💆‍♀️ 1) Select Nodes for Balancing"
        echo "  ⚖️  2) Set Balancing Mode"
        echo "  🔥 3) Apply Balancer to Passwall"
        echo "  🚫 4) Disable Balancer"
        echo "  🚪 0) Back"
        echo "  ───────────────────────────────────────────────────────────"
        echo

        printf "  ⁉️ Select option [0-4] : "
        read -r choice </dev/tty

        case "$choice" in
            1) select_nodes ;;
            2) set_balancer_mode ;;
            3) apply_balancer ;;
            4) disable_balancer ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
        read -r _ </dev/tty
    done
}