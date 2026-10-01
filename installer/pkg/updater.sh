#!/bin/sh

inspect_and_confirm_updates()
{
    _in_title="DayPass"
    _in_category=""
    if command -v mf_inspection_title >/dev/null 2>&1; then
        _in_title="$(mf_inspection_title)"
        _in_category="$(mf_inspection_category)"
    elif [ -n "${SELECTED_PROFILE:-}" ]; then
        _in_title="${SELECTED_PROFILE}"
    fi

    echo "  📦 ${_in_title} Package Inspection Table"
    echo "  ─────────────────────────────────────────────────────────── "
    [ -n "$_in_category" ] && printf "  ${GRAY}Category : %s${RESET}\n" "$_in_category"
    printf "  ${GRAY}Manifest : %s${RESET}\n" "${MANIFEST_REL:-unknown} / ${ARCH:-unknown}"
    echo "  ─────────────────────────────────────────────────────────── "
    printf "   %-28s %-16s %-16s %-12s\n" "Package" "Installed" "Manifest Ver" "Action"
    echo "  ─────────────────────────────────────────────────────────── "

    PACKAGES_TO_PROCESS=""
    UPGRADE_COUNT=0
    INSTALL_COUNT=0
    SKIP_COUNT=0

    for pkg in $FINAL_PACKAGES; do
        raw_inst_ver=$(pkg_get_installed_version "$pkg" 2>/dev/null | head -n1)
        inst_ver=$(echo "$raw_inst_ver" | awk '{print $1}' | tr -d ':')
        
        if [ "$inst_ver" = "$pkg" ] || [ -z "$inst_ver" ]; then
            inst_ver="None"
        fi
        
        manif_ver=$(manifest_lookup "version" "$pkg")
        manif_hash=$(manifest_lookup "sha256" "$pkg")
        
        [ -z "$manif_ver" ] || [ "$manif_ver" = "null" ] && manif_ver="N/A"

        ACTION_STR=""
        
        if [ "$inst_ver" = "None" ]; then
            ACTION_STR="${GREEN}[➕ Install]${RESET}"
            INSTALL_COUNT=$((INSTALL_COUNT + 1))
            PACKAGES_TO_PROCESS="$PACKAGES_TO_PROCESS $pkg"
        elif [ "$manif_ver" != "N/A" ] && [ "$manif_ver" != "Latest" ] && [ "$inst_ver" != "$manif_ver" ]; then
            ACTION_STR="${YELLOW}[🔄 Upgrade]${RESET}"
            UPGRADE_COUNT=$((UPGRADE_COUNT + 1))
            PACKAGES_TO_PROCESS="$PACKAGES_TO_PROCESS $pkg"
        elif [ "$manif_ver" = "Latest" ] || [ "$inst_ver" = "$manif_ver" ]; then
            inst_hash=$(pkg_get_installed_hash "$pkg" 2>/dev/null)
            if [ -n "$manif_hash" ] && [ "$manif_hash" != "null" ] && [ -n "$inst_hash" ] && [ "$inst_hash" != "$manif_hash" ]; then
                ACTION_STR="${ORANGE}[🩹 Patch]${RESET}"
                UPGRADE_COUNT=$((UPGRADE_COUNT + 1))
                PACKAGES_TO_PROCESS="$PACKAGES_TO_PROCESS $pkg"
            else
                ACTION_STR="${GREEN}[✅ Up-to-date]${RESET}"
                SKIP_COUNT=$((SKIP_COUNT + 1))
            fi
        fi

        inst_ver_fmt=$(printf "%.14s" "$inst_ver")
        manif_ver_fmt=$(printf "%.14s" "$manif_ver")

        printf "   🔹 ${CYAN}%-24s${RESET} ${YELLOW}%-14s${RESET} %-14s %b\n" \
            "$pkg" "$inst_ver_fmt" "$manif_ver_fmt" "$ACTION_STR"
    done

    echo "  ─────────────────────────────────────────────────────────── "
    printf "   Summary : %d to install, %d to upgrade, %d skipped!\n" "$INSTALL_COUNT" "$UPGRADE_COUNT" "$SKIP_COUNT"
    echo "  ─────────────────────────────────────────────────────────── "
    echo

    if [ -z "$PACKAGES_TO_PROCESS" ]; then
        log_success "All packages are up-to-date! No changes required!"
        return 2
    fi

    printf "  ⁉️ Do you want to proceed with deployment? [Y/n] : "
    read -r user_confirm </dev/tty
    echo

    case "$user_confirm" in
        [nN][oO]|[nN])
            log_warn "Update cancelled by user!"
            return 3
            ;;
        *)
            log_info "User confirmed. Proceeding with updates ..."
            echo
            ;;
    esac

    export PACKAGES_TO_PROCESS
    return 0
}


