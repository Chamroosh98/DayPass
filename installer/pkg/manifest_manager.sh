#!/bin/sh
# ============================================================
# POSIX backing store: $DAYPASS_DIR/manifest.d/<id>
# Public JSON    : $DAYPASS_DIR/installed_manifest.json
# ============================================================

mf_path() {
    echo "${DAYPASS_MANIFEST:-${DAYPASS_DIR:-/etc/daypass}/installed_manifest.json}"
}

mf_dir() {
    echo "${DAYPASS_DIR:-/etc/daypass}/manifest.d"
}

_mf_init() {
    mkdir -p "$(dirname "$(mf_path)")" "$(mf_dir)" 2>/dev/null
}

_mf_safe_id() {
    case "$1" in
        ''|*[!A-Za-z0-9_-]*) return 1 ;;
    esac
    return 0
}

_mf_json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

_mf_json_str_array() {
    _mf_first=1
    printf '['
    for _mf_w in $1; do
        [ "$_mf_first" -eq 1 ] || printf ','
        printf '"%s"' "$(_mf_json_escape "$_mf_w")"
        _mf_first=0
    done
    printf ']'
}

# passwall2 -> Passwall 2 ; network_tools -> Network Tools
_mf_pretty() {
    printf '%s' "$1" | sed 's/_/ /g; s/-/ /g; s/\([A-Za-z]\)\([0-9]\)/\1 \2/g' | awk '{
        for (i = 1; i <= NF; i++)
            $i = toupper(substr($i, 1, 1)) substr($i, 2)
        print
    }'
}

_mf_kv_get() {
    _mf_file="$1"
    _mf_key="$2"
    [ -f "$_mf_file" ] || return 1
    sed -n "/^${_mf_key}=/{s/^${_mf_key}=//;p;q;}" "$_mf_file"
}

# Rebuild installed_manifest.json from manifest.d
mf_export_json() (
    _mf_init || return 1
    _mf_out="$(mf_path)"
    _mf_tmp=$(mktemp "${_mf_out}.XXXXXX") || exit 1
    trap 'rm -f "$_mf_tmp"' EXIT
    _mf_first=1

    printf '{\n  "modules": {\n' > "$_mf_tmp" || return 1
    for _mf_file in "$(mf_dir)"/*; do
        [ -f "$_mf_file" ] || continue
        _mf_id="${_mf_file##*/}"
        _mf_safe_id "$_mf_id" || continue
        [ "$_mf_first" -eq 1 ] || printf ',\n' >> "$_mf_tmp" || return 1
        _mf_first=0
        printf '    "%s": {\n' "$(_mf_json_escape "$_mf_id")" >> "$_mf_tmp" || return 1
        printf '      "title": "%s",\n' "$(_mf_json_escape "$(_mf_kv_get "$_mf_file" title)")" >> "$_mf_tmp" || return 1
        printf '      "category": "%s",\n' "$(_mf_json_escape "$(_mf_kv_get "$_mf_file" category)")" >> "$_mf_tmp" || return 1
        printf '      "installed_at": "%s",\n' "$(_mf_json_escape "$(_mf_kv_get "$_mf_file" installed_at)")" >> "$_mf_tmp" || return 1
        printf '      "packages": %s,\n' "$(_mf_json_str_array "$(_mf_kv_get "$_mf_file" packages)")" >> "$_mf_tmp" || return 1
        printf '      "configs": %s,\n' "$(_mf_json_str_array "$(_mf_kv_get "$_mf_file" configs)")" >> "$_mf_tmp" || return 1
        printf '      "services": %s\n' "$(_mf_json_str_array "$(_mf_kv_get "$_mf_file" services)")" >> "$_mf_tmp" || return 1
        printf '    }' >> "$_mf_tmp" || return 1
    done
    printf '\n  }\n}\n' >> "$_mf_tmp" || return 1
    mv "$_mf_tmp" "$_mf_out"
)

mf_module_ids() {
    _mf_init || return 1
    for _mf_file in "$(mf_dir)"/*; do
        [ -f "$_mf_file" ] || continue
        _mf_id="${_mf_file##*/}"
        _mf_safe_id "$_mf_id" || continue
        printf '%s\n' "$_mf_id"
    done
}

mf_has_modules() {
    [ -n "$(mf_module_ids)" ]
}

mf_module_title()    { _mf_kv_get "$(mf_dir)/$1" title; }
mf_module_category() { _mf_kv_get "$(mf_dir)/$1" category; }
mf_module_packages() { _mf_kv_get "$(mf_dir)/$1" packages; }
mf_module_owned()    { _mf_kv_get "$(mf_dir)/$1" owned; }
mf_module_configs()  { _mf_kv_get "$(mf_dir)/$1" configs; }
mf_module_services() { _mf_kv_get "$(mf_dir)/$1" services; }

