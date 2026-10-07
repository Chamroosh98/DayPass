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
        || command -v wget >/dev/null 2>&1 \
        || command -v openssl >/dev/null 2>&1
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

# Copy headers and, for a faked PUT, add the override lines BusyBox can send.
# $1 source header file (optional), $2 dest, $3 real method or empty
_dh_prepare_headers() {
    : > "$2" 2>/dev/null || return 1
    if [ -n "$1" ] && [ -f "$1" ]; then
        cat "$1" >> "$2" 2>/dev/null || return 1
    fi
    if [ -n "$3" ] && [ "$3" != "POST" ] && [ "$3" != "GET" ] && [ "$3" != "HEAD" ]; then
        printf 'X-HTTP-Method-Override: %s\n' "$3" >> "$2"
        printf 'X-Method: %s\n' "$3" >> "$2"
    fi
    return 0
}

# $1 method $2 url $3 outfile $4 body $5 headerfile
# Prints a status and returns 0, or returns 2 when this client cannot do the method.
_dh_via_uclient() {
    _dh_m="$1"
    _dh_u="$2"
    _dh_o="$3"
    _dh_b="$4"
    _dh_h="$5"
    _dh_help="$(_dh_tool_help uclient-fetch)"
    _dh_send="$_dh_m"
    _dh_hdrs="$_dh_h"

    if [ "$_dh_m" != "GET" ] && [ "$_dh_m" != "HEAD" ] && [ "$_dh_m" != "POST" ] \
        && ! printf '%s\n' "$_dh_help" | grep -q -- '--method'; then
        if [ -n "$_dh_b" ] && printf '%s\n' "$_dh_help" | grep -q -e '--post-file' -e '--post-data'; then
            _dh_send="POST"
            _dh_hdrs="${DAYPASS_HTTP_ERR}.override.hdr"
            _dh_prepare_headers "$_dh_h" "$_dh_hdrs" "$_dh_m" || return 2
        else
            return 2
        fi
    fi

    set -- uclient-fetch -O "$_dh_o" -T 180

    if [ -n "$_dh_hdrs" ] && [ -f "$_dh_hdrs" ]; then
        while IFS= read -r _dh_line || [ -n "$_dh_line" ]; do
            [ -n "$_dh_line" ] || continue
            set -- "$@" --header="$_dh_line"
        done < "$_dh_hdrs"
    fi

    if [ -n "$_dh_b" ] && [ -f "$_dh_b" ]; then
        if printf '%s\n' "$_dh_help" | grep -q -- '--method'; then
            set -- "$@" --method="$_dh_send" --body-file="$_dh_b"
        elif [ "$_dh_send" = "POST" ] && printf '%s\n' "$_dh_help" | grep -q -- '--post-file'; then
            set -- "$@" --post-file="$_dh_b"
        elif [ "$_dh_send" = "POST" ] && printf '%s\n' "$_dh_help" | grep -q -- '--post-data'; then
            set -- "$@" --post-data="$(cat "$_dh_b")"
        else
            return 2
        fi
    elif [ "$_dh_send" != "GET" ] && [ "$_dh_send" != "HEAD" ]; then
        if printf '%s\n' "$_dh_help" | grep -q -- '--method'; then
            set -- "$@" --method="$_dh_send"
        else
            return 2
        fi
    fi

    _dh_err="$( "$@" "$_dh_u" 2>&1 )"
    _dh_rc=$?
    printf '%s\n' "$_dh_err" > "$DAYPASS_HTTP_ERR" 2>/dev/null

    _dh_code="$(printf '%s\n' "$_dh_err" | sed -n 's/.*HTTP error \([0-9][0-9][0-9]\).*/\1/p' | sed -n '$p')"
    if [ -z "$_dh_code" ] && [ "$_dh_rc" -eq 0 ]; then
        _dh_code="200"
    fi
    [ -n "$_dh_code" ] || return 1

    # A POST that only pretends to be PUT is not a real upload unless it succeeded.
    if [ "$_dh_send" = "POST" ] && [ "$_dh_m" != "POST" ]; then
        case "$_dh_code" in
            2[0-9][0-9]) ;;
            *) return 2 ;;
        esac
    fi

    printf '%s\n' "$_dh_code"
    return 0
}

