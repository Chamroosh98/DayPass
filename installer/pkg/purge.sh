#!/bin/sh
# ============================================================
# Groups tracked packages by config/package_profiles.json, then
# removes verified DayPass installations through the native package manager.
# ============================================================


# ------------------------------------------------------------
_pu_tracked_file() {
    echo "${INSTALL_LOG:-${DAYPASS_DIR:-/etc/daypass}/install.log}"
}

_pu_tracked_pkgs() {
    _pu_log="$(_pu_tracked_file)"
    [ -s "$_pu_log" ] || return 1
    sort -u "$_pu_log" | sed '/^[[:space:]]*$/d'
}

_pu_in_words() {
    _pu_needle="$1"
    _pu_hay="$2"
    for _pu_w in $_pu_hay; do
        [ "$_pu_w" = "$_pu_needle" ] && return 0
    done
    return 1
}

_pu_profiles_json() {
    if command -v load_package_profiles >/dev/null 2>&1 && load_package_profiles; then
        echo "$PROFILES_FILE"
        return 0
    fi
    return 1
}

# id<TAB>title<TAB>space-separated names declared by the profile
_pu_profile_catalog() {
    _pu_json="$(_pu_profiles_json)" || return 1
    command -v jq >/dev/null 2>&1 || return 1
    jq -r '
        def names:
            [.. | objects |
                (.name // empty),
                ((.alternatives // [])[]?),
                ((.depends // [])[]?),
                ((.packages // [])[]? | if type == "string" then . else empty end)
            ]
            | map(select(type == "string" and test("^[A-Za-z0-9._+-]+$")))
            | unique;
        .profiles | to_entries[] |
        [.key, (.value.title // .key), ((.value | names) | join(" "))] | @tsv
    ' "$_pu_json" 2>/dev/null
}

# Assign each tracked package to the first matching profile, else "other".
# Writes: id|title|pkg pkg ...
_pu_build_groups() {
    _pu_out="$1"
    : > "$_pu_out"

    _pu_tracked="$(_pu_tracked_pkgs)" || return 1
    _pu_assigned=""
    _pu_catalog="$(_pu_profile_catalog)" || _pu_catalog=""

    if [ -n "$_pu_catalog" ]; then
        printf '%s\n' "$_pu_catalog" | while IFS="$(printf '\t')" read -r _pu_id _pu_title _pu_names; do
            [ -n "$_pu_id" ] || continue
            _pu_hit=""
            for _pu_pkg in $_pu_tracked; do
                _pu_in_words "$_pu_pkg" "$_pu_assigned" && continue
                if _pu_in_words "$_pu_pkg" "$_pu_names"; then
                    _pu_hit="${_pu_hit:+$_pu_hit }$_pu_pkg"
                    _pu_assigned="${_pu_assigned:+$_pu_assigned }$_pu_pkg"
                fi
            done
            [ -n "$_pu_hit" ] && printf '%s|%s|%s\n' "$_pu_id" "$_pu_title" "$_pu_hit"
        done > "$_pu_out"

        # The pipeline subshell cannot update _pu_assigned in the parent, so
        # recompute leftovers from the groups file.
        _pu_assigned=""
        while IFS='|' read -r _pu_id _pu_title _pu_hit; do
            _pu_assigned="${_pu_assigned:+$_pu_assigned }$_pu_hit"
        done < "$_pu_out"
    fi

    _pu_other=""
    for _pu_pkg in $_pu_tracked; do
        _pu_in_words "$_pu_pkg" "$_pu_assigned" && continue
        _pu_other="${_pu_other:+$_pu_other }$_pu_pkg"
    done
    [ -n "$_pu_other" ] && printf '%s|%s|%s\n' "other" "Other DayPass packages" "$_pu_other" >> "$_pu_out"

    [ -s "$_pu_out" ]
}

_pu_count_words() {
    _pu_n=0
    for _pu_w in $1; do
        _pu_n=$((_pu_n + 1))
    done
    echo "$_pu_n"
}

_pu_print_list() {
    _pu_label="$1"
    _pu_items="$2"
    printf "  ${BOLD}%s${RESET}\n" "$_pu_label"
    if [ -z "$_pu_items" ]; then
        printf "    ${GRAY}(none)${RESET}\n"
        return 0
    fi
    for _pu_item in $_pu_items; do
        printf "    • ${CYAN}%s${RESET}\n" "$_pu_item"
    done
}

# ------------------------------------------------------------
# Remove only proven DayPass installations with no retained module owner.
# ------------------------------------------------------------
purge_packages() {
    _pu_targets="$1"
    [ -n "$_pu_targets" ] || return 1

    PKG_MGR="${PKG_MANAGER:-opkg}"
    [ -n "${PKG_MANAGER:-}" ] || {
        command -v apk >/dev/null 2>&1 && PKG_MGR="apk"
    }

    local pkg id owned owners selected_ids removable="" failed=0
    selected_ids=$(mf_module_ids) || return 1
    local members tracked="" retained resources protected resource other
    for id in $selected_ids; do
        members=$(mf_module_packages "$id")
        [ -n "$members" ] || { log_error "Cannot determine package membership for [$id]."; return 1; }
        tracked="$tracked $members"
    done
    for pkg in $_pu_targets; do
        _pu_in_words "$pkg" "$removable" && continue
        owners=0
        owned=0
        for id in $selected_ids; do
            _pu_in_words "$pkg" "$(mf_module_packages "$id")" || continue
            owners=$((owners + 1))
            if [ -n "${PURGE_MODULE_ID:-}" ] && [ "$PURGE_MODULE_ID" != "$id" ]; then
                owned=0
                break
            fi
            if _pu_in_words "$pkg" "$(mf_module_owned "$id")"; then owned=1; fi
        done
        if [ "$owned" = 1 ] && { [ "$owners" = 1 ] || [ "${2:-}" = all ]; }; then
            removable="${removable:+$removable }$pkg"
        else
            log_warn "Keeping [$pkg]: shared, pre-existing, or ownership unknown."
            failed=1
        fi
    done
    [ -n "$removable" ] || return 1
    # Other targets may also remain installed if their removal fails.
    # Check for known shared resources before making any changes.
    for pkg in $removable; do
        retained=""
        for other in $tracked; do
            [ "$other" = "$pkg" ] || retained="$retained $other"
        done
        [ -n "$retained" ] || continue
        protected="$(mf_discover_configs "$retained") $(mf_discover_services "$retained")"
        resources="$(mf_discover_configs "$pkg") $(mf_discover_services "$pkg")"
        for resource in $resources; do
            if _pu_in_words "$resource" "$protected"; then
                log_warn "Keeping packages: another package also uses [$resource]."
                return 1
            fi
        done
    done
    ui_divider
    _pu_print_list "Packages to remove" "$removable"
    echo "  Package-owned files are handled by the native package manager."
    ui_divider
    printf "  ⁉️ Proceed with this purge? [y/N]: "
    read -r _pu_confirm </dev/tty || return 1
    case "$_pu_confirm" in
        [yY]|[yY][eE][sS]) ;;
        *)
            log_info "Purge cancelled."
            return 1
            ;;
    esac

    local remaining simulation
    for pkg in $removable; do
        case "$PKG_MGR" in
            apk)
                simulation=$(LC_ALL=C apk --simulate del "$pkg") || return 1
                if ! printf '%s\n' "$simulation" | awk -v pkg="$pkg" '
                    /^\([0-9]+\/[0-9]+\)/ {if ($2 != "Purging" || $3 != pkg) unsafe=1; count++}
                    END {exit !(count==1 && !unsafe)}'; then
                    log_error "Cannot confirm a single-package removal for [$pkg]."
                    return 1
                fi
                apk del "$pkg" ;;
            opkg) opkg remove "$pkg" ;;
            *) log_error "Unsupported package manager."; return 1 ;;
        esac || {
            log_error "Removal failed for [$pkg]. Tracking retained."
            failed=1
            continue
        }
        remaining=$(pkg_installed_names) || {
            log_error "Cannot verify removal of [$pkg]. Tracking retained."
            return 1
        }
        if printf '%s\n' "$remaining" | grep -Fxq -- "$pkg"; then
            log_error "Package [$pkg] remains installed. Tracking retained."
            failed=1
            continue
        fi
        case "$pkg" in
            -*|*[!a-zA-Z0-9.+_-]*) return 1 ;;
        esac
        rm -f "${DAYPASS_DIR:-/etc/daypass}/package-receipts/$pkg" || return 1
        if [ -n "${PURGE_MODULE_ID:-}" ]; then
            mf_drop_packages "$PURGE_MODULE_ID" "$pkg" && mf_sync_install_log || return 1
        else
            mf_drop_packages_from_all "$pkg" || return 1
        fi
    done
    [ "$failed" -eq 0 ] || return 1
    log_success "Package purge complete."

}

# ------------------------------------------------------------
# Multi-select a subset of a package list
# ------------------------------------------------------------
_pu_pick_packages() {
    _pu_pool="$1"
    _pu_n="$(_pu_count_words "$_pu_pool")"
    [ "$_pu_n" -gt 0 ] || return 1

    echo
    printf "  ${BOLD}Select packages to remove${RESET}\n"
    ui_divider
    _pu_i=0
    for _pu_pkg in $_pu_pool; do
        _pu_i=$((_pu_i + 1))
        printf "  ${CYAN}%s${RESET}) %s\n" "$_pu_i" "$_pu_pkg"
    done
    ui_divider
    printf "  ${GRAY}Numbers separated by spaces, [a] all, [0] cancel${RESET}\n"
    printf "  ⁉️ Selection : "
    read -r _pu_sel </dev/tty || return 1

    case "$_pu_sel" in
        ''|0) return 1 ;;
        a|A)
            PURGE_SELECTION="$_pu_pool"
            return 0
            ;;
    esac

    PURGE_SELECTION=""
    for _pu_tok in $_pu_sel; do
        case "$_pu_tok" in
            *[!0-9]*) continue ;;
        esac
        [ "$_pu_tok" -ge 1 ] && [ "$_pu_tok" -le "$_pu_n" ] || continue
        _pu_i=0
        for _pu_pkg in $_pu_pool; do
            _pu_i=$((_pu_i + 1))
            if [ "$_pu_i" -eq "$_pu_tok" ]; then
                _pu_in_words "$_pu_pkg" "$PURGE_SELECTION" || \
                    PURGE_SELECTION="${PURGE_SELECTION:+$PURGE_SELECTION }$_pu_pkg"
                break
            fi
        done
    done

    [ -n "$PURGE_SELECTION" ]
}

