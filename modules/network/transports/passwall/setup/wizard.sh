#!/bin/sh
# Passwall and Passwall 2 installation wizard.

proxy_install_wizard()
{
    local SELECTED_PROFILE SELECTED_MODE SELECTED_ENGINE SELECTED_LANGUAGE SELECTED_GEO
    local SELECTED_PACKAGES GEOIP_URL GEOSITE_URL FINAL_PACKAGES REVIEW_FEED_PACKAGES
    local MANIFEST_FILE="${MANIFEST_FILE:-}" _PR_MANIFEST _PR_ARCH wizard_status
    reset_state

    while true; do
        render_persistent_header
        ui_title "Select Passwall version"
        echo "  1) Passwall 1"
        echo "  2) Passwall 2 (Recommended)"
        ui_nav_footer
        ui_prompt 2

        case "$UI_CHOICE" in
            1) SELECTED_PROFILE="passwall" ;;
            2) SELECTED_PROFILE="passwall2" ;;
            0) return 0 ;;
            *)
                ui_nav_common "$UI_CHOICE" "packages" && continue
                log_warn "Select Passwall 1 or Passwall 2."
                sleep 1
                continue
                ;;
        esac

        export SELECTED_PROFILE
        wizard_status=0
        menu_mode || wizard_status=$?
        case "$wizard_status" in
            0) break ;;
            1) continue ;;
            *) return "$wizard_status" ;;
        esac
    done

    review_install || wizard_status=$?
    case "$wizard_status" in
        0) ;;
        1) return 0 ;;
        *) return "$wizard_status" ;;
    esac

    case "$SELECTED_GEO" in
        iran-full|iran-lite)
            if ! pw_stage_iran_assets "$SELECTED_PROFILE" "$SELECTED_GEO" "$GEOIP_URL" "$GEOSITE_URL"; then
                log_error "Dataset staging failed. Package deployment was cancelled."
                ui_pause
                return 1
            fi
            ;;
    esac

    MANIFEST_FILE="$_PR_MANIFEST"
    local ARCH="$_PR_ARCH"
    render_persistent_header
    if deploy_targeted_packages "$FINAL_PACKAGES" "$SELECTED_PROFILE" "$REVIEW_FEED_PACKAGES"; then
        if command -v system_banner_post_install >/dev/null 2>&1 &&
            ! system_banner_post_install; then
            log_warn "Package deployment succeeded. The login banner could not be installed."
        fi
        ui_pause
        return 0
    fi

    log_error "Package deployment failed."
    ui_pause
    return 1
}
