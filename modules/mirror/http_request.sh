#!/bin/sh
# ============================================================
# DayPass - HTTP client wrapper
# Order: curl, then uclient-fetch, then wget.
# Stock OpenWrt has uclient-fetch and usually no curl.
#
# daypass_http_request METHOD URL OUTFILE [BODYFILE] [HEADERFILE]
#   HEADERFILE is "Name: value" lines (Authorization, Content-Type, ...).
#   Prints the HTTP status code (000 when nothing answered).
#   Returns 0 when a status was captured, 1 otherwise.
#   A short reason is written to ${DAYPASS_HTTP_ERR:-/tmp/daypass_http.err}.
# ============================================================

DAYPASS_HTTP_ERR="${DAYPASS_HTTP_ERR:-/tmp/daypass_http.err}"

daypass_http_available() {
    command -v curl >/dev/null 2>&1 \
        || command -v uclient-fetch >/dev/null 2>&1 \
        || command -v wget >/dev/null 2>&1
}

_dh_fail() {
    printf '%s\n' "$1" > "$DAYPASS_HTTP_ERR" 2>/dev/null
    printf '%s\n' "000"
    return 1
}

_dh_tool_help() {
    "$1" --help 2>&1 || true
}

# $1 method $2 url $3 outfile $4 body $5 headerfile
_dh_via_curl() {
    _dh_cfg="${DAYPASS_HTTP_ERR}.curl.cfg"
    _dh_umask="$(umask)"
    umask 077
    {
        printf '%s\n' "silent" "show-error"
        printf 'output = "%s"\n' "$3"
        printf 'request = "%s"\n' "$1"
        printf '%s\n' "connect-timeout = 15" "max-time = 180"
        printf '%s\n' 'write-out = "%{http_code}"'
        if [ -n "$4" ] && [ -f "$4" ]; then
            printf 'data-binary = "@%s"\n' "$4"
        fi
        if [ -n "$5" ] && [ -f "$5" ]; then
            while IFS= read -r _dh_line || [ -n "$_dh_line" ]; do
                [ -n "$_dh_line" ] || continue
                printf 'header = "%s"\n' "$_dh_line"
            done < "$5"
        fi
    } > "$_dh_cfg" 2>/dev/null || { umask "$_dh_umask"; return 1; }
    umask "$_dh_umask"

    _dh_code="$(curl -K "$_dh_cfg" "$2" 2>"$DAYPASS_HTTP_ERR")"
    rm -f "$_dh_cfg" 2>/dev/null
    case "$_dh_code" in
        [0-9][0-9][0-9]) printf '%s\n' "$_dh_code"; return 0 ;;
    esac
    return 1
}

# $1 method $2 url $3 outfile $4 body $5 headerfile
_dh_via_uclient() {
    _dh_m="$1"
    _dh_u="$2"
    _dh_o="$3"
    _dh_b="$4"
    _dh_h="$5"
    _dh_help="$(_dh_tool_help uclient-fetch)"
    set -- uclient-fetch -O "$_dh_o" -T 180

    if [ -n "$_dh_h" ] && [ -f "$_dh_h" ]; then
        while IFS= read -r _dh_line || [ -n "$_dh_line" ]; do
            [ -n "$_dh_line" ] || continue
            set -- "$@" --header="$_dh_line"
        done < "$_dh_h"
    fi

    if [ -n "$_dh_b" ] && [ -f "$_dh_b" ]; then
        if printf '%s\n' "$_dh_help" | grep -q -- '--method'; then
            set -- "$@" --method="$_dh_m" --body-file="$_dh_b"
        elif [ "$_dh_m" = "POST" ] && printf '%s\n' "$_dh_help" | grep -q -- '--post-file'; then
            set -- "$@" --post-file="$_dh_b"
        elif [ "$_dh_m" = "POST" ] && printf '%s\n' "$_dh_help" | grep -q -- '--post-data'; then
            set -- "$@" --post-data="$(cat "$_dh_b")"
        else
            printf '%s\n' "uclient-fetch cannot send ${_dh_m}." > "$DAYPASS_HTTP_ERR"
            return 1
        fi
    elif [ "$_dh_m" != "GET" ] && [ "$_dh_m" != "HEAD" ]; then
        if printf '%s\n' "$_dh_help" | grep -q -- '--method'; then
            set -- "$@" --method="$_dh_m"
        else
            printf '%s\n' "uclient-fetch cannot send ${_dh_m}." > "$DAYPASS_HTTP_ERR"
            return 1
        fi
    fi

    _dh_err="$( "$@" "$_dh_u" 2>&1 )"
    _dh_rc=$?
    printf '%s\n' "$_dh_err" > "$DAYPASS_HTTP_ERR" 2>/dev/null

    _dh_code="$(printf '%s\n' "$_dh_err" | sed -n 's/.*HTTP error \([0-9][0-9][0-9]\).*/\1/p' | sed -n '$p')"
    if [ -n "$_dh_code" ]; then
        printf '%s\n' "$_dh_code"
        return 0
    fi
    if [ "$_dh_rc" -eq 0 ]; then
        printf '%s\n' "200"
        return 0
    fi
    return 1
}

