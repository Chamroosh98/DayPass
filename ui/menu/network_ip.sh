#!/bin/sh
# DayPass - Network info screens. Printing only; no HTTP here.

# Display columns of $1. A 4-byte emoji counts as 2. BusyBox awk only; no od.
_net_disp_width() {
    local s="$1" w=""

    [ -n "$s" ] || { printf '%s\n' "0"; return 0; }
    w=$(printf '%s' "$s" | LC_ALL=C awk '
        BEGIN {
            for (i = 0; i < 256; i++) ord[sprintf("%c", i)] = i
            w = 0
            n = 0
        }
        {
            for (i = 1; i <= length($0); i++) {
                b = ord[substr($0, i, 1)]
                if (b == "") b = 0
                if (n > 0) { n--; continue }
                if (b < 128) { w++ }
                else if (b < 224) { w++; n = 1 }
                else if (b < 240) { w++; n = 2 }
                else { w += 2; n = 3 }
            }
        }
        END { print w + 0 }
    ' 2>/dev/null)
    case "$w" in
        ''|*[!0-9]*) w=${#s} ;;
    esac
    printf '%s\n' "$w"
}

# Append spaces so $1 reaches display width $2. Longer lines are kept whole.
_net_pad() {
    local s="$1" width="$2" w=0

    w=$(_net_disp_width "$s")
    while [ "$w" -lt "$width" ]; do
        s="$s "
        w=$((w + 1))
    done
    printf '%s\n' "$s"
}

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

# One emoji, display width 2, so the tree colons stay aligned.
_net_provider_icon() {
    case "$1" in
        IR) printf '%s\n' "🦁" ;;
        "") printf '%s\n' "📶" ;;
        *)  country_flag "$1" ;;
    esac
}

# $1 interface count. Operations only; the shared footer is printed by the menu.
net_render_left_menu() {
    local count="${1:-0}"

    echo "  📋 Operations"
    echo "  ─────────────"
    echo "  📊 1) Live Speed Monitor"
    echo "  🔄 2) Refresh Information"
    if [ "$count" -gt 1 ]; then
        echo
        echo "  ⚖️ Multi-WAN"
        echo "  ─────────────"
        echo "  $count interfaces"
    fi
}

# $1 snapshot file. Each line:
# iface|dev|metric|mwan|success|ip|country|code|flag|city|isp|asn
net_render_right_tree() {
    local file="$1"
    local iface dev metric mwan success ip country code flag city isp asn
    local icon picon st_icon st_txt prov first=1

    if [ ! -s "$file" ]; then
        echo "  No WAN interface detected."
        return 0
    fi

    while IFS='|' read -r iface dev metric mwan success ip country code flag city isp asn; do
        [ -n "$iface" ] || continue
        if [ "$first" -eq 0 ]; then
            echo "  ─────────────"
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

# $1 left file  $2 right file  $3 display width of the left column
_net_zip_columns() {
    local leftf="$1" rightf="$2" width="$3"
    local l r gotl gotr

    while true; do
        l=""; r=""; gotl=0; gotr=0
        if IFS= read -r l <&3; then gotl=1; else l=""; fi
        if IFS= read -r r <&4; then gotr=1; else r=""; fi
        [ "$gotl" -eq 0 ] && [ "$gotr" -eq 0 ] && break
        l=$(_net_pad "$l" "$width")
        printf '%s │ %s\n' "$l" "$r"
    done 3<"$leftf" 4<"$rightf"
}

# $1 snapshot  $2 interface count  $3 optional note shown instead of the tree
net_render_columns() {
    local snap="$1" count="$2" note="$3"
    local left right

    left="/tmp/daypass_netleft.$$"
    right="/tmp/daypass_netright.$$"
    net_render_left_menu "$count" > "$left"
    if [ -n "$note" ]; then
        printf '  %s\n' "$note" > "$right"
    else
        net_render_right_tree "$snap" > "$right"
    fi
    _net_zip_columns "$left" "$right" 32
    rm -f "$left" "$right"
}
