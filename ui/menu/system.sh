#!/bin/sh
# ============================================================
# DayPass - System Maintenance & Backup
# ============================================================

# $1 grep -iE filter (empty = all of logread)
_system_log_fetch() {
    local filter="$1"
    local lines="$2"
    local dest="$3"

    : > "$dest"
    if [ -n "$filter" ]; then
        logread 2>/dev/null | grep -iE "$filter" | tail -n "$lines" > "$dest" 2>/dev/null || true
    else
        logread 2>/dev/null | tail -n "$lines" > "$dest" 2>/dev/null || true
    fi
}

_system_log_render() {
    local filter="$1"
    local label="$2"
    local lines dest shown

    render_persistent_header
    ui_title "📜 Log Viewer — $label"
    printf "  ${GRAY}Source : logread${RESET}\n"
    ui_divider
    printf "  ⁉️ ${YELLOW}Number of lines${RESET} ${GRAY}[50] :${RESET} "

    if ! read -r UI_CHOICE </dev/tty; then
        UI_CHOICE=""
        daypass_quit
    fi

    case "$UI_CHOICE" in
        0) return 0 ;;
        q|Q) daypass_quit ;;
        ''|*[!0-9]*) lines=50 ;;
        *) lines="$UI_CHOICE" ;;
    esac
    [ "$lines" -gt 0 ] 2>/dev/null || lines=50

    dest="/tmp/daypass_logview.$$"
    _system_log_fetch "$filter" "$lines" "$dest"

    echo
    if [ ! -s "$dest" ]; then
        ui_divider
        if [ -n "$filter" ]; then
            log_warn "No log entries found for the selected module."
        else
            log_info "Log buffer is empty."
        fi
        ui_divider
    else
        shown=$(wc -l < "$dest" | tr -d ' ')
        echo "  📋 Log Output (Last $shown lines)"
        ui_divider
        sed 's/^/  /' "$dest"
        ui_divider
    fi

    rm -f "$dest" 2>/dev/null
}

system_log_viewer() {
    local HELP_MODULE_ID="system_menu"

    while true; do
        render_persistent_header

        if ! command -v logread >/dev/null 2>&1; then
            ui_title "📜 Log Viewer"
            log_warn "logread is not available on this system."
            ui_divider
            return 0
        fi

        ui_title "📜 Log Viewer"
        echo "  🛡️ 1) DayPass & proxy engines"
        echo "  🌐 2) Network (netifd, dnsmasq, mwan3)"
        echo "  🔌 3) Kernel (USB / modem events)"
        echo "  📚 4) Everything"
        ui_nav_footer
        ui_prompt 4

        case "$UI_CHOICE" in
            1) _system_log_render "daypass|passwall|xray|sing-box|openvpn|wireguard|wg[0-9]" "DayPass & engines" ;;
            2) _system_log_render "netifd|dnsmasq|mwan3|odhcpd|udhcpc" "Network" ;;
            3) _system_log_render "kernel" "Kernel" ;;
            4) _system_log_render "" "Everything" ;;
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

system_restore_configs() {
    local archive="$BACKUP_DIR/latest_backup.tar.gz"

    render_persistent_header
    ui_title "💾 Restore DayPass Engine Configs"

    if [ -d "$BACKUP_DIR" ]; then
        ls -1t "$BACKUP_DIR"/daypass_config_backup_*.tar.gz 2>/dev/null | sed 's/^/  • /'
        ui_divider
    else
        log_info "No backup directory yet."
        ui_divider
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
            4) system_log_viewer; continue ;;
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
