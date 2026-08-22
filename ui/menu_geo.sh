#!/bin/sh

geo_menu()
{
    render_persistent_header

    echo "  🕵️‍♀️ Select Geo Database                                     "
    echo "  ─────────────────────────────────────────────────────────── "
    echo "  🫸🏻 1) Skip       (Do not install Geo databases)             "
    echo "  👔 2) Official   (Standard official release packages)       "
    echo "  🍺 3) Iran Full  (Custom ruleset - Full database)           "
    echo "  🍷 4) Iran Lite  (Custom ruleset - Compact database)        "
    echo "  ─────────────────────────────────────────────────────────── "
    echo

    printf "  ⁉️ Select option [1-4] (Default: 1) : "
    read -r choice </dev/tty

    GEOIP_URL=""
    GEOSITE_URL=""

    case "$choice" in
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