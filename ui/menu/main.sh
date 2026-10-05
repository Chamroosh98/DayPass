#!/bin/sh

main_menu()
{
    local HELP_MODULE_ID="main"

    trap daypass_interrupt INT TERM

    while true; do
        render_persistent_header

        ui_title "🏠 Main Menu"
        echo "  📦 1) Package Profiles & Dependencies"
        echo "  🔌 2) Hardware & USB Tethering Manager"
        echo "  🌐 3) Network & Routing Configuration"
        echo "  🛡️ 4) Proxy & Tunnel Engine Manager"
        echo "  ⚖️ 5) Node Balancer & Health Diagnostics"
        echo "  🛠️ 6) System Maintenance & Backup"
        echo "  📖 7) Help & Manuals"
        echo "  🌐 8) Network Bootstrap Wizard"
        echo "  📡 9) Network Interfaces State"
        ui_nav_footer root

        ui_prompt 9

        case "$UI_CHOICE" in
            1) ui_run packages_menu "Package Profiles" ;;
            2) ui_run hardware_menu "Hardware & USB Tethering" ;;
            3) ui_run network_menu "Network" ;;
            4) ui_run proxy_menu "Proxy & Tunnel Engine" ;;
            5) ui_run diagnostics_menu "Node Balancer & Diagnostics" ;;
            6) ui_run system_menu "System Maintenance" ;;
            7) ui_run help_menu "Help" ;;
            8) ui_run network_bootstrap_from_menu "Network Bootstrap" ;;
            9) ui_run network_interfaces_state "Network Interfaces State" ;;
            0) daypass_quit ;;
            *)
                ui_nav_common "$UI_CHOICE" "$HELP_MODULE_ID" && continue
                log_warn "Invalid choice!"
                sleep 1
                ;;
        esac
    done
}
