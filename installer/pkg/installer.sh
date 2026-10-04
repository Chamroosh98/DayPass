#!/bin/sh

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
| .feeds[]?[]?
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
| .feeds[]?[]?
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
            return 0
        fi
        rm -f "$target"
    fi

    DOWNLOAD_SUCCESS=0
    trap 'rm -f "$tmp" 2>/dev/null' INT TERM

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 15 --max-time 120 --retry 3 --retry-delay 2 "$target_url" -o "$tmp" 2>/dev/null && DOWNLOAD_SUCCESS=1
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=20 --tries=3 -O "$tmp" "$target_url" 2>/dev/null && DOWNLOAD_SUCCESS=1
    elif command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -q --timeout=20 -O "$tmp" "$target_url" 2>/dev/null && DOWNLOAD_SUCCESS=1
    fi

    if [ "$DOWNLOAD_SUCCESS" -ne 1 ] || [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        trap - INT TERM
        return 1
    fi

    if [ -n "$sha256" ] && [ "$sha256" != "null" ]; then
        if ! echo "$sha256  $tmp" | sha256sum -c - >/dev/null 2>&1; then
            rm -f "$tmp"
            trap - INT TERM
            return 1
        fi
    fi

    mv "$tmp" "$target"
    trap - INT TERM
    return 0
}

deploy_targeted_packages()
{
    rm -f /var/lock/opkg.lock /lib/apk/db/lock /var/run/apk.lock /run/apk/db.lock 2>/dev/null

    mkdir -p "$(dirname "$INSTALL_LOG")"
    touch "$INSTALL_LOG"
    rm -f "$TRANSACTION_LOG"
    touch "$TRANSACTION_LOG"

    if [ -z "$PACKAGES_TO_PROCESS" ]; then
        PACKAGES_TO_PROCESS="$FINAL_PACKAGES"
    fi
    PACKAGES_PLANNED="$PACKAGES_TO_PROCESS"

    echo "  🔍 Executing Pre-Flight System Resource Validation ..."
    resource_snapshot

    APPLY_LIST="${TMP_DIR:-/tmp}/daypass_applied.list"
    : > "$APPLY_LIST"
    PACKAGES_NEEDED=""

    echo
    log_info "Checking packages already on this router ..."
    for pkg in $PACKAGES_PLANNED; do
        if command -v pkg_payload_required >/dev/null 2>&1 && ! pkg_payload_required "$pkg"; then
            printf "  ${GRAY}[SKIP]${RESET} Package %s is already installed and up-to-date.\n" "$pkg"
            printf '%s\t%s\n' "$pkg" "(Already Installed)" >> "$APPLY_LIST"
        else
            PACKAGES_NEEDED="$PACKAGES_NEEDED $pkg"
            printf '%s\t%s\n' "$pkg" "pending" >> "$APPLY_LIST"
        fi
    done
    echo

    if ! estimate_install_size; then
        log_error "Installation aborted due to system resource limits!"
        return 1
    fi

    INSTALL_FILES=""
    total_pkgs=0
    for p in $PACKAGES_NEEDED; do
        total_pkgs=$((total_pkgs + 1))
    done

    if [ "$total_pkgs" -gt 0 ]; then
        current_idx=0
        log_info "Downloading required packages ..."

        for pkg in $PACKAGES_NEEDED; do
            current_idx=$((current_idx + 1))

            curr_ram_bytes=$(get_free_ram_bytes 2>/dev/null)
            curr_ram_fmt=$(human_readable_bytes "$curr_ram_bytes" 2>/dev/null)

            if command -v show_ascii_progress >/dev/null 2>&1; then
                show_ascii_progress "Downloading ($pkg) [Free RAM: ${curr_ram_fmt:-N/A}]" "$current_idx" "$total_pkgs"
            else
                echo "  📦 [$current_idx/$total_pkgs] Downloading $pkg ... (Free RAM: ${curr_ram_fmt:-N/A})"
            fi

            if ! download_package "$pkg"; then
                echo
                log_error "Failed downloading dependency : [$pkg]"
                rollback_failed_install
                return 1
            fi

            file=$(manifest_lookup "file" "$pkg")
            file_basename=$(basename "$file")
            INSTALL_FILES="$INSTALL_FILES $TMP_DIR/$file_basename"
            echo "$pkg" >> "$TRANSACTION_LOG"
        done
        echo
    else
        log_info "Nothing to download — every selected package is already current."
        echo
    fi

    INSTALL_SUCCESS=1
    CURRENT_PKG_MGR="${PKG_MANAGER:-opkg}"
    DAYPASS_OPKG_LOG="${DAYPASS_OPKG_LOG:-/tmp/daypass_opkg.log}"
    DAYPASS_APK_LOG="${DAYPASS_APK_LOG:-/tmp/daypass_apk.log}"

    if [ -n "$INSTALL_FILES" ]; then
        INSTALL_SUCCESS=0
        case "$CURRENT_PKG_MGR" in
            apk)
                : > "$DAYPASS_APK_LOG"
                (apk add --allow-untrusted --no-progress $INSTALL_FILES >"$DAYPASS_APK_LOG" 2>&1) &
                BG_PID=$!
                if command -v ui_spinner >/dev/null 2>&1; then
                    ui_spinner "$BG_PID" "Installing packages ..."
                elif command -v show_timer_progress >/dev/null 2>&1; then
                    show_timer_progress "$BG_PID" "applying APK package bundle"
                    wait "$BG_PID"
                else
                    wait "$BG_PID"
                fi
                [ $? -eq 0 ] && INSTALL_SUCCESS=1
                ;;
            opkg|*)
                : > "$DAYPASS_OPKG_LOG"
                (opkg install --force-checksum $INSTALL_FILES >"$DAYPASS_OPKG_LOG" 2>&1) &
                BG_PID=$!
                if command -v ui_spinner >/dev/null 2>&1; then
                    ui_spinner "$BG_PID" "Installing packages ..."
                elif command -v show_timer_progress >/dev/null 2>&1; then
                    show_timer_progress "$BG_PID" "applying OPKG package bundle"
                    wait "$BG_PID"
                else
                    wait "$BG_PID"
                fi
                [ $? -eq 0 ] && INSTALL_SUCCESS=1
                ;;
        esac
    fi

    if [ "$INSTALL_SUCCESS" -eq 1 ]; then
        _apply_tmp="${APPLY_LIST}.tmp"
        : > "$_apply_tmp"
        while IFS='	' read -r _ap_name _ap_note; do
            [ -n "$_ap_name" ] || continue
            if [ "$_ap_note" = "pending" ]; then
                _ap_ver=$(pkg_get_installed_version "$_ap_name" 2>/dev/null | awk 'NR==1 { print $1 }')
                [ -z "$_ap_ver" ] && _ap_ver=$(manifest_lookup "version" "$_ap_name" 2>/dev/null)
                case "$_ap_ver" in
                    ""|null|Latest|N/A) _ap_note="(Installed)" ;;
                    *) _ap_note="(Installed v${_ap_ver})" ;;
                esac
            fi
            printf '%s\t%s\n' "$_ap_name" "$_ap_note" >> "$_apply_tmp"
            echo "$_ap_name" >> "$INSTALL_LOG"
        done < "$APPLY_LIST"
        mv "$_apply_tmp" "$APPLY_LIST"

        if [ -f "$INSTALL_LOG" ]; then
            sort -u "$INSTALL_LOG" -o "$INSTALL_LOG"
        fi

        render_applied_components "$APPLY_LIST"
        resource_compare

        rm -f $INSTALL_FILES 2>/dev/null
        rm -f "$TRANSACTION_LOG"

        log_success "All targeted packages deployed successfully!"

        if command -v mf_record_install >/dev/null 2>&1; then
            mf_record_install "${INSPECT_MODULE_ID:-${SELECTED_PROFILE:-proxy}}" "$PACKAGES_PLANNED"
        fi

        return 0
    fi

    echo
    log_error "Package manager batch execution failed!"
    case "$CURRENT_PKG_MGR" in
        apk)  log_info "Details : ${DAYPASS_APK_LOG}" ;;
        *)    log_info "Details : ${DAYPASS_OPKG_LOG}" ;;
    esac
    rollback_failed_install
    return 1
}

