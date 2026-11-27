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
    ui_divider
    [ -n "$_in_category" ] && printf "  ${GRAY}Category : %s${RESET}\n" "$_in_category"
    printf "  ${GRAY}Manifest : %s${RESET}\n" "${MANIFEST_REL:-unknown} / ${ARCH:-unknown}"
    ui_divider
    printf "   %-28s %-16s %-16s %-12s\n" "Package" "Installed" "Manifest Ver" "Action"
    ui_divider

    PACKAGES_TO_PROCESS=""
    UPDATE_FEEDS=""
    UPDATE_PATCHES=""
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

        ACTION_STR="[Version unknown]"
        
        receipt=$(pkg_receipt "$pkg" 2>/dev/null)
        if [ "$receipt" = feed ] || { [ -z "$receipt" ] && [ -z "$(manifest_lookup file "$pkg")" ]; }; then
            ACTION_STR="[Source unavailable]"
            if pkg_feed_available "$pkg"; then
                ACTION_STR="[Feed current]"
                if [ "$inst_ver" = None ]; then
                    ACTION_STR="[Feed install]"
                else
                    case "$PKG_MANAGER" in
                        opkg) listing=$(opkg list-upgradable) && listing=$(printf '%s\n' "$listing" | awk -v n="$pkg" '$1==n') ;;
                        apk) listing=$(apk list -u "$pkg") ;;
                    esac || { log_error "Cannot inspect feed updates for [$pkg]."; return 1; }
                    [ -z "$listing" ] || ACTION_STR="[Feed upgrade]"
                fi
                case "$ACTION_STR" in
                    "[Feed install]"|"[Feed upgrade]")
                        UPDATE_FEEDS="$UPDATE_FEEDS $pkg"
                        PACKAGES_TO_PROCESS="$PACKAGES_TO_PROCESS $pkg"
                        if [ "$inst_ver" = None ]; then INSTALL_COUNT=$((INSTALL_COUNT + 1)); else UPGRADE_COUNT=$((UPGRADE_COUNT + 1)); fi ;;
                    *) SKIP_COUNT=$((SKIP_COUNT + 1)) ;;
                esac
            else
                SKIP_COUNT=$((SKIP_COUNT + 1))
            fi
        elif [ -z "$(manifest_lookup file "$pkg")" ]; then
            ACTION_STR="[Manifest unavailable]"
            SKIP_COUNT=$((SKIP_COUNT + 1))
        elif [ "$inst_ver" = "None" ]; then
            ACTION_STR="${GREEN}[➕ Install]${RESET}"
            INSTALL_COUNT=$((INSTALL_COUNT + 1))
            PACKAGES_TO_PROCESS="$PACKAGES_TO_PROCESS $pkg"
        elif [ "$manif_ver" != "N/A" ] && [ "$manif_ver" != "Latest" ] && ! pkg_versions_match "$inst_ver" "$manif_ver"; then
            ACTION_STR="${YELLOW}[🔄 Upgrade]${RESET}"
            UPGRADE_COUNT=$((UPGRADE_COUNT + 1))
            PACKAGES_TO_PROCESS="$PACKAGES_TO_PROCESS $pkg"
        else
            manif_hash=$(printf %s "$manif_hash" | tr A-F a-f)
            inst_hash=$(pkg_get_installed_hash "$pkg" 2>/dev/null)
            if [ -n "$manif_hash" ] && [ "$manif_hash" != "null" ] && [ -n "$inst_hash" ] && [ "$inst_hash" != "$manif_hash" ]; then
                UPDATE_PATCHES="$UPDATE_PATCHES $pkg"
                ACTION_STR="${ORANGE}[🩹 Patch]${RESET}"
                UPGRADE_COUNT=$((UPGRADE_COUNT + 1))
                PACKAGES_TO_PROCESS="$PACKAGES_TO_PROCESS $pkg"
            else
                ACTION_STR="[Digest unknown]"
                [ -z "$inst_hash" ] || [ -z "$manif_hash" ] || ACTION_STR="[Current]"
                SKIP_COUNT=$((SKIP_COUNT + 1))
            fi
        fi

        inst_ver_fmt=$(printf "%.14s" "$inst_ver")
        manif_ver_fmt=$(printf "%.14s" "$manif_ver")

        printf "   🔹 ${CYAN}%-24s${RESET} ${YELLOW}%-14s${RESET} %-14s %b\n" \
            "$pkg" "$inst_ver_fmt" "$manif_ver_fmt" "$ACTION_STR"
    done

    ui_divider
    printf "   Summary : %d to install, %d to upgrade, %d skipped!\n" "$INSTALL_COUNT" "$UPGRADE_COUNT" "$SKIP_COUNT"
    ui_divider
    echo

    if [ -z "$PACKAGES_TO_PROCESS" ]; then
        log_success "No actionable package updates. See individual results above."
        return 2
    fi

    printf "  ⁉️ Do you want to proceed with deployment? [Y/n] : "
    read -r user_confirm </dev/tty || return 3
    echo

    case "$user_confirm" in
        ""|[yY]|[yY][eE][sS]) log_info "User confirmed. Proceeding with updates ..." ;;
        *) log_warn "Update cancelled."; return 3 ;;
    esac

    export PACKAGES_TO_PROCESS
    return 0
}


update_packages_menu()
{
    local UPDATE_FEEDS="" UPDATE_PATCHES="" FINAL_PACKAGES="" PACKAGES_TO_PROCESS=""
    local INSPECT_MODULE_ID="" INSPECT_MODULE_TITLE="" INSPECT_MODULE_CATEGORY=""
    render_persistent_header

    if command -v mf_migrate_from_log >/dev/null 2>&1; then
        mf_migrate_from_log || { log_error "Package registry migration failed."; return 1; }
    fi

    if command -v mf_has_modules >/dev/null 2>&1 && mf_has_modules; then
        echo "  📦 ${BOLD}Select a module to inspect${RESET}"
        ui_divider
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
        read -r _ </dev/tty || :
        return 1
    fi

    inspect_and_confirm_updates
    INSPECT_STATUS=$?

    if [ "$INSPECT_STATUS" -eq 2 ] || [ "$INSPECT_STATUS" -eq 3 ]; then
        printf "  ${GRAY}Press [ENTER] to go back ...${RESET}"
        read -r _ </dev/tty || :
        return 0
    fi

    [ "$INSPECT_STATUS" -eq 0 ] || return "$INSPECT_STATUS"
    local deploy_status=0
    if deploy_targeted_packages "$PACKAGES_TO_PROCESS" "$INSPECT_MODULE_ID" "$UPDATE_FEEDS" "$UPDATE_PATCHES" update; then
        echo
        log_success "All packages updated successfully!"
    else
        deploy_status=$?
        echo
        log_error "Update process failed!"
    fi

    echo
    printf "  ${GRAY}Press [ENTER] to go back ...${RESET}"
    read -r _ </dev/tty || :
    return "$deploy_status"
}
