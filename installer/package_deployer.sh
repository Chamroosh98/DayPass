#!/bin/sh


INSTALL_LOG="/tmp/daypass/install.log"
TRANSACTION_LOG="/tmp/daypass/transaction.log"

# Queries manifest metadata for a given package and field

manifest_lookup()
{
    field="$1"
    package="$2"

    jq -r \
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
"$MANIFEST_FILE" 2>/dev/null | head -n1
}


# Formats package size into human-readable units (KB / MB)

format_size()
{
    bytes="$1"
    if [ -z "$bytes" ] || [ "$bytes" = "null" ]; then
        echo "0 B"
        return
    fi

    if [ "$bytes" -ge 1048576 ]; then
        mb=$(awk "BEGIN {printf \"%.2f\", $bytes/1048576}")
        echo "${mb} MB"
    elif [ "$bytes" -ge 1024 ]; then
        kb=$(awk "BEGIN {printf \"%.1f\", $bytes/1024}")
        echo "${kb} KB"
    else
        echo "${bytes} Bytes"
    fi
}


# Fetches package details for UI display

manifest_info()
{
    package="$1"

    raw_size=$(manifest_lookup "size" "$package")
    formatted_size=$(format_size "$raw_size")
    file_name=$(manifest_lookup "file" "$package")

    echo "[$package] -> $file_name ($formatted_size)"
}


# Downloads and verifies package integrity against SHA256 checksum

download_package()
{
    package="$1"

    file=$(manifest_lookup "file" "$package")
    sha256=$(manifest_lookup "sha256" "$package")

    if [ -z "$file" ] || [ "$file" = "null" ]; then
        log_error "Package [$package] not found in manifest for architecture [$ARCH]!"
        return 1
    fi

    # download_base from manifest
    base_url=$(jq -r '.download_base // empty' "$MANIFEST_FILE" 2>/dev/null)
    
    if [ -n "$base_url" ]; then
        target_url="${base_url}/${file}"
    else
        target_url="${REPO_URL}/${file}"
    fi

    file_basename=$(basename "$file")
    target="$TMP_DIR/$file_basename"
    tmp="$target.part"

    mkdir -p "$(dirname "$target")"

    log_info "Processing Package : $(manifest_info "$package")"
    log_info "Target URL         : $target_url"
    log_info "Downloading [$package] ..."

    # Resilient download logic with fallback
    DOWNLOAD_SUCCESS=0
    
    trap 'rm -f "$tmp" 2>/dev/null; return 1' INT TERM

    # تنظیم پارامترهای تایم‌اوت برای جلوگیری از Hang در پکت‌لاس
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 10 --max-time 60 --speed-time 15 --speed-limit 1000 "$target_url" -o "$tmp" && DOWNLOAD_SUCCESS=1
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=15 --tries=2 -O "$tmp" "$target_url" && DOWNLOAD_SUCCESS=1
    elif command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -q --timeout=15 -O "$tmp" "$target_url" && DOWNLOAD_SUCCESS=1
    fi

    if [ "$DOWNLOAD_SUCCESS" -ne 1 ] || [ ! -s "$tmp" ]; then
        log_error "Download failed or produced empty file for : [$package]!"
        rm -f "$tmp"
        trap - INT TERM    # Reset trap 
        return 1
    fi

    # SHA256 Checksum Verification
    log_info "Verifying SHA256 checksum for : [$file_basename]!"
    if ! echo "$sha256  $tmp" | sha256sum -c - >/dev/null 2>&1; then
        log_error "Checksum verification FAILED for : [$package]!"
        log_warn "Expected Hash : [$sha256]"
        rm -f "$tmp"
        trap - INT TERM    # Reset trap
        return 1
    fi

    mv "$tmp" "$target"
    trap - INT TERM    # Reset trap
    log_success "Package [$package] verified successfully!"
}


# Orchestrates download, dependency resolution, and batch installation