update_packages_menu()
{
    render_persistent_header

    if command -v mf_migrate_from_log >/dev/null 2>&1; then
        mf_migrate_from_log >/dev/null 2>&1 || true
    fi

    if command -v mf_has_modules >/dev/null 2>&1 && mf_has_modules; then
        echo "  📦 ${BOLD}Select a module to inspect${RESET}"
        echo "  ───────────────────────────────────────────────────────────"
        _up_i=0
        _up_ids=""
        for _up_id in $(mf_module_ids); do
            _up_i=$((_up_i + 1))
            _up_ids="${_up_ids:+$_up_ids }$_up_id"
            printf "  ${CYAN}%s${RESET}) %s ${GRAY}(%s)${RESET}\n" \
                "$_up_i" "$(mf_module_title "$_up_id")" "$(mf_module_category "$_up_id")"
        done
        _up_all=$((_up_i + 1))
        printf "  ${CYAN}%s${RESET}) All DayPass packages\n" "$_up_all"
        ui_nav_footer
        ui_prompt "$_up_all"

        case "$UI_CHOICE" in
            0) return 0 ;;
            q|Q) daypass_quit ;;
            h|H) ui_show_help "packages"; return 0 ;;
        esac

        INSPECT_MODULE_ID=""
        INSPECT_MODULE_TITLE=""
        INSPECT_MODULE_CATEGORY=""
        FINAL_PACKAGES=""

        if [ "$UI_CHOICE" = "$_up_all" ]; then
            FINAL_PACKAGES=$(cat "${INSTALL_LOG:-/dev/null}" 2>/dev/null | tr '\n' ' ')
            INSPECT_MODULE_TITLE="DayPass"
        elif [ "$UI_CHOICE" -ge 1 ] 2>/dev/null && [ "$UI_CHOICE" -le "$_up_i" ]; then
            _up_n=0
            for _up_id in $_up_ids; do
                _up_n=$((_up_n + 1))
                if [ "$_up_n" -eq "$UI_CHOICE" ]; then
                    INSPECT_MODULE_ID="$_up_id"
                    INSPECT_MODULE_TITLE="$(mf_module_title "$_up_id")"
                    INSPECT_MODULE_CATEGORY="$(mf_module_category "$_up_id")"
                    FINAL_PACKAGES="$(mf_module_packages "$_up_id")"
                    break
                fi
            done
        else
            log_warn "Invalid option!"
            ui_pause
            return 1
        fi
        export FINAL_PACKAGES INSPECT_MODULE_ID INSPECT_MODULE_TITLE INSPECT_MODULE_CATEGORY
        echo
    elif [ -f "$INSTALL_LOG" ] && [ -s "$INSTALL_LOG" ]; then
        FINAL_PACKAGES=$(cat "$INSTALL_LOG" | tr '\n' ' ')
        export FINAL_PACKAGES
    else
        log_warn "No installed packages log found. Please install DayPass packages first!"
        echo
        printf "  ${GRAY}Press [ENTER] to go back ...${RESET}"
        read -r _ </dev/tty || daypass_quit
        return 1
    fi

    inspect_and_confirm_updates
    INSPECT_STATUS=$?

    if [ "$INSPECT_STATUS" -eq 2 ] || [ "$INSPECT_STATUS" -eq 3 ]; then
        printf "  ${GRAY}Press [ENTER] to go back ...${RESET}"
        read -r _ </dev/tty || daypass_quit
        return 0
    fi

    if deploy_targeted_packages; then
        echo
        log_success "All packages updated successfully!"
    else
        echo
        log_error "Update process failed!"
    fi

    echo
    printf "  ${GRAY}Press [ENTER] to go back ...${RESET}"
    read -r _ </dev/tty || daypass_quit
}