_pu_category_menu() {
    _pu_id="$1"
    _pu_title="$2"
    _pu_pkgs="$3"

    while true; do
        render_persistent_header
        printf "  🧹 ${BOLD}%s${RESET}\n" "$_pu_title"
        ui_divider
        [ -n "$_pu_id" ] && command -v mf_module_category >/dev/null 2>&1 && \
            printf "  ${GRAY}Category : %s${RESET}\n" "$(mf_module_category "$_pu_id")"
        for _pu_pkg in $_pu_pkgs; do
            printf "    • %s\n" "$_pu_pkg"
        done
        ui_divider
        printf "  ${CYAN}1${RESET}) Purge this entire module\n"
        printf "  ${CYAN}2${RESET}) Choose individual packages\n"
        ui_nav_footer
        ui_prompt 2

        case "$UI_CHOICE" in
            1)
                PURGE_MODULE_ID="$_pu_id"
                purge_packages "$_pu_pkgs"
                _pu_rc=$?
                PURGE_MODULE_ID=""
                return "$_pu_rc"
                ;;
            2)
                if _pu_pick_packages "$_pu_pkgs"; then
                    PURGE_MODULE_ID="$_pu_id"
                    purge_packages "$PURGE_SELECTION"
                    _pu_rc=$?
                    PURGE_MODULE_ID=""
                    return "$_pu_rc"
                fi
                ;;
            0) return 0 ;;
            *)
                ui_nav_common "$UI_CHOICE" "system" && continue
                log_warn "Invalid option!"
                sleep 1
                ;;
        esac
    done
}

