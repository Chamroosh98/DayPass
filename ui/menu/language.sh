#!/bin/sh

language_menu()
{
    if [ "$SELECTED_PROFILE" != "passwall2" ]; then
        SELECTED_LANGUAGE="en"
        export SELECTED_LANGUAGE
        return 0
    fi

    render_persistent_header

    echo "  🕵️‍♀️ Select Language (Passwall 2)                             "
    ui_divider
    echo "  1) 🦁☀️ Persian  (fa)                                       "
    echo "  2) 🇬🇧   English  (en)                                       "
    echo "  3) 🇨🇳   Chinese  (zh)                                       "
    echo "  4) 🇷🇺   Russian  (ru)                                       "
    ui_divider
    echo

    if command -v ui_nav_footer >/dev/null 2>&1; then
        ui_nav_footer
    fi
    printf "  ⁉️ Select option [1-4] : "
    read -r choice </dev/tty

    case "$choice" in
        0) return 0 ;;
        q|Q) command -v daypass_quit >/dev/null 2>&1 && daypass_quit; return 0 ;;
        h|H) command -v ui_show_help >/dev/null 2>&1 && ui_show_help "packages"; language_menu; return ;;
        1|"")
            SELECTED_LANGUAGE="fa"
            add_selected_package "luci-i18n-passwall2-fa"
            ;;
        2)
            SELECTED_LANGUAGE="en"
            ;;
        3)
            SELECTED_LANGUAGE="zh-cn"
            add_selected_package "luci-i18n-passwall2-zh-cn"
            ;;
        4)
            SELECTED_LANGUAGE="ru"
            add_selected_package "luci-i18n-passwall2-ru"
            ;;
        *)
            log_warn "Invalid choice! Defaulting to English."
            SELECTED_LANGUAGE="en"
            ;;
    esac

    export SELECTED_LANGUAGE
}