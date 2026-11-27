#!/bin/sh
# ============================================================
# DayPass - Guest Network Module
# Creates isolated Guest network with firewall rules & DHCP
# ============================================================

# ------------------------------------------------------------
# Create Guest Network + Firewall + DHCP
# ------------------------------------------------------------
# A UCI zone and a successful firewall reload do not establish isolation.
# In particular, earlier rules, IPv6 and bridge forwarding can bypass a
# guest-to-LAN reject. This CLI has no independent guest traffic probe.
setup_guest_network() {
    log_error "Guest setup requires verified subnet and firewall isolation. Automatic setup is unavailable."
    return 1
}

setup_guest_wifi() {
    log_error "Guest isolation has no verified traffic test. Guest Wi-Fi activation stopped."
    return 1
}

remove_guest_network() {
    log_error "Legacy guest sections and their consumers have no ownership record. Removal stopped."
    return 1
}

guest_network_menu() {
    while true; do
        render_persistent_header

        echo "  👥 Guest Network Manager"
        ui_divider
        echo "  1) Setup Guest Network (Interface + Firewall)"
        echo "  2) Setup Guest WiFi"
        echo "  3) Remove Guest Network completely"
        ui_nav_footer
        ui_prompt 3
        choice="$UI_CHOICE"

        case "$choice" in
            1) setup_guest_network ;;
            2) setup_guest_wifi ;;
            3) remove_guest_network ;;
            0) return 0 ;;
            q|Q) daypass_quit ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press ENTER ...${RESET}"
        read -r _ </dev/tty || daypass_quit
    done
}