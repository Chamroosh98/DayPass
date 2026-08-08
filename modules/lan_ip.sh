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

    echo "  🌐 Local LAN IP Subnet Configuration                    "
    echo "  ───────────────────────────────────────────────────────────"
    echo "  📌 Current Router LAN IP : ${CYAN}${CURRENT_IP}${RESET}"
    echo "  ───────────────────────────────────────────────────────────"
    echo "  💡 Note : Changing LAN IP prevents 'IP Conflicts' if your"
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
            log_error "Invalid IP address format! Please try again."
        fi
    done

    if [ "$NEW_IP" = "$CURRENT_IP" ]; then
        log_warn "New IP is identical to current IP. Nothing changed."
        sleep 2
        return 0
    fi

    log_info "Updating LAN IP address to [$NEW_IP]..."

    uci set network.lan.ipaddr="$NEW_IP"
    uci commit network

    echo
    log_warn "NETWORK RESTART REQUIRED!"
    log_warn "After applying, your terminal/SSH session will disconnect."
    log_warn "Reconnect to LuCI / SSH using the new IP: ${GREEN}http://${NEW_IP}${RESET}"
    echo

    printf "  ⁉️ Apply changes now and restart network? [y/N] : "
    read -r apply_confirm </dev/tty

    case "$apply_confirm" in
        y|Y)
            log_info "Restarting network stack..."
            (/etc/init.d/network restart >/dev/null 2>&1 &)
            log_success "LAN IP updated to $NEW_IP! Goodbye!"
            exit 0
            ;;
        *)
            log_warn "Changes saved to UCI, but network restart skipped."
            sleep 2
            ;;
    esac
}