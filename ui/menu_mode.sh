#!/bin/sh

menu_mode()
{
    render_persistent_header

    echo "  ───────────────────────────────────────────────────────────"
    echo "    🕵️‍♀️ Select Installation Mode                              "
    echo "  ───────────────────────────────────────────────────────────"
    echo "    1) ⚡ Recommended (Quick & Pre-configured for users)     "
    echo "    2) 🛠️ Custom      (Advanced package selection)           "
    echo "  ───────────────────────────────────────────────────────────"
    echo

    printf "  ⁉️ Select option [1-2] (Default: 1) : "
    read -r choice </dev/tty

    case "$choice" in
        1|"")
            handle_recommended_profile
            ;;
        2)
            handle_custom_profile
            ;;
        *)
            log_warn "Invalid choice! Defaulting to Recommended mode!"
            handle_recommended_profile
            ;;
    esac
}