#!/bin/sh
# ============================================================
# DayPass - Proxy & Tunnel Engine Manager
# Lists every transport engine known to the transport bridge
# (Passwall, Passwall2, sing-box, Xray, WireGuard, OpenVPN)
# and controls the installed ones.
# ============================================================

# Package profile that provides an engine (Package Profiles menu entry)
_pe_install_hint() {
    case "$1" in
        wireguard|openvpn) echo "Package Profiles -> 2 (VPN & Tunnels)" ;;
        *)                 echo "Package Profiles -> 1 (Proxy & Evasion Cores)" ;;
    esac
}

# Prints the engine table; numbers follow TRANSPORT_ENGINES order
show_transport_status() {
    local active engine i state intercept

    active=$(get_active_engine)
    ui_title "🚀 Transport Engines"

    i=1
    for engine in $TRANSPORT_ENGINES; do
        if ! transport_call "$engine" detect >/dev/null 2>&1; then
            printf "  ${GRAY}%s) %-24s not installed${RESET}\n" "$i" "$(transport_engine_label "$engine")"
            i=$((i + 1))
            continue
        fi

        intercept=$(transport_call "$engine" interception)
        if status_engine "$engine" >/dev/null 2>&1; then
            state="${GREEN}running${RESET}"
        else
            state="${YELLOW}stopped${RESET}"
        fi

        if [ "$engine" = "$active" ]; then
            printf "  %s) ${BOLD}%-24s${RESET} %b  ${GRAY}[%s]${RESET} ${GREEN}◀ active${RESET}\n" \
                "$i" "$(transport_engine_label "$engine")" "$state" "$intercept"
        else
            printf "  %s) %-24s %b  ${GRAY}[%s]${RESET}\n" \
                "$i" "$(transport_engine_label "$engine")" "$state" "$intercept"
        fi
        i=$((i + 1))
    done

    [ "$active" = "none" ] && echo "  ${GRAY}No supported engine detected.${RESET}"
    echo "  ───────────────────────────────────────────────────────────"
}

# Makes $1 the active engine, offers to stop the previous one and
# re-applies the saved routing mode to the new engine.
proxy_engine_activate() {
    local engine="$1"
    local previous

    previous=$(get_active_engine)
    set_active_engine "$engine" || return 1
    [ "$previous" = "$engine" ] && return 0

    if [ "$previous" != "none" ] && status_engine "$previous" >/dev/null 2>&1; then
        ui_read "Stop previous engine [$previous] to avoid double interception? [Y/n]"
        case "$UI_CHOICE" in
            n|N) log_warn "Both engines may intercept traffic until one is stopped." ;;
            q|Q) daypass_quit ;;
            *)   stop_engine "$previous" ;;
        esac
    fi

    if command -v routing_reapply >/dev/null 2>&1; then
        routing_reapply "$engine"
    fi
}

proxy_engine_show_nodes() {
    local engine="$1"
    local nodes current id name proto host port

    nodes=$(transport_call "$engine" list_nodes 2>/dev/null)
    if [ -z "$nodes" ]; then
        log_warn "No nodes / endpoints found in [$(transport_engine_label "$engine")]."
        return 0
    fi

    current=$(transport_call "$engine" active_node 2>/dev/null)
    echo
    ui_title "🧶 Nodes of $(transport_engine_label "$engine")"
    while IFS='|' read -r id name proto host port _; do
        [ -n "$id" ] || continue
        if [ "$id" = "$current" ]; then
            printf "  ${GREEN}◀${RESET} %s  ${GRAY}(%s %s%s)${RESET} ${GREEN}active${RESET}\n" "$name" "$proto" "$host" "${port:+:$port}"
        else
            printf "    %s  ${GRAY}(%s %s%s)${RESET}\n" "$name" "$proto" "$host" "${port:+:$port}"
        fi
    done << EOF
$nodes
EOF
    echo "  ───────────────────────────────────────────────────────────"
}

# Actions for one installed engine
proxy_engine_actions_menu() {
    local engine="$1"
    local HELP_MODULE_ID="proxy_transport"
    local label active status detail

    label=$(transport_engine_label "$engine")

    while true; do
        render_persistent_header

        active=$(get_active_engine)
        status=$(status_engine "$engine" 2>/dev/null)
        detail=$(transport_call "$engine" describe 2>/dev/null)

        ui_title "🛡️ $label"
        printf "  ⚙️ Status       : %s\n" "${status#*: }"
        printf "  🧭 Interception : %s\n" "$(transport_call "$engine" interception)"
        [ -n "$detail" ] && printf "  📄 Details      : ${GRAY}%s${RESET}\n" "$detail"
        if [ "$engine" = "$active" ]; then
            printf "  🎯 Active       : ${GREEN}yes${RESET}\n"
        else
            printf "  🎯 Active       : ${GRAY}no (active: %s)${RESET}\n" "$active"
        fi
        echo "  ───────────────────────────────────────────────────────────"
        echo "  🎯 1) Set as Active Engine"
        echo "  ▶️  2) Start"
        echo "  ⏹️  3) Stop"
        echo "  🔁 4) Restart"
        echo "  🔄 5) Reload Rules"
        echo "  🧶 6) Show Nodes / Endpoints"
        echo "  ───────────────────────────────────────────────────────────"
        ui_nav_footer

        ui_prompt 6

        case "$UI_CHOICE" in
            1) proxy_engine_activate "$engine" ;;
            2) start_engine "$engine" ;;
            3) stop_engine "$engine" ;;
            4) stop_engine "$engine"; start_engine "$engine" ;;
            5) reload_rules "$engine" ;;
            6) proxy_engine_show_nodes "$engine" ;;
            0) return 0 ;;
            *)
                ui_nav_common "$UI_CHOICE" "$HELP_MODULE_ID" && continue
                log_warn "Invalid option!"
                sleep 1
                continue
                ;;
        esac

        ui_pause
    done
}

proxy_engine_menu() {
    local HELP_MODULE_ID="proxy_transport"
    local count engine i picked

    if ! command -v get_active_engine >/dev/null 2>&1; then
        log_error "Transport bridge module not found!"
        sleep 2
        return 1
    fi

    set -- $TRANSPORT_ENGINES
    count=$#

    while true; do
        render_persistent_header
        show_transport_status
        echo "  ${GRAY}Pick an engine number to manage it.${RESET}"
        ui_nav_footer

        ui_prompt "$count"

        case "$UI_CHOICE" in
            0) return 0 ;;
            ''|*[!0-9]*)
                ui_nav_common "$UI_CHOICE" "$HELP_MODULE_ID" && continue
                log_warn "Invalid option!"
                sleep 1
                continue
                ;;
        esac

        picked=""
        i=1
        for engine in $TRANSPORT_ENGINES; do
            [ "$UI_CHOICE" = "$i" ] && picked="$engine"
            i=$((i + 1))
        done

        if [ -z "$picked" ]; then
            log_warn "Invalid option!"
            sleep 1
        elif ! transport_call "$picked" detect >/dev/null 2>&1; then
            log_warn "$(transport_engine_label "$picked") is not installed. Install it from : $(_pe_install_hint "$picked")"
            ui_pause
        else
            proxy_engine_actions_menu "$picked"
        fi
    done
}
