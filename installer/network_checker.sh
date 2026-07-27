#!/bin/sh

# Cross-platform sleeping utility for UI spinner rendering
spin_sleep() {
    if command -v usleep >/dev/null 2>&1; then
        usleep 100000
    else
        sleep 1
    fi
}

GREEN_COUNT=0
YELLOW_COUNT=0
RED_COUNT=0
TOTAL_CHECKS=0
DNS_FAILED=0

ROW_HOST=""
ROW_DNS_ICON="·"
ROW_PING_ICON="·"
ROW_HTTPS_ICON="·"
ROW_ACTIVE=""

# Redraw the current table row with updated status icons / spinner
redraw_row()
{
    spin="$1"
    d="$ROW_DNS_ICON"
    p="$ROW_PING_ICON"
    h="$ROW_HTTPS_ICON"

    case "$ROW_ACTIVE" in
        dns)   d="$spin" ;;
        ping)  p="$spin" ;;
        https) h="$spin" ;;
    esac

    printf "\r  %-16s %-6s %-7s %-6s\033[K" "$ROW_HOST" "$d" "$p" "$h"
}

# Run execution cell asynchronously while displaying animated CLI spinner
run_cell()
{
    ROW_ACTIVE="$1"
    tmp="$2"
    shift 2

    "$@" >"$tmp" 2>&1 &
    pid=$!

    trap 'kill -9 "$pid" 2>/dev/null; rm -f "$tmp" 2>/dev/null; exit 130' INT TERM

    spin_chars='-\|/'
    i=0
    while kill -0 "$pid" 2>/dev/null; do
        c="$(printf '%s' "$spin_chars" | cut -c$(( (i % 4) + 1 )))"

        if [ -n "${CYAN:-}" ] && [ -n "${RESET:-}" ]; then
            redraw_row "${CYAN}${c}${RESET}"
        else
            redraw_row "$c"
        fi
        i=$((i + 1))
        spin_sleep
    done

    wait "$pid" 2>/dev/null
    CELL_EXIT=$?
    CELL_OUTPUT="$(cat "$tmp" 2>/dev/null)"
    rm -f "$tmp"
}

# Execute health diagnostics for a single target hostname
process_host()
{
    ROW_HOST="$1"
    ROW_DNS_ICON="·"
    ROW_PING_ICON="·"
    ROW_HTTPS_ICON="·"
    ROW_ACTIVE=""
    redraw_row "·"

    # 1. DNS Resolution Check
    if command -v nslookup >/dev/null 2>&1; then
        run_cell "dns" "/tmp/.nc_dns_$$" nslookup "$ROW_HOST"
    elif command -v host >/dev/null 2>&1; then
        run_cell "dns" "/tmp/.nc_dns_$$" host "$ROW_HOST"
    else
        # Fallback using ping host resolution
        run_cell "dns" "/tmp/.nc_dns_$$" ping -c 1 -W 2 "$ROW_HOST"
    fi

    if [ "$CELL_EXIT" -eq 0 ]; then
        ROW_DNS_ICON="🟢"
    else
        ROW_DNS_ICON="🔴"
        DNS_FAILED=1
    fi

    # 2. ICMP Ping / Latency Check
    run_cell "ping" "/tmp/.nc_ping_$$" ping -c 2 -W 2 "$ROW_HOST"
    LOSS="$(printf '%s' "$CELL_OUTPUT" | grep -o '[0-9]*% packet loss' | grep -o '^[0-9]*')"
    [ -z "$LOSS" ] && LOSS=100

    if [ "$LOSS" -eq 0 ]; then
        ROW_PING_ICON="🟢"
    elif [ "$LOSS" -lt 100 ]; then
        ROW_PING_ICON="🟡"
    else
        ROW_PING_ICON="🔴"
    fi

    # 3. HTTPS Reachability & Performance Check
    if command -v curl >/dev/null 2>&1; then
        run_cell "https" "/tmp/.nc_https_$$" curl -fsS -o /dev/null -w '%{time_total}' --connect-timeout 5 "https://$ROW_HOST"
    elif command -v uclient-fetch >/dev/null 2>&1; then
        run_cell "https" "/tmp/.nc_https_$$" uclient-fetch -q -T 5 -O /dev/null "https://$ROW_HOST"
    else
        run_cell "https" "/tmp/.nc_https_$$" wget -q --spider --timeout=5 "https://$ROW_HOST"
    fi

    if [ "$CELL_EXIT" -ne 0 ]; then
        ROW_HTTPS_ICON="🔴"
    else
        if command -v curl >/dev/null 2>&1; then
            IS_FAST="$(awk -v t="$CELL_OUTPUT" 'BEGIN { print (t < 2) ? "1" : "0" }' 2>/dev/null)"
            if [ "$IS_FAST" = "1" ]; then
                ROW_HTTPS_ICON="🟢"
            else
                ROW_HTTPS_ICON="🟡"
            fi
        else
            ROW_HTTPS_ICON="🟢"
        fi
    fi

    ROW_ACTIVE=""
    redraw_row " "
    printf "\n"

    for icon in "$ROW_DNS_ICON" "$ROW_PING_ICON" "$ROW_HTTPS_ICON"; do
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        case "$icon" in
            🟢) GREEN_COUNT=$((GREEN_COUNT + 1)) ;;
            🟡) YELLOW_COUNT=$((YELLOW_COUNT + 1)) ;;
            🔴) RED_COUNT=$((RED_COUNT + 1)) ;;
        esac
    done
}

