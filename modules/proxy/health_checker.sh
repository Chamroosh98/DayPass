#!/bin/sh
# ============================================================
# DayPass - Node Health Checker
# Tests reachability + approximate latency of proxy nodes
# ============================================================

# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------
PROXY_DIR="/etc/daypass/proxy"
CONFIG_DIR="$PROXY_DIR/configs"
HEALTH_DIR="$PROXY_DIR/health"
mkdir -p "$HEALTH_DIR"

# ------------------------------------------------------------
# Extract host and port from share link
# ------------------------------------------------------------
extract_host_port() {
    local link="$1"
    HOST=""
    PORT=""

    # VLESS / Trojan style: protocol://uuid@host:port
    HOST=$(echo "$link" | sed -n 's/.*@\([^:/]*\).*/\1/p' | head -1)
    PORT=$(echo "$link" | sed -n 's/.*@[^:]*:\([0-9]*\).*/\1/p' | head -1)

    # Fallback: protocol://host:port
    if [ -z "$HOST" ]; then
        HOST=$(echo "$link" | sed -n 's/.*\/\/\([^:/]*\).*/\1/p' | head -1)
        PORT=$(echo "$link" | sed -n 's/.*\/\/[^:]*:\([0-9]*\).*/\1/p' | head -1)
    fi

    # Last fallback for some formats
    if [ -z "$PORT" ]; then
        PORT=$(echo "$link" | grep -oE ':[0-9]{2,5}' | head -1 | tr -d ':')
    fi
}

# ------------------------------------------------------------
# Test a single node (TCP + latency)
# ------------------------------------------------------------
test_node() {
    local name="$1"
    local file="$CONFIG_DIR/${name}.json"

    if [ ! -f "$file" ]; then
        log_error "$name → file not found"
        return 1
    fi

    # Skip disabled configs
    local enabled
    enabled=$(jq -r '.enabled // true' "$file" 2>/dev/null)
    if [ "$enabled" = "false" ]; then
        log_warn "$name → disabled (skipped)"
        return 1
    fi

    local share_link
    share_link=$(jq -r '.share_link // empty' "$file" 2>/dev/null)

    if [ -z "$share_link" ]; then
        log_error "$name → no share link"
        return 1
    fi

    extract_host_port "$share_link"

    if [ -z "$HOST" ] || [ -z "$PORT" ]; then
        log_warn "$name → could not parse address"
        return 1
    fi

    # Measure approximate latency using TCP connect
    local start_time end_time latency
    start_time=$(date +%s%N 2>/dev/null || date +%s)

    local reachable=0

    if command -v nc >/dev/null 2>&1; then
        if nc -z -w 3 "$HOST" "$PORT" >/dev/null 2>&1; then
            reachable=1
        fi
    else
        if timeout 3 sh -c "echo > /dev/tcp/$HOST/$PORT" 2>/dev/null; then
            reachable=1
        fi
    fi

    end_time=$(date +%s%N 2>/dev/null || date +%s)

    if [ "$reachable" -eq 1 ]; then
        # Calculate latency in ms if nanoseconds available
        if [ "${#start_time}" -ge 13 ] 2>/dev/null; then
            latency=$(( (end_time - start_time) / 1000000 ))
            log_success "$name → ${HOST}:${PORT}  |  ${latency} ms"
        else
            log_success "$name → ${HOST}:${PORT}  |  Reachable"
        fi
        return 0
    else
        log_error "$name → ${HOST}:${PORT}  |  Unreachable"
        return 1
    fi
}

# ------------------------------------------------------------
# Test all nodes
# ------------------------------------------------------------
test_all_nodes() {
    echo
    echo "  🩺 Testing all nodes ..."
    echo "  ───────────────────────────────────────────────────────────"

    local total=0
    local ok=0
    local skipped=0

    for file in "$CONFIG_DIR"/*.json; do
        [ -f "$file" ] || continue
        name=$(basename "$file" .json)
        total=$((total + 1))

        if test_node "$name"; then
            ok=$((ok + 1))
        else
            # Count disabled separately if needed
            enabled=$(jq -r '.enabled // true' "$file" 2>/dev/null)
            [ "$enabled" = "false" ] && skipped=$((skipped + 1))
        fi
    done

    echo "  ───────────────────────────────────────────────────────────"
    if [ "$skipped" -gt 0 ]; then
        echo "  Result : ${GREEN}$ok${RESET} / $total reachable  ${GRAY}($skipped disabled)${RESET}"
    else
        echo "  Result : ${GREEN}$ok${RESET} / $total nodes are reachable"
    fi
    echo
}

# ------------------------------------------------------------
# Test selected nodes only
# ------------------------------------------------------------
test_selected_nodes() {
    echo
    echo "  📋 Available Configs:"
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
        log_warn "No configs found!"
        return 1
    fi

    echo "  ───────────────────────────────────────────────────────────"
    printf "  💊 Enter node numbers to check (e.g. 1 2 4) : "
    read -r selected </dev/tty

    if [ -z "$selected" ]; then
        log_warn "No selection entered!"
        return 1
    fi

    echo
    echo "  🩺 Testing selected nodes ..."
    echo "  ───────────────────────────────────────────────────────────"

    local idx=1
    for name in $configs; do
        for num in $selected; do
            if [ "$num" = "$idx" ]; then
                test_node "$name"
            fi
        done
        idx=$((idx + 1))
    done

    echo "  ───────────────────────────────────────────────────────────"
}

# ------------------------------------------------------------
# Main Menu
# ------------------------------------------------------------
health_checker_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear

        echo "  🩺 Node Health Checker"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  🔭 1) Check All Nodes"
        echo "  🔬 2) Check Selected Nodes"
        echo "  🚪 0) Back"
        echo "  ───────────────────────────────────────────────────────────"
        echo

        printf "  ⁉️ Select option [0-2] : "
        read -r choice </dev/tty

        case "$choice" in
            1) test_all_nodes ;;
            2) test_selected_nodes ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
        read -r _ </dev/tty
    done
}