# $1 method $2 url $3 outfile $4 body $5 headerfile
# Prints a status and returns 0, or returns 2 when this client cannot do the method.
_dh_via_wget() {
    _dh_m="$1"
    _dh_u="$2"
    _dh_o="$3"
    _dh_b="$4"
    _dh_h="$5"
    _dh_help="$(_dh_tool_help wget)"
    _dh_send="$_dh_m"
    _dh_hdrs="$_dh_h"

    if [ "$_dh_m" != "GET" ] && [ "$_dh_m" != "HEAD" ] && [ "$_dh_m" != "POST" ] \
        && ! printf '%s\n' "$_dh_help" | grep -q -- '--method'; then
        if [ -n "$_dh_b" ] && printf '%s\n' "$_dh_help" | grep -q -e '--post-file' -e '--post-data'; then
            _dh_send="POST"
            _dh_hdrs="${DAYPASS_HTTP_ERR}.override.hdr"
            _dh_prepare_headers "$_dh_h" "$_dh_hdrs" "$_dh_m" || return 2
        else
            return 2
        fi
    fi

    set -- wget -O "$_dh_o" -T 180 -S

    if printf '%s\n' "$_dh_help" | grep -q -- '--no-check-certificate'; then
        set -- "$@" --no-check-certificate
    fi

    if [ -n "$_dh_hdrs" ] && [ -f "$_dh_hdrs" ]; then
        while IFS= read -r _dh_line || [ -n "$_dh_line" ]; do
            [ -n "$_dh_line" ] || continue
            set -- "$@" --header="$_dh_line"
        done < "$_dh_hdrs"
    fi

    if [ -n "$_dh_b" ] && [ -f "$_dh_b" ]; then
        if [ "$_dh_send" = "$_dh_m" ] && printf '%s\n' "$_dh_help" | grep -q -- '--method' \
            && printf '%s\n' "$_dh_help" | grep -q -- '--body-file'; then
            set -- "$@" --method="$_dh_send" --body-file="$_dh_b"
        elif [ "$_dh_send" = "POST" ] && printf '%s\n' "$_dh_help" | grep -q -- '--post-file'; then
            set -- "$@" --post-file="$_dh_b"
        elif [ "$_dh_send" = "POST" ] && printf '%s\n' "$_dh_help" | grep -q -- '--post-data'; then
            set -- "$@" --post-data="$(cat "$_dh_b")"
        else
            return 2
        fi
    elif [ "$_dh_send" != "GET" ] && [ "$_dh_send" != "HEAD" ]; then
        if printf '%s\n' "$_dh_help" | grep -q -- '--method'; then
            set -- "$@" --method="$_dh_send"
        else
            return 2
        fi
    fi

    _dh_err="$( "$@" "$_dh_u" 2>&1 )"
    _dh_rc=$?
    printf '%s\n' "$_dh_err" > "$DAYPASS_HTTP_ERR" 2>/dev/null

    _dh_code="$(printf '%s\n' "$_dh_err" | sed -n 's|.*HTTP/[0-9.][0-9.]* \([0-9][0-9][0-9]\).*|\1|p' | sed -n '$p')"
    if [ -z "$_dh_code" ] && [ "$_dh_rc" -eq 0 ]; then
        _dh_code="200"
    fi
    [ -n "$_dh_code" ] || return 1

    if [ "$_dh_send" = "POST" ] && [ "$_dh_m" != "POST" ]; then
        case "$_dh_code" in
            2[0-9][0-9]) ;;
            *) return 2 ;;
        esac
    fi

    printf '%s\n' "$_dh_code"
    return 0
}

