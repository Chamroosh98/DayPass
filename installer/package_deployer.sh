#!/bin/sh

INSTALL_LOG="/tmp/daypass/install.log"
TRANSACTION_LOG="/tmp/daypass/transaction.log"

manifest_lookup()
{
    field="$1"
    package="$2"

    val=$(jq -r \
        --arg pkg "$package" \
        --arg arch "$ARCH" \
        --arg field "$field" \
'
.architectures[]?
| select(.name == $arch)
| .packages[]?
| select(
    (.package == $pkg)
    or
    (.package | startswith($pkg + "-"))
)
| .[$field] // empty
' \
"$MANIFEST_FILE" 2>/dev/null | head -n1)

    if [ -z "$val" ] || [ "$val" = "null" ]; then
        alt_field=""
        case "$field" in
            size) alt_field="Size" ;;
            Size) alt_field="size" ;;
            version) alt_field="Version" ;;
            Version) alt_field="version" ;;
        esac

        if [ -n "$alt_field" ]; then
            val=$(jq -r \
                --arg pkg "$package" \
                --arg arch "$ARCH" \
                --arg field "$alt_field" \
'
.architectures[]?
| select(.name == $arch)
| .packages[]?
| select(
    (.package == $pkg)
    or
    (.package | startswith($pkg + "-"))
)
| .[$field] // empty
' \
"$MANIFEST_FILE" 2>/dev/null | head -n1)
        fi
    fi

    echo "$val"
}

format_size()
{
    bytes="${1:-0}"
    if [ "$bytes" -ge 1048576 ]; then
        awk "BEGIN {printf \"%.2f MB\", $bytes/1048576}" 2>/dev/null
    elif [ "$bytes" -ge 1024 ]; then
        awk "BEGIN {printf \"%.1f KB\", $bytes/1024}" 2>/dev/null
    else
        echo "${bytes} Bytes"
    fi
}

# Resilient Download Logic with SHA256 Verification & Timeout Control
download_package()
{
    package="$1"

    file=$(manifest_lookup "file" "$package")
    sha256=$(manifest_lookup "sha256" "$package")

    if [ -z "$file" ] || [ "$file" = "null" ]; then
        log_error "Package [$package] not found in manifest for target [$ARCH]!"
        return 1
    fi

    base_url=$(jq -r '.download_base // empty' "$MANIFEST_FILE" 2>/dev/null)
    [ -z "$base_url" ] && base_url="$REPO_URL"
    target_url="${base_url}/${file}"

    file_basename=$(basename "$file")
    target="$TMP_DIR/$file_basename"
    tmp="$target.part"

    # Skip download if already verified in current session
    if [ -f "$target" ]; then
        if echo "$sha256  $target" | sha256sum -c - >/dev/null 2>&1; then
            log_info "Cached package [$package] verified successfully. Skipping download."
            return 0
        fi
        rm -f "$target"
    fi

    log_info "Downloading [$package] -> $target_url"
    
    DOWNLOAD_SUCCESS=0
    trap 'rm -f "$tmp" 2>/dev/null' INT TERM

    # Network resilient parameters (Retry 3 times, longer timeouts for Iran connections)
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 15 --max-time 120 --retry 3 --retry-delay 2 "$target_url" -o "$tmp" && DOWNLOAD_SUCCESS=1
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=20 --tries=3 -O "$tmp" "$target_url" && DOWNLOAD_SUCCESS=1
    elif command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -q --timeout=20 -O "$tmp" "$target_url" && DOWNLOAD_SUCCESS=1
    fi

    if [ "$DOWNLOAD_SUCCESS" -ne 1 ] || [ ! -s "$tmp" ]; then
        log_error "Download failed or timed out for : [$package]!"
        rm -f "$tmp"
        trap - INT TERM
        return 1
    fi

    # SHA256 Check
    if ! echo "$sha256  $tmp" | sha256sum -c - >/dev/null 2>&1; then
        log_error "SHA256 checksum MISMATCH for : [$package]!"
        rm -f "$tmp"
        trap - INT TERM
        return 1
    fi

    mv "$tmp" "$target"
    trap - INT TERM
    log_success "Package [$package] downloaded and SHA256 verified!"
    return 0
}