_mf_in_words() {
    local _mf_w
    _mf_n="$1"
    _mf_h="$2"
    for _mf_w in $_mf_h; do
        [ "$_mf_w" = "$_mf_n" ] && return 0
    done
    return 1
}

_mf_union() {
    _mf_out="$1"
    shift
    for _mf_w in $*; do
        [ -n "$_mf_w" ] || continue
        _mf_in_words "$_mf_w" "$_mf_out" || _mf_out="${_mf_out:+$_mf_out }$_mf_w"
    done
    printf '%s' "$_mf_out"
}

_mf_profile_title() {
    _mf_id="$1"
    if command -v load_package_profiles >/dev/null 2>&1 && load_package_profiles \
        && command -v jq >/dev/null 2>&1; then
        jq -r --arg id "$_mf_id" '.profiles[$id].title // empty' "$PROFILES_FILE" 2>/dev/null
    fi
}

# Category for a module: profile title when the id is a profile, else proxy title.
mf_category_for() {
    _mf_id="$1"
    _mf_t="$(_mf_profile_title "$_mf_id")"
    if [ -n "$_mf_t" ]; then
        printf '%s' "$_mf_t"
        return 0
    fi
    _mf_t="$(_mf_profile_title "proxy")"
    [ -n "$_mf_t" ] && printf '%s' "$_mf_t" && return 0
    printf '%s' "DayPass"
}

mf_title_for() {
    _mf_id="$1"
    _mf_t="$(_mf_profile_title "$_mf_id")"
    if [ -n "$_mf_t" ]; then
        printf '%s' "$_mf_t"
        return 0
    fi
    printf '%s Suite' "$(_mf_pretty "$_mf_id")"
}

_mf_pkg_files() {
    case "${PKG_MANAGER:-opkg}" in
        apk) apk info -L "$1" 2>/dev/null ;;
        *)   opkg files "$1" 2>/dev/null ;;
    esac
}

mf_discover_services() {
    _mf_seen=""
    for _mf_pkg in $1; do
        [ -n "$_mf_pkg" ] || continue
        for _mf_svc in $(_mf_pkg_files "$_mf_pkg" | sed -n 's|^/etc/init.d/\([^/]*\)$|\1|p'); do
            _mf_in_words "$_mf_svc" "$_mf_seen" && continue
            _mf_seen="${_mf_seen:+$_mf_seen }$_mf_svc"
        done
        case "$_mf_pkg" in
            luci-app-*|luci-proto-*)
                _mf_svc="${_mf_pkg#luci-app-}"
                _mf_svc="${_mf_svc#luci-proto-}"
                if [ -x "/etc/init.d/$_mf_svc" ] && ! _mf_in_words "$_mf_svc" "$_mf_seen"; then
                    _mf_seen="${_mf_seen:+$_mf_seen }$_mf_svc"
                fi
                ;;
            luci-i18n-*|kmod-*) ;;
            *)
                if [ -x "/etc/init.d/$_mf_pkg" ] && ! _mf_in_words "$_mf_pkg" "$_mf_seen"; then
                    _mf_seen="${_mf_seen:+$_mf_seen }$_mf_pkg"
                fi
                ;;
        esac
    done
    printf '%s' "$_mf_seen"
}

mf_discover_configs() {
    _mf_seen=""
    for _mf_pkg in $1; do
        [ -n "$_mf_pkg" ] || continue
        for _mf_cfg in $(_mf_pkg_files "$_mf_pkg" | sed -n 's|^/etc/config/\([^/]*\)$|/etc/config/\1|p'); do
            _mf_in_words "$_mf_cfg" "$_mf_seen" && continue
            _mf_seen="${_mf_seen:+$_mf_seen }$_mf_cfg"
        done
        case "$_mf_pkg" in
            luci-app-*|luci-proto-*)
                _mf_stem="${_mf_pkg#luci-app-}"
                _mf_stem="${_mf_stem#luci-proto-}"
                _mf_cfg="/etc/config/$_mf_stem"
                _mf_in_words "$_mf_cfg" "$_mf_seen" || _mf_seen="${_mf_seen:+$_mf_seen }$_mf_cfg"
                ;;
        esac
    done
    printf '%s' "$_mf_seen"
}

