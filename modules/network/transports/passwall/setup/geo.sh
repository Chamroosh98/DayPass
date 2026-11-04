#!/bin/sh

geo_menu()
{
    while true; do
        render_persistent_header
        ui_title "🕵️‍♀️ Select Geo Database"
        echo "  🫸🏻 1) Skip       (The DB files won't install)"
        echo "  👔 2) Official   (Standard packages)"
        echo "  🍺 3) Iran Full  (Full database)"
        echo "  🍷 4) Iran Lite  (Compact database)"
        ui_nav_footer

        ui_prompt 4

        GEOIP_URL=""
        GEOSITE_URL=""

        case "$UI_CHOICE" in
            1|"")
                SELECTED_GEO="none"
                break
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
                break
                ;;
            3)
                SELECTED_GEO="iran-full"
                GEOIP_URL="https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geoip.dat"
                GEOSITE_URL="https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geosite.dat"
                break
                ;;
            4)
                SELECTED_GEO="iran-lite"
                GEOIP_URL="https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geoip-lite.dat"
                GEOSITE_URL="https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geosite-lite.dat"
                break
                ;;
            0) return 0 ;;
            q|Q) daypass_quit ;;
            *)
                log_warn "Invalid choice!"
                sleep 1
                ;;
        esac
    done

    export SELECTED_GEO
    export GEOIP_URL
    export GEOSITE_URL
}