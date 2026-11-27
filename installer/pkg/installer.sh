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
| select(.package == $pkg)
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
| select(.package == $pkg)
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
    local package="$1" file sha256 base_url target_url file_basename target

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
    target="$2/$file_basename"
    _pr_stage_payload "$target_url" "$target" "$sha256" || return 1
    staged_payload="$target"
    staged_hash=$(printf %s "$sha256" | tr A-F a-f)

}

deploy_targeted_packages()
(

    mkdir -p "$(dirname "$INSTALL_LOG")" || return 1
    mf_migrate_from_log || { log_error "Cannot preserve existing package records."; return 1; }
    local before newly_installed="" journal="" staged_payload

    [ -n "$1" ] && [ "$#" -ge 2 ] && [ "$#" -le 5 ] || { log_error "Missing deployment plan."; return 1; }
    local PACKAGES_TO_PROCESS="$1"
    local PACKAGES_PLANNED="$PACKAGES_TO_PROCESS" module_id="$2"

    local feeds="${3:-}" patches="${4:-}" operation="${5:-install}"
    local feed_needed="" staged_hash="" patch_needed="" needed
    mkdir -p "${TMP_DIR:-/tmp/daypass}" || return 1
    TMP_DIR=$(mktemp -d "${TMP_DIR:-/tmp/daypass}/deploy.XXXXXX") || return 1
    # Once native mutation is possible, keep the journal and logs on failure.
    trap '[ -f "$TMP_DIR/transaction.log" ] || rm -rf "$TMP_DIR"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    echo "  🔍 Executing Pre-Flight System Resource Validation ..."
    resource_snapshot

    APPLY_LIST="${TMP_DIR:-/tmp}/daypass_applied.list"
    : > "$APPLY_LIST" || return 1
    PACKAGES_NEEDED=""

    echo
    log_info "Checking packages already on this router ..."
    for pkg in $PACKAGES_PLANNED; do
        case "$pkg" in -*|*[!a-zA-Z0-9.+_-]*) log_error "Invalid package name [$pkg]."; return 1 ;; esac
        needed=yes
        case " $feeds " in
            *" $pkg "*)
                if [ "$operation" != update ] && pkg_installed_live "$pkg"; then needed=no; fi
                ;;
            *)
                case " $patches " in
                    *" $pkg "*) ;;
                    *) if ! pkg_payload_required "$pkg"; then needed=no; fi ;;
                esac
                ;;
        esac
        if [ "$needed" = no ]; then
            printf "  ${GRAY}[SKIP]${RESET} Package %s is already installed and up-to-date.\n" "$pkg"
            printf '%s\t%s\n' "$pkg" "(Already Installed)" >> "$APPLY_LIST" || return 1
        else
            PACKAGES_NEEDED="$PACKAGES_NEEDED $pkg"
            printf '%s\t%s\n' "$pkg" "pending" >> "$APPLY_LIST" || return 1
        fi
    done
    echo

    if ! estimate_install_size "$PACKAGES_NEEDED" "$feeds"; then
        log_error "Installation aborted due to system resource limits!"
        return 1
    fi

    set --
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

            case " $feeds " in
                *" $pkg "*) feed_needed="$feed_needed $pkg"; continue ;;
            esac
            mkdir "$TMP_DIR/payload.$current_idx" || return 1
            if ! download_package "$pkg" "$TMP_DIR/payload.$current_idx"; then
                echo
                log_error "Failed downloading dependency : [$pkg]"
                # No package-manager operation has started.
                log_warn "Installation cancelled before applying any packages."
                return 1
            fi

            if [ -n "$staged_hash" ]; then
                printf '%s %s\n' "$pkg" "manifest:$staged_hash" >> "$TMP_DIR/receipts" || return 1
            fi
            case " $patches " in
                *" $pkg "*) printf '%s\n' "$staged_payload" >> "$TMP_DIR/patches" || return 1; patch_needed=yes ;;
                *) set -- "$@" "$staged_payload" ;;
            esac

        done
        echo
    else
        log_info "Nothing to download — every selected package is already current."
        echo
    fi

    INSTALL_SUCCESS=1
    CURRENT_PKG_MGR="${PKG_MANAGER:-opkg}"
    DAYPASS_OPKG_LOG="$TMP_DIR/opkg.log"
    DAYPASS_APK_LOG="$TMP_DIR/apk.log"

    if [ -n "$PACKAGES_NEEDED" ]; then
        before=$(pkg_installed_names) || { log_error "Cannot inspect installed packages."; return 1; }
        journal="$TMP_DIR/transaction.log"
        {
            printf 'Requested: %s\n' "$PACKAGES_NEEDED" &&
                printf 'Previously installed package names:\n%s\n' "$before"
        } > "$journal" || return 1
        before=$(printf '%s' "$before" | tr '\n' ' ')
        for pkg in $PACKAGES_NEEDED; do
            case " $before " in
                *" $pkg "*) ;;
                *) newly_installed="${newly_installed:+$newly_installed }$pkg" ;;
            esac
        done
        INSTALL_SUCCESS=0
        if [ "$#" -gt 0 ]; then
            case "$CURRENT_PKG_MGR" in
                apk)
                    : > "$DAYPASS_APK_LOG"
                    (apk add --allow-untrusted --no-progress "$@" >"$DAYPASS_APK_LOG" 2>&1) &
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
                    (opkg install --force-checksum "$@" >"$DAYPASS_OPKG_LOG" 2>&1) &
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
        else
            INSTALL_SUCCESS=1
        fi
        if [ "$INSTALL_SUCCESS" = 1 ] && [ -n "$patch_needed" ]; then
            while IFS= read -r payload; do
                case "$CURRENT_PKG_MGR" in
                    opkg) opkg install --force-reinstall --force-checksum "$payload" >> "$DAYPASS_OPKG_LOG" 2>&1 ;;
                    apk) apk add --allow-untrusted "$payload" >> "$DAYPASS_APK_LOG" 2>&1 ;;
                esac || { INSTALL_SUCCESS=0; break; }
            done < "$TMP_DIR/patches"
        fi
        if [ "$INSTALL_SUCCESS" = 1 ] && [ -n "$feed_needed" ]; then
            # Native feeds retain the manager's normal trust checks.
            case "$CURRENT_PKG_MGR" in
                opkg) opkg install $feed_needed >> "$DAYPASS_OPKG_LOG" 2>&1 ;;
                apk) apk add --upgrade $feed_needed >> "$DAYPASS_APK_LOG" 2>&1 ;;
            esac && {
                for pkg in $feed_needed; do
                    printf '%s feed\n' "$pkg" >> "$TMP_DIR/receipts" || return 1
                done
            } || INSTALL_SUCCESS=0
        fi
    fi

    if [ "$INSTALL_SUCCESS" -eq 1 ]; then
        if [ -f "$TMP_DIR/receipts" ]; then
            while read -r pkg receipt; do
                pkg_receipt "$pkg" "$receipt" || { log_error "Native install succeeded but receipt storage failed. Inspect $journal."; return 1; }
            done < "$TMP_DIR/receipts"
        fi
        _apply_tmp="${APPLY_LIST}.tmp"
        : > "$_apply_tmp" || return 1
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
            printf '%s\t%s\n' "$_ap_name" "$_ap_note" >> "$_apply_tmp" || return 1
        done < "$APPLY_LIST"
        mv "$_apply_tmp" "$APPLY_LIST" || return 1

        render_applied_components "$APPLY_LIST"
        resource_compare

        if [ -n "$module_id" ]; then
            mf_record_install "$module_id" "$PACKAGES_PLANNED" "$newly_installed" || {
                log_error "Package processing finished but registry update failed. Inspect $journal."
                return 1
            }
        elif ! mf_sync_install_log; then
            log_error "Package processing finished but install log update failed."
            return 1
        fi

        [ -z "$journal" ] || rm -f "$journal" || return 1
        log_success "All targeted packages deployed successfully!"
        return 0
    fi

    echo
    log_error "Package manager batch execution failed!"
    case "$CURRENT_PKG_MGR" in
        apk)  log_info "Details : ${DAYPASS_APK_LOG}" ;;
        *)    log_info "Details : ${DAYPASS_OPKG_LOG}" ;;
    esac
    log_warn "Native transaction may be partially applied. No packages were removed by DayPass. Inspect $journal and the manager log before retrying."
    return 1
)

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
