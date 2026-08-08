#!/bin/sh

main_menu()
{
    while true; 
        do

            render_persistent_header
            
            printf "  📦 1) Install Package Profile\n"
            printf "  🔄 2) Check & Update Packages\n"
            printf "  📡 3) Configure WiFi & Guest Networks\n"
            printf "  🌐 4) Change Local Router LAN IP\n"
            printf "  ⚖️ 5) Multi-WAN Load Balancer (USB Tethering / Wi-Fi WAN)\n"
            printf "  🖥️ 6) Network Info & Speed Monitor\n"
            printf "  📊 7) System Resources & Hardware Info\n"
            printf "  🛠️ 8) Maintenance & Recovery\n"
            printf "  🚪 0) Exit\n\n"

            printf "  ⁉️ Select option [0-8] : "
            read -r choice </dev/tty

            case "$choice" in
                1)
                    if command -v package_menu >/dev/null 2>&1; then
                        package_menu || true
                    else
                        log_error "Package module not found!"
                        sleep 2
                    fi
                    ;;
                2)
                    if command -v update_packages_menu >/dev/null 2>&1; then
                        update_packages_menu || true
                    else
                        log_error "Update module not found!"
                        sleep 2
                    fi
                    ;;
                3)
                    if command -v wifi_menu >/dev/null 2>&1; then
                        wifi_menu || true
                    else
                        log_error "WiFi setup module not found!"
                        sleep 2
                    fi
                    ;;
                4)
                    if command -v change_lan_ip_menu >/dev/null 2>&1; then
                        change_lan_ip_menu || true
                    else
                        log_error "LAN IP module not found!"
                        sleep 2
                    fi
                    ;;
                5)
                    if command -v load_balancer_menu >/dev/null 2>&1; then
                        load_balancer_menu || true
                    else
                        log_error "Load Balancer module not found!"
                        sleep 2
                    fi
                    ;;
                6)
                    if command -v network_menu >/dev/null 2>&1; then
                        network_menu || true
                    else
                        log_error "Network monitor module not found!"
                        sleep 2
                    fi
                    ;;
                7)
                    if command -v show_system_resources_menu >/dev/null 2>&1; then
                        show_system_resources_menu || true
                    else
                        log_error "Resource checker module not found!"
                        sleep 2
                    fi
                    ;;
                8)
                    if command -v maintenance_menu >/dev/null 2>&1; then
                        maintenance_menu || true
                    else
                        log_error "Maintenance module not found!"
                        sleep 2
                    fi
                    ;;
                0)
                    printf "  ${GRAY:-}TNX for using DayPass! =)  \n${RESET:-}"
                    exit 0
                    ;;
                *)
                    log_warn "Invalid choice!"
                    sleep 2
                    clear
                    ;;
            esac
        done
}