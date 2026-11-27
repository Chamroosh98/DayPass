#!/bin/sh

BACKUP_DNS_FILE="/etc/resolv.conf.daypass.bak"

# Keep the original and a receipt for the temporary resolver in one private
# directory. Existing legacy backups have no corresponding ownership receipt.
_dns_swap_resolver() (
    local live="$1" journal="$2" action="$3" address="${4:-}" tmp tmp_archive
    if [ "$action" = apply ]; then
        [ -f "$live" ] || return 1
        umask 077
        mkdir "$journal" || { log_error "Resolver recovery already pending: $journal"; return 1; }
        cp -a "$live" "$journal/original" || return 1
        if [ -L "$live" ]; then
            [ -L "$journal/original" ] &&
                [ "$(readlink "$live")" = "$(readlink "$journal/original")" ] || return 1
        else
            cmp -s "$live" "$journal/original" || return 1
        fi
        printf 'nameserver %s\n' "$address" > "$journal/applied" || return 1
        cp "$journal/applied" "$journal/expected" || return 1
        chmod 644 "$journal/applied" || return 1
        ln "$journal/applied" "$journal/next" && mv -f "$journal/next" "$live" || return 1
        return 0
    fi
    [ -d "$journal" ] && [ ! -L "$journal" ] &&
        [ ! -L "$live" ] && [ "$live" -ef "$journal/applied" ] && cmp -s "$live" "$journal/expected" ||
        { log_error "Current resolver has no matching recovery receipt."; return 1; }
    # Stage alongside the journal so relative symlinks resolve at their
    # original location after rename. Keep the original backup on all exits.
    tmp=$(mktemp -d "${live}.restore.XXXXXX") || return 1
    trap 'rm -f "$tmp/resolver"; rmdir "$tmp"' EXIT
    cp -a "$journal/original" "$tmp/resolver" &&
        mv -f "$tmp/resolver" "$live" || return 1
    if [ -L "$journal/original" ]; then
        [ -L "$live" ] && [ "$(readlink "$live")" = "$(readlink "$journal/original")" ] &&
            [ -f "$live" ] || return 1
    else
        cmp -s "$live" "$journal/original" || return 1
    fi
    tmp_archive=$(mktemp -d "${journal}.retained.XXXXXX") || return 1
    mv "$journal" "$tmp_archive/backup" || return 1
    log_warn "Resolver file restored. Backup retained at $tmp_archive/backup pending DNS service verification."
)

apply_dns() {
    case "${1:-1.1.1.1}" in 1.1.1.1|8.8.8.8|9.9.9.9) ;; *) return 1 ;; esac
    [ ! -e "$BACKUP_DNS_FILE" ] && [ ! -L "$BACKUP_DNS_FILE" ] ||
        { log_error "Legacy resolver backup requires manual verification."; return 1; }
    _dns_swap_resolver /etc/resolv.conf "$BACKUP_DNS_FILE.recovery" apply "${1:-1.1.1.1}"
}

restore_dns() {
    _dns_swap_resolver /etc/resolv.conf "$BACKUP_DNS_FILE.recovery" restore
}

# Interactive DNS resolution recovery menu
dns_fix_menu()
{
    local HELP_MODULE_ID="network_dns_recovery"

    while true; do
        render_persistent_header

        ui_divider
        echo "   📡 DNS Resolution Recovery                                "
        ui_divider
        echo "   ☁️ 1) Cloudflare DNS   (1.1.1.1)                          "
        echo "   🔍 2) Google DNS       (8.8.8.8)                          "
        echo "   🛡️ 3) Quad9 DNS        (9.9.9.9)                          "

        if [ -d "$BACKUP_DNS_FILE.recovery" ]; then
            echo "   4) 🔄 Restore Original DNS                           "
            echo "   5) 🚫 Skip                                           "
            MAX_OPT="5"
        else
            echo "   4) 🚫 Skip                                           "
            MAX_OPT="4"
        fi
        if command -v ui_nav_footer >/dev/null 2>&1; then
            ui_nav_footer
        fi

        printf "  ⁉️ Select option [1-%s] : " "$MAX_OPT"
        read -r dns_choice </dev/tty

        case "$dns_choice" in
            0) return 0 ;;
            q|Q)
                command -v daypass_quit >/dev/null 2>&1 && daypass_quit
                return 0
                ;;
            h|H)
                if command -v show_help >/dev/null 2>&1; then
                    show_help "$HELP_MODULE_ID"
                else
                    log_warn "Help module not loaded!"
                    sleep 1
                fi
                continue
                ;;
            1|"")
                apply_dns "1.1.1.1" || return $?
                ;;
            2)
                apply_dns "8.8.8.8" || return $?
                ;;
            3)
                apply_dns "9.9.9.9" || return $?
                ;;
            4)
                if [ -d "$BACKUP_DNS_FILE.recovery" ]; then
                    restore_dns || return $?
                else
                    log_info "Skipping DNS fix!"
                fi
                ;;
            5)
                log_info "Skipping DNS fix!"
                ;;
            *)
                log_info "Skipping DNS fix!"
                ;;
        esac
        return 0
    done
}

# Standalone execution handler
case "$0" in
    *dns_fix.sh) dns_fix_menu ;;
esac