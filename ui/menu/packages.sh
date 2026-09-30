#!/bin/sh
# ============================================================
# DayPass - Package Profiles & Dependencies
# ============================================================

# Proxy stack wizard: Passwall app -> mode -> review -> deploy
proxy_install_wizard()
{
    render_persistent_header

    ui_title "🕵️‍♀️ Select Package Type"
    echo "  🔒 1) Passwall-1  (Legacy Stable Release)"
    echo "  🔒 2) Passwall-2  (Modern Release - Recommended)"
    echo "  ───────────────────────────────────────────────────────────"
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

    # 1. Select Mode (Recommended or Custom)
    menu_mode || return 0

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
    review_install || return 0

    # 4. Deployment Pipeline
    render_persistent_header
    if deploy_targeted_packages; then
        echo
        log_success "All targeted components deployed successfully!"
        ui_pause
    else
        echo
        log_error "Installation process failed!"
        ui_pause
        return 1
    fi

    return 0
}

# Resolves a profile, shows the plan and installs it after confirmation.
# $1 profile id from config/package_profiles.json
install_profile_interactive()
{
    local profile="$1"
    local count

    render_persistent_header

    if ! command -v resolve_profile >/dev/null 2>&1; then
        log_error "Package resolver not loaded!"
        ui_pause
        return 1
    fi

    if ! resolve_profile "$profile"; then
        ui_pause
        return 1
    fi

    count=$(echo $PROFILE_PACKAGES | wc -w | tr -d ' ')
    echo
    ui_title "📦 Profile [$profile] : ${count:-0} package(s)"
    printf '%s\n' "$PROFILE_PLAN" | while IFS='|' read -r name source optional alts _; do
        [ -n "$name" ] || continue
        if [ "$optional" = "1" ]; then
            printf "     ├─ 🔹 ${CYAN}%s${RESET} ${GRAY}(%s, optional)${RESET}\n" "$name" "$source"
        else
            printf "     ├─ 🔹 ${CYAN}%s${RESET} ${GRAY}(%s)${RESET}\n" "$name" "$source"
        fi
        [ -n "$alts" ] && printf "     │    ${GRAY}alternatives : %s${RESET}\n" "$alts"
    done
    echo "  ───────────────────────────────────────────────────────────"
    echo

    ui_read "Install this profile? [y/N]"
    case "$UI_CHOICE" in
        y|Y) ;;
        q|Q) daypass_quit ;;
        *)
            log_info "Installation cancelled."
            ui_pause
            return 0
            ;;
    esac

    echo
    install_profile "$profile"
    ui_pause
}

packages_menu()
{
    local HELP_MODULE_ID="packages"

    while true; do
        render_persistent_header

        ui_title "📦 Package Profiles & Dependencies"
        printf "  ${GRAY}Package manager : %s | OpenWrt : %s${RESET}\n" "${PKG_MANAGER:-auto}" "${OPENWRT_MAJOR:-auto}"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  🛡️ 1) Proxy & Evasion Cores     (Passwall wizard)"
        echo "  🔐 2) VPN & Tunnels             (WireGuard, OpenVPN, ...)"
        echo "  🔌 3) USB & Hardware Drivers    (RNDIS, CDC, ModeSwitch)"
        echo "  📈 4) Network Tools & Traffic   (mwan3, SQM, TPROXY, ...)"
        echo "  🔄 5) Check & Update Installed Packages"
        echo "  📋 6) List Package Profiles"
        echo "  ───────────────────────────────────────────────────────────"
        ui_nav_footer main

        ui_prompt 6

        case "$UI_CHOICE" in
            1) ui_run proxy_install_wizard "Proxy installer" ;;
            2) install_profile_interactive vpn ;;
            3) install_profile_interactive usb ;;
            4) install_profile_interactive network_tools ;;
            5) ui_run update_packages_menu "Update" ;;
            6)
                echo
                ui_run list_package_profiles "Package resolver"
                ui_pause
                ;;
            0) return 0 ;;
            *)
                ui_nav_common "$UI_CHOICE" "$HELP_MODULE_ID" && continue
                log_warn "Invalid option!"
                sleep 1
                ;;
        esac
    done
}
