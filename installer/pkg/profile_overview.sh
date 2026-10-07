#!/bin/sh
# DayPass - Profile overview dashboard (option 6).
# POSIX ash only. Counters never share names with package strings.

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
    _pd_needle="$1"
    _pd_hay="$2"
    for _pd_w in $_pd_hay; do
        [ "$_pd_w" = "$_pd_needle" ] && return 0
    done
    return 1
}

_pd_pkg_present() {
    _pd_pname="$1"
    _pd_palts="$2"
    _pd_pids="$3"

    if command -v _pr_is_installed >/dev/null 2>&1; then
        _pr_is_installed "$_pd_pname" && return 0
        for _pd_alt in $_pd_palts; do
            [ -n "$_pd_alt" ] || continue
            _pr_is_installed "$_pd_alt" && return 0
        done
    fi

    if command -v mf_module_packages >/dev/null 2>&1; then
        for _pd_mid in $_pd_pids; do
            _pd_mpkgs="$(mf_module_packages "$_pd_mid" 2>/dev/null)"
            [ -n "$_pd_mpkgs" ] || continue
            _pd_in_words "$_pd_pname" "$_pd_mpkgs" && return 0
            for _pd_alt in $_pd_palts; do
                [ -n "$_pd_alt" ] || continue
                _pd_in_words "$_pd_alt" "$_pd_mpkgs" && return 0
            done
        done
    fi
    return 1
}

_pd_highlights() {
    _pd_hid="$1"
    _pd_pkgs="$2"
    _pd_list=""
    _pd_out=""
    _pd_cnt=0

    if command -v jq >/dev/null 2>&1 && load_package_catalog >/dev/null 2>&1; then
        _pd_list=$(jq -r --arg id "$_pd_hid" '(.profiles[$id].highlights // []) | join(" ")' \
            "$PACKAGE_CATALOG_FILE" 2>/dev/null)
    fi

    for _pd_h in $_pd_list; do
        [ "${_pd_cnt:-0}" -ge 4 ] && break
        if [ -n "$_pd_pkgs" ] && ! _pd_in_words "$_pd_h" "$_pd_pkgs"; then
            case "$_pd_hid" in
                proxy) ;;
                *) continue ;;
            esac
        fi
        _pd_lab="$(_pd_tool_label "$_pd_h")"
        _pd_in_words "$_pd_lab" "$_pd_out" && continue
        _pd_out="${_pd_out:+$_pd_out, }$_pd_lab"
        _pd_cnt=$((${_pd_cnt:-0} + 1))
    done

    if [ "${_pd_cnt:-0}" -lt 3 ]; then
        for _pd_h in $_pd_pkgs; do
            [ "${_pd_cnt:-0}" -ge 4 ] && break
            case "$_pd_h" in
                luci-i18n-*) continue ;;
            esac
            _pd_lab="$(_pd_tool_label "$_pd_h")"
            _pd_in_words "$_pd_lab" "$_pd_out" && continue
            _pd_out="${_pd_out:+$_pd_out, }$_pd_lab"
            _pd_cnt=$((${_pd_cnt:-0} + 1))
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

_pd_word_count() {
    _pd_words="$1"
    _pd_wc=0
    for _pd_w in $_pd_words; do
        _pd_wc=$((${_pd_wc:-0} + 1))
    done
    printf '%s\n' "${_pd_wc:-0}"
}

# Interactive Option 6: stacked status cards with live install status.
profile_status_dashboard() {
    _pd_saved_plan="${PROFILE_PLAN:-}"
    _pd_saved_pkgs="${PROFILE_PACKAGES:-}"
    _pd_quiet="${DAYPASS_RESOLVE_QUIET:-0}"
    _pd_first=1

    render_persistent_header
    ui_title "📋 Profile Overview & Status Dashboard"
    printf "  ${GRAY}Live status from this router and the DayPass install record.${RESET}\n"
    echo

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
            _pd_count="$(_pd_word_count "$PROFILE_PACKAGES")"
            while IFS='|' read -r _pd_name _pd_src _pd_opt _pd_alts _; do
                [ -n "$_pd_name" ] || continue
                if _pd_pkg_present "$_pd_name" "$_pd_alts" "$_pd_ids"; then
                    _pd_hit=$((${_pd_hit:-0} + 1))
                else
                    _pd_miss=$((${_pd_miss:-0} + 1))
                fi
            done <<EOF
$PROFILE_PLAN
EOF
            _pd_tools="$(_pd_highlights "$_pd_id" "$PROFILE_PACKAGES")"
        else
            _pd_tools="$(_pd_highlights "$_pd_id" "")"
        fi

        _pd_count="${_pd_count:-0}"
        _pd_hit="${_pd_hit:-0}"
        _pd_miss="${_pd_miss:-0}"

        if [ "$_pd_hit" -eq 0 ]; then
            _pd_badge="${GRAY}✖ Not Installed${RESET}"
        elif [ "$_pd_miss" -eq 0 ]; then
            _pd_badge="${GREEN}✔ Installed${RESET}"
        else
            _pd_badge="${YELLOW}⚠ Partial${RESET}"
        fi

        [ "$_pd_first" -eq 1 ] || echo
        _pd_first=0

        echo "  $_pd_icon $_pd_title"
        printf "    Status : %b\n" "$_pd_badge"
        printf "    Tools  : ${GRAY}%s${RESET}\n" "${_pd_tools:-—}"
        echo "    Count  : ${_pd_count} package(s)"
    done

    DAYPASS_RESOLVE_QUIET="$_pd_quiet"
    export DAYPASS_RESOLVE_QUIET
    PROFILE_PLAN="$_pd_saved_plan"
    PROFILE_PACKAGES="$_pd_saved_pkgs"
    export PROFILE_PLAN PROFILE_PACKAGES

    echo
    if command -v ui_pause >/dev/null 2>&1; then
        ui_pause
    else
        printf "  ${GRAY}Press [Enter] to return to menu ...${RESET}"
        read -r _ </dev/tty || true
    fi
}