# $1 id, $2 title, $3 category, $4 packages (space-separated)
# Optional: $5 configs, $6 services (discovered when omitted)
mf_register_module() {
    _mf_id="$1"
    _mf_title="$2"
    _mf_cat="$3"
    _mf_pkgs="$4"
    _mf_cfgs="$5"
    _mf_svcs="$6"
    local owned="${7:-}"

    _mf_safe_id "$_mf_id" || return 1
    _mf_init || return 1

    _mf_file="$(mf_dir)/$_mf_id"
    if [ -f "$_mf_file" ]; then
        owned="$(_mf_union "$(_mf_kv_get "$_mf_file" owned)" $owned)"
        _mf_pkgs="$(_mf_union "$(_mf_kv_get "$_mf_file" packages)" $_mf_pkgs)"
        [ -z "$_mf_title" ] && _mf_title="$(_mf_kv_get "$_mf_file" title)"
        [ -z "$_mf_cat" ] && _mf_cat="$(_mf_kv_get "$_mf_file" category)"
        _mf_cfgs="$(_mf_union "$(_mf_kv_get "$_mf_file" configs)" $_mf_cfgs)"
        _mf_svcs="$(_mf_union "$(_mf_kv_get "$_mf_file" services)" $_mf_svcs)"
    fi

    [ -n "$_mf_title" ] || _mf_title="$(mf_title_for "$_mf_id")"
    [ -n "$_mf_cat" ] || _mf_cat="$(mf_category_for "$_mf_id")"
    [ -n "$_mf_cfgs" ] || _mf_cfgs="$(mf_discover_configs "$_mf_pkgs")"
    [ -n "$_mf_svcs" ] || _mf_svcs="$(mf_discover_services "$_mf_pkgs")"

    local staged
    staged=$(mktemp "$(mf_dir)/.record.XXXXXX") || return 1
    printf '%s\n' "title=$_mf_title" "category=$_mf_cat" \
        "installed_at=$(date +%Y-%m-%d 2>/dev/null || echo unknown)" \
        "owned=$owned" "packages=$_mf_pkgs" "configs=$_mf_cfgs" "services=$_mf_svcs" \
        > "$staged" && mv "$staged" "$_mf_file" || { rm -f "$staged"; return 1; }

    mf_export_json
}

mf_unregister_module() {
    _mf_safe_id "$1" || return 1
    rm -f "$(mf_dir)/$1" || return 1
    mf_export_json
}

# Drop package names from a module; unregister when none remain.
mf_drop_packages() {
    _mf_id="$1"
    _mf_drop="$2"
    _mf_file="$(mf_dir)/$_mf_id"
    [ -f "$_mf_file" ] || return 0

    _mf_keep=""
    local previous
    previous=$(_mf_kv_get "$_mf_file" packages) || return 1
    [ -n "$previous" ] || return 1
    for _mf_pkg in $previous; do
        _mf_in_words "$_mf_pkg" "$_mf_drop" && continue
        _mf_keep="${_mf_keep:+$_mf_keep }$_mf_pkg"
    done

    if [ -z "$_mf_keep" ]; then
        mf_unregister_module "$_mf_id"
        return $?
    fi

    local owned="" item
    for item in $(_mf_kv_get "$_mf_file" owned); do
        _mf_in_words "$item" "$_mf_keep" && owned="${owned:+$owned }$item"
    done
    local staged
    staged=$(mktemp "$(mf_dir)/.record.XXXXXX") || return 1
    awk -v owned="$owned" -v packages="$_mf_keep" \
        -v configs="$(mf_discover_configs "$_mf_keep")" -v services="$(mf_discover_services "$_mf_keep")" '
        !/^(owned|packages|configs|services)=/ { print }
        END { print "owned=" owned; print "packages=" packages; print "configs=" configs; print "services=" services }
    ' "$_mf_file" > "$staged" && mv "$staged" "$_mf_file" || { rm -f "$staged"; return 1; }
    mf_export_json
}

mf_drop_packages_from_all() {
    for _mf_id in $(mf_module_ids); do
        mf_drop_packages "$_mf_id" "$1" || return 1
    done
    mf_sync_install_log
}

# Rebuild INSTALL_LOG from every module's package list.
mf_sync_install_log() (
    _mf_log="${INSTALL_LOG:-${DAYPASS_DIR:-/etc/daypass}/install.log}"
    local ids names staged
    mkdir -p "$(dirname "$_mf_log")" || return 1
    staged=$(mktemp "${_mf_log}.XXXXXX") || return 1
    trap 'rm -f "$staged"' EXIT
    ids=$(mf_module_ids) || return 1
    for _mf_id in $ids; do
        names=$(mf_module_packages "$_mf_id") || return 1
        for _mf_pkg in $names; do
            printf '%s\n' "$_mf_pkg" >> "$staged" || return 1
        done
    done
    sort -u "$staged" -o "$staged" && mv "$staged" "$_mf_log"
)

