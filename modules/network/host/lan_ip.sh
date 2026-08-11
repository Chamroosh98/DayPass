#!/bin/sh

validate_ip()
{
    ip="$1"
    case "$ip" in
        ""|*[!0-9.]*) return 1 ;;
    esac

    O1=$(echo "$ip" | cut -d. -f1)
    O2=$(echo "$ip" | cut -d. -f2)
    O3=$(echo "$ip" | cut -d. -f3)
    O4=$(echo "$ip" | cut -d. -f4)

    [ -z "$O1" ] || [ -z "$O2" ] || [ -z "$O3" ] || [ -z "$O4" ] && return 1
    [ "$O1" -gt 255 ] || [ "$O2" -gt 255 ] || [ "$O3" -gt 255 ] || [ "$O4" -ge 255 ] && return 1
    [ "$O4" -le 0 ] && return 1

    return 0
}

change_lan_ip_menu()
{
    render_persistent_header 2>/dev/null || clear

    CURRENT_IP=$(uci -q get network.lan.ipaddr || echo "192.168.1.1")
    CURRENT_NETMASK=$(uci -q get network.lan.netmask || echo "255.255.255.0")

    echo "  🌐 Local LAN IP Subnet Configuration"
    echo "  ───────────────────────────────────────────────────────────"
    echo "  ➡️ Current Router LAN IP : ${CYAN}${CURRENT_IP}${RESET}"
    echo "  ➡️ Current Netmask       : ${CYAN}${CURRENT_NETMASK}${RESET}"
    echo "  ───────────────────────────────────────────────────────────"
    echo "  💡 Note : Changing LAN IP prevents IP Conflicts if your"
    echo "     upstream ISP Modem is also using 192.168.1.1."
    echo "  ───────────────────────────────────────────────────────────"
    echo

    printf "  ⁉️ Do you want to change the Router LAN IP? [y/N] : "
    read -r confirm </dev/tty

    case "$confirm" in
        y|Y) ;;
        *)
            log_warn "LAN IP change cancelled!"
            sleep 1
            return 0
            ;;
    esac

    echo
    while true; do
        printf "  ✏️ Enter New LAN IP Address [e.g. 192.168.10.1] : "
        read -r NEW_IP </dev/tty

        if validate_ip "$NEW_IP"; then
            break
        else
            log_error "Invalid IP address format! Please try again!"
        fi
    done

    if [ "$NEW_IP" = "$CURRENT_IP" ]; then
        log_warn "New IP is identical to current IP. Nothing changed!"
        sleep 2
        return 0
    fi

    # Extract network prefix (first 3 octets)
    PREFIX=$(echo "$NEW_IP" | cut -d. -f1-3)

    log_info "Updating LAN IP address to [$NEW_IP] ..."

    # 1. Change LAN IP
    uci set network.lan.ipaddr="$NEW_IP"
    uci set network.lan.netmask="255.255.255.0"

    # 2. Update DHCP settings (important!)
    # Start from .100 and give 150 addresses (up to .249)
    uci set dhcp.lan.start="100"
    uci set dhcp.lan.limit="150"
    uci set dhcp.lan.leasetime="12h"

    # Make sure DHCP is enabled on lan
    uci set dhcp.lan.interface="lan"
    uci set dhcp.lan.ignore="0"

    uci commit network
    uci commit dhcp

    echo
    log_warn "NETWORK RESTART REQUIRED!"
    log_warn "After applying, your terminal/SSH session will disconnect!"
    log_warn "Reconnect using the new IP : ${GREEN}http://${NEW_IP}${RESET}"
    echo
    log_info "DHCP Pool will be : ${CYAN}${PREFIX}.100 - ${PREFIX}.249${RESET}"
    echo

    printf "  ⁉️ Apply changes now and restart network + DHCP? [y/N] : "
    read -r apply_confirm </dev/tty

    case "$apply_confirm" in
        y|Y)
            log_info "Clearing old DHCP leases ..."
            rm -f /tmp/dhcp.leases /tmp/hosts/dhcp* 2>/dev/null

            log_info "Restarting network and dnsmasq ..."
            (
                /etc/init.d/network restart >/dev/null 2>&1
                sleep 2
                /etc/init.d/dnsmasq restart >/dev/null 2>&1
            ) &

            log_success "LAN IP updated to $NEW_IP"
            log_success "DHCP pool set to ${PREFIX}.100 - ${PREFIX}.249"
            log_warn "Please reconnect your devices to get new IPv4 address!"
            exit 0
            ;;
        *)
            log_warn "Changes saved to UCI, but services were not restarted!"
            log_info "You can apply later with ==> /etc/init.d/network restart"
            sleep 2
            ;;
    esac
}