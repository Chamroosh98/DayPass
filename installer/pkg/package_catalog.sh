#!/bin/sh
# ============================================================
# DayPass - Friendly package titles for the Profile Install UI
# Data: config/package_catalog.json (embedded as daypass_embedded_catalog)
# ============================================================

PACKAGE_CATALOG_FILE="${PACKAGE_CATALOG_FILE:-}"
DAYPASS_RESOLVE_LOG="${DAYPASS_RESOLVE_LOG:-/tmp/daypass_resolve.log}"

load_package_catalog() {
    if [ -n "$PACKAGE_CATALOG_FILE" ] && [ -s "$PACKAGE_CATALOG_FILE" ]; then
        return 0
    fi

    _pc_dir="${TMP_DIR:-/tmp/daypass}"
    _pc_cache="$_pc_dir/package_catalog.json"
    mkdir -p "$_pc_dir" 2>/dev/null

    if [ -s "${DAYPASS_DIR:-/etc/daypass}/package_catalog.json" ]; then
        PACKAGE_CATALOG_FILE="${DAYPASS_DIR}/package_catalog.json"
        export PACKAGE_CATALOG_FILE
        return 0
    fi

    if command -v daypass_embedded_catalog >/dev/null 2>&1; then
        daypass_embedded_catalog > "$_pc_cache" 2>/dev/null
        if [ -s "$_pc_cache" ]; then
            PACKAGE_CATALOG_FILE="$_pc_cache"
            export PACKAGE_CATALOG_FILE
            return 0
        fi
    fi

    if [ -s "config/package_catalog.json" ]; then
        PACKAGE_CATALOG_FILE="config/package_catalog.json"
        export PACKAGE_CATALOG_FILE
        return 0
    fi

    return 1
}

_pc_field() {
    _pc_pkg="$1"
    _pc_key="$2"
    command -v jq >/dev/null 2>&1 || return 1
    [ -n "$PACKAGE_CATALOG_FILE" ] || load_package_catalog || return 1
    jq -r --arg p "$_pc_pkg" --arg k "$_pc_key" \
        '.packages[$p][$k] // empty' "$PACKAGE_CATALOG_FILE" 2>/dev/null
}

pkg_display_title() {
    _pc_t="$(_pc_field "$1" title)"
    if [ -n "$_pc_t" ]; then
        printf '%s' "$_pc_t"
        return 0
    fi
    case "$1" in
        luci-app-*)
            printf 'Web Interface for %s' "$(printf '%s' "${1#luci-app-}" | tr '-' ' ')"
            ;;
        luci-i18n-*)
            printf 'Translation pack (%s)' "${1#luci-i18n-}"
            ;;
        luci-proto-*)
            printf 'Web protocol helper (%s)' "${1#luci-proto-}"
            ;;
        *)
            printf '%s' "$1"
            ;;
    esac
}

pkg_display_desc() {
    _pc_d="$(_pc_field "$1" description)"
    [ -n "$_pc_d" ] && printf '%s' "$_pc_d"
}

pkg_display_role() {
    _pc_pkg="$1"
    _pc_optional="$2"
    _pc_r="$(_pc_field "$_pc_pkg" role)"
    if [ -z "$_pc_r" ]; then
        case "$_pc_pkg" in
            luci-app-*|luci-proto-*) _pc_r="web" ;;
            luci-i18n-*)             _pc_r="enhancement" ;;
            *)
                if [ "$_pc_optional" = "1" ]; then
                    _pc_r="enhancement"
                else
                    _pc_r="core"
                fi
                ;;
        esac
    fi
    case "$_pc_r" in
        web)         printf '%s' "Web Interface" ;;
        enhancement) printf '%s' "Enhancement" ;;
        *)           printf '%s' "Core" ;;
    esac
}

profile_display_title() {
    _pc_id="$1"
    if command -v load_package_profiles >/dev/null 2>&1 && load_package_profiles \
        && command -v jq >/dev/null 2>&1; then
        _pc_t=$(jq -r --arg id "$_pc_id" '.profiles[$id].title // empty' "$PROFILES_FILE" 2>/dev/null)
        [ -n "$_pc_t" ] && printf '%s' "$_pc_t" && return 0
    fi
    command -v _mf_pretty >/dev/null 2>&1 && _mf_pretty "$_pc_id" && return 0
    printf '%s' "$_pc_id"
}