# Seed the registry from a legacy install.log grouped by package profiles.
mf_migrate_from_log() {
    local known="" missing="" id item
    _mf_log="${INSTALL_LOG:-${DAYPASS_DIR:-/etc/daypass}/install.log}"
    [ -s "$_mf_log" ] || return 0

    local legacy remaining ids names
    legacy=$(sort -u "$_mf_log") || return 1
    ids=$(mf_module_ids) || return 1
    for id in $ids; do
        names=$(mf_module_packages "$id") || return 1
        known="$known $names"
    done
    for item in $legacy; do
        _mf_in_words "$item" "$known" || missing="$missing $item"
    done
    [ -n "$missing" ] || return 0

    if command -v load_package_profiles >/dev/null 2>&1 && load_package_profiles \
        && command -v jq >/dev/null 2>&1; then
        jq -r '
            def names:
                [.. | objects |
                    (.name // empty),
                    ((.alternatives // [])[]?),
                    ((.depends // [])[]?),
                    ((.packages // [])[]? | if type == "string" then . else empty end)
                ]
                # Preserve the old end anchor, which also accepts one trailing LF.
                | map(select(strings | rtrimstr("\n") | explode
                    | length > 0 and all(.[];
                        (. >= 48 and . <= 57) or (. >= 65 and . <= 90) or
                        (. >= 97 and . <= 122) or . == 43 or . == 45 or . == 46 or . == 95)))
                | unique;
            .profiles | to_entries[] |
            [.key, (.value.title // .key), ((.value | names) | join(" "))] | @tsv
        ' "$PROFILES_FILE" 2>/dev/null | while IFS="$(printf '\t')" read -r _mf_id _mf_title _mf_names; do
            _mf_hit=""
            for _mf_pkg in $missing; do
                _mf_in_words "$_mf_pkg" "$_mf_names" && _mf_hit="${_mf_hit:+$_mf_hit }$_mf_pkg"
            done
            [ -n "$_mf_hit" ] || continue
            mf_register_module "$_mf_id" "$_mf_title" "$_mf_title" "$_mf_hit" || exit 1
        done || return 1
    fi

    known=""
    ids=$(mf_module_ids) || return 1
    for id in $ids; do
        names=$(mf_module_packages "$id") || return 1
        known="$known $names"
    done
    remaining=""
    for item in $missing; do
        _mf_in_words "$item" "$known" || remaining="${remaining:+$remaining }$item"
    done
    [ -z "$remaining" ] || mf_register_module daypass DayPass DayPass "$remaining"
}

# Heading used by the inspection table.
mf_inspection_title() {
    if [ -n "${INSPECT_MODULE_TITLE:-}" ]; then
        printf '%s' "$INSPECT_MODULE_TITLE"
        return 0
    fi
    if [ -n "${INSPECT_MODULE_ID:-}" ]; then
        _mf_t="$(mf_module_title "$INSPECT_MODULE_ID")"
        [ -n "$_mf_t" ] && printf '%s' "$_mf_t" && return 0
        mf_title_for "$INSPECT_MODULE_ID"
        return 0
    fi
    if [ -n "${SELECTED_PROFILE:-}" ]; then
        mf_title_for "$SELECTED_PROFILE"
        return 0
    fi
    _mf_ids=$(mf_module_ids)
    _mf_n=0
    _mf_one=""
    for _mf_id in $_mf_ids; do
        _mf_n=$((_mf_n + 1))
        _mf_one="$_mf_id"
    done
    if [ "$_mf_n" -eq 1 ]; then
        mf_module_title "$_mf_one"
        return 0
    fi
    printf '%s' "DayPass"
}

mf_inspection_category() {
    if [ -n "${INSPECT_MODULE_CATEGORY:-}" ]; then
        printf '%s' "$INSPECT_MODULE_CATEGORY"
        return 0
    fi
    if [ -n "${INSPECT_MODULE_ID:-}" ]; then
        mf_module_category "$INSPECT_MODULE_ID"
        return 0
    fi
    if [ -n "${SELECTED_PROFILE:-}" ]; then
        mf_category_for "$SELECTED_PROFILE"
        return 0
    fi
    printf '%s' ""
}

# Record the current install session as a named module.
# $1 module id, $2 packages
mf_record_install() {
    _mf_id="$1"
    _mf_pkgs="$2"
    [ -n "$_mf_id" ] && [ -n "$_mf_pkgs" ] || return 1
    mf_register_module "$_mf_id" "$(mf_title_for "$_mf_id")" "$(mf_category_for "$_mf_id")" "$_mf_pkgs" "" "" "${3:-}" || return 1
    mf_sync_install_log
}
