#!/bin/sh
# ============================================================
# DayPass - Passwall Installation Mode Selector
# ============================================================

menu_mode()
{
    render_persistent_header

    ui_title "🕵️‍♀️ Select Installation Mode"
    echo "  1) ⚡ Recommended (Quick & Pre-configured for IRANIAN users)"
    echo "  2) 🛠️ Custom      (Advanced package selection)"
    ui_nav_footer

    ui_prompt 2
    choice="$UI_CHOICE"

    case "$choice" in
        0)
            return 1
            ;;
        q|Q)
            daypass_quit
            ;;
        h|H)
            ui_show_help "packages"
            menu_mode
            return $?
            ;;
        1|"")
            SELECTED_MODE="recommended"
            export SELECTED_MODE
            handle_recommended_profile
            ;;
        2)
            SELECTED_MODE="custom"
            export SELECTED_MODE
            handle_custom_profile || return 1
            ;;
        *)
            log_warn "Invalid choice! Defaulting to Recommended mode!"
            SELECTED_MODE="recommended"
            export SELECTED_MODE
            handle_recommended_profile
            ;;
    esac
}