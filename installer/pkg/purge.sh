#!/bin/sh
# ============================================================
# Groups tracked packages by config/package_profiles.json, then
# stops services, removes packages, drops leftover UCI files and
# flushes the LuCI index cache.
# ============================================================

PURGE_CORE_CONFIGS="network firewall dhcp system wireless luci rpcd uhttpd dropbear fstab ubootenv"

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

_pu_union() {
    _pu_out="$1"
    shift
    for _pu_w in $*; do
        [ -n "$_pu_w" ] || continue
        _pu_in_words "$_pu_w" "$_pu_out" || _pu_out="${_pu_out:+$_pu_out }$_pu_w"
    done
    printf '%s' "$_pu_out"
}

_pu_is_core_config() {
    _pu_base="${1##*/}"
    _pu_in_words "$_pu_base" "$PURGE_CORE_CONFIGS"
}

# Files owned by a package (needed before the package is deleted).
_pu_pkg_files() {
    case "${PKG_MANAGER:-opkg}" in
        apk)
            apk info -L "$1" 2>/dev/null
            ;;
        *)
            opkg files "$1" 2>/dev/null
            ;;
    esac
}

# Init scripts shipped by the package, plus a luci-app-* / luci-proto-* name map.
_pu_discover_services() {
    _pu_pkg="$1"
    _pu_pkg_files "$_pu_pkg" | sed -n 's|^/etc/init.d/\([^/]*\)$|\1|p'
    case "$_pu_pkg" in
        luci-app-*|luci-proto-*)
            _pu_svc="${_pu_pkg#luci-app-}"
            _pu_svc="${_pu_svc#luci-proto-}"
            [ -x "/etc/init.d/$_pu_svc" ] && echo "$_pu_svc"
            ;;
        luci-i18n-*)
            ;;
        *)
            [ -x "/etc/init.d/$_pu_pkg" ] && echo "$_pu_pkg"
            ;;
    esac
}

# UCI files shipped by the package, plus leftover names derived from the pkg.
_pu_discover_configs() {
    _pu_pkg="$1"
    _pu_pkg_files "$_pu_pkg" | sed -n 's|^/etc/config/\([^/]*\)$|/etc/config/\1|p'
    case "$_pu_pkg" in
        luci-app-*|luci-proto-*)
            _pu_cfg="${_pu_pkg#luci-app-}"
            _pu_cfg="${_pu_cfg#luci-proto-}"
            echo "/etc/config/$_pu_cfg"
            ;;
        luci-i18n-*|kmod-*)
            ;;
        *)
            echo "/etc/config/$_pu_pkg"
            ;;
    esac
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

