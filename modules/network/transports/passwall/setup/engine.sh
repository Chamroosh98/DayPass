#!/bin/sh

engine_menu()
{
    while true; do
        render_persistent_header
        ui_title "🕵️‍♀️ Select Proxy Engine"
        echo "  1) ⚡ Auto      (Recommended)"
        echo "  2) ✖️ Xray                  "
        echo "  3) 📦 SingBox               "
        ui_nav_footer

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
                read -r confirm </dev/tty
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
            0) return 0 ;;
            q|Q) daypass_quit ;;
            *)
                log_warn "Invalid choice!"
                sleep 1
                ;;
        esac
    done
    export SELECTED_ENGINE
}