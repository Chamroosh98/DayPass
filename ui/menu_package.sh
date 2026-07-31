#!/bin/sh

package_menu()
{
    render_persistent_header

    echo "    🕵️‍♀️ Select Package Type                                   "
    echo "  ───────────────────────────────────────────────────────────"
    echo "    🔒 1) Passwall-1  (Legacy Stable Release)                "
    echo "    🔒 2) Passwall-2  (Modern Release - Recommended)         "
    echo "  ───────────────────────────────────────────────────────────"
    echo

    printf "  ⁉️ Select option [1-2] : "
    read -r choice </dev/tty

    SELECTED_PACKAGES=""

    case "$choice" in
        1)
            SELECTED_PROFILE="passwall"
            ;;
        2)
            SELECTED_PROFILE="passwall2"
            ;;
        *)
            log_error "Invalid choice! Returning to menu ..."
            sleep 1
            return 1
            ;;
    esac

    export SELECTED_PROFILE

    # 1. Select Mode (Recommended or Custom)
    menu_mode

    # 2. Set environment vars based on Mode
    if [ "${SELECTED_MODE:-}" = "recommended" ]; then
        SELECTED_ENGINE="xray"
        SELECTED_LANGUAGE="fa"
        SELECTED_GEO="official"
        export SELECTED_ENGINE SELECTED_LANGUAGE SELECTED_GEO
    else
        SELECTED_ENGINE="custom"
        SELECTED_LANGUAGE="auto-detected"
        SELECTED_GEO="auto-detected"
        export SELECTED_ENGINE SELECTED_LANGUAGE SELECTED_GEO
    fi

    # 3. Review Summary Screen 
    review_install || return 1

    # 4. Deployment Pipeline
    render_persistent_header
    if deploy_targeted_packages; then
        echo
        log_success "All targeted components deployed successfully!"
        echo
        printf "  ${GRAY}Press [ENTER] to return to main menu ...${RESET}"
        read -r _ </dev/tty
        render_persistent_header
    else
        echo
        log_error "Installation process failed!"
        echo
        printf "  ${GRAY}Press [ENTER] to return to main menu ...${RESET}"
        read -r _ </dev/tty
        render_persistent_header
        return 1
    fi

    return 0
}