# Raw HTTP/1.1 over TLS. openssl s_client, or ncat --ssl.
# $1 method $2 url $3 outfile $4 body $5 headerfile
_dh_via_tls() {
    _dh_m="$1"
    _dh_u="$2"
    _dh_o="$3"
    _dh_b="$4"
    _dh_h="$5"
    _dh_rest="${_dh_u#*://}"
    _dh_host="${_dh_rest%%/*}"
    _dh_path="/${_dh_rest#*/}"
    [ "$_dh_path" = "/$_dh_rest" ] && _dh_path="/"
    _dh_host="${_dh_host%%:*}"
    [ -n "$_dh_host" ] || return 2

    if command -v openssl >/dev/null 2>&1; then
        _dh_tls_cmd="openssl s_client -quiet -connect ${_dh_host}:443 -servername ${_dh_host}"
    elif command -v ncat >/dev/null 2>&1 && _dh_tool_help ncat | grep -q -- '--ssl'; then
        _dh_tls_cmd="ncat --ssl ${_dh_host} 443"
    else
        return 2
    fi

    _dh_req="${DAYPASS_HTTP_ERR}.raw.req"
    _dh_resp="${DAYPASS_HTTP_ERR}.raw.resp"
    _dh_len=0
    if [ -n "$_dh_b" ] && [ -f "$_dh_b" ]; then
        _dh_len="$(wc -c < "$_dh_b" | tr -d ' ')"
    fi

    _dh_umask="$(umask)"
    umask 077
    {
        printf '%s %s HTTP/1.1\r\n' "$_dh_m" "$_dh_path"
        printf 'Host: %s\r\n' "$_dh_host"
        printf 'Content-Length: %s\r\n' "${_dh_len:-0}"
        printf 'Connection: close\r\n'
        if [ -n "$_dh_h" ] && [ -f "$_dh_h" ]; then
            while IFS= read -r _dh_line || [ -n "$_dh_line" ]; do
                [ -n "$_dh_line" ] || continue
                printf '%s\r\n' "$_dh_line"
            done < "$_dh_h"
        fi
        printf '\r\n'
        if [ -n "$_dh_b" ] && [ -f "$_dh_b" ]; then
            cat "$_dh_b"
        fi
    } > "$_dh_req" 2>/dev/null || { umask "$_dh_umask"; return 2; }
    umask "$_dh_umask"

    rm -f "$_dh_resp" 2>/dev/null
    if command -v timeout >/dev/null 2>&1; then
        timeout 25 $_dh_tls_cmd < "$_dh_req" > "$_dh_resp" 2>"$DAYPASS_HTTP_ERR" || true
    else
        $_dh_tls_cmd < "$_dh_req" > "$_dh_resp" 2>"$DAYPASS_HTTP_ERR" &
        _dh_tls_pid=$!
        _dh_tls_n=0
        while [ "$_dh_tls_n" -lt 25 ]; do
            kill -0 "$_dh_tls_pid" 2>/dev/null || break
            sleep 1
            _dh_tls_n=$((_dh_tls_n + 1))
        done
        kill "$_dh_tls_pid" 2>/dev/null || true
        wait "$_dh_tls_pid" 2>/dev/null || true
    fi
    rm -f "$_dh_req" 2>/dev/null

    _dh_code="$(tr -d '\r' < "$_dh_resp" 2>/dev/null | sed -n 's/^HTTP\/[0-9.][0-9.]* \([0-9][0-9][0-9]\).*/\1/p' | sed -n '1p')"
    [ -n "$_dh_code" ] || return 1

    awk 'BEGIN { body = 0 }
        { sub(/\r$/, "") }
        body { print }
        $0 == "" { body = 1 }' "$_dh_resp" > "$_dh_o" 2>/dev/null
    rm -f "$_dh_resp" 2>/dev/null
    printf '%s\n' "$_dh_code"
    return 0
}

_dh_put_unsupported() {
    printf '%s\n' "PUT_UNSUPPORTED" > "$DAYPASS_HTTP_ERR" 2>/dev/null
    printf '%s\n' "000"
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

    case "$_dh_method" in
        PUT|PATCH|DELETE)
            if _dh_via_tls "$_dh_method" "$_dh_url" "$_dh_out" "$_dh_body" "$_dh_hdr"; then
                return 0
            fi
            _dh_put_unsupported
            return 1
            ;;
    esac

    if [ ! -s "$DAYPASS_HTTP_ERR" ]; then
        printf '%s\n' "No HTTP client found (curl, uclient-fetch or wget)." > "$DAYPASS_HTTP_ERR"
    fi
    printf '%s\n' "000"
    return 1
}