# $1 method $2 url $3 outfile $4 body $5 headerfile
_dh_via_wget() {
    _dh_m="$1"
    _dh_u="$2"
    _dh_o="$3"
    _dh_b="$4"
    _dh_h="$5"
    _dh_help="$(_dh_tool_help wget)"
    set -- wget -O "$_dh_o" -T 180 -S

    if printf '%s\n' "$_dh_help" | grep -q -- '--no-check-certificate'; then
        set -- "$@" --no-check-certificate
    fi

    if [ -n "$_dh_h" ] && [ -f "$_dh_h" ]; then
        while IFS= read -r _dh_line || [ -n "$_dh_line" ]; do
            [ -n "$_dh_line" ] || continue
            set -- "$@" --header="$_dh_line"
        done < "$_dh_h"
    fi

    if [ -n "$_dh_b" ] && [ -f "$_dh_b" ]; then
        if printf '%s\n' "$_dh_help" | grep -q -- '--method' \
            && printf '%s\n' "$_dh_help" | grep -q -- '--body-file'; then
            set -- "$@" --method="$_dh_m" --body-file="$_dh_b"
        elif [ "$_dh_m" = "POST" ] && printf '%s\n' "$_dh_help" | grep -q -- '--post-file'; then
            set -- "$@" --post-file="$_dh_b"
        elif [ "$_dh_m" = "POST" ] && printf '%s\n' "$_dh_help" | grep -q -- '--post-data'; then
            set -- "$@" --post-data="$(cat "$_dh_b")"
        else
            printf '%s\n' "wget cannot send ${_dh_m}." > "$DAYPASS_HTTP_ERR"
            return 1
        fi
    elif [ "$_dh_m" != "GET" ] && [ "$_dh_m" != "HEAD" ]; then
        if printf '%s\n' "$_dh_help" | grep -q -- '--method'; then
            set -- "$@" --method="$_dh_m"
        else
            printf '%s\n' "wget cannot send ${_dh_m}." > "$DAYPASS_HTTP_ERR"
            return 1
        fi
    fi

    _dh_err="$( "$@" "$_dh_u" 2>&1 )"
    _dh_rc=$?
    printf '%s\n' "$_dh_err" > "$DAYPASS_HTTP_ERR" 2>/dev/null

    _dh_code="$(printf '%s\n' "$_dh_err" | sed -n 's|.*HTTP/[0-9.][0-9.]* \([0-9][0-9][0-9]\).*|\1|p' | sed -n '$p')"
    if [ -n "$_dh_code" ]; then
        printf '%s\n' "$_dh_code"
        return 0
    fi
    if [ "$_dh_rc" -eq 0 ]; then
        printf '%s\n' "200"
        return 0
    fi
    return 1
}

daypass_http_request() {
    _dh_method="$1"
    _dh_url="$2"
    _dh_out="$3"
    _dh_body="$4"
    _dh_hdr="$5"

    : > "$DAYPASS_HTTP_ERR" 2>/dev/null
    rm -f "$_dh_out" 2>/dev/null

    case "$_dh_method" in
        GET|POST|PUT|HEAD|DELETE|PATCH) ;;
        *)
            _dh_fail "Unsupported HTTP method [${_dh_method}]."
            return 1
            ;;
    esac

    if [ -z "$_dh_url" ] || [ -z "$_dh_out" ]; then
        _dh_fail "HTTP request is missing a URL or output file."
        return 1
    fi

    if command -v curl >/dev/null 2>&1; then
        if _dh_via_curl "$_dh_method" "$_dh_url" "$_dh_out" "$_dh_body" "$_dh_hdr"; then
            return 0
        fi
        _dh_fail "curl could not complete the request."
        return 1
    fi

    if command -v uclient-fetch >/dev/null 2>&1; then
        if _dh_via_uclient "$_dh_method" "$_dh_url" "$_dh_out" "$_dh_body" "$_dh_hdr"; then
            return 0
        fi
    fi

    if command -v wget >/dev/null 2>&1; then
        if _dh_via_wget "$_dh_method" "$_dh_url" "$_dh_out" "$_dh_body" "$_dh_hdr"; then
            return 0
        fi
    fi

    if [ ! -s "$DAYPASS_HTTP_ERR" ]; then
        printf '%s\n' "No HTTP client found (curl, uclient-fetch or wget)." > "$DAYPASS_HTTP_ERR"
    fi
    printf '%s\n' "000"
    return 1
}
