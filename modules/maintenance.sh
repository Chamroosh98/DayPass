#!/bin/sh

# 1. Purge Packages Installed by DayPass
purge_daypass_packages()
{
    log_info "Analyzing installed DayPass packages ..."

    if [ ! -s "$INSTALL_LOG" ]; then
        log_warn "No installed package records found in $INSTALL_LOG!"
        return 0
    fi

    # Extract unique packages list safely
    INSTALLED_PKGS=$(sort -u "$INSTALL_LOG" | tr '\n' ' ')

    if [ -z "$INSTALLED_PKGS" ]; then
        log_warn "No tracked packages to purge."
        return 0
    fi

    echo
    printf "   ${YELLOW}⚠️ The following packages will be REMOVED:${RESET}\n"
    printf "   ${CYAN}%s${RESET}\n\n" "$INSTALLED_PKGS"

    printf "   Are you sure you want to purge these packages? [y/N]: "
    read -r confirm </dev/tty
    case "$confirm" in
        [yY][eE][sS]|[yY])
            log_info "Initiating package purge ..."
            
            PKG_MGR="${PKG_MANAGER:-opkg}"
            for pkg in $INSTALLED_PKGS; do
                [ -z "$pkg" ] && continue
                log_info "Removing [$pkg]..."
                case "$PKG_MGR" in
                    apk)  apk del "$pkg" >/dev/null 2>&1 || true ;;
                    opkg|*) opkg remove "$pkg" >/dev/null 2>&1 || true ;;
                esac
            done

            rm -f "$INSTALL_LOG"
            log_success "DayPass packages purged successfully!"
            ;;
        *)
            log_info "Purge cancelled by use :("
            ;;
    esac
}

# 2. OpenWrt Factory Reset
factory_reset_system()
{
    echo
    printf "   ${RED}🚨 WARNING : FACTORY RESET SYSTEM${RESET}\n"
    printf "   This will erase ALL user configurations and restore system defaults!\n\n"
    
    printf "   Type '${BOLD}RESET${RESET}' to confirm factory reset : "
    read -r confirm </dev/tty

    if [ "$confirm" = "RESET" ]; then
        log_warn "Initiating Firstboot / Factory Reset procedure ..."
        sleep 2
        if command -v firstboot >/dev/null 2>&1; then
            firstboot -y && reboot
        else
            log_error "Command 'firstboot' not found on this system!"
        fi
    else
        log_info "Factory reset aborted."
    fi
}

# 3. Clean DayPass Temporary Cache
clean_daypass_cache()
{
    log_info "Cleaning DayPass temporary files and package caches ..."
    rm -rf "${DAYPASS_DIR:?}"/*.apk "${DAYPASS_DIR:?}"/*.ipk "${DAYPASS_DIR:?}"/*.part 2>/dev/null
    log_success "Cache cleaned successfully!"
}

# 4. Backup System Configuration
backup_system_config()
{
    BACKUP_FILE="/tmp/backup-$(date +%Y%m%d_%H%M%S).tar.gz"
    log_info "Generating OpenWrt system configuration backup..."
    if sysupgrade -b "$BACKUP_FILE" >/dev/null 2>&1; then
        log_success "Backup saved to : [$BACKUP_FILE]"
    else
        log_error "Failed to generate system backup!"
    fi
}

# Maintenance Sub-Menu
maintenance_menu()
{
    while true; do
        render_persistent_header
        
        printf "   🛠️  ${BOLD}DayPass Maintenance & Recovery${RESET}\n"
        printf "   ──────────────────────────────────────────────────\n"
        printf "   🧹 1) Purge DayPass Installed Packages\n"
        printf "   🗑️ 2) Clean Temporary Cache & Downloads\n"
        printf "   💾 3) Backup System Configuration\n"
        printf "   🚨 4) Factory Reset OpenWrt (Firstboot)\n"
        printf "   🚪 0) Back to Main Menu\n\n"

        printf "   ⁉️ Select option [0-4] : "
        read -r choice </dev/tty

        case "$choice" in
            1) purge_daypass_packages ;;
            2) clean_daypass_cache ;;
            3) backup_system_config ;;
            4) factory_reset_system ;;
            0) break ;;
            *)
                log_warn "Invalid choice!"
                sleep 2
                ;;
        esac
        
        printf "   ${GRAY:-}\nPress [Enter] to continue ... ${RESET:-}"
        read -r _ </dev/tty
    done
}