_pu_collect_preview() {
    PURGE_SERVICES=""
    PURGE_CONFIGS=""
    for _pu_pkg in $1; do
        [ -n "$_pu_pkg" ] || continue
        for _pu_svc in $(_pu_discover_services "$_pu_pkg"); do
            [ -x "/etc/init.d/$_pu_svc" ] || continue
            _pu_in_words "$_pu_svc" "$PURGE_SERVICES" || \
                PURGE_SERVICES="${PURGE_SERVICES:+$PURGE_SERVICES }$_pu_svc"
        done
        for _pu_cfg in $(_pu_discover_configs "$_pu_pkg"); do
            [ -e "$_pu_cfg" ] || continue
            _pu_is_core_config "$_pu_cfg" && continue
            _pu_in_words "$_pu_cfg" "$PURGE_CONFIGS" || \
                PURGE_CONFIGS="${PURGE_CONFIGS:+$PURGE_CONFIGS }$_pu_cfg"
        done
    done
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
# Deep-clean pipeline for a space-separated package list
# ------------------------------------------------------------
purge_packages() {
    _pu_targets="$1"
    [ -n "$_pu_targets" ] || return 1

    PKG_MGR="${PKG_MANAGER:-opkg}"
    [ -n "${PKG_MANAGER:-}" ] || {
        command -v apk >/dev/null 2>&1 && PKG_MGR="apk"
    }

    _pu_collect_preview "$_pu_targets"
    if [ -n "${PURGE_MODULE_ID:-}" ] && command -v mf_module_services >/dev/null 2>&1; then
        PURGE_SERVICES="$(_pu_union "$PURGE_SERVICES" $(mf_module_services "$PURGE_MODULE_ID"))"
        PURGE_CONFIGS="$(_pu_union "$PURGE_CONFIGS" $(mf_module_configs "$PURGE_MODULE_ID"))"
    fi

    echo
    printf "  ${YELLOW}⚠️ The following will be removed${RESET}\n"
    echo "  ───────────────────────────────────────────────────────────"
    _pu_print_list "Packages" "$_pu_targets"
    _pu_print_list "Services" "$PURGE_SERVICES"
    _pu_print_list "UCI configs" "$PURGE_CONFIGS"
    echo "  ───────────────────────────────────────────────────────────"
    printf "  ${GRAY}LuCI index cache will be flushed and rpcd restarted.${RESET}\n"
    echo

    printf "  ⁉️ Proceed with this purge? [y/N]: "
    read -r _pu_confirm </dev/tty || return 1
    case "$_pu_confirm" in
        [yY]|[yY][eE][sS]) ;;
        *)
            log_info "Purge cancelled."
            return 1
            ;;
    esac

    echo
    log_info "── 1/4  Service termination"
    for _pu_svc in $PURGE_SERVICES; do
        log_info "Stopping and disabling [$_pu_svc] ..."
        if [ -x "/etc/init.d/$_pu_svc" ]; then
            /etc/init.d/"$_pu_svc" stop >/dev/null 2>&1 || true
            /etc/init.d/"$_pu_svc" disable >/dev/null 2>&1 || true
        fi
    done
    log_success "Service termination finished."

    echo
    log_info "── 2/4  Package removal ($PKG_MGR)"
    for _pu_pkg in $_pu_targets; do
        [ -n "$_pu_pkg" ] || continue
        log_info "Removing [$_pu_pkg] ..."
        case "$PKG_MGR" in
            apk)
                apk del "$_pu_pkg" >/dev/null 2>&1 || true
                ;;
            *)
                opkg remove --autoremove "$_pu_pkg" >/dev/null 2>&1 \
                    || opkg remove "$_pu_pkg" >/dev/null 2>&1 \
                    || true
                ;;
        esac
    done
    if [ "$PKG_MGR" = "apk" ] && command -v apk >/dev/null 2>&1; then
        apk autoremove >/dev/null 2>&1 || true
    fi
    log_success "Package removal finished."

    echo
    log_info "── 3/4  Config cleanup"
    for _pu_cfg in $PURGE_CONFIGS; do
        _pu_is_core_config "$_pu_cfg" && continue
        if [ -e "$_pu_cfg" ]; then
            log_info "Deleting [$_pu_cfg] ..."
            rm -f "$_pu_cfg" 2>/dev/null || true
        fi
    done
    log_success "Config cleanup finished."

    echo
    log_info "── 4/4  LuCI cache flush"
    rm -f /tmp/luci-indexcache* 2>/dev/null || true
    rm -rf /tmp/luci-modulecache 2>/dev/null || true
    if [ -x /etc/init.d/rpcd ]; then
        log_info "Restarting rpcd ..."
        /etc/init.d/rpcd restart >/dev/null 2>&1 || true
    fi
    if [ -x /etc/init.d/uhttpd ]; then
        /etc/init.d/uhttpd reload >/dev/null 2>&1 || true
    fi
    log_success "LuCI menus will refresh on the next page load."

    echo
    log_success "Purge completed."

    if [ -n "${PURGE_MODULE_ID:-}" ] && command -v mf_unregister_module >/dev/null 2>&1; then
        _pu_left="$(mf_module_packages "$PURGE_MODULE_ID")"
        _pu_still=""
        for _pu_pkg in $_pu_left; do
            _pu_in_words "$_pu_pkg" "$_pu_targets" && continue
            _pu_still="${_pu_still:+$_pu_still }$_pu_pkg"
        done
        if [ -z "$_pu_still" ]; then
            mf_unregister_module "$PURGE_MODULE_ID"
        else
            mf_drop_packages "$PURGE_MODULE_ID" "$_pu_targets"
        fi
        mf_sync_install_log
        PURGE_MODULE_ID=""
    elif command -v mf_drop_packages_from_all >/dev/null 2>&1; then
        mf_drop_packages_from_all "$_pu_targets"
    else
        _pu_logf="$(_pu_tracked_file)"
        if [ -f "$_pu_logf" ]; then
            _pu_keep=""
            while IFS= read -r _pu_line || [ -n "$_pu_line" ]; do
                [ -n "$_pu_line" ] || continue
                _pu_in_words "$_pu_line" "$_pu_targets" && continue
                _pu_keep="${_pu_keep:+$_pu_keep
}$_pu_line"
            done < "$_pu_logf"
            if [ -n "$_pu_keep" ]; then
                printf '%s\n' "$_pu_keep" | sort -u > "$_pu_logf"
            else
                rm -f "$_pu_logf"
            fi
        fi
    fi

    return 0
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
    echo "  ───────────────────────────────────────────────────────────"
    _pu_i=0
    for _pu_pkg in $_pu_pool; do
        _pu_i=$((_pu_i + 1))
        printf "  ${CYAN}%s${RESET}) %s\n" "$_pu_i" "$_pu_pkg"
    done
    echo "  ───────────────────────────────────────────────────────────"
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
        echo "  ───────────────────────────────────────────────────────────"
        [ -n "$_pu_id" ] && command -v mf_module_category >/dev/null 2>&1 && \
            printf "  ${GRAY}Category : %s${RESET}\n" "$(mf_module_category "$_pu_id")"
        for _pu_pkg in $_pu_pkgs; do
            printf "    • %s\n" "$_pu_pkg"
        done
        echo "  ───────────────────────────────────────────────────────────"
        printf "  ${CYAN}1${RESET}) Purge this entire module\n"
        printf "  ${CYAN}2${RESET}) Choose individual packages\n"
        ui_nav_footer
        ui_prompt 2

        case "$UI_CHOICE" in
            1)
                PURGE_MODULE_ID="$_pu_id"
                purge_packages "$_pu_pkgs"
                PURGE_MODULE_ID=""
                return 0
                ;;
            2)
                if _pu_pick_packages "$_pu_pkgs"; then
                    PURGE_MODULE_ID="$_pu_id"
                    purge_packages "$PURGE_SELECTION"
                    PURGE_MODULE_ID=""
                    return 0
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
    command -v mf_migrate_from_log >/dev/null 2>&1 && mf_migrate_from_log >/dev/null 2>&1 || true

    while true; do
        render_persistent_header
        printf "  🧹 ${BOLD}Purge DayPass Installed Modules${RESET}\n"
        echo "  ───────────────────────────────────────────────────────────"

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
            for _pu_id in $_pu_ids; do
                PURGE_MODULE_ID="$_pu_id"
                purge_packages "$(mf_module_packages "$_pu_id")" || true
            done
            PURGE_MODULE_ID=""
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
