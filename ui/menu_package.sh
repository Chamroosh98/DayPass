#!/bin/sh

package_menu()
{
    render_persistent_header

    echo "  ───────────────────────────────────────────────────────────"
    echo "    🕵️‍♀️ Select Package Type                                   "
    echo "  ───────────────────────────────────────────────────────────"
    echo "    🔒 1) Passwall-1  (Legacy Stable Release)                "
    echo "    🔒 2) Passwall-2  (Modern Release - Recommended)         "
    echo "  ───────────────────────────────────────────────────────────"
    echo

    printf "  ⁉️ Select option [1-2] : "
    read -r choice </dev/tty

    # Reset manual selections to let resolver handle exact dependency hierarchy
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

    # 1. Select Mode (Recommended / Custom) via modular menu
    menu_mode

    # 2. Select Engine, Language and Geo if Custom mode requires
    if [ "${SELECTED_MODE:-}" = "custom" ]; then
        engine_menu || return 1
        language_menu || return 1
        geo_menu || return 1
    else
        SELECTED_ENGINE="xray"
        SELECTED_LANGUAGE="fa"
        SELECTED_GEO="official"
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
        printf "  ${GRAY}Press [ENTER] to return to main menu ...${NC}"
        read -r _ </dev/tty
        render_persistent_header
    else
        echo
        log_error "Installation process failed!"
        echo
        printf "  ${GRAY}Press [ENTER] to return to main menu ...${NC}"
        read -r _ </dev/tty
        render_persistent_header
        return 1
    fi

    return 0
}