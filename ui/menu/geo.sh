#!/bin/sh

geo_menu()
{
    render_persistent_header

    echo "  🕵️‍♀️ Select Geo Database                                      "
    echo "  ─────────────────────────────────────────────────────────── "
    echo "  🫸🏻 1) Skip       (Do not install Geo databases)             "
    echo "  👔 2) Official   (Standard official release packages)       "
    echo "  🍺 3) Iran Full  (Custom ruleset - Full database)           "
    echo "  🍷 4) Iran Lite  (Custom ruleset - Compact database)        "
    echo "  ─────────────────────────────────────────────────────────── "
    echo

    if command -v ui_nav_footer >/dev/null 2>&1; then
        ui_nav_footer
    fi
    printf "  ⁉️ Select option [1-4] : "
    read -r choice </dev/tty

    GEOIP_URL=""
    GEOSITE_URL=""

    case "$choice" in
        0) return 0 ;;
        q|Q) command -v daypass_quit >/dev/null 2>&1 && daypass_quit; return 0 ;;
        h|H) command -v ui_show_help >/dev/null 2>&1 && ui_show_help "packages"; geo_menu; return ;;
        1|"")
            SELECTED_GEO="none"
            ;;
        2)
            SELECTED_GEO="official"
            if [ "${PKG_MANAGER:-opkg}" = "apk" ]; then
                add_selected_package "geosite" 2>/dev/null || add_selected_package "v2ray-geosite"
                add_selected_package "geoip" 2>/dev/null || add_selected_package "v2ray-geoip"
            else
                add_selected_package "v2ray-geoip"
                add_selected_package "v2ray-geosite"
            fi
            ;;
        3)
            SELECTED_GEO="iran-full"
            GEOIP_URL="https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geoip.dat"
            GEOSITE_URL="https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geosite.dat"
            ;;
        4)
            SELECTED_GEO="iran-lite"
            GEOIP_URL="https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geoip-lite.dat"
            GEOSITE_URL="https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geosite-lite.dat"
            ;;
        *)
            log_warn "Invalid choice! Defaulting to Skip!"
            SELECTED_GEO="none"
            ;;
    esac

    export SELECTED_GEO
    export GEOIP_URL
    export GEOSITE_URL
}