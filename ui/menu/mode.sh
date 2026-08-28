#!/bin/sh

handle_recommended_profile()
{
    SELECTED_PACKAGES=""
    export SELECTED_PACKAGES
}

menu_mode()
{
    render_persistent_header

    echo "  🕵️‍♀️ Select Installation Mode                                "
    echo "  ───────────────────────────────────────────────────────────"
    echo "  1) ⚡ Recommended (Quick & Pre-configured for users)       "
    echo "  2) 🛠️ Custom      (Advanced package selection)             "
    echo "  ───────────────────────────────────────────────────────────"
    echo

    printf "  ⁉️ Select option [1-2] (Default: 1) : "
    read -r choice </dev/tty

    case "$choice" in
        1|"")
            SELECTED_MODE="recommended"  
            export SELECTED_MODE
            handle_recommended_profile
            ;;
        2)
            SELECTED_MODE="custom"       
            export SELECTED_MODE
            handle_custom_profile
            ;;
        *)
            log_warn "Invalid choice! Defaulting to Recommended mode!"
            SELECTED_MODE="recommended"   
            export SELECTED_MODE
            handle_recommended_profile
            ;;
    esac
}