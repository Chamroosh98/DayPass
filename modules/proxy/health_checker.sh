#!/bin/sh
# ============================================================
# Tests latency and availability of proxy configs
# ============================================================

# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------
PROXY_DIR="/etc/daypass/proxy"
CONFIG_DIR="$PROXY_DIR/configs"
HEALTH_DIR="$PROXY_DIR/health"
mkdir -p "$HEALTH_DIR"

# ------------------------------------------------------------
# Test a single node (simple TCP/HTTP check)
# ------------------------------------------------------------

test_node() {
    local name="$1"
    local file="$CONFIG_DIR/${name}.json"

    if [ ! -f "$file" ]; then
        log_error "$name (file not found)"
        return 1
    fi

    local share_link
    share_link=$(jq -r '.share_link // empty' "$file" 2>/dev/null)

    if [ -z "$share_link" ]; then
        log_error "$name (no share link)"
        return 1
    fi

    # Extract host and port (basic parser)
    local host port
    host=$(echo "$share_link" | sed -n 's/.*@\([^:]*\):.*/\1/p' | head -1)
    port=$(echo "$share_link" | sed -n 's/.*:\([0-9]*\).*/\1/p' | head -1)

    # Fallback for some formats
    if [ -z "$host" ]; then
        host=$(echo "$share_link" | sed -n 's/.*\/\/\([^:]*\):.*/\1/p' | head -1)
    fi

    if [ -z "$host" ] || [ -z "$port" ]; then
        log_warn "$name (could not parse address)"
        return 1
    fi

    # TCP connectivity test
    if command -v nc >/dev/null 2>&1; then
        if nc -z -w 3 "$host" "$port" >/dev/null 2>&1; then
            log_success "$name (${host}:${port}) - Reachable"
            return 0
        else
            log_error "$name (${host}:${port}) - Unreachable"
            return 1
        fi
    else
        if timeout 3 sh -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
            log_success "$name (${host}:${port}) - Reachable"
            return 0
        else
            log_error "$name (${host}:${port}) - Unreachable"
            return 1
        fi
    fi
}

# ------------------------------------------------------------
# Test all nodes
# ------------------------------------------------------------
test_all_nodes() {
    echo
    echo "  🩺 Testing all nodes ..."

    local total=0
    local ok=0

    for file in "$CONFIG_DIR"/*.json; do
        [ -f "$file" ] || continue
        name=$(basename "$file" .json)
        total=$((total + 1))

        if test_node "$name"; then
            ok=$((ok + 1))
        fi
    done

    echo "  Result : ${GREEN}$ok${RESET} / $total nodes are reachable"
    echo
}

# ------------------------------------------------------------
# Test selected nodes only
# ------------------------------------------------------------
test_selected_nodes() {
    echo
    echo "  📋 Available Configs:"
    local configs=""
    local i=1

    for file in "$CONFIG_DIR"/*.json; do
        [ -f "$file" ] || continue
        name=$(basename "$file" .json)
        echo "  $i) $name"
        configs="$configs $name"
        i=$((i + 1))
    done

    if [ "$i" -eq 1 ]; then
        log_warn "No configs found."
        return 1
    fi

    echo
    printf "  💊 Enter node numbers to check (e.g. 1 2 4) : "
    read -r selected </dev/tty

    echo
    echo "  🩺 Checking selected nodes ..."

    local idx=1
    for name in $configs; do
        for num in $selected; do
            if [ "$num" = "$idx" ]; then
                test_node "$name"
            fi
        done
        idx=$((idx + 1))
    done
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
        echo "  ⚰️ 0) Back"
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

        printf "\n  ${GRAY}Press ENTER ...${RESET}"
        read -r _ </dev/tty
    done
}