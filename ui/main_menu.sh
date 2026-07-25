#!/bin/sh

main_menu()
{
    while true; 
        do
            printf "   📦 1) Install Package\n"
            printf "   🖥️ 2) Network Info & Speed Monitor\n"
            printf "   🚪 0) Exit\n\n"

            printf "   ⁉️ Select option [0-2] : "
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
                0)
                    log_info "Exiting DayPass ..."
                    exit 0
                    ;;
                *)
                    log_warn "Invalid choice!"
                    sleep 3
                    clear
                    ;;
            esac
        done
}