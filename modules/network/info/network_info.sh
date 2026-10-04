#!/bin/sh
# DayPass - Network info menu.
# Discovery, queries, screens, and the speed monitor live in
# discover.sh, fetch.sh, ui.sh, panel.sh, and speed.sh.

show_full_network_info() {
    net_show_panel
}

show_live_speed() {
    net_monitor_live_speed
}

network_info_menu() {
    local HELP_MODULE_ID="network_info"

    while true; do
        if command -v render_persistent_header >/dev/null 2>&1; then
            render_persistent_header
        fi
        show_full_network_info
        ui_nav_footer
        ui_prompt 2

        case "$UI_CHOICE" in
            q|Q) daypass_quit ;;
            h|H)
                if command -v show_help >/dev/null 2>&1; then
                    show_help "$HELP_MODULE_ID"
                else
                    log_warn "Help module not loaded!"
                    sleep 1
                fi
                continue
                ;;
            1) show_live_speed ;;
            2) continue ;;
            0) break ;;
            *)
                if command -v log_warn >/dev/null 2>&1; then
                    log_warn "Invalid choice!"
                else
                    echo "  Invalid choice!"
                fi
                ;;
        esac
    done
}

case "$0" in
    *network_info.sh)
        command -v ui_prompt >/dev/null 2>&1 || { echo "Run this menu from DayPass (install.sh)."; exit 1; }
        network_info_menu
        ;;
esac
