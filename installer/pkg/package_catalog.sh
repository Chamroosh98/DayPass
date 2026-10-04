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
    ui_divider
    printf "  ${GRAY}OpenWrt %s  ·  %s  ·  %s component(s)${RESET}\n" \
        "${PROFILE_RELEASE:-?}.x" "${PKG_MANAGER:-opkg}" "${_pc_count:-0}"
    ui_divider
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

    ui_divider
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

# Profile overview lives in installer/pkg/profile_overview.sh.