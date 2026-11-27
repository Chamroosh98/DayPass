#!/bin/sh
# ============================================================
# DayPass - Wi-Fi Scanner (Client Mode)
# ============================================================

wifi_parse_scan() {
    LC_ALL=C awk -v backend="$1" '
        function emit() {
            if (ssid == "" || ssid == "unknown" || ssid ~ /[|[:cntrl:]]/ || index(ssid, "\\"))
                return
            if (psk) enc = "psk"
            else if (open_net && !secure) enc = "none"
            else return
            print ssid "|" (signal == "" ? "-999" : signal) "|" enc
        }
        function reset_record() {
            ssid = signal = section = ""
            open_net = secure = psk = 0
        }
        (backend == "iwinfo" && /^[[:space:]]*Cell [0-9]+ - Address:/) ||
        (backend == "iw" && /^BSS /) {
            if (active) emit()
            reset_record()
            active = 1
            next
        }
        !active { next }
        backend == "iwinfo" && /^[[:space:]]*ESSID: "/ {
            ssid = $0
            sub(/^[[:space:]]*ESSID: "/, "", ssid)
            if (!sub(/"$/, "", ssid)) ssid = ""
        }
        backend == "iw" && /^[[:space:]]*SSID: / {
            ssid = $0
            sub(/^[[:space:]]*SSID: /, "", ssid)
        }
        /^[[:space:]]*(Signal|signal): -?[0-9.]+ dBm/ {
            signal = $2 + 0
        }
        backend == "iwinfo" && /^[[:space:]]*Encryption:/ {
            open_net = ($2 == "none")
            psk = ($0 ~ /WPA2 PSK|mixed WPA\/WPA2 PSK/)
        }
        backend == "iw" && /^[[:space:]]*capability:/ {
            open_net = ($0 ~ /[[:space:]]ESS([[:space:]]|$)/)
            if ($0 ~ /[[:space:]]Privacy([[:space:]]|$)/) secure = 1
        }
        backend == "iw" && /^[[:space:]]*(RSN|WPA):/ {
            secure = 1
            section = $1
        }
        backend == "iw" && section == "RSN:" && /^[[:space:]]*\* Authentication suites:/ &&
            /[[:space:]]PSK([[:space:]]|$)/ { psk = 1 }
        END { if (active) emit() }
    ' "$2"
}

wifi_scan_networks() {
    local radio="$1"
    local scan_file="$2" raw_file="$2.raw" backend=iwinfo status=1
    local target_iface wireless
    [ -n "$scan_file" ] || return 1
    case "$radio" in ''|*[!a-zA-Z0-9_]*) return 1 ;; esac
    wireless=$(ubus call network.wireless status) || return 1
    target_iface=$(jsonfilter -s "$wireless" -e "@['$radio'].interfaces[0].ifname") || return 1
    case "$target_iface" in ''|-*|*[!a-zA-Z0-9_.-]*) return 1 ;; esac

    if [ -n "$target_iface" ]; then
        if iwinfo "$target_iface" scan > "$raw_file" 2>/dev/null &&
            grep -Eq '^[[:space:]]*(Cell [0-9]+ - Address:|No scan results)' "$raw_file"; then
            status=0
        elif command -v iw >/dev/null 2>&1; then
            backend=iw
            iw dev "$target_iface" scan > "$raw_file" 2>/dev/null && status=0
        fi
    fi

    if [ "$status" -eq 0 ]; then
        wifi_parse_scan "$backend" "$raw_file" > "$scan_file.records" &&
            LC_ALL=C sort -t '|' -k2,2nr "$scan_file.records" > "$scan_file.sorted" &&
            awk -F '|' '!seen[$1]++' "$scan_file.sorted" > "$scan_file" || status=1
    fi

    return "$status"
}
