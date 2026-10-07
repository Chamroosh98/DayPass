#!/bin/sh
# DayPass - Public IP lookup. curl only, bound to one Linux device.

# $1 country code
country_flag() {
    case "$1" in
        IR) printf '%s\n' "🦁☀️" ;;
        IL) printf '%s\n' "🇮🇱" ;;
        AZ) printf '%s\n' "🇦🇿" ;;
        DE) printf '%s\n' "🇩🇪" ;;
        US) printf '%s\n' "🇺🇸" ;;
        NL) printf '%s\n' "🇳🇱" ;;
        RU) printf '%s\n' "🇷🇺" ;;
        CN) printf '%s\n' "🇨🇳" ;;
        JP) printf '%s\n' "🇯🇵" ;;
        SG) printf '%s\n' "🇸🇬" ;;
        TR) printf '%s\n' "🇹🇷" ;;
        GB) printf '%s\n' "🇬🇧" ;;
        FR) printf '%s\n' "🇫🇷" ;;
        FI) printf '%s\n' "🇫🇮" ;;
        SE) printf '%s\n' "🇸🇪" ;;
        PL) printf '%s\n' "🇵🇱" ;;
        *)  printf '%s\n' "🌐" ;;
    esac
}

# $1 linux device. Prints success|ip|country|code|flag|city|isp|asn
# Bound to that device so mwan3 cannot move the query.
net_fetch_iface_ip() {
    local dev="$1"
    local json=""

    if [ -z "$dev" ] || [ ! -e "/sys/class/net/$dev" ]; then
        printf '%s\n' "false|||||||"
        return 1
    fi
    if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        printf '%s\n' "false|||||||"
        return 1
    fi

    json=$(curl -fsS --connect-timeout 2 --max-time 4 --interface "$dev" "https://ipwho.is/" 2>/dev/null || true)
    if printf '%s' "$json" | jq -e '.success == true' >/dev/null 2>&1; then
        printf '%s\n' "$json" | jq -r '"true|\(.ip // "")|\(.country // "")|\(.country_code // "")|\(.flag.emoji // "")|\(.city // "")|\(.connection.isp // "")|\(.connection.asn // "")"'
        return 0
    fi

    json=$(curl -fsS --connect-timeout 2 --max-time 4 --interface "$dev" "https://ipapi.co/json/" 2>/dev/null || true)
    if printf '%s' "$json" | jq -e '.ip != null and .ip != ""' >/dev/null 2>&1; then
        printf '%s\n' "$json" | jq -r '"true|\(.ip // "")|\(.country_name // "")|\(.country_code // "")||\(.city // "")|\(.org // "")|\(.asn // "")"'
        return 0
    fi

    printf '%s\n' "false|||||||"
    return 1
}