# Renders PROFILE_PLAN as a framed, non-technical list.
render_profile_plan() {
    _pc_profile="$1"
    _pc_title="$(profile_display_title "$_pc_profile")"
    _pc_count=$(echo $PROFILE_PACKAGES | wc -w | tr -d ' ')

    load_package_catalog >/dev/null 2>&1 || true

    echo
    printf "  📦 ${BOLD}Profile Installation: %s${RESET}\n" "$_pc_title"
    echo "  ───────────────────────────────────────────────────────────"
    printf "  ${GRAY}OpenWrt %s  ·  %s  ·  %s component(s)${RESET}\n" \
        "${PROFILE_RELEASE:-?}.x" "${PKG_MANAGER:-opkg}" "${_pc_count:-0}"
    echo "  ───────────────────────────────────────────────────────────"
    echo

    printf '%s\n' "$PROFILE_PLAN" | while IFS='|' read -r _pc_name _pc_src _pc_opt _pc_alts _; do
        [ -n "$_pc_name" ] || continue
        _pc_role="$(pkg_display_role "$_pc_name" "$_pc_opt")"
        _pc_pt="$(pkg_display_title "$_pc_name")"
        _pc_pd="$(pkg_display_desc "$_pc_name")"
        case "$_pc_role" in
            Core)            _pc_tag="${GREEN}[Core]${RESET}" ;;
            "Web Interface") _pc_tag="${CYAN}[Web Interface]${RESET}" ;;
            *)               _pc_tag="${YELLOW}[Enhancement]${RESET}" ;;
        esac
        printf "  %b  ${BOLD}%s${RESET}\n" "$_pc_tag" "$_pc_pt"
        if [ -n "$_pc_pd" ]; then
            printf "         ${GRAY}%s${RESET}\n" "$_pc_pd"
        fi
        if [ -n "$_pc_alts" ]; then
            printf "         ${GRAY}If unavailable, a compatible fallback is tried.${RESET}\n"
        fi
        echo
    done

    echo "  ───────────────────────────────────────────────────────────"
}

profile_install_prompt() {
    _pc_title="$1"
    _pc_count="$2"
    printf "  ⁉️ ${YELLOW}Install profile [%s] (%s packages)?${RESET} ${GRAY}[Y/n] :${RESET} " \
        "$_pc_title" "$_pc_count"
    if ! read -r UI_CHOICE </dev/tty; then
        UI_CHOICE=""
        daypass_quit
    fi
}

profile_display_icon() {
    _pc_id="$1"
    _pc_icon=""
    if command -v jq >/dev/null 2>&1 && load_package_catalog >/dev/null 2>&1; then
        _pc_icon=$(jq -r --arg id "$_pc_id" '.profiles[$id].icon // empty' "$PACKAGE_CATALOG_FILE" 2>/dev/null)
    fi
    if [ -n "$_pc_icon" ]; then
        printf '%s' "$_pc_icon"
        return 0
    fi
    case "$_pc_id" in
        proxy)          printf '⚡' ;;
        vpn)            printf '🔐' ;;
        usb)            printf '🔌' ;;
        network_tools)  printf '📈' ;;
        *)              printf '📦' ;;
    esac
}

# Manifest ids that belong to a package profile (proxy wizard records passwall / passwall2).
_pd_related_ids() {
    case "$1" in
        proxy) printf '%s' "proxy passwall passwall2" ;;
        *)     printf '%s' "$1" ;;
    esac
}

_pd_tool_label() {
    case "$1" in
        luci-app-passwall2) printf 'passwall2' ;;
        luci-app-passwall)  printf 'passwall' ;;
        luci-app-*)         printf '%s' "${1#luci-app-}" ;;
        *)                  printf '%s' "$1" ;;
    esac
}

_pd_in_words() {
    _pd_n="$1"
    _pd_h="$2"
    for _pd_w in $_pd_h; do
        [ "$_pd_w" = "$_pd_n" ] && return 0
    done
    return 1
}

_pd_pkg_present() {
    _pd_name="$1"
    _pd_alts="$2"
    _pd_ids="$3"

    if command -v _pr_is_installed >/dev/null 2>&1; then
        _pr_is_installed "$_pd_name" && return 0
        for _pd_alt in $_pd_alts; do
            [ -n "$_pd_alt" ] || continue
            _pr_is_installed "$_pd_alt" && return 0
        done
    fi

    if command -v mf_module_packages >/dev/null 2>&1; then
        for _pd_mid in $_pd_ids; do
            _pd_mpkgs="$(mf_module_packages "$_pd_mid" 2>/dev/null)"
            [ -n "$_pd_mpkgs" ] || continue
            _pd_in_words "$_pd_name" "$_pd_mpkgs" && return 0
            for _pd_alt in $_pd_alts; do
                [ -n "$_pd_alt" ] || continue
                _pd_in_words "$_pd_alt" "$_pd_mpkgs" && return 0
            done
        done
    fi
    return 1
}

_pd_highlights() {
    _pd_id="$1"
    _pd_pkgs="$2"
    _pd_list=""

    if command -v jq >/dev/null 2>&1 && load_package_catalog >/dev/null 2>&1; then
        _pd_list=$(jq -r --arg id "$_pd_id" '(.profiles[$id].highlights // []) | join(" ")' \
            "$PACKAGE_CATALOG_FILE" 2>/dev/null)
    fi

    _pd_out=""
    _pd_n=0
    for _pd_h in $_pd_list; do
        [ "$_pd_n" -ge 4 ] && break
        if [ -n "$_pd_pkgs" ] && ! _pd_in_words "$_pd_h" "$_pd_pkgs"; then
            case "$_pd_id" in
                proxy) ;;
                *) continue ;;
            esac
        fi
        _pd_lab="$(_pd_tool_label "$_pd_h")"
        _pd_in_words "$_pd_lab" "$_pd_out" && continue
        _pd_out="${_pd_out:+$_pd_out, }$_pd_lab"
        _pd_n=$((_pd_n + 1))
    done

    if [ "$_pd_n" -lt 3 ]; then
        for _pd_h in $_pd_pkgs; do
            [ "$_pd_n" -ge 4 ] && break
            case "$_pd_h" in
                luci-i18n-*) continue ;;
            esac
            _pd_lab="$(_pd_tool_label "$_pd_h")"
            _pd_in_words "$_pd_lab" "$_pd_out" && continue
            _pd_out="${_pd_out:+$_pd_out, }$_pd_lab"
            _pd_n=$((_pd_n + 1))
        done
    fi

    [ -n "$_pd_out" ] && printf '%s' "$_pd_out"
}

