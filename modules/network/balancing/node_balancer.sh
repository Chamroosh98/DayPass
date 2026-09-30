#!/bin/sh
# ============================================================
# DayPass - Node Load Balancing
# Probes the active transport engine's nodes and switches to the
# best one per mode (Passwall nodes, WireGuard peers, OpenVPN
# instances, sing-box / Xray outbounds)
# ============================================================

# ------------------------------------------------------------
# Paths
# nodes.list : engine|node_id per line
# ------------------------------------------------------------
PROXY_DIR="/etc/daypass/proxy"
CONFIG_DIR="$PROXY_DIR/configs"
BALANCER_DIR="$PROXY_DIR/balancer"
mkdir -p "$BALANCER_DIR"

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

# Prints the list_nodes line (id|name|proto|host|port|l4) for a node id
_nb_node_line() {
    transport_call "$1" list_nodes 2>/dev/null | awk -F'|' -v id="$2" '$1 == id { print; exit }'
}

_nb_node_name() {
    local line
    line=$(_nb_node_line "$1" "$2")
    if [ -n "$line" ]; then
        echo "$line" | cut -d'|' -f2
    else
        echo "$2"
    fi
}

# Selected node ids for an engine, in saved order
_nb_selected_ids() {
    [ -f "$BALANCER_DIR/nodes.list" ] || return 0
    awk -F'|' -v e="$1" 'NF >= 2 && $1 == e { print $2 }' "$BALANCER_DIR/nodes.list"
}

_nb_legacy_entries() {
    [ -f "$BALANCER_DIR/nodes.list" ] || { echo 0; return; }
    grep -vc '|' "$BALANCER_DIR/nodes.list" 2>/dev/null || true
}

_nb_random() {
    awk -v seed="$(( $(date +%s) + $$ ))" -v n="$1" 'BEGIN { srand(seed); print int(rand() * n) + 1 }'
}

# ------------------------------------------------------------
# Show current balancer status
# ------------------------------------------------------------
show_balancer_status() {
    local mode engine count names id current legacy

    echo "  ⚖️  Current Node Balancer Status"
    echo "  ───────────────────────────────────────────────────────────"

    if [ -f "$BALANCER_DIR/mode" ]; then
        mode=$(cat "$BALANCER_DIR/mode")
        echo "  🫀 Active Mode  : ${GREEN}$mode${RESET}"
    else
        echo "  🫀 Active Mode  : ${GRAY}Disabled${RESET}"
    fi

    engine=$(get_active_engine)

    count=0
    names=""
    if [ "$engine" != "none" ]; then
        while IFS= read -r id <&3; do
            [ -n "$id" ] || continue
            count=$((count + 1))
            names="$names $(_nb_node_name "$engine" "$id")"
        done 3<< EOF
$(_nb_selected_ids "$engine")
EOF
    fi
    echo "  🧠 Active Nodes : $count"
    [ "$count" -gt 0 ] && echo "  📋 Nodes        : ${GRAY}${names# }${RESET}"

    legacy=$(_nb_legacy_entries)
    [ "${legacy:-0}" -gt 0 ] && echo "  ⚠️  ${YELLOW}$legacy old-format entr(ies) ignored - reselect nodes.${RESET}"

    if [ "$engine" = "none" ]; then
        echo "  🛡️  Engine       : ${GRAY}none${RESET}"
    else
        echo "  🛡️  Engine       : ${CYAN}$(transport_engine_label "$engine")${RESET}"
        current=$(transport_call "$engine" active_node 2>/dev/null)
        [ -n "$current" ] && echo "  🎯 Current Node : ${GREEN}$(_nb_node_name "$engine" "$current")${RESET}"
    fi
    echo "  ───────────────────────────────────────────────────────────"
}

