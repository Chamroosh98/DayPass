#!/bin/sh

menu_mode()
{
    local custom_status

    while true; do
        render_persistent_header
        ui_title "Select installation mode"
        echo "  1) Recommended (Xray and standard GeoIP/GeoSite packages)"
        echo "  2) Custom      (Choose packages and preferences)"
        ui_nav_footer
        ui_prompt 2

        case "$UI_CHOICE" in
            0) return 1 ;;
            1|"")
                SELECTED_MODE="recommended"
                export SELECTED_MODE
                handle_recommended_profile
                return $?
                ;;
            2)
                SELECTED_MODE="custom"
                export SELECTED_MODE
                custom_status=0
                handle_custom_profile || custom_status=$?
                [ "$custom_status" -ne 1 ] || continue
                return "$custom_status"
                ;;
            *)
                ui_nav_common "$UI_CHOICE" "packages" && continue
                log_warn "Select Recommended or Custom."
                sleep 1
                ;;
        esac
    done
}
