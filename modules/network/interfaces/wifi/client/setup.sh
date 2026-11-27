#!/bin/sh

# Only new wireless sections are created. Upstream networks, zones and radios
# are borrowed read-only. Refuse name collisions, including old DayPass names.
wifi_create_owned_iface() (
    local radio="$1" mode="$2" net="$3" ssid="$4" enc="$5" key="$6"
    local option sec="daypass_${mode}_${radio}" delta pending expected current
    case "$radio" in ''|*[!a-zA-Z0-9_]*) return 1 ;; esac
    case "$mode:$enc" in ap:psk2|sta:psk2) [ "${#key}" -ge 8 ] || return 1 ;;
        sta:none) [ -z "$key" ] || return 1 ;; *) return 1 ;;
    esac
    [ -n "$ssid" ] && [ "$(uci -q get "wireless.$radio")" = wifi-device ] &&
        [ "$(uci -q get "network.$net")" = interface ] || return 1
    [ "$(uci -q get "wireless.$radio.disabled")" != 1 ] || return 1
    pending=$(uci changes wireless) && [ -z "$pending" ] || return 1
    uci show wireless >/dev/null || return 1
    if uci -q get "wireless.$sec" >/dev/null; then
        log_warn "Wireless section $sec already exists."; return 1
    fi
    delta=$(mktemp -d /tmp/daypass_wifi_apply.XXXXXX) || return 1
    trap 'rm -f "$delta/wireless"; rmdir "$delta"' EXIT
    uci -P "$delta" set "wireless.$sec=wifi-iface" || return 1
    for option in "daypass_owner=wifi_v1" "device=$radio" "mode=$mode" "network=$net" \
        "ssid=$ssid" "encryption=$enc"; do
        uci -P "$delta" set "wireless.$sec.$option" || return 1
    done
    if [ "$enc" = psk2 ]; then uci -P "$delta" set "wireless.$sec.key=$key" || return 1; fi
    expected=$(uci -P "$delta" show "wireless.$sec") || return 1
    uci -P "$delta" commit wireless || return 1
    wifi reload && return 0
    current=$(uci show "wireless.$sec") && [ "$current" = "$expected" ] &&
        wifi_remove_owned_iface "$sec" "$mode" ||
        log_error "Wireless rollback incomplete for $sec."
    return 1
)

wifi_remove_owned_iface() (
    local sec="$1" mode="$2" pending delta
    case "$sec" in *[!a-zA-Z0-9_]*) return 1 ;; daypass_"${mode}"_*) ;; *) return 1 ;; esac
    pending=$(uci changes wireless) && [ -z "$pending" ] &&
        [ "$(uci -q get "wireless.$sec.daypass_owner")" = wifi_v1 ] &&
        [ "$(uci -q get "wireless.$sec.mode")" = "$mode" ] || return 1
    delta=$(mktemp -d /tmp/daypass_wifi_remove.XXXXXX) || return 1
    trap 'rm -f "$delta/wireless"; rmdir "$delta"' EXIT
    uci -P "$delta" delete "wireless.$sec" && uci -P "$delta" commit wireless && wifi reload
)

wifi_connect_client() {
    local radio="$1" ssid="$2" net zone zones encryption found=0 sections sec
    net="wan_$(printf '%s' "$ssid" | LC_ALL=C tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')"
    [ "$net" != wan_ ] || return 1
    [ "$(uci -q get "network.$net.proto")" = dhcp ] &&
        [ "$(uci -q get "network.$net.daypass_owner")" = wifi_v1 ] || {
        log_warn "Provision a dedicated wifi_v1-owned DHCP interface $net in the WAN zone first."; return 1
    }
    sections=$(uci show wireless) || return 1
    for sec in $(printf '%s\n' "$sections" | sed -n 's/^wireless\.\([^.]*\)=wifi-iface$/\1/p'); do
        case " $(uci -q get "wireless.$sec.network") " in
            *" $net "*) log_warn "Wi-Fi network $net is already in use."; return 1 ;;
        esac
    done
    zones=$(uci show firewall) || return 1
    for zone in $(printf '%s\n' "$zones" | sed -n 's/^firewall\.\([^.]*\)=zone$/\1/p'); do
        [ "$(uci -q get "firewall.$zone.name")" = wan ] || continue
        case " $(uci -q get "firewall.$zone.network") " in *" $net "*) found=1; break ;; esac
    done
    [ "$found" = 1 ] || return 1
    case "$3" in psk) encryption=psk2 ;; none) encryption=none ;; *) return 1 ;; esac
    wifi_create_owned_iface "$radio" sta "$net" "$ssid" "$encryption" "$4"
}