_pd_profile_ids() {
    _pd_all=""
    if command -v load_package_profiles >/dev/null 2>&1 && load_package_profiles \
        && command -v jq >/dev/null 2>&1; then
        _pd_all=$(jq -r '.profiles | keys[]' "$PROFILES_FILE" 2>/dev/null)
    fi
    [ -n "$_pd_all" ] || _pd_all="proxy vpn usb network_tools"
    for _pd_pref in proxy vpn usb network_tools; do
        _pd_in_words "$_pd_pref" "$_pd_all" && printf '%s\n' "$_pd_pref"
    done
    for _pd_x in $_pd_all; do
        case "$_pd_x" in
            proxy|vpn|usb|network_tools) continue ;;
        esac
        printf '%s\n' "$_pd_x"
    done
}

# Interactive Option 6: framed dashboard with live install status.
profile_status_dashboard() {
    local _pd_id _pd_title _pd_icon _pd_count _pd_hit _pd_miss
    local _pd_tools _pd_badge _pd_name _pd_src _pd_opt _pd_alts
    local _pd_ids _pd_saved_plan _pd_saved_pkgs _pd_quiet

    render_persistent_header
    ui_title "📋 Profile Overview & Status Dashboard"
    printf "  ${GRAY}Live status from this router and the DayPass install record.${RESET}\n"
    echo "  ───────────────────────────────────────────────────────────"
    echo

    _pd_saved_plan="${PROFILE_PLAN:-}"
    _pd_saved_pkgs="${PROFILE_PACKAGES:-}"
    _pd_quiet="${DAYPASS_RESOLVE_QUIET:-0}"

    load_package_catalog >/dev/null 2>&1 || true

    for _pd_id in $(_pd_profile_ids); do
        [ -n "$_pd_id" ] || continue
        _pd_title="$(profile_display_title "$_pd_id")"
        _pd_icon="$(profile_display_icon "$_pd_id")"
        _pd_ids="$(_pd_related_ids "$_pd_id")"
        _pd_count=0
        _pd_hit=0
        _pd_miss=0

        DAYPASS_RESOLVE_QUIET=1
        export DAYPASS_RESOLVE_QUIET
        if command -v resolve_profile >/dev/null 2>&1 && resolve_profile "$_pd_id"; then
            _pd_count=$(echo $PROFILE_PACKAGES | wc -w | tr -d ' ')
            while IFS='|' read -r _pd_name _pd_src _pd_opt _pd_alts _; do
                [ -n "$_pd_name" ] || continue
                if _pd_pkg_present "$_pd_name" "$_pd_alts" "$_pd_ids"; then
                    _pd_hit=$((_pd_hit + 1))
                else
                    _pd_miss=$((_pd_miss + 1))
                fi
            done <<EOF
$PROFILE_PLAN
EOF
            _pd_tools="$(_pd_highlights "$_pd_id" "$PROFILE_PACKAGES")"
        else
            _pd_tools="$(_pd_highlights "$_pd_id" "")"
        fi

        if [ "$_pd_hit" -eq 0 ]; then
            _pd_badge="${GRAY}[✖ Not Installed]${RESET}"
        elif [ "$_pd_miss" -eq 0 ]; then
            _pd_badge="${GREEN}[✔ Installed]${RESET}"
        else
            _pd_badge="${YELLOW}[⚠ Partial]${RESET}"
        fi

        printf "  %s  ${BOLD}%s${RESET}\n" "$_pd_icon" "$_pd_title"
        printf "      Status   %b\n" "$_pd_badge"
        printf "      Tools    ${GRAY}%s${RESET}\n" "${_pd_tools:-—}"
        printf "      Count    %s package(s)\n" "${_pd_count:-0}"
        echo
    done

    DAYPASS_RESOLVE_QUIET="$_pd_quiet"
    export DAYPASS_RESOLVE_QUIET
    PROFILE_PLAN="$_pd_saved_plan"
    PROFILE_PACKAGES="$_pd_saved_pkgs"
    export PROFILE_PLAN PROFILE_PACKAGES

    echo "  ───────────────────────────────────────────────────────────"
    printf "  ${GRAY}Press [Enter] to return to menu ...${RESET}"
    read -r _ </dev/tty || daypass_quit
}
