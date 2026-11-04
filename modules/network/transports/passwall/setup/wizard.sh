#!/bin/sh
# ============================================================
# DayPass - Passwall & Passwall 2 Installation Wizard
# ============================================================

# Proxy stack wizard: Passwall app -> mode -> review -> deploy
proxy_install_wizard()
{
    render_persistent_header

    ui_title "🕵️‍♀️ Select Package Type"
    echo "  1) 🔒 Passwall-1  (Legacy Stable Release)"
    echo "  2) 🔒 Passwall-2  (Modern Release - Recommended)"
    ui_nav_footer

    ui_prompt 2

    SELECTED_PACKAGES=""

    case "$UI_CHOICE" in
        1)
            SELECTED_PROFILE="passwall"
            ;;
        2)
            SELECTED_PROFILE="passwall2"
            ;;
        0)
            return 0
            ;;
        *)
            ui_nav_common "$UI_CHOICE" "packages" && return 0
            log_error "Invalid choice! Returning to menu ..."
            sleep 1
            return 1
            ;;
    esac

    export SELECTED_PROFILE

    # 1. Select Mode & Populate Profile Variables (Recommended or Custom)
    menu_mode || return 0

    # 2. Review Summary Screen
    review_install || return 0

    # 3. Deployment Pipeline
    render_persistent_header
    if deploy_targeted_packages; then
        echo
        log_success "All targeted components deployed successfully!"

        if command -v system_banner_post_install >/dev/null 2>&1; then
            system_banner_post_install
        fi

        ui_pause
    else
        echo
        log_error "Installation process failed!"
        ui_pause
        return 1
    fi

    return 0
}