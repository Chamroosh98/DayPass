#!/bin/sh
# ============================================================
# Load balance traffic between multiple proxy configs
# ============================================================

# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------
PROXY_DIR="/etc/daypass/proxy"
CONFIG_DIR="$PROXY_DIR/configs"
BALANCER_DIR="$PROXY_DIR/balancer"
mkdir -p "$BALANCER_DIR"

# ------------------------------------------------------------
# Show current balancer status
# ------------------------------------------------------------
show_balancer_status() {
    echo "  ⚖️ Current Node Balancer Status"

    if [ -f "$BALANCER_DIR/mode" ]; then
        mode=$(cat "$BALANCER_DIR/mode")
        echo "  🫀 Active Mode : ${GREEN}$mode${RESET}"
    else
        echo "  🫀 Active Mode : ${GRAY}Disabled${RESET}"
    fi

    if [ -f "$BALANCER_DIR/nodes.list" ]; then
        count=$(wc -l < "$BALANCER_DIR/nodes.list" 2>/dev/null || echo 0)
        echo "  🧠 Active Nodes : $count"
    else
        echo "  🧠 Active Nodes : 0"
    fi

    echo ""
}

# ------------------------------------------------------------
# Select nodes for balancing
# ------------------------------------------------------------
select_nodes() {
    echo
    echo "  📋 Available Configs :"

    local configs=""
    local i=1
    for file in "$CONFIG_DIR"/*.json; do
        [ -f "$file" ] || continue
        name=$(basename "$file" .json)
        protocol=$(jq -r '.protocol // "unknown"' "$file" 2>/dev/null)
        echo "  $i) $name  ${GRAY}($protocol)${RESET}"
        configs="$configs $name"
        i=$((i + 1))
    done

    if [ "$i" -eq 1 ]; then
        log_warn "No configs found. Add some configs first!"
        return 1
    fi

    echo
    printf "  🧶 Enter node numbers to include (e.g. 1 3 4) : "
    read -r selected </dev/tty

    > "$BALANCER_DIR/nodes.list"   # clear previous list

    local idx=1
    for name in $configs; do
        for num in $selected; do
            if [ "$num" = "$idx" ]; then
                echo "$name" >> "$BALANCER_DIR/nodes.list"
                log_success "Added : [$name]"
            fi
        done
        idx=$((idx + 1))
    done
}

# ------------------------------------------------------------
# Set balancing mode
# ------------------------------------------------------------
set_balancer_mode() {
    echo
    echo "  ⚖️ Select Load Balancing Mode :"
    echo "  ⏳ 1) Round-Robin      (distribute equally)"
    echo "  🏓 2) Least Ping       (prefer lowest latency)"
    echo "  👨‍👨‍👧‍👧 3) Failover         (use next only if previous fails)"
    echo "  🤹🏻 4) Random"
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
# Disable balancer
# ------------------------------------------------------------
disable_balancer() {
    rm -f "$BALANCER_DIR/mode"
    rm -f "$BALANCER_DIR/nodes.list"
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
        echo "  💆🏻‍♀️ 1) Select Nodes for Balancing"
        echo "  ⚖️ 2) Set Balancing Mode"
        echo "  🧑🏻‍🦽‍➡️ 3) Disable Balancer"
        echo "  🚪 0) Back"
        echo "  ───────────────────────────────────────────────────────────"
        echo

        printf "  ⁉️ Select option [0-3] : "
        read -r choice </dev/tty

        case "$choice" in
            1) select_nodes ;;
            2) set_balancer_mode ;;
            3) disable_balancer ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press [Enter] to continue ... ${RESET}"
        read -r _ </dev/tty
    done
}