# ------------------------------------------------------------
# Select nodes for balancing (from the active engine)
# ------------------------------------------------------------
select_nodes() {
    local engine nodes rc i idx selected num added id name proto host port

    engine=$(_transport_target_engine "") || return 1
    nodes=$(transport_call "$engine" list_nodes 2>/dev/null)
    rc=$?
    if [ "$rc" -eq 3 ]; then
        log_error "Engine [$engine] does not expose switchable nodes."
        return 1
    fi

    if [ -z "$nodes" ]; then
        log_warn "No nodes found in [$(transport_engine_label "$engine")]. Add some nodes first!"
        return 1
    fi

    echo
    echo "  📋 Available Nodes ($(transport_engine_label "$engine")) :"
    echo "  ───────────────────────────────────────────────────────────"

    i=1
    while IFS='|' read -r id name proto host port _; do
        [ -n "$id" ] || continue
        echo "  $i) $name  ${GRAY}($proto $host${port:+:$port})${RESET}"
        i=$((i + 1))
    done << EOF
$nodes
EOF

    echo "  ───────────────────────────────────────────────────────────"
    printf "  🧶 Enter node numbers to include (e.g. 1 3 4) : "
    read -r selected </dev/tty

    if [ -z "$selected" ]; then
        log_warn "No selection entered!"
        return 1
    fi

    : > "$BALANCER_DIR/nodes.list"
    rm -f "$BALANCER_DIR/last_index"

    added=0
    for num in $selected; do
        idx=1
        while IFS='|' read -r id name _; do
            [ -n "$id" ] || continue
            if [ "$num" = "$idx" ]; then
                if ! grep -qxF "$engine|$id" "$BALANCER_DIR/nodes.list"; then
                    echo "$engine|$id" >> "$BALANCER_DIR/nodes.list"
                    log_success "Added : [$name]"
                    added=$((added + 1))
                fi
            fi
            idx=$((idx + 1))
        done << EOF
$nodes
EOF
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
    local mode_choice mode

    while true; do
        echo
        echo "  ⚖️  Select Load Balancing Mode :"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  ⏳ 1) Round-Robin      (distribute equally)"
        echo "  🏓 2) Least Ping       (prefer lowest latency)"
        echo "  👨‍👩‍👧‍👦 3) Failover         (use next only if previous fails)"
        echo "  🤹 4) Random"
        echo "  ───────────────────────────────────────────────────────────"
        printf "  ⁉️ Select mode [1-4] or [h] Help : "
        read -r mode_choice </dev/tty

        case "$mode_choice" in
            h|H)
                if command -v show_help >/dev/null 2>&1; then
                    show_help "proxy_balancer_modes"
                else
                    log_warn "Help module not loaded!"
                    sleep 1
                fi
                continue
                ;;
            1) mode="round-robin" ;;
            2) mode="least-ping" ;;
            3) mode="failover" ;;
            4) mode="random" ;;
            *) log_warn "Invalid mode!"; return 1 ;;
        esac
        break
    done

    echo "$mode" > "$BALANCER_DIR/mode"
    log_success "Balancer mode set to : [$mode]"
}

# ------------------------------------------------------------
# Probe selected nodes
# Writes $BALANCER_DIR/probe.last : id|state|ms|method (selection order)
# ------------------------------------------------------------
probe_nodes() {
    local engine="$1"
    local quiet="${2:-0}"
    local id line name host port l4 total=0 up=0

    : > "$BALANCER_DIR/probe.last"

    while IFS= read -r id <&3; do
        [ -n "$id" ] || continue
        line=$(_nb_node_line "$engine" "$id")
        total=$((total + 1))

        if [ -z "$line" ]; then
            echo "$id|missing||" >> "$BALANCER_DIR/probe.last"
            [ "$quiet" = "1" ] || echo "  ❌ $id  ${GRAY}(no longer in engine config)${RESET}"
            continue
        fi

        name=$(echo "$line" | cut -d'|' -f2)
        host=$(echo "$line" | cut -d'|' -f4)
        port=$(echo "$line" | cut -d'|' -f5)
        l4=$(echo "$line" | cut -d'|' -f6)

        transport_probe "$host" "$port" "$l4"
        echo "$id|$PROBE_STATE|$PROBE_MS|$PROBE_METHOD" >> "$BALANCER_DIR/probe.last"

        [ "$PROBE_STATE" = "down" ] || up=$((up + 1))
        if [ "$quiet" != "1" ]; then
            case "$PROBE_STATE" in
                up)      echo "  ✅ $name  ${GRAY}($host:$port)${RESET}  ${GREEN}${PROBE_MS:-?} ms${RESET} ${GRAY}[$PROBE_METHOD]${RESET}" ;;
                unknown) echo "  ❔ $name  ${GRAY}($host:$port)${RESET}  ${YELLOW}no ICMP reply (UDP not verifiable)${RESET}" ;;
                *)       echo "  ❌ $name  ${GRAY}($host:$port)${RESET}  ${RED}unreachable${RESET} ${GRAY}[$PROBE_METHOD]${RESET}" ;;
            esac
        fi
    done 3<< EOF
$(_nb_selected_ids "$engine")
EOF

    [ "$quiet" = "1" ] || log_info "$up / $total node(s) reachable."
    [ "$total" -gt 0 ]
}

probe_selected_nodes() {
    local engine
    engine=$(_transport_target_engine "") || return 1

    if [ -z "$(_nb_selected_ids "$engine")" ]; then
        log_warn "No nodes selected for balancing."
        return 1
    fi

    log_info "Probing nodes of [$(transport_engine_label "$engine")] ..."
    probe_nodes "$engine"
}