# ------------------------------------------------------------
# Interactive purge (maintenance menu option 1)
# ------------------------------------------------------------
purge_menu() {
    if command -v mf_migrate_from_log >/dev/null 2>&1; then
        mf_migrate_from_log || { log_error "Package registry migration failed."; return 1; }
    fi

    while true; do
        render_persistent_header
        printf "  🧹 ${BOLD}Purge DayPass Installed Modules${RESET}\n"
        ui_divider

        _pu_ids=""
        if command -v mf_has_modules >/dev/null 2>&1 && mf_has_modules; then
            _pu_ids=$(mf_module_ids)
        fi

        if [ -z "$_pu_ids" ]; then
            if ! _pu_tracked_pkgs >/dev/null; then
                log_warn "No installed modules recorded in [$(mf_path 2>/dev/null || echo /etc/daypass/installed_manifest.json)]"
                return 0
            fi
            _pu_groups="/tmp/daypass_purge_groups.$$"
            if ! _pu_build_groups "$_pu_groups"; then
                log_warn "No tracked packages to purge!"
                rm -f "$_pu_groups"
                return 0
            fi
            _pu_all=""
            _pu_idx=0
            while IFS='|' read -r _pu_id _pu_title _pu_pkgs; do
                _pu_idx=$((_pu_idx + 1))
                printf "  ${CYAN}%s${RESET}) %s ${GRAY}(%s)${RESET}\n" \
                    "$_pu_idx" "$_pu_title" "$(_pu_count_words "$_pu_pkgs")"
                _pu_all="${_pu_all:+$_pu_all }$_pu_pkgs"
            done < "$_pu_groups"
            _pu_cats="$_pu_idx"
            _pu_all_n=$((_pu_cats + 1))
            printf "  ${CYAN}%s${RESET}) Purge ALL DayPass-installed packages\n" "$_pu_all_n"
            ui_nav_footer
            ui_prompt "$_pu_all_n"
            case "$UI_CHOICE" in
                0) rm -f "$_pu_groups"; return 0 ;;
                q|Q) rm -f "$_pu_groups"; daypass_quit ;;
                h|H) ui_show_help "system"; continue ;;
            esac
            if [ "$UI_CHOICE" = "$_pu_all_n" ]; then
                PURGE_MODULE_ID=""
                purge_packages "$_pu_all"
            elif [ "$UI_CHOICE" -ge 1 ] 2>/dev/null && [ "$UI_CHOICE" -le "$_pu_cats" ]; then
                _pu_line="$(sed -n "${UI_CHOICE}p" "$_pu_groups")"
                _pu_id="${_pu_line%%|*}"
                _pu_rest="${_pu_line#*|}"
                _pu_title="${_pu_rest%%|*}"
                _pu_pkgs="${_pu_rest#*|}"
                _pu_category_menu "$_pu_id" "$_pu_title" "$_pu_pkgs"
            else
                log_warn "Invalid option!"
                sleep 1
            fi
            rm -f "$_pu_groups"
            continue
        fi

        _pu_idx=0
        _pu_all=""
        for _pu_id in $_pu_ids; do
            _pu_idx=$((_pu_idx + 1))
            _pu_pkgs="$(mf_module_packages "$_pu_id")"
            _pu_n="$(_pu_count_words "$_pu_pkgs")"
            printf "  ${CYAN}%s${RESET}) %s ${GRAY}[%s] — %s package(s)${RESET}\n" \
                "$_pu_idx" "$(mf_module_title "$_pu_id")" "$(mf_module_category "$_pu_id")" "$_pu_n"
            _pu_all="${_pu_all:+$_pu_all }$_pu_pkgs"
        done

        _pu_cats="$_pu_idx"
        _pu_all_n=$((_pu_cats + 1))
        _pu_pick_n=$((_pu_cats + 2))
        printf "  ${CYAN}%s${RESET}) Purge ALL recorded modules\n" "$_pu_all_n"
        printf "  ${CYAN}%s${RESET}) Choose individual packages\n" "$_pu_pick_n"
        ui_nav_footer
        ui_prompt "$_pu_pick_n"

        case "$UI_CHOICE" in
            0) return 0 ;;
            q|Q) daypass_quit ;;
            h|H) ui_show_help "system"; continue ;;
        esac

        case "$UI_CHOICE" in
            *[!0-9]*|'') log_warn "Invalid option!"; sleep 1; continue ;;
        esac

        if [ "$UI_CHOICE" -eq "$_pu_all_n" ]; then
            PURGE_MODULE_ID=""
            purge_packages "$_pu_all" all
            continue
        fi

        if [ "$UI_CHOICE" -eq "$_pu_pick_n" ]; then
            if _pu_pick_packages "$_pu_all"; then
                PURGE_MODULE_ID=""
                purge_packages "$PURGE_SELECTION"
            fi
            continue
        fi

        if [ "$UI_CHOICE" -ge 1 ] && [ "$UI_CHOICE" -le "$_pu_cats" ]; then
            _pu_n=0
            for _pu_id in $_pu_ids; do
                _pu_n=$((_pu_n + 1))
                if [ "$_pu_n" -eq "$UI_CHOICE" ]; then
                    _pu_category_menu "$_pu_id" "$(mf_module_title "$_pu_id")" "$(mf_module_packages "$_pu_id")"
                    break
                fi
            done
            continue
        fi

        log_warn "Invalid option!"
        sleep 1
    done
}

# Backwards-compatible name used by the maintenance menu
purge_daypass_packages() {
    purge_menu
}
