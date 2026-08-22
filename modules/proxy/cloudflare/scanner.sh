#!/bin/sh

# ------------------------------------------------------------
# Basic TCP connectivity test on specific port
# ------------------------------------------------------------
test_ip_basic() {
    local ip="$1"
    local port="$2"
    local timeout_sec="${3:-3}"

    if command -v nc >/dev/null 2>&1; then
        if nc -z -w "$timeout_sec" "$ip" "$port" >/dev/null 2>&1; then
            return 0
        fi
        return 1
    fi

    if timeout "$timeout_sec" sh -c "echo > /dev/tcp/$ip/$port" 2>/dev/null; then
        return 0
    fi

    return 1
}

# ------------------------------------------------------------
# Measure rough latency (ms)
# ------------------------------------------------------------
measure_latency() {
    local ip="$1"
    local port="$2"
    local start end

    start=$(date +%s%N 2>/dev/null || date +%s)

    if test_ip_basic "$ip" "$port" 2; then
        end=$(date +%s%N 2>/dev/null || date +%s)
        if [ "${#start}" -ge 13 ] 2>/dev/null; then
            echo $(( (end - start) / 1000000 ))
        else
            echo "0"
        fi
        return 0
    fi

    echo ""
    return 1
}

# ------------------------------------------------------------
# Advanced validation placeholder (xray / sing-box)
# ------------------------------------------------------------
test_ip_advanced() {
    local ip="$1"
    local port="$2"
    local share_link="$3"
    local core

    core=$(detect_proxy_core)

    case "$core" in
        xray)
            log_info "Advanced Xray validation not fully implemented yet. Using basic test!"
            test_ip_basic "$ip" "$port"
            ;;
        sing-box)
            log_info "Advanced Sing-box validation not fully implemented yet. Using basic test!"
            test_ip_basic "$ip" "$port"
            ;;
        *)
            test_ip_basic "$ip" "$port"
            ;;
    esac
}

# ------------------------------------------------------------
# Ensure candidate IP list exists
# ------------------------------------------------------------
ensure_candidate_file() {
    if [ -f "$CANDIDATE_FILE" ] && [ -s "$CANDIDATE_FILE" ]; then
        return 0
    fi

    cat > "$CANDIDATE_FILE" << EOF
# DayPass Clean IP candidates (Cloudflare-focused)
# One IP per line. Lines starting with # are ignored!
1.1.1.1
1.0.0.1
104.16.0.1
104.17.0.1
104.18.0.1
104.19.0.1
104.20.0.1
104.21.0.1
104.22.0.1
104.24.0.1
EOF

    log_info "Default candidate list created at : [$CANDIDATE_FILE]"
}

# ------------------------------------------------------------
# Scan candidate IPs using the config port
# ------------------------------------------------------------
scan_candidate_ips() {
    local port="$1"
    local share_link="$2"
    local mode="${3:-basic}"

    ensure_candidate_file
    > "$RESULT_FILE"

    echo
    echo "  🔍 Scanning candidate IPs on port [$port] ..."
    echo "  ───────────────────────────────────────────────────────────"

    local total=0
    local ok=0
    local ip latency

    while IFS= read -r line; do
        line=$(echo "$line" | xargs)
        [ -z "$line" ] && continue
        case "$line" in
            \#*) continue ;;
        esac

        ip="$line"
        total=$((total + 1))

        if [ "$mode" = "advanced" ]; then
            if test_ip_advanced "$ip" "$port" "$share_link"; then
                latency=$(measure_latency "$ip" "$port")
                [ -z "$latency" ] && latency="?"
                log_success "$ip:$port  |  ${latency} ms"
                echo "$latency $ip" >> "$RESULT_FILE"
                ok=$((ok + 1))
            else
                log_error "$ip:$port  |  Unreachable"
            fi
        else
            if test_ip_basic "$ip" "$port"; then
                latency=$(measure_latency "$ip" "$port")
                [ -z "$latency" ] && latency="?"
                log_success "$ip:$port  |  ${latency} ms"
                echo "$latency $ip" >> "$RESULT_FILE"
                ok=$((ok + 1))
            else
                log_error "$ip:$port  |  Unreachable"
            fi
        fi
    done < "$CANDIDATE_FILE"

    echo "  ───────────────────────────────────────────────────────────"
    echo "  Result : ${GREEN}$ok${RESET} / $total IP(s) reachable ;)"
    echo

    if [ "$ok" -gt 0 ]; then
        sort -n "$RESULT_FILE" -o "$RESULT_FILE" 2>/dev/null || true
        echo "  🏆 Best candidates :"
        awk '{printf "   - %s  (%s ms)\n", $2, $1}' "$RESULT_FILE" | head -n 10
        echo
    fi
}

# ------------------------------------------------------------
# Show / hint edit candidate list
# ------------------------------------------------------------
edit_candidates() {
    ensure_candidate_file
    echo
    log_info "Candidate file : [$CANDIDATE_FILE]"
    echo "  Current list :"
    echo "  ───────────────────────────────────────────────────────────"
    cat  "  $CANDIDATE_FILE"
    echo "  ───────────────────────────────────────────────────────────"
    echo
    log_info "Edit this file manually, then rerun scan!"
}