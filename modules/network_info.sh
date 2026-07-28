#!/bin/sh

# Map country codes to custom emoji flags
country_flag()
{
    case "$1" in
        IR) echo "🦁☀️" ;;
        AZ) echo "🇦🇿" ;;
        DE) echo "🇩🇪" ;;
        US) echo "🇺🇸" ;;
        NL) echo "🇳🇱" ;;
        RU) echo "🇷🇺" ;;
        CN) echo "🇨🇳" ;;
        JP) echo "🇯🇵" ;;
        SG) echo "🇸🇬" ;;
        TR) echo "🇹🇷" ;;
        GB) echo "🇬🇧" ;;
        FR) echo "🇫🇷" ;;
        FI) echo "🇫🇮" ;;
        SE) echo "🇸🇪" ;;
        PL) echo "🇵🇱" ;;
        *)  echo "🌐" ;;
    esac
}

# Fetch public IP details using cascading fallback providers
fetch_ip_data()
{
    # Provider 1: ipwho.is
    NETWORK_JSON="$($FETCH_CMD https://ipwho.is/ 2>/dev/null || true)"
    if [ -n "$NETWORK_JSON" ] && echo "$NETWORK_JSON" | grep -q '"success":true'; then
        echo "$NETWORK_JSON" | jq -r '"true|\(.ip // "")|\(.country // "")|\(.country_code // "")|\(.flag.emoji // "")|\(.city // "")|\(.connection.isp // "")|\(.connection.asn // "")"' 2>/dev/null || echo "false|||||||"
        return 0
    fi

    # Provider 2: ipapi.co
    NETWORK_JSON="$($FETCH_CMD https://ipapi.co/json/ 2>/dev/null || true)"
    if [ -n "$NETWORK_JSON" ] && echo "$NETWORK_JSON" | grep -q '"ip"'; then
        echo "$NETWORK_JSON" | jq -r '"true|\(.ip // "")|\(.country_name // "")|\(.country_code // "")||\(.city // "")|\(.org // "")|\(.asn // "")"' 2>/dev/null || echo "false|||||||"
        return 0
    fi
    
    # Provider 3: ifconfig.co
    NETWORK_JSON="$($FETCH_CMD https://ifconfig.co/json 2>/dev/null || true)"
    if [ -n "$NETWORK_JSON" ] && echo "$NETWORK_JSON" | grep -q '"ip"'; then
        echo "$NETWORK_JSON" | jq -r '"true|\(.ip // "")|\(.country // "")|\(.country_iso // "")||\(.city // "")|\(.asn_org // "")|\(.asn // "")"' 2>/dev/null || echo "false|||||||"
        return 0
    fi

    echo "false|||||||"
}

# Render full network information panel
show_full_network_info()
{
    # Render persistent header if function is available
    if command -v render_persistent_header >/dev/null 2>&1; then
        render_persistent_header
    else
        clear
        [ -n "$(command -v show_banner)" ] && show_banner
    fi
    
    printf "\n   ${CYAN:-}🌐 Network Diagnostics & Information${RESET:-}\n"
    printf "   ${GRAY:-}─────────────────────────────────────────${RESET:-}\n"

    # Determine available HTTP client engine
    if command -v curl >/dev/null 2>&1; then
        FETCH_CMD="curl -fsS --connect-timeout 2 --max-time 4"
    elif command -v uclient-fetch >/dev/null 2>&1; then
        FETCH_CMD="uclient-fetch -q -T 4 -O-"
    elif command -v wget >/dev/null 2>&1; then
        FETCH_CMD="wget -q -T 4 -O-"
    else
        printf "   ${YELLOW:-}⚠️  curl / uclient-fetch / wget unavailable!${RESET:-}\n\n"
        return 0
    fi

    # Ensure JSON parser dependency is met
    if ! command -v jq >/dev/null 2>&1; then
        PKG_CMD="${PKG_MANAGER:-opkg} install jq"
        printf "   ${YELLOW:-}⚠️  jq is missing! Install via: %s${RESET:-}\n\n" "$PKG_CMD"
        return 0
    fi

    printf "   ${GRAY:-}Fetching network details ...${RESET:-}\r"
    PARSED_DATA="$(fetch_ip_data 2>/dev/null || echo "false|||||||")"

    IFS='|' read -r SUCCESS PUBLIC_IP COUNTRY COUNTRY_CODE FLAG CITY ISP ASN <<EOF
$PARSED_DATA
EOF

    if [ "${SUCCESS:-false}" != "true" ] || [ -z "$PUBLIC_IP" ]; then
        printf "   ${GRAY:-}Public IP :${RESET:-} ${RED:-}Offline / Disconnected${RESET:-}\n"
        printf "   ${GRAY:-}Status    :${RESET:-} ${YELLOW:-}No Internet Access${RESET:-}\n"
    else
        if [ "$COUNTRY_CODE" = "IR" ]; then
            FLAG="🦁☀️"
        elif [ -z "$FLAG" ]; then
            FLAG="$(country_flag "$COUNTRY_CODE")"
        fi

        CITY_STR=""
        [ -n "$CITY" ] && CITY_STR=" ${GRAY:-}($CITY)${RESET:-}"

        printf "   Public IP   : %s\n" "$PUBLIC_IP"
        printf "   Country     : %s %s%s\n" "$FLAG" "$COUNTRY" "${CITY_STR}"
        [ -n "$ISP" ] && printf "   ISP         : %s\n" "$ISP"
        [ -n "$ASN" ] && printf "   ASN         : %s%s%s\n" "${GRAY:-}" "$ASN" "${RESET:-}"
    fi

    printf "   ${GRAY:-}─────────────────────────────────────────${RESET:-}\n\n"
}

