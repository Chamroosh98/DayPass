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
            sha256) alt_field="SHA256" ;;
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

    if [ -n "$sha256" ] && [ "$sha256" != "null" ]; then
        if ! echo "$sha256  $tmp" | sha256sum -c - >/dev/null 2>&1; then
            log_error "SHA256 checksum MISMATCH for : [$package]!"
            rm -f "$tmp"
            trap - INT TERM
            return 1
        fi
    fi

    mv "$tmp" "$target"
    trap - INT TERM
    log_success "Package [$package] downloaded and verified!"
    return 0
}

# Pre-Install Inspection Table with strict ANSI alignment
inspect_and_confirm_packages()
{
    C_RESET="\033[0m"
    C_PKG="\033[1;36m"
    C_VER="\033[0;33m"
    C_UPG="\033[1;33m"
    C_INS="\033[1;32m"
    C_OK="\033[0;32m"

    echo "  📦 DayPass Package Inspection Table"
    echo "  ──────────────────────────────────────────────────────────────────────────────────────────"
    printf "   %-32s %-18s %-18s %-12s\n" "Package" "Installed" "Manifest Ver" "Action"
    echo "  ──────────────────────────────────────────────────────────────────────────────────────────"

    PACKAGES_TO_PROCESS=""
    UPGRADE_COUNT=0
    INSTALL_COUNT=0
    SKIP_COUNT=0

    for pkg in $FINAL_PACKAGES; do
        inst_ver=$(pkg_get_installed_version "$pkg")
        manif_ver=$(manifest_lookup "version" "$pkg")
        manif_hash=$(manifest_lookup "sha256" "$pkg")
        
        [ -z "$inst_ver" ] && inst_ver="None"
        [ -z "$manif_ver" ] || [ "$manif_ver" = "null" ] && manif_ver="N/A"

        ACTION_STR=""
        
        if [ "$inst_ver" = "None" ]; then
            ACTION_STR="${C_INS}[➕ Install]${C_RESET}"
            INSTALL_COUNT=$((INSTALL_COUNT + 1))
            PACKAGES_TO_PROCESS="$PACKAGES_TO_PROCESS $pkg"
        elif [ "$manif_ver" != "N/A" ] && [ "$manif_ver" != "Latest" ] && [ "$inst_ver" != "$manif_ver" ]; then
            ACTION_STR="${C_UPG}[🔄 Upgrade]${C_RESET}"
            UPGRADE_COUNT=$((UPGRADE_COUNT + 1))
            PACKAGES_TO_PROCESS="$PACKAGES_TO_PROCESS $pkg"
        elif [ "$manif_ver" = "Latest" ] || [ "$inst_ver" = "$manif_ver" ]; then
            # Hash Mismatch Check for Patch updates (SourceForge/Rebuilds)
            inst_hash=$(pkg_get_installed_hash "$pkg" 2>/dev/null)
            if [ -n "$manif_hash" ] && [ "$manif_hash" != "null" ] && [ -n "$inst_hash" ] && [ "$inst_hash" != "$manif_hash" ]; then
                ACTION_STR="${C_UPG}[🩹 Patch]${C_RESET}"
                UPGRADE_COUNT=$((UPGRADE_COUNT + 1))
                PACKAGES_TO_PROCESS="$PACKAGES_TO_PROCESS $pkg"
            else
                ACTION_STR="${C_OK}[✅ Up-to-date]${C_RESET}"
                SKIP_COUNT=$((SKIP_COUNT + 1))
            fi
        fi

        printf "   🔹 ${C_PKG}%-26s${C_RESET} ${C_VER}%-16s${C_RESET} %-16s %b\n" \
            "$pkg" "$inst_ver" "$manif_ver" "$ACTION_STR"
    done

    echo "  ──────────────────────────────────────────────────────────────────────────────────────────"
    printf "   Summary: %d to install, %d to upgrade, %d skipped.\n" "$INSTALL_COUNT" "$UPGRADE_COUNT" "$SKIP_COUNT"
    echo "  ──────────────────────────────────────────────────────────────────────────────────────────"
    echo

    if [ -z "$PACKAGES_TO_PROCESS" ]; then
        log_success "All packages are up-to-date! No changes required."
        return 2
    fi

    # Interactive User Confirmation Prompt
    printf " Do you want to proceed with deployment? [Y/n]: "
    read -r user_confirm
    case "$user_confirm" in
        [nN][oO]|[nN])
            log_warn "Installation cancelled by user."
            return 3
            ;;
        *)
            log_info "User confirmed. Proceeding with installation..."
            ;;
    esac

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

    if [ "$INSPECT_STATUS" -eq 2 ] || [ "$INSPECT_STATUS" -eq 3 ]; then
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
        
        rm -f $INSTALL_FILES 2>/dev/null
        rm -f "$TRANSACTION_LOG"
        
        log_success "All targeted packages deployed successfully!"
        return 0
    fi

    log_error "Package manager batch execution failed!"
    rollback_failed_install
    return 1
}

rollback_failed_install()
{
    echo
    log_warn "=================================================="
    log_warn "Initiating Selective Atomic Rollback Procedures ..."
    log_warn "=================================================="
    echo

    rm -f "$TMP_DIR"/*.part "$TMP_DIR"/*.apk "$TMP_DIR"/*.ipk 2>/dev/null

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