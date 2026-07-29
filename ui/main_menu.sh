#!/bin/sh

main_menu()
{
    while true; 
        do

            render_persistent_header
            
            printf "   📦 1) Install Package\n"
            printf "   🖥️ 2) Network Info & Speed Monitor\n"
            printf "   🛠️ 3) Maintenance & Recovery\n"
            printf "   🚪 0) Exit\n\n"

            printf "   ⁉️ Select option [0-3] : "
            read -r choice </dev/tty

            case "$choice" in
                1)
                    if command -v package_menu >/dev/null 2>&1; then
                        package_menu || true
                    fi
                    ;;
                2)
                    if command -v network_menu >/dev/null 2>&1; then
                        network_menu || true
                    fi
                    ;;
                3)
                    if command -v maintenance_menu >/dev/null 2>&1; then
                        maintenance_menu || true
                    else
                        log_error "Maintenance module not found!"
                        sleep 2
                    fi
                    ;;
                0)
                    printf "  ${GRAY:-}TNX for using DayPass! =)${RESET:-}"
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