# Real-time WAN bandwidth monitoring
show_live_speed() {
    # Auto-detect active primary network interface across OpenWrt v24/v25
    IFACE=$(uci -q get network.wan.device || uci -q get network.wan.ifname || echo "")
    
    if [ -z "$IFACE" ] || [ ! -d "/sys/class/net/$IFACE" ]; then
        # Fallback search for default route interface or common WAN defaults
        IFACE="$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')"
        [ -z "$IFACE" ] || [ ! -d "/sys/class/net/$IFACE" ] && IFACE="eth0"
    fi

    echo
    MSG="Monitoring live speed on [${CYAN:-}$IFACE${RESET:-}] ${GRAY:-}(Press Ctrl+C to stop)...${RESET:-}"
    if command -v log_info >/dev/null 2>&1; then
        log_info "$MSG"
    else
        echo "$MSG"
    fi
    echo

    RX_PREV=$(cat "/sys/class/net/$IFACE/statistics/rx_bytes" 2>/dev/null || echo 0)
    TX_PREV=$(cat "/sys/class/net/$IFACE/statistics/tx_bytes" 2>/dev/null || echo 0)

    # Trap signal to restore terminal formatting on SIGINT (Ctrl+C)
    trap 'echo ""; trap - INT; return 0' INT

    while true; do
        sleep 1
        RX_NOW=$(cat "/sys/class/net/$IFACE/statistics/rx_bytes" 2>/dev/null || echo 0)
        TX_NOW=$(cat "/sys/class/net/$IFACE/statistics/tx_bytes" 2>/dev/null || echo 0)

        RX_SPEED=$(( (RX_NOW - RX_PREV) / 1024 ))
        TX_SPEED=$(( (TX_NOW - TX_PREV) / 1024 ))

        if [ "$RX_SPEED" -gt 1024 ]; then
            RX_FMT="$(awk "BEGIN {printf \"%.2f MB/s\", $RX_SPEED/1024}")"
        else
            RX_FMT="${RX_SPEED} KB/s"
        fi

        if [ "$TX_SPEED" -gt 1024 ]; then
            TX_FMT="$(awk "BEGIN {printf \"%.2f MB/s\", $TX_SPEED/1024}")"
        else
            TX_FMT="${TX_SPEED} KB/s"
        fi

        printf "\r   📥 ${GREEN:-}Down:${RESET:-} %s%-10s%s ${GRAY:-}|${RESET:-}    📤 ${YELLOW:-}Up:${RESET:-} %s%-10s%s\033[K" \
            "${GREEN:-}" "$RX_FMT" "${RESET:-}" \
            "${YELLOW:-}" "$TX_FMT" "${RESET:-}"

        RX_PREV=$RX_NOW
        TX_PREV=$TX_NOW
    done
}

# Main interactive network menu loop
network_menu()
{
    while true; do
        show_full_network_info
        
        printf "   📊 ${CYAN:-}1${RESET:-}) Live Speed Monitor\n"
        printf "   🔄 ${CYAN:-}2${RESET:-}) Refresh Information\n"
        printf "   ⬅️ ${CYAN:-}0${RESET:-}) Back to Main Menu\n\n"
        
        printf "   ⁉️ ${YELLOW:-}Select${RESET:-} ${GRAY:-}:${RESET:-} "
        read -r net_choice </dev/tty

        case "$net_choice" in
            1) show_live_speed ;;
            2) continue ;;
            0) echo "   🚪${GRAY} Exiting ...${RESET}"
                sleep 1
                clear
                break 
                ;;
            *) 
                if command -v log_warn >/dev/null 2>&1; then
                    log_warn "Invalid choice!"
                else
                    echo "Invalid choice!"
                fi
                ;;
        esac
    done
}

# Script entry point handler
case "$0" in
    *network_checker.sh|*network_info.sh) network_menu ;;
esac