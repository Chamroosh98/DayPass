#!/bin/sh

# ------------------------------------------------------------
# Interactive flow: select config -> scan -> apply
# ------------------------------------------------------------
clean_ip_for_config() {
    echo
    echo "  📋 Available Configs :"
    echo "  ───────────────────────────────────────────────────────────"

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
        log_warn "No configs found!"
        return 1
    fi

    echo "  ───────────────────────────────────────────────────────────"
    printf "  🎯 Select config number : "
    read -r choice </dev/tty

    local idx=1
    local conf_name=""
    for name in $configs; do
        if [ "$choice" = "$idx" ]; then
            conf_name="$name"
            break
        fi
        idx=$((idx + 1))
    done

    if [ -z "$conf_name" ]; then
        log_warn "Invalid selection!"
        return 1
    fi

    local file="$CONFIG_DIR/${conf_name}.json"
    local share_link port old_addr core
    share_link=$(jq -r '.share_link // empty' "$file" 2>/dev/null)
    port=$(extract_port_from_link "$share_link")
    old_addr=$(extract_address_from_link "$share_link")
    core=$(detect_proxy_core)

    echo
    log_info "Config   : $conf_name"
    log_info "Address  : ${old_addr:-unknown}"
    log_info "Port     : $port"
    log_info "Core     : $core"
    echo

    echo "  🧪 Test mode :"
    echo "  👼🏻 1) Basic TCP only"
    echo "  👩🏻‍🔬 2) Advanced (Xray/Sing-box aware - placeholder)"
    printf "  ⁉️ Select mode [1-2] (default: 1) : "
    read -r mode_choice </dev/tty

    local mode="basic"
    [ "$mode_choice" = "2" ] && mode="advanced"

    scan_candidate_ips "$port" "$share_link" "$mode"

    if [ ! -s "$RESULT_FILE" ]; then
        log_warn "No reachable clean IPs found!"
        return 1
    fi

    printf "  🧼 Enter Clean IP to apply (or empty to cancel) : "
    read -r clean_ip </dev/tty
    [ -z "$clean_ip" ] && { log_info "Cancelled."; return 0; }

    apply_clean_ip_to_config "$conf_name" "$clean_ip"

    printf "  🫸🏻 Push updated config to Passwall now? [y/N] : "
    read -r push_now </dev/tty
    case "$push_now" in
        y|Y)
            if command -v push_config_to_passwall >/dev/null 2>&1; then
                push_config_to_passwall "$conf_name"
            else
                log_warn "push_config_to_passwall() not found!"
            fi
            ;;
    esac
}

# ------------------------------------------------------------
# Main Cloudflare Clean IP Menu
# ------------------------------------------------------------
clean_ip_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear

        local core
        core=$(detect_proxy_core)

        echo "  🧼 Clean IP Manager (Cloudflare)"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  🛡️ Proxy Core : ${CYAN}$core${RESET}"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  🕵🏻‍♀️ 1) Find Clean IP for a Config"
        echo "  👫🏻 2) Show / Edit Candidate IP List"
        echo "  📺 3) Show Last Scan Results"
        echo "  🚪 0) Back"
        echo "  ───────────────────────────────────────────────────────────"
        echo

        printf "  ⁉️ Select option [0-3] : "
        read -r choice </dev/tty

        case "$choice" in
            1) clean_ip_for_config ;;
            2) edit_candidates ;;
            3)
                if [ -f "$RESULT_FILE" ] && [ -s "$RESULT_FILE" ]; then
                    echo
                    echo "  🏆 Last Results :"
                    echo "  ───────────────────────────────────────────────────────────"
                    awk '{printf "   - %s  (%s ms)\n", $2, $1}' "$RESULT_FILE"
                    echo "  ───────────────────────────────────────────────────────────"
                else
                    log_warn "No scan results yet!"
                fi
                ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
        read -r _ </dev/tty
    done
}