deploy_targeted_packages()
{
    rm -f /var/lock/opkg.lock /lib/apk/db/lock /var/run/apk.lock 2>/dev/null

    mkdir -p "$(dirname "$INSTALL_LOG")"
    touch "$INSTALL_LOG"
    
    # Initialize transaction log for rollback tracking
    rm -f "$TRANSACTION_LOG"
    touch "$TRANSACTION_LOG"

    if command -v pkg_update >/dev/null 2>&1; then
        pkg_update
    fi

    echo
    log_info "=================================================="
    log_info "Starting Package Deployment Pipeline"
    log_info "=================================================="
    echo

    # Resource check integration (if available)
    if command -v resource_snapshot >/dev/null 2>&1; then
        resource_snapshot
    fi

    if command -v estimate_install_size >/dev/null 2>&1; then
        estimate_install_size
    fi

    INSTALL_FILES=""

    # 1. Download and verify all target packages
    for pkg in $FINAL_PACKAGES; do
        if ! download_package "$pkg"; then
            log_error "Failed during download phase : [$pkg]"
            rollback_failed_install
            return 1
        fi

        file=$(manifest_lookup "file" "$pkg")
        file_basename=$(basename "$file")
        INSTALL_FILES="$INSTALL_FILES $TMP_DIR/$file_basename"
        
        # Record package in transaction log BEFORE installation
        echo "[$pkg]" >> "$TRANSACTION_LOG"
    done

    echo
    log_info "Batch installing resolved package files ..."
    log_info "Package List : [$FINAL_PACKAGES]"
    echo

    # 2. Perform installation via native package manager
    INSTALL_SUCCESS=0

    case "$PKG_MANAGER" in
        apk)
            log_info "Installing packages into system via APK..."
            APK_LOG=$(mktemp)
            
            if apk add --allow-untrusted --no-progress $INSTALL_FILES >"$APK_LOG" 2>&1; then
                INSTALL_SUCCESS=1
            else
                log_error "APK installation failed! Output:"
                cat "$APK_LOG"
            fi
            rm -f "$APK_LOG"
            ;;
        opkg)
            log_info "Installing packages into system via OPKG..."
            OPKG_LOG=$(mktemp)
            
            if opkg install $INSTALL_FILES >"$OPKG_LOG" 2>&1; then
                INSTALL_SUCCESS=1
            else
                log_error "OPKG installation failed! Output:"
                cat "$OPKG_LOG"
            fi
            rm -f "$OPKG_LOG"
            ;;
    esac

    # 3. Post-installation check and state commit
    if [ "$INSTALL_SUCCESS" -eq 1 ]; then
        echo "$FINAL_PACKAGES" >> "$INSTALL_LOG"
        
        if command -v resource_compare >/dev/null 2>&1; then
            resource_compare
        fi

        # Clear transaction log on successful deployment
        rm -f "$TRANSACTION_LOG"
        log_success "All targeted packages deployed successfully!"
        return 0
    fi

    log_error "Batch installation failed during package manager execution!"
    rollback_failed_install
    return 1
}


# Rolls back changes if installation fails mid-way

rollback_failed_install()
{
    echo
    log_warn "=================================================="
    log_warn "Initiating Automatic Rollback Procedures ..."
    log_warn "=================================================="
    echo

    if [ ! -s "$TRANSACTION_LOG" ]; then
        log_warn "Transaction log is empty! No installed packages to Rollback!"
        return 0
    fi

    case "$PKG_MANAGER" in
        opkg)
            while read -r pkg; do
                [ -z "$pkg" ] && continue
                log_info "Rollback : Removing package [$pkg] ..."
                opkg remove "$pkg" >/dev/null 2>&1 || log_warn "Could not remove : [$pkg]"
            done < "$TRANSACTION_LOG"
            ;;
        apk)
            while read -r pkg; do
                [ -z "$pkg" ] && continue
                log_info "Rollback : Removing package [$pkg] ..."
                apk del "$pkg" >/dev/null 2>&1 || log_warn "Could not remove : [$pkg]"
            done < "$TRANSACTION_LOG"
            ;;
    esac

    rm -f "$TRANSACTION_LOG"
    log_success "Rollback process completed!"
}