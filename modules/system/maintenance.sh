#!/bin/sh

# 1. Purge Packages Installed by DayPass (selective engine in installer/pkg/purge.sh)
maintenance_purge_packages()
{
    if command -v purge_menu >/dev/null 2>&1; then
        purge_menu
        return $?
    fi
    log_error "Purge engine is not loaded."
    return 1
}

# 2. OpenWrt Factory Reset
factory_reset_system()
{
    echo
    printf "  ${RED}🚨 WARNING : FACTORY RESET SYSTEM${RESET}\n"
    printf "  This will erase ALL user configurations and restore system defaults!\n\n"
    
    printf "  Type '${BOLD}RESET${RESET}' to confirm factory reset : "
    read -r confirm </dev/tty

    if [ "$confirm" = "RESET" ]; then
        log_warn "Initiating Firstboot / Factory Reset procedure ..."
        sleep 2
        if command -v firstboot >/dev/null 2>&1; then
            firstboot -y && reboot
        else
            log_error "Command 'firstboot' not found on this system!"
            return 1
        fi
    else
        log_info "Factory reset aborted!"
    fi
}

# 3. Clean DayPass Temporary Cache
clean_daypass_cache()
{
    # Deployers clean their own workspaces; remaining files can be recovery evidence.
    log_info "Downloads are cleaned by each transaction. No separately owned cache files to remove."
}

# 4. Backup System Configuration
backup_system_config()
(
    umask 077
    local dir
    dir=$(mktemp -d /tmp/daypass-system-backup.XXXXXX) || return 1
    log_info "Generating OpenWrt system configuration backup ..."
    if sysupgrade -b "$dir/archive.part" && gzip -t "$dir/archive.part" &&
        tar -tzf "$dir/archive.part" >/dev/null && mv "$dir/archive.part" "$dir/backup.tar.gz"; then
        log_success "Backup saved to : [$dir/backup.tar.gz]"
    else
        rm -rf "$dir"
        log_error "Failed to generate system backup!"
        return 1
    fi
)

# Maintenance Sub-Menu
maintenance_menu()
{
    local HELP_MODULE_ID="system"

    while true; do
        render_persistent_header
        
        printf "  🛠️ ${BOLD}DayPass Maintenance & Recovery${RESET}\n"
        ui_divider
        printf "  🧹 1) Purge DayPass Installed Packages\n"
        printf "  🗑️ 2) Temporary Download Cleanup Status\n"
        printf "  💾 3) Backup System Configuration\n"
        printf "  🚨 4) Factory Reset OpenWrt (Firstboot)\n"
        printf "  🪧 5) SSH Login Banner (install / restore)\n"
        ui_nav_footer
        ui_prompt 5
        choice="$UI_CHOICE"

        case "$choice" in
            1) maintenance_purge_packages ;;
            2) clean_daypass_cache ;;
            3) backup_system_config ;;
            4) factory_reset_system ;;
            5)
                if command -v system_banner_manage >/dev/null 2>&1; then
                    system_banner_manage
                else
                    log_warn "Login banner module not loaded!"
                fi
                ;;
            q|Q) daypass_quit ;;
            h|H)
                if command -v show_help >/dev/null 2>&1; then
                    show_help "$HELP_MODULE_ID"
                else
                    log_warn "Help module not loaded!"
                    sleep 1
                fi
                continue
                ;;
            0) break ;;
            *)
                log_warn "Invalid choice!"
                sleep 2
                ;;
        esac
        
        printf "\n  ${GRAY:-}Press [Enter] to continue ... ${RESET:-}"
        read -r _ </dev/tty || daypass_quit
    done
}