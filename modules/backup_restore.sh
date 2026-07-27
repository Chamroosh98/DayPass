#!/bin/sh

# Config Backup and Restore Module for DayPass Deployment Stack
# Preserves critical UCI configurations during updates and system migration

BACKUP_DIR="/tmp/daypass/backups"
CONFIG_PATHS="/etc/config/passwall /etc/config/passwall2 /etc/config/xray /etc/config/sing-box /etc/config/niki"

# Creates a compressed timestamped archive of target configuration files
backup_configs()
{
    log_info "Initiating UCI configuration backup ..." 2>/dev/null || echo "[INFO] Initiating UCI configuration backup ..."

    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    ARCHIVE_FILE="$BACKUP_DIR/daypass_config_backup_$TIMESTAMP.tar.gz"

    EXISTING_TARGETS=""
    for path in $CONFIG_PATHS; do
        if [ -e "$path" ]; then
            EXISTING_TARGETS="$EXISTING_TARGETS $path"
        fi
    done

    if [ -z "$EXISTING_TARGETS" ]; then
        log_warn "No existing target configuration files found to backup." 2>/dev/null || echo "[WARN] No existing configs to backup."
        return 0
    fi

    if tar -czf "$ARCHIVE_FILE" $EXISTING_TARGETS 2>/dev/null; then
        # Create a symlink to latest backup
        ln -sf "$ARCHIVE_FILE" "$BACKUP_DIR/latest_backup.tar.gz"
        log_success "Backup created successfully : [$ARCHIVE_FILE]" 2>/dev/null || echo "[SUCCESS] Backup created."
        return 0
    else
        log_error "Failed to create configuration backup archive!" 2>/dev/null || echo "[ERROR] Backup failed."
        return 1
    fi
}

# Restores configurations from the latest backup archive
restore_configs()
{
    TARGET_ARCHIVE="${1:-$BACKUP_DIR/latest_backup.tar.gz}"

    if [ ! -f "$TARGET_ARCHIVE" ]; then
        log_error "Backup archive not found at path : [$TARGET_ARCHIVE]" 2>/dev/null || echo "[ERROR] Backup archive missing."
        return 1
    fi

    log_info "Restoring UCI configuration from : [$TARGET_ARCHIVE] ..." 2>/dev/null || echo "[INFO] Restoring configs..."

    if tar -xzf "$TARGET_ARCHIVE" -C / 2>/dev/null; then
        log_success "Configurations restored successfully from backup!" 2>/dev/null || echo "[SUCCESS] Configs restored."
        
        # Reload UCI subsystem to commit restored configs
        uci commit 2>/dev/null
        return 0
    else
        log_error "Failed to unpack backup archive during restore!" 2>/dev/null || echo "[ERROR] Restore failed."
        return 1
    fi
}

# Standalone execution handler
case "$0" in
    *backup_restore.sh)
        case "${1:-backup}" in
            backup)  backup_configs ;;
            restore) restore_configs "$2" ;;
        esac
        ;;
esac