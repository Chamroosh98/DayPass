#!/bin/sh
# ============================================================
# DayPass - System Maintenance & Backup
# ============================================================

system_log_viewer() {
    local lines filter

    if ! command -v logread >/dev/null 2>&1; then
        log_warn "logread not available on this system."
        return 0
    fi

    echo
    ui_title "📜 Log Viewer"
    echo "  1) DayPass & proxy engines"
    echo "  2) Network (netifd, dnsmasq, mwan3)"
    echo "  3) Kernel (USB / modem events)"
    echo "  4) Everything"
    echo "  🚪 0) Back"
    ui_read "Select option [0-4]"

    case "$UI_CHOICE" in
        1) filter="daypass|passwall|xray|sing-box|openvpn|wireguard|wg[0-9]" ;;
        2) filter="netifd|dnsmasq|mwan3|odhcpd|udhcpc" ;;
        3) filter="kernel" ;;
        4) filter="" ;;
        q|Q) daypass_quit ;;
        *) return 0 ;;
    esac

    ui_read "Number of lines [50]"
    case "$UI_CHOICE" in
        q|Q) daypass_quit ;;
        ''|*[!0-9]*) lines=50 ;;
        *) lines="$UI_CHOICE" ;;
    esac

    echo "  ───────────────────────────────────────────────────────────"
    if [ -n "$filter" ]; then
        logread 2>/dev/null | grep -iE "$filter" | tail -n "$lines"
    else
        logread 2>/dev/null | tail -n "$lines"
    fi
    echo "  ───────────────────────────────────────────────────────────"
}

system_restore_configs() {
    local archive="$BACKUP_DIR/latest_backup.tar.gz"

    if [ -d "$BACKUP_DIR" ]; then
        echo
        ui_title "💾 Available Backups"
        ls -1t "$BACKUP_DIR"/daypass_config_backup_*.tar.gz 2>/dev/null | sed 's/^/  • /'
    fi

    ui_read "Archive path [latest], [0] Cancel"
    case "$UI_CHOICE" in
        0) return 0 ;;
        q|Q) daypass_quit ;;
        '') ;;
        *) archive="$UI_CHOICE" ;;
    esac

    ui_read "Overwrite current engine configs from [$archive]? [y/N]"
    case "$UI_CHOICE" in
        y|Y) restore_configs "$archive" ;;
        q|Q) daypass_quit ;;
    esac
}

system_menu() {
    local HELP_MODULE_ID="system_menu"

    while true; do
        render_persistent_header

        ui_title "🛠️ System Maintenance & Backup"
        echo "  🧰 1) Maintenance & Recovery (purge, cache, factory reset)"
        echo "  💾 2) Backup DayPass Engine Configs"
        echo "  ♻️ 3) Restore DayPass Engine Configs"
        echo "  📜 4) Log Viewer"
        echo "  🔄 5) System Updates (check & update packages)"
        ui_nav_footer main

        ui_prompt 5

        case "$UI_CHOICE" in
            1) ui_run maintenance_menu "Maintenance"; continue ;;
            2) ui_run backup_configs "Backup" ;;
            3) system_restore_configs ;;
            4) system_log_viewer ;;
            5) ui_run update_packages_menu "Update"; continue ;;
            0) return 0 ;;
            *)
                ui_nav_common "$UI_CHOICE" "$HELP_MODULE_ID" && continue
                log_warn "Invalid option!"
                sleep 1
                continue
                ;;
        esac

        ui_pause
    done
}
