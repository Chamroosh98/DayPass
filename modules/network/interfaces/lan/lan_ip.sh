#!/bin/sh

validate_ip()
{
    # This menu configures a /24 and reserves the network and broadcast hosts.
    printf '%s\n' "$1" | LC_ALL=C awk -F '.' '
        NF != 4 { exit 1 }
        {
            for (i=1; i<=4; i++)
                if ($i !~ /^(0|[1-9][0-9]?[0-9]?)$/ || $i+0 > 255) exit 1
            if ($4+0 == 0 || $4+0 == 255) exit 1
        }
        END { if (NR != 1) exit 1 }
    '
}

# Keep the DHCP configuration intact. A subnet-relative DHCP pool follows the
# static /24 address. Limit this path to a single scalar address on a local console.
_lan_replace_address() (
    local old="$1" new="$2" delta pending
    pending=$(uci changes network) && [ -z "$pending" ] || return 1
    [ "$(uci -q get network.lan.ipaddr)" = "$old" ] || return 1
    validate_ip "$old" && validate_ip "$new" || return 1
    delta=$(mktemp -d /tmp/daypass_lan.XXXXXX) || return 1
    trap 'rm -f "$delta/network"; rmdir "$delta"' EXIT
    uci -P "$delta" set "network.lan.ipaddr=$new" &&
        uci -P "$delta" commit network
)

_lan_reload_services() {
    /etc/init.d/network reload && /etc/init.d/dnsmasq reload
}

_lan_apply_address() {
    local old="$1" new="$2" answer
    _lan_replace_address "$old" "$new" || return 1
    if _lan_reload_services; then
        printf 'Confirm access at the new address from another LAN device. Keep change? [y/N] '
        if read -r answer && [ "$answer" = y ]; then return 0; fi
    fi
    if _lan_replace_address "$new" "$old" && _lan_reload_services; then
        log_warn "Restored the previous LAN address."
    else
        log_error "LAN rollback incomplete. Inspect network.lan from the local console."
    fi
    return 1
}

change_lan_ip_menu() {
    local console current new pending answer
    console=$(tty) || return 1
    case "$console" in /dev/console|/dev/ttyS[0-9]*|/dev/ttyAMA[0-9]*|/dev/tty[0-9]*) ;;
        *) log_warn "Use a local router console for LAN address changes."; return 1 ;;
    esac
    pending=$(uci changes dhcp) && [ -z "$pending" ] || return 1
    current=$(uci -q get network.lan.ipaddr) && validate_ip "$current" &&
        [ "$(uci -q get network.lan.proto)" = static ] &&
        [ "$(uci -q get network.lan.netmask)" = 255.255.255.0 ] &&
        [ "$(uci -q get dhcp.lan.interface)" = lan ] ||
        { log_warn "Only a static IPv4 /24 LAN with an existing LAN DHCP section is supported."; return 1; }
    printf 'Current LAN address %s/24. Enter new address (DHCP settings are preserved): ' "$current"
    read -r new && validate_ip "$new" || return 1
    [ "$new" != "$current" ] || return 0
    printf 'Apply %s/24 and reload LAN services? [y/N] ' "$new"
    read -r answer && [ "$answer" = y ] || return 0
    _lan_apply_address "$current" "$new"
}
