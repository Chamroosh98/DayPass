#!/bin/sh
# DayPass - Network info screens. Printing only; no HTTP here.

# $1 uci name
_net_iface_icon() {
    case "$1" in
        wan6*)    printf '%s\n' "🌐" ;;
        wan_usb*) printf '%s\n' "📱" ;;
        wwan*)    printf '%s\n' "📶" ;;
        wan|wan_*) printf '%s\n' "🔌" ;;
        *)        printf '%s\n' "🌐" ;;
    esac
}

_net_provider_icon() {
    case "$1" in
        IR) printf '%s\n' "🦁" ;;
        "") printf '%s\n' "📶" ;;
        *)  country_flag "$1" ;;
    esac
}

# $1 snapshot file. Each line:
# iface|dev|metric|mwan|success|ip|country|code|flag|city|isp|asn
net_render_status_card() {
    local file="$1" note="$2"
    local iface dev metric mwan success ip country code flag city isp asn
    local icon picon st_icon st_txt prov first=1

    echo "  🌐 Network Diagnostics"
    ui_divider

    if [ -n "$note" ]; then
        echo "  $note"
        return 0
    fi
    if [ ! -s "$file" ]; then
        echo "  No WAN interface detected."
        return 0
    fi

    while IFS='|' read -r iface dev metric mwan success ip country code flag city isp asn; do
        [ -n "$iface" ] || continue
        if [ "$first" -eq 0 ]; then
            echo
        fi
        first=0

        icon=$(_net_iface_icon "$iface")
        picon=$(_net_provider_icon "$code")
        [ -n "$dev" ] || dev="-"
        [ -n "$metric" ] || metric="default"
        if [ "$success" = "true" ] && [ -n "$ip" ]; then
            :
        else
            ip="unavailable"
        fi
        [ -n "$isp" ] || isp="—"
        [ -n "$asn" ] || asn="—"
        prov="$isp [$asn]"

        case "$mwan" in
            online)  st_icon="🟢"; st_txt="Online" ;;
            offline) st_icon="🔴"; st_txt="Offline" ;;
            unknown) st_icon="🟡"; st_txt="Unknown" ;;
            *)       st_icon="⚪"; st_txt="Not tracked" ;;
        esac

        echo "  $icon $iface ($dev)"
        echo "  ├── 📍 IP       : $ip"
        echo "  ├── $picon Provider : $prov"
        echo "  └── $st_icon Status   : $st_txt (Metric $metric)"
    done < "$file"

    if [ "$first" -eq 1 ]; then
        echo "  No WAN interface detected."
    fi
}

net_render_operations() {
    echo "  🛠️ Operations"
    ui_divider
    echo "  1) 📊 Live Speed Monitor"
    echo "  2) 🔄 Refresh Information"
}

# $1 snapshot  $2 unused (kept for callers)  $3 optional note
net_render_panel() {
    net_render_status_card "$1" "$3"
    echo
    net_render_operations
}
