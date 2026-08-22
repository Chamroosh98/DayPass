#!/bin/sh

main_menu()
{
    while true; do
        render_persistent_header

        printf "  📦 1) Install Package Profile\n"
        printf "  🔄 2) Check & Update Packages\n"
        printf "  🌐 3) Network Settings\n"
        printf "  🛡️ 4) Proxy & Routing Manager\n"
        printf "  🖥️ 5) System Resources & Hardware Info\n"
        printf "  🛠️ 6) Maintenance & Recovery\n"
        printf "  🚪 0) Exit\n\n"

        printf "  ⁉️ Select option [0-6] : "
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
                if command -v network_menu >/dev/null 2>&1; then
                    network_menu || true
                else
                    log_error "Network menu not found!"
                    sleep 2
                fi
                ;;
            4)
                if command -v proxy_menu >/dev/null 2>&1; then
                    proxy_menu || true
                else
                    log_error "Proxy menu not found!"
                    sleep 2
                fi
                ;;
            
            5)
                if command -v show_system_resources_menu >/dev/null 2>&1; then
                    show_system_resources_menu || true
                else
                    log_error "Resource checker module not found!"
                    sleep 2
                fi
                ;;
            6)
                if command -v maintenance_menu >/dev/null 2>&1; then
                    maintenance_menu || true
                else
                    log_error "Maintenance module not found!"
                    sleep 2
                fi
                ;;
            0)
                printf "  ${GRAY}TNX for using DayPass! =)${RESET}\n"
                exit 0
                ;;
            *)
                log_warn "Invalid choice!"
                sleep 1
                ;;
        esac
    done
}