#!/bin/sh

# Tests reachability + approximate latency of proxy nodes
# ============================================================


# Paths

PROXY_DIR="/etc/daypass/proxy"
CONFIG_DIR="$PROXY_DIR/configs"
HEALTH_DIR="$PROXY_DIR/health"
mkdir -p "$HEALTH_DIR"


# True unless the config is explicitly disabled.
# jq's "//" treats false as absent, so '.enabled // true' reads a disabled
# config as enabled; test the value itself instead.

_hc_enabled() {
    [ "$(jq -r 'if .enabled == false then "false" else "true" end' "$1" 2>/dev/null)" != "false" ]
}


# Extract host, port and L4 protocol from share link

extract_host_port() {
    local link="$1"
    HOST=""
    PORT=""
    L4="tcp"

    # The transport bridge's parser understands every scheme DayPass supports
    if command -v parse_share_link >/dev/null 2>&1 && parse_share_link "$link"; then
        HOST="$PARSED_ADDRESS"
        PORT="$PARSED_PORT"
        L4="${PARSED_L4:-tcp}"
        [ -n "$HOST" ] && [ -n "$PORT" ] && return 0
    fi

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


# Test a single node (TCP + latency)

test_node() {
    local name="$1"
    local file="$CONFIG_DIR/${name}.json"

    if [ ! -f "$file" ]; then
        log_error "$name → file not found"
        return 1
    fi

    # Skip disabled configs
    if ! _hc_enabled "$file"; then
        log_warn "$name → disabled (skipped)"
        return 1
    fi

    local share_link
    share_link=$(jq -r '.share_link // empty' "$file" 2>/dev/null)

    if [ -z "$share_link" ]; then
        log_error "[$name] → no share link"
        return 1
    fi

    extract_host_port "$share_link"

    if [ -z "$HOST" ] || [ -z "$PORT" ]; then
        log_warn "[$name] → could not parse address"
        return 1
    fi

    local state="down"
    local latency=""
    local start_time end_time

    if command -v transport_probe >/dev/null 2>&1; then
        # Shared probe: knows whether this busybox nc supports -z and reports
        # UDP endpoints as unknown instead of unreachable.
        transport_probe "$HOST" "$PORT" "${L4:-tcp}"
        state="$PROBE_STATE"
        latency="$PROBE_MS"
    else
        start_time=$(date +%s%N 2>/dev/null || date +%s)

        if command -v nc >/dev/null 2>&1; then
            # busybox nc has no -z: connect with stdin closed instead
            if nc -w 3 "$HOST" "$PORT" </dev/null >/dev/null 2>&1; then
                state="up"
            fi
        elif timeout 3 sh -c "echo > /dev/tcp/$HOST/$PORT" 2>/dev/null; then
            state="up"
        fi

        end_time=$(date +%s%N 2>/dev/null || date +%s)
        if [ "$state" = "up" ] && [ "${#start_time}" -ge 13 ] 2>/dev/null; then
            latency=$(( (end_time - start_time) / 1000000 ))
        fi
    fi

    case "$state" in
        up)
            if [ -n "$latency" ]; then
                log_success "$name → ${HOST}:${PORT}  |  ${latency} ms"
            else
                log_success "$name → ${HOST}:${PORT}  |  Reachable"
            fi
            return 0
            ;;
        unknown)
            log_warn "$name → ${HOST}:${PORT}  |  UDP endpoint, no ICMP reply (unknown)"
            return 1
            ;;
    esac

    log_error "$name → ${HOST}:${PORT}  |  Unreachable"
    return 1
}


# Test all nodes

test_all_nodes() {
    echo
    echo "  🩺 Checking all nodes ..."
    ui_divider

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
            _hc_enabled "$file" || skipped=$((skipped + 1))
        fi
    done

    ui_divider
    if [ "$skipped" -gt 0 ]; then
        echo "  Result : ${GREEN}$ok${RESET} / $total reachable  ${GRAY}($skipped disabled)${RESET}"
    else
        echo "  Result : ${GREEN}$ok${RESET} / $total nodes are reachable"
    fi
    echo
}


# Test selected nodes only

test_selected_nodes() {
    echo
    echo "  📋 Available Configs :"
    ui_divider

    local configs=""
    local i=1

    for file in "$CONFIG_DIR"/*.json; do
        [ -f "$file" ] || continue
        name=$(basename "$file" .json)
        protocol=$(jq -r '.protocol // "unknown"' "$file" 2>/dev/null)

        if _hc_enabled "$file"; then
            echo "  $i) $name  ${GRAY}($protocol)${RESET}"
        else
            echo "  $i) $name  ${GRAY}($protocol) [DISABLED]${RESET}"
        fi

        configs="$configs $name"
        i=$((i + 1))
    done

    if [ "$i" -eq 1 ]; then
        log_warn "No configs found!"
        return 1
    fi

    ui_divider
    printf "  💊 Enter node numbers to check (e.g. 1 2 4) : "
    read -r selected </dev/tty

    if [ -z "$selected" ]; then
        log_warn "No selection entered!"
        return 1
    fi

    echo
    echo "  🩺 Checking selected nodes ..."
    ui_divider

    local idx=1
    for name in $configs; do
        for num in $selected; do
            if [ "$num" = "$idx" ]; then
                test_node "$name"
            fi
        done
        idx=$((idx + 1))
    done

    ui_divider
}


# Main Menu

health_checker_menu() {
    local HELP_MODULE_ID="proxy_health_checker"

    while true; do
        render_persistent_header

        echo "  🩺 Node Health Checker"
        ui_divider
        echo "  🔭 1) Check All Nodes"
        echo "  🔬 2) Check Selected Nodes"
        ui_nav_footer

        ui_prompt 2
        choice="$UI_CHOICE"

        case "$choice" in
            1) test_all_nodes ;;
            2) test_selected_nodes ;;
            q|Q) daypass_quit ;;
            h|H)
                if command -v show_help >/dev/null 2>&1; then
                    show_help "$HELP_MODULE_ID"
                else
                    log_warn "Help module not loaded!"
                    sleep 1
                fi
                continue
                ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
        read -r _ </dev/tty || daypass_quit
    done
}