# $1 tab-separated file: package<TAB>note
render_applied_components()
{
    [ -s "$1" ] || return 0

    echo
    echo "  📦 Applied Package Components"
    ui_divider
    while IFS='	' read -r _rc_name _rc_note; do
        [ -n "$_rc_name" ] || continue
        printf "  ${GREEN}✔${RESET} %s  %s\n" "$_rc_name" "$_rc_note"
    done < "$1"
    ui_divider
    echo
}

rollback_failed_install()
{
    echo
    log_warn "Initiating Selective Atomic Rollback Procedures ..."
    echo

    rm -f "$TMP_DIR"/*.part "$TMP_DIR"/*.apk "$TMP_DIR"/*.ipk 2>/dev/null

    if [ -s "$TRANSACTION_LOG" ]; then
        log_info "Rolling back modified packages from current session ..."
        while read -r pkg; do
            [ -z "$pkg" ] && continue
            log_info "Rollback : Removing package [$pkg] ..."
            
            case "${PKG_MANAGER:-opkg}" in
                apk)  apk del "$pkg" >/dev/null 2>&1 || true ;;
                opkg|*) opkg remove "$pkg" >/dev/null 2>&1 || true ;;
            esac
        done < "$TRANSACTION_LOG"
    else
        log_info "No system packages were installed in this session. Skipping removal!"
    fi

    rm -f "$TRANSACTION_LOG"
    log_success "Rollback procedure completed safely!"
}