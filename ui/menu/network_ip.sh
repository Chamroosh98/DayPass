#!/bin/sh
# DayPass - Network info screens. Printing only; no HTTP here.

# $1 uci name
_net_iface_icon() {
    case "$1" in
        wan_usb*) printf '%s\n' "📱" ;;
        wwan*)    printf '%s\n' "📶" ;;
        wan_lan*) printf '%s\n' "🔌" ;;
        *)        printf '%s\n' "🌐" ;;
    esac
}

# $1 iface  $2 linux dev  $3 metric  $4 fetch record
net_render_standalone_ui() {
    local iface="$1"
    local dev="$2"
    local metric="$3"
    local data="$4"
    local success ip country code flag city isp asn icon

    IFS='|' read -r success ip country code flag city isp asn <<EOF
$data
EOF

    icon=$(_net_iface_icon "$iface")
    if [ "$code" = "IR" ] || [ -z "$flag" ]; then
        flag=$(country_flag "$code")
    fi
    [ -n "$metric" ] || metric="default"
    [ -n "$dev" ] || dev="unknown"

    echo "  🌐 Network Diagnostics"
    echo "  ───────────────────────────────────────────────────────────"
    echo "  $icon Interface : $iface ($dev)"
    echo "  📊 Metric     : $metric"

    if [ "$success" != "true" ] || [ -z "$ip" ]; then
        echo "  🌐 Public IP  : offline"
        echo "  📶 Status     : no answer on this interface"
    else
        echo "  🌐 Public IP  : $ip"
        if [ -n "$city" ]; then
            echo "  $flag Country    : $country ($city)"
        else
            echo "  $flag Country    : $country"
        fi
        [ -n "$isp" ] && echo "  📶 ISP        : $isp"
        [ -n "$asn" ] && echo "  🔌 ASN        : $asn"
    fi
    echo "  ───────────────────────────────────────────────────────────"
}

# $1 snapshot file. Each line:
# iface|dev|metric|mwan|success|ip|country|code|flag|city|isp|asn
net_render_multiwan_ui() {
    local file="$1"
    local iface dev metric mwan success ip country code flag city isp asn icon

    echo "  🌐 Multi-WAN"
    echo "  ───────────────────────────────────────────────────────────"
    while IFS='|' read -r iface dev metric mwan success ip country code flag city isp asn; do
        [ -n "$iface" ] || continue
        icon=$(_net_iface_icon "$iface")
        if [ "$code" = "IR" ] || [ -z "$flag" ]; then
            flag=$(country_flag "$code")
        fi
        [ -n "$metric" ] || metric="default"
        [ -n "$dev" ] || dev="-"
        [ "$success" = "true" ] && [ -n "$ip" ] || ip="offline"
        [ -n "$isp" ] || isp="-"
        echo "  $icon $iface"
        echo "     Device  $dev"
        echo "     IP      $ip"
        echo "     ISP     $isp"
        echo "     $flag $country"
        echo "     Metric  $metric"
        echo "     mwan3   $mwan"
        echo
    done < "$file"
    echo "  ───────────────────────────────────────────────────────────"
}