# Pre-Install Inspection Table
inspect_and_confirm_packages()
{
    echo
    echo "  ───────────────────────────────────────────────────────────"
    echo "   📦 DayPass Package Inspection Table"
    echo "  ───────────────────────────────────────────────────────────"
    printf "   %-22s %-12s %-15s\n" "Package" "Installed" "Manifest Ver"
    echo "  ───────────────────────────────────────────────────────────"

    PACKAGES_TO_PROCESS=""
    UPGRADE_COUNT=0
    INSTALL_COUNT=0
    SKIP_COUNT=0

    for pkg in $FINAL_PACKAGES; do
        inst_ver=$(pkg_get_installed_version "$pkg")
        manif_ver=$(manifest_lookup "version" "$pkg")
        
        [ -z "$inst_ver" ] && inst_ver="None"
        [ -z "$manif_ver" ] && manif_ver="Latest"

        if [ "$inst_ver" = "None" ]; then
            ACTION="📥 Install"
            INSTALL_COUNT=$((INSTALL_COUNT + 1))
            PACKAGES_TO_PROCESS="$PACKAGES_TO_PROCESS $pkg"
        elif [ "$inst_ver" != "$manif_ver" ]; then
            ACTION="🔄 Upgrade"
            UPGRADE_COUNT=$((UPGRADE_COUNT + 1))
            PACKAGES_TO_PROCESS="$PACKAGES_TO_PROCESS $pkg"
        else
            ACTION="⚡ Up-to-date"
            SKIP_COUNT=$((SKIP_COUNT + 1))
        fi

        printf "   %-22s %-12s %-15s [%s]\n" "$pkg" "$inst_ver" "$manif_ver" "$ACTION"
    done

    echo "  ───────────────────────────────────────────────────────────"
    printf "   Summary: %d to install, %d to upgrade, %d skipped.\n" "$INSTALL_COUNT" "$UPGRADE_COUNT" "$SKIP_COUNT"
    echo "  ───────────────────────────────────────────────────────────"
    echo

    if [ -z "$PACKAGES_TO_PROCESS" ]; then
        log_success "All packages are up-to-date! No changes required."
        return 2
    fi

    export PACKAGES_TO_PROCESS
    return 0
}

deploy_targeted_packages()
{
    rm -f /var/lock/opkg.lock /lib/apk/db/lock /var/run/apk.lock /run/apk/db.lock 2>/dev/null

    mkdir -p "$(dirname "$INSTALL_LOG")"
    touch "$INSTALL_LOG"
    rm -f "$TRANSACTION_LOG"
    touch "$TRANSACTION_LOG"

    inspect_and_confirm_packages
    INSPECT_STATUS=$?

    if [ "$INSPECT_STATUS" -eq 2 ]; then
        return 0
    fi

    resource_snapshot
    if ! estimate_install_size; then
        log_error "Installation aborted due to system resource limits."
        return 1
    fi

    INSTALL_FILES=""

    # Download Phase
    for pkg in $PACKAGES_TO_PROCESS; do
        if ! download_package "$pkg"; then
            log_error "Failed downloading dependency : [$pkg]"
            rollback_failed_install
            return 1
        fi

        file=$(manifest_lookup "file" "$pkg")
        file_basename=$(basename "$file")
        INSTALL_FILES="$INSTALL_FILES $TMP_DIR/$file_basename"
    done

    echo
    log_info "Executing Batch Package Installation ..."

    # Log into Transaction File for Rollback tracking
    for pkg in $PACKAGES_TO_PROCESS; do
        echo "$pkg" >> "$TRANSACTION_LOG"
    done

    INSTALL_SUCCESS=0
    CURRENT_PKG_MGR="${PKG_MANAGER:-opkg}"

    case "$CURRENT_PKG_MGR" in
        apk)
            log_info "Installing packages via APK engine..."
            if apk add --allow-untrusted --no-progress $INSTALL_FILES >/tmp/apk_inst.log 2>&1; then
                INSTALL_SUCCESS=1
            else
                log_error "APK install error:"
                cat /tmp/apk_inst.log
            fi
            rm -f /tmp/apk_inst.log
            ;;
        opkg|*)
            log_info "Installing packages via OPKG engine..."
            if opkg install --force-reinstall --force-checksum $INSTALL_FILES >/tmp/opkg_inst.log 2>&1; then
                INSTALL_SUCCESS=1
            else
                log_error "OPKG install error:"
                cat /tmp/opkg_inst.log
            fi
            rm -f /tmp/opkg_inst.log
            ;;
    esac

    if [ "$INSTALL_SUCCESS" -eq 1 ]; then
        echo "$PACKAGES_TO_PROCESS" >> "$INSTALL_LOG"
        resource_compare
        
        # Cleanup temporary files
        rm -f $INSTALL_FILES 2>/dev/null
        rm -f "$TRANSACTION_LOG"
        
        log_success "All targeted packages deployed successfully!"
        return 0
    fi

    log_error "Package manager batch execution failed!"
    rollback_failed_install
    return 1
}

# Atomic Rollback Function
rollback_failed_install()
{
    echo
    log_warn "=================================================="
    log_warn "Initiating Selective Atomic Rollback Procedures ..."
    log_warn "=================================================="
    echo

    # 1. Clean downloaded temp packages
    rm -f "$TMP_DIR"/*.part "$TMP_DIR"/*.apk "$TMP_DIR"/*.ipk 2>/dev/null

    # 2. Rollback only modified/partially installed packages from transaction log
    if [ -s "$TRANSACTION_LOG" ]; then
        log_info "Rolling back modified packages from current session..."
        while read -r pkg; do
            [ -z "$pkg" ] && continue
            log_info "Rollback: Removing package [$pkg] ..."
            
            case "${PKG_MANAGER:-opkg}" in
                apk)  apk del "$pkg" >/dev/null 2>&1 || true ;;
                opkg|*) opkg remove "$pkg" >/dev/null 2>&1 || true ;;
            esac
        done < "$TRANSACTION_LOG"
    else
        log_info "No system packages were installed in this session. Skipping removal."
    fi

    rm -f "$TRANSACTION_LOG"
    log_success "Rollback procedure completed safely!"
}