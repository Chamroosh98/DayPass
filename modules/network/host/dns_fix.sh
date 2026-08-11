#!/bin/sh

BACKUP_DNS_FILE="/etc/resolv.conf.daypass.bak"

# Apply temporary DNS fix for package managers (opkg/apk) and system resolution
apply_dns()
{
    NEW_DNS="${1:-1.1.1.1}"
    log_info "Setting temporary DNS to : [$NEW_DNS]"

    if [ -f /etc/resolv.conf ] || [ -L /etc/resolv.conf ]; then
        # Backup original resolv.conf structure if not already backed up
        if [ ! -f "$BACKUP_DNS_FILE" ]; then
            cp -a /etc/resolv.conf "$BACKUP_DNS_FILE" 2>/dev/null
            log_success "Original DNS backed up to : [$BACKUP_DNS_FILE]"
        fi

        # Unlink if /etc/resolv.conf is a symlink to prevent overwriting targets unexpectedly
        if [ -L /etc/resolv.conf ]; then
            rm -f /etc/resolv.conf
        fi

        # Write new nameserver directly for immediate resolution
        echo "nameserver $NEW_DNS" > /etc/resolv.conf
        
        # Optionally apply to UCI network configuration for persistence during setup
        if command -v uci >/dev/null 2>&1; then
            uci -q del network.wan.dns 2>/dev/null || true
            uci -q add_list network.wan.dns="$NEW_DNS" 2>/dev/null || true
        fi

        log_success "DNS changed to : [$NEW_DNS]"
    fi
}

# Restore original DNS configuration from backup
restore_dns()
{
    if [ -f "$BACKUP_DNS_FILE" ]; then
        rm -f /etc/resolv.conf 2>/dev/null
        cp -a "$BACKUP_DNS_FILE" /etc/resolv.conf 2>/dev/null
        rm -f "$BACKUP_DNS_FILE" 2>/dev/null
        
        # Revert UCI changes if needed
        if command -v uci >/dev/null 2>&1; then
            uci -q del network.wan.dns 2>/dev/null || true
        fi

        log_success "Original DNS restored successfully!"
    else
        log_warn "No DNS backup found to restore!"
    fi
}

# Interactive DNS resolution recovery menu
dns_fix_menu()
{
    if command -v render_persistent_header >/dev/null 2>&1; then
        render_persistent_header
    else
        clear
    fi

    echo "  ───────────────────────────────────────────────────────────"
    echo "   📡 DNS Resolution Recovery                                "
    echo "  ───────────────────────────────────────────────────────────"
    echo "   ☁️ 1) Cloudflare DNS   (1.1.1.1)                          "
    echo "   🔍 2) Google DNS       (8.8.8.8)                          "
    echo "   🛡️ 3) Quad9 DNS        (9.9.9.9)                          "
    
    if [ -f "$BACKUP_DNS_FILE" ]; then
        echo "   4) 🔄 Restore Original DNS                           "
        echo "   5) 🚫 Skip                                           "
        MAX_OPT="5"
    else
        echo "   4) 🚫 Skip                                           "
        MAX_OPT="4"
    fi
    echo "  ───────────────────────────────────────────────────────────"
    echo

    printf "  ⁉️ Select option [1-%s] (Default: 1) : " "$MAX_OPT"
    read -r dns_choice </dev/tty

    case "$dns_choice" in
        1|"")
            apply_dns "1.1.1.1"
            ;;
        2)
            apply_dns "8.8.8.8"
            ;;
        3)
            apply_dns "9.9.9.9"
            ;;
        4) 
            if [ -f "$BACKUP_DNS_FILE" ]; then
                restore_dns
            else
                log_info "Skipping DNS fix!"
            fi
            ;;
        *)
            log_info "Skipping DNS fix!"
            ;;
    esac
}

# Standalone execution handler
case "$0" in
    *dns_fix.sh) dns_fix_menu ;;
esac