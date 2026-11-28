#!/bin/sh

engine_menu()
{
    local confirm

    while true; do
        render_persistent_header
        ui_title "🕵️‍♀️ Select proxy engine"
        echo "  1) ⚡ Auto (profile defaults to Xray)"
        echo "  2) ✖️ Xray"
        echo "  3) 📦 Sing-box"
        ui_nav_footer back

        ui_prompt 3

        case "$UI_CHOICE" in
            1|"")
                SELECTED_ENGINE="auto"
                break
                ;;
            2)
                SELECTED_ENGINE="xray"
                add_selected_package "xray-core"
                break
                ;;
            3)
                SELECTED_ENGINE="sing-box"
                echo
                log_warn "Sing-box may consume higher RAM on low-end hardware!"
                printf "  ⁉️  Are you sure you want to proceed with Sing-box? [y/N] : "
                read -r confirm </dev/tty || daypass_quit
                case "$confirm" in
                    y|Y)
                        add_selected_package "sing-box"
                        break
                        ;;
                    *)
                        log_info "Reverting Proxy Engine selection to Auto!"
                        SELECTED_ENGINE="auto"
                        break
                        ;;
                esac
                ;;
            0) return 1 ;;
            q|Q) daypass_quit ;;
            h|H) ui_show_help "packages" ;;
            *)
                log_warn "Invalid choice!"
                sleep 1
                ;;
        esac
    done
    export SELECTED_ENGINE
}
