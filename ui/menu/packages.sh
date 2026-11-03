#!/bin/sh
# ============================================================
# DayPass - Package Profiles & Dependencies
# ============================================================

# Resolves a profile, shows a friendly plan and installs it after confirmation.
# $1 profile id from config/package_profiles.json
install_profile_interactive()
{
    local profile="$1"
    local count title rel_label

    render_persistent_header

    if ! command -v resolve_profile >/dev/null 2>&1; then
        log_error "Package resolver not loaded!"
        ui_pause
        return 1
    fi

    title="$(profile_display_title "$profile" 2>/dev/null || echo "$profile")"
    printf "  📦 ${BOLD}Profile Installation: %s${RESET}\n" "$title"
    ui_divider

    rel_label="${OPENWRT_MAJOR:-${PROFILE_RELEASE:-?}}"
    log_info "Resolving package dependencies for OpenWrt [${rel_label}.x]..."

    : > "${DAYPASS_RESOLVE_LOG:-/tmp/daypass_resolve.log}"
    DAYPASS_RESOLVE_QUIET=1
    export DAYPASS_RESOLVE_QUIET
    if ! resolve_profile "$profile"; then
        DAYPASS_RESOLVE_QUIET=0
        log_error "Could not build the package list for this profile."
        log_info "Details : ${DAYPASS_RESOLVE_LOG:-/tmp/daypass_resolve.log}"
        ui_pause
        return 1
    fi
    DAYPASS_RESOLVE_QUIET=0

    count=$(echo $PROFILE_PACKAGES | wc -w | tr -d ' ')
    log_success "Ready — ${count:-0} component(s) selected."

    render_persistent_header
    render_profile_plan "$profile"

    profile_install_prompt "$title" "${count:-0}"
    case "$UI_CHOICE" in
        ''|y|Y)
            ;;
        0|n|N)
            log_info "Installation cancelled."
            ui_pause
            return 0
            ;;
        q|Q)
            daypass_quit
            ;;
        *)
            log_warn "Please answer Y or n."
            ui_pause
            return 0
            ;;
    esac

    echo
    DAYPASS_RESOLVE_QUIET=1
    DAYPASS_INSTALL_UI=1
    export DAYPASS_RESOLVE_QUIET DAYPASS_INSTALL_UI
    install_profile "$profile"
    _ip_rc=$?
    DAYPASS_RESOLVE_QUIET=0
    DAYPASS_INSTALL_UI=0
    export DAYPASS_RESOLVE_QUIET DAYPASS_INSTALL_UI
    echo
    ui_pause
    return "$_ip_rc"
}

packages_menu()
{
    local HELP_MODULE_ID="packages"

    while true; do
        render_persistent_header

        ui_title "📦 Package Profiles & Dependencies"
        echo "  🛡️ 1) Proxy & Evasion Cores"
        echo "  🔐 2) VPN & Tunnels"
        echo "  🔌 3) USB & Hardware Drivers"
        echo "  📈 4) Network Tools & Traffic"
        echo "  🔄 5) Check & Update Installed Packages"
        echo "  📋 6) Profile Status Dashboard"
        ui_nav_footer main

        ui_prompt 6

        case "$UI_CHOICE" in
            1) ui_run proxy_install_wizard "Proxy installer" ;;
            2) install_profile_interactive vpn ;;
            3) install_profile_interactive usb ;;
            4) install_profile_interactive network_tools ;;
            5) ui_run update_packages_menu "Update" ;;
            6) ui_run profile_status_dashboard "Profile dashboard" ;;
            0) return 0 ;;
            *)
                ui_nav_common "$UI_CHOICE" "$HELP_MODULE_ID" && continue
                log_warn "Invalid option!"
                sleep 1
                ;;
        esac
    done
}