# Picks a node id from probe.last for the mode. up nodes are preferred, unknown
# (UDP without ICMP) nodes are used only when no node is confirmed up.
_nb_pick() {
    local mode="$1"
    local usable n pick last

    usable=$(awk -F'|' '$2 == "up" { print $1 }' "$BALANCER_DIR/probe.last")
    [ -z "$usable" ] && usable=$(awk -F'|' '$2 == "unknown" { print $1 }' "$BALANCER_DIR/probe.last")
    [ -n "$usable" ] || return 1

    n=$(echo "$usable" | wc -l)

    case "$mode" in
        failover)
            echo "$usable" | head -n 1
            ;;
        least-ping)
            pick=$(awk -F'|' '$2 == "up" && $3 != "" { if (best == "" || $3 + 0 < best) { best = $3 + 0; id = $1 } } END { print id }' "$BALANCER_DIR/probe.last")
            [ -z "$pick" ] && pick=$(echo "$usable" | head -n 1)
            echo "$pick"
            ;;
        round-robin)
            last=$(cat "$BALANCER_DIR/last_index" 2>/dev/null)
            case "$last" in ''|*[!0-9]*) last=0 ;; esac
            pick=$(( last % n + 1 ))
            echo "$pick" > "$BALANCER_DIR/last_index"
            echo "$usable" | sed -n "${pick}p"
            ;;
        random)
            echo "$usable" | sed -n "$(_nb_random "$n")p"
            ;;
        *)
            return 1
            ;;
    esac
}

# ------------------------------------------------------------
# Apply balancer: probe selected nodes and switch the active engine
# ------------------------------------------------------------
apply_balancer() {
    local engine mode chosen current name

    engine=$(_transport_target_engine "") || return 1

    if [ ! -f "$BALANCER_DIR/mode" ]; then
        log_warn "No balancer mode selected yet."
        return 1
    fi

    if [ -z "$(_nb_selected_ids "$engine")" ]; then
        if [ -s "$BALANCER_DIR/nodes.list" ]; then
            log_warn "Selected nodes do not belong to [$engine] (or use the old format). Select nodes again."
        else
            log_warn "No nodes selected for balancing."
        fi
        return 1
    fi

    if ! transport_has_hook "$engine" select_node; then
        log_error "Engine [$engine] does not support node switching."
        return 1
    fi

    transport_call "$engine" cleanup >/dev/null 2>&1

    mode=$(cat "$BALANCER_DIR/mode")
    log_info "Applying balancer [$mode] to $engine ..."

    probe_nodes "$engine" || return 1

    if ! chosen=$(_nb_pick "$mode") || [ -z "$chosen" ]; then
        log_error "No reachable node among the selected nodes. Active node unchanged."
        return 1
    fi

    name=$(_nb_node_name "$engine" "$chosen")
    current=$(transport_call "$engine" active_node 2>/dev/null)

    if [ "$chosen" = "$current" ]; then
        echo "$chosen" > "$BALANCER_DIR/current"
        log_success "Node [$name] is already active on $engine."
        return 0
    fi

    if ! transport_call "$engine" select_node "$chosen"; then
        log_error "Failed to switch $engine to node [$name]!"
        return 1
    fi

    echo "$chosen" > "$BALANCER_DIR/current"
    log_success "Switched $engine to node [$name] ($mode)."
}

# ------------------------------------------------------------
# Disable balancer
# ------------------------------------------------------------
disable_balancer() {
    local engine

    rm -f "$BALANCER_DIR/mode" "$BALANCER_DIR/nodes.list" "$BALANCER_DIR/last_index" \
        "$BALANCER_DIR/probe.last" "$BALANCER_DIR/current"

    engine=$(get_active_engine)
    [ "$engine" != "none" ] && transport_call "$engine" cleanup >/dev/null 2>&1

    log_success "Node Balancer disabled!"
}

# ------------------------------------------------------------
# Main Menu
# ------------------------------------------------------------
node_balancer_menu() {
    local HELP_MODULE_ID="proxy_balancer"

    while true; do
        render_persistent_header

        echo "  🧶 Node Load Balancing"
        echo "  ───────────────────────────────────────────────────────────"
        show_balancer_status
        echo
        echo "  💆‍♀️ 1) Select Nodes for Balancing"
        echo "  ⚖️  2) Set Balancing Mode"
        echo "  🔥 3) Apply Balancer (probe & switch node)"
        echo "  🚫 4) Disable Balancer"
        echo "  🏓 5) Probe Selected Nodes"
        ui_nav_footer

        ui_prompt 5
        choice="$UI_CHOICE"

        case "$choice" in
            1) select_nodes ;;
            2) set_balancer_mode ;;
            3) apply_balancer ;;
            4) disable_balancer ;;
            5) probe_selected_nodes ;;
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
