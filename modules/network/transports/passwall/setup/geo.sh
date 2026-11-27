#!/bin/sh

geo_menu()
{
    while true; do
        render_persistent_header
        ui_title "Select GeoIP/GeoSite data"
        echo "  1) Skip adding GeoIP/GeoSite targets"
        echo "  2) Official (standard packages)"
        echo "  3) Iran Full (stage only)"
        echo "  4) Iran Lite (stage only)"
        ui_nav_footer back

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
            0) return 1 ;;
            q|Q) daypass_quit ;;
            h|H) ui_show_help "packages" ;;
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
