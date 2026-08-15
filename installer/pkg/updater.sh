#!/bin/sh

inspect_and_confirm_updates()
{
    echo "  📦 DayPass Package Inspection Table"
    echo "  ──────────────────────────────────────────────────────────────────────────────────────────"
    printf "   %-28s %-16s %-16s %-12s\n" "Package" "Installed" "Manifest Ver" "Action"
    echo "  ──────────────────────────────────────────────────────────────────────────────────────────"

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

    echo "  ──────────────────────────────────────────────────────────────────────────────────────────"
    printf "   Summary : %d to install, %d to upgrade, %d skipped!\n" "$INSTALL_COUNT" "$UPGRADE_COUNT" "$SKIP_COUNT"
    echo "  ──────────────────────────────────────────────────────────────────────────────────────────"
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

    if [ ! -f "$INSTALL_LOG" ] || [ ! -s "$INSTALL_LOG" ]; then
        log_warn "No installed packages log found. Please install DayPass packages first!"
        echo
        printf "  ${GRAY}Press [ENTER] to return to main menu ...${RESET}"
        read -r _ </dev/tty
        return 1
    fi

    FINAL_PACKAGES=$(cat "$INSTALL_LOG" | tr '\n' ' ')
    export FINAL_PACKAGES

    inspect_and_confirm_updates
    INSPECT_STATUS=$?

    if [ "$INSPECT_STATUS" -eq 2 ] || [ "$INSPECT_STATUS" -eq 3 ]; then
        printf "  ${GRAY}Press [ENTER] to return to main menu ...${RESET}"
        read -r _ </dev/tty
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
    printf "  ${GRAY}Press [ENTER] to return to main menu ...${RESET}"
    read -r _ </dev/tty
}