# Master execution function for system network checks
network_check()
{
    GREEN_COUNT=0
    YELLOW_COUNT=0
    RED_COUNT=0
    TOTAL_CHECKS=0
    DNS_FAILED=0

    echo
    printf "  ${BOLD:-}${CYAN:-}🔎 DayPass Network Health Check${RESET:-}\n"
    
    printf "  ${GRAY:-}──────────────────────────────────────────${RESET:-}\n"

    printf "  ${BOLD:-}%-16s %-6s %-7s %-6s${RESET:-}\n" "Host" "DNS" "Ping" "HTTPS"
    printf "  ${GRAY:-}──────────────────────────────────────────${RESET:-}\n"

    process_host "google.com"
    process_host "github.com"
    process_host "openwrt.org"
    process_host "cloudflare.com"

    printf "  ${GRAY:-}──────────────────────────────────────────${RESET:-}\n\n"

    PCT=0
    [ "$TOTAL_CHECKS" -gt 0 ] && PCT=$((GREEN_COUNT * 100 / TOTAL_CHECKS))

    printf "  ${BOLD:-}Overall Score :${RESET:-} "
    if command -v draw_bar >/dev/null 2>&1; then
        draw_bar "$PCT" 12 "score"
    fi
    printf " %s%% (🟢 %s  🟡 %s  🔴 %s)\n\n" "$PCT" "$GREEN_COUNT" "$YELLOW_COUNT" "$RED_COUNT"

    printf "  ${BOLD:-}Diagnostic Report :${RESET:-} "
    if [ "$DNS_FAILED" -eq 1 ]; then
        if command -v log_error >/dev/null 2>&1; then
            log_error "DNS resolution is failing! Router cannot translate domain names."
        else
            printf "❌${RED:-}DNS resolution failed! Domain name lookup is broken.${RESET:-}\n"
        fi
        
        if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
            if command -v dns_fix_menu >/dev/null 2>&1; then
                dns_fix_menu
            fi
        fi
    elif [ "$RED_COUNT" -gt 0 ]; then
        if command -v log_warn >/dev/null 2>&1; then
            log_warn "HTTPS connections are blocked or filtered (Possible Censorship/DPI)."
        else
            printf "⚠️${YELLOW:-}HTTPS traffic is blocked or severely interfered with.${RESET:-}\n"
        fi
    elif [ "$YELLOW_COUNT" -gt 0 ]; then
        if command -v log_warn >/dev/null 2>&1; then
            log_warn "Network is active but experiencing high packet loss/latency (>2s)."
        else
            printf "⚠️${YELLOW:-}High latency or degraded response time detected.${RESET:-}\n"
        fi
    else
        if command -v log_success >/dev/null 2>&1; then
            log_success "Network is fully functional with clean connectivity!"
        else
            printf "✅${GREEN:-}Network is fully functional!${RESET:-}\n"
        fi
    fi

    echo
    printf "  ${GRAY:-}Press [Enter] to continue ...${RESET:-}"
    read -r _ </dev/tty
    echo
    return 0
}

# Standalone execution handler
case "$0" in
    *network_check.sh|*network_checker.sh) network_check ;;
esac