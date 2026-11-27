#!/bin/sh

language_menu()
{
    if [ "$SELECTED_PROFILE" != "passwall2" ]; then
        SELECTED_LANGUAGE="en"
        export SELECTED_LANGUAGE
        return 0
    fi

    while true; do
        render_persistent_header
        ui_title "Select Passwall 2 translation"
        echo "  1) Persian (fa)"
        echo "  2) English (built in)"
        echo "  3) Simplified Chinese (zh-cn)"
        echo "  4) Russian (ru)"
        ui_nav_footer back

        ui_prompt 4

        case "$UI_CHOICE" in
            1|"")
                SELECTED_LANGUAGE="fa"
                add_selected_package "luci-i18n-passwall2-fa"
                break
                ;;
            2)
                SELECTED_LANGUAGE="en"
                break
                ;;
            3)
                SELECTED_LANGUAGE="zh-cn"
                add_selected_package "luci-i18n-passwall2-zh-cn"
                break
                ;;
            4)
                SELECTED_LANGUAGE="ru"
                add_selected_package "luci-i18n-passwall2-ru"
                break
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
    export SELECTED_LANGUAGE
}
