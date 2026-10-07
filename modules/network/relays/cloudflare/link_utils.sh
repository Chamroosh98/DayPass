#!/bin/sh
# ============================================================
# DayPass - Share link helpers for the Cloudflare Clean IP flow
# ============================================================

# Transports Cloudflare can front; anything else cannot survive an address swap
_cf_cdn_transport() {
    case "$1" in
        ws|websocket|httpupgrade|h2|h2c|http|grpc|xhttp|splithttp) return 0 ;;
    esac
    return 1
}

# A name we can pin as SNI / Host; bare IP literals are not
_cf_is_domain() {
    case "$1" in
        ''|*:*)        return 1 ;;   # empty or IPv6 literal
        *[A-Za-z]*)    return 0 ;;   # has letters, so not an IPv4 literal
        *)             return 1 ;;
    esac
}

# Sets CF_HOST / CF_PORT from host:port or [v6]:port
_cf_split_hostport() {
    local hp="${1%%/*}"

    CF_HOST=""
    CF_PORT=""

    case "$hp" in
        '['*)
            CF_HOST=${hp#\[}
            CF_HOST=${CF_HOST%%\]*}
            CF_PORT=${hp##*\]}
            CF_PORT=${CF_PORT#:}
            ;;
        *:*:*)
            CF_HOST="$hp"
            ;;
        *:*)
            CF_HOST=${hp%:*}
            CF_PORT=${hp##*:}
            ;;
        *)
            CF_HOST="$hp"
            ;;
    esac

    CF_PORT=${CF_PORT%%,*}
    case "$CF_PORT" in
        ''|*[!0-9]*) CF_PORT="" ;;
    esac
}

# base64 decode / encode tolerating the url-safe alphabet and missing padding
_cf_b64d() {
    local data pad

    data=$(printf '%s' "$1" | tr -d '\r\n' | tr '_-' '/+')
    [ -n "$data" ] || return 1

    pad=$(( ${#data} % 4 ))
    case "$pad" in
        2) data="${data}==" ;;
        3) data="${data}=" ;;
        1) return 1 ;;
    esac

    printf '%s' "$data" | base64 -d 2>/dev/null
}

_cf_b64e() {
    printf '%s' "$1" | base64 2>/dev/null | tr -d '\n'
}

_cf_json_get() {
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$1" | jq -r --arg k "$2" '.[$k] // empty | tostring' 2>/dev/null
        return 0
    fi

    printf '%s' "$1" | tr ',{' '\n\n' | \
        sed -n "s/^[[:space:]]*\"$2\"[[:space:]]*:[[:space:]]*//p" | head -n 1 | \
        sed 's/^"//;s/"[[:space:]]*}*[[:space:]]*$//;s/[[:space:]]*}*[[:space:]]*$//'
}

# Decoded JSON document of a vmess:// link
_cf_vmess_json() {
    local body="${1#vmess://}"
    _cf_b64d "${body%%#*}"
}

_cf_query_get() {
    printf '%s\n' "$1" | tr '&' '\n' | sed -n "s/^$2=//p" | head -n 1
}

# Appends key=value to a query string
_cf_query_add() {
    if [ -z "$1" ]; then
        printf '%s=%s' "$2" "$3"
    else
        printf '%s&%s=%s' "$1" "$2" "$3"
    fi
}

# ------------------------------------------------------------
# Extract address from share link
# ------------------------------------------------------------
extract_address_from_link() {
    local link="$1"
    local body json

    case "$link" in
        vmess://*)
            json=$(_cf_vmess_json "$link")
            [ -n "$json" ] && _cf_json_get "$json" add
            return 0
            ;;
        *://*) body=${link#*://} ;;
        *)     body="$link" ;;
    esac

    body=${body%%#*}
    body=${body%%\?*}
    case "$body" in *@*) body=${body##*@} ;; esac

    _cf_split_hostport "$body"
    echo "$CF_HOST"
}

# ------------------------------------------------------------
# Extract port from share link
# ------------------------------------------------------------
extract_port_from_link() {
    local link="$1"
    local body json port=""

    case "$link" in
        vmess://*)
            json=$(_cf_vmess_json "$link")
            [ -n "$json" ] && port=$(_cf_json_get "$json" port)
            ;;
        *)
            case "$link" in
                *://*) body=${link#*://} ;;
                *)     body="$link" ;;
            esac
            body=${body%%#*}
            body=${body%%\?*}
            case "$body" in *@*) body=${body##*@} ;; esac
            _cf_split_hostport "$body"
            port="$CF_PORT"
            ;;
    esac

    [ -z "$port" ] && port="443"
    echo "$port"
}

# ------------------------------------------------------------
# Replace only the connect address of a share link with a clean IP
#
# A clean IP only works when the link is fronted by Cloudflare: the TLS
# handshake and the CDN's own routing still have to target the original
# domain, so that domain is pinned into sni= / host= when the link has
# neither. Links where an address swap cannot work are refused (rc 1,
# nothing printed): Reality, QUIC transports and shadowsocks.
#
# Sets CF_REPLACE_NOTE describing what was pinned.
# ------------------------------------------------------------
replace_address_in_link() {
    local link="$1"
    local new_ip="$2"
    local scheme body frag userinfo query hostport
    local old_host port network security sni host_header json

    CF_REPLACE_NOTE=""

    if [ -z "$link" ] || [ -z "$new_ip" ]; then
        log_error "replace_address_in_link needs a share link and a clean IP!"
        return 1
    fi

    case "$link" in
        *://*)
            scheme=${link%%://*}
            body=${link#*://}
            ;;
        *)
            log_warn "Not a share link; cannot replace its address."
            return 1
            ;;
    esac

    case "$scheme" in
        vless|trojan|vmess) ;;
        ss|ssr)
            log_warn "Shadowsocks has no SNI to fall back on, so a clean IP cannot replace its address. Config left unchanged."
            return 1
            ;;
        hysteria|hysteria2|hy2|tuic|naive+quic)
            log_warn "[$scheme] runs over QUIC/UDP, which Cloudflare's proxy does not carry. Config left unchanged."
            return 1
            ;;
        *)
            log_warn "Unsupported share link type [$scheme] for Clean IP. Config left unchanged."
            return 1
            ;;
    esac

    # ---------------- vmess: edit the JSON document, never the base64 ----------------
    if [ "$scheme" = "vmess" ]; then
        frag=""
        case "$body" in *'#'*) frag="#${body#*#}" ;; esac

        json=$(_cf_vmess_json "$link")
        case "$json" in
            '{'*) ;;
            *)
                log_warn "Could not decode this vmess link. Config left unchanged."
                return 1
                ;;
        esac

        if ! command -v jq >/dev/null 2>&1; then
            log_error "jq is required to rewrite a vmess link safely!"
            return 1
        fi

        network=$(_cf_json_get "$json" net)
        [ -n "$network" ] || network="tcp"
        old_host=$(_cf_json_get "$json" add)

        if ! _cf_cdn_transport "$network"; then
            log_warn "vmess over [$network] is not fronted by Cloudflare, so a clean IP would break it. Config left unchanged."
            return 1
        fi
        if [ -z "$old_host" ]; then
            log_warn "This vmess link carries no address. Config left unchanged."
            return 1
        fi

        sni=$(_cf_json_get "$json" sni)
        host_header=$(_cf_json_get "$json" host)
        if [ -z "$sni" ] && [ -z "$host_header" ]; then
            if ! _cf_is_domain "$old_host"; then
                log_warn "This vmess link connects to the bare address [$old_host] with no host/sni, so there is no domain to keep targeting. Config left unchanged."
                return 1
            fi
            CF_REPLACE_NOTE="Host header pinned to [$old_host] so the CDN still routes to it."
        fi

        json=$(printf '%s' "$json" | jq -c --arg ip "$new_ip" --arg dom "$old_host" '
            .add = $ip
            | if ((.sni // "") == "") and ((.host // "") == "") then .host = $dom else . end
        ' 2>/dev/null)
        if [ -z "$json" ]; then
            log_error "Failed to rewrite the vmess link!"
            return 1
        fi

        printf 'vmess://%s%s\n' "$(_cf_b64e "$json")" "$frag"
        return 0
    fi

    # ---------------- vless / trojan ----------------
    frag=""
    userinfo=""
    query=""
    case "$body" in *'#'*) frag="#${body#*#}"; body=${body%%#*} ;; esac
    case "$body" in *'?'*) query=${body#*\?};  body=${body%%\?*} ;; esac
    case "$body" in *@*)   userinfo="${body%@*}@"; body=${body##*@} ;; esac

    _cf_split_hostport "$body"
    old_host="$CF_HOST"
    port="$CF_PORT"

    if [ -z "$old_host" ]; then
        log_warn "Could not read the address of this link. Config left unchanged."
        return 1
    fi

    network=$(_cf_query_get "$query" type)
    [ -n "$network" ] || network="tcp"
    security=$(_cf_query_get "$query" security)
    if [ -z "$security" ] && [ "$scheme" = "trojan" ]; then
        security="tls"
    fi
    sni=$(_cf_query_get "$query" sni)
    [ -n "$sni" ] || sni=$(_cf_query_get "$query" peer)
    host_header=$(_cf_query_get "$query" host)

    if [ "$security" = "reality" ]; then
        log_warn "Reality pins the server's public key to its real address, so a clean IP cannot be used. Config left unchanged."
        return 1
    fi
    if ! _cf_cdn_transport "$network"; then
        log_warn "[$scheme] over [$network] is not fronted by Cloudflare, so a clean IP would break it. Config left unchanged."
        return 1
    fi

    case "$security" in
        tls|xtls)
            # host already defines the SNI; only pin it when neither is set
            if [ -z "$sni" ] && [ -z "$host_header" ]; then
                if ! _cf_is_domain "$old_host"; then
                    log_warn "This link connects to the bare address [$old_host] with no sni/host, so there is no domain for the TLS handshake to keep targeting. Config left unchanged."
                    return 1
                fi
                query=$(_cf_query_add "$query" "sni" "$old_host")
                CF_REPLACE_NOTE="TLS SNI pinned to [$old_host] so the handshake still targets it."
            fi
            ;;
        *)
            # plaintext over the CDN: the Host header is what routes the request
            if [ -z "$host_header" ]; then
                if ! _cf_is_domain "$old_host"; then
                    log_warn "This link connects to the bare address [$old_host] with no host header, so the CDN would have nothing to route on. Config left unchanged."
                    return 1
                fi
                query=$(_cf_query_add "$query" "host" "$old_host")
                CF_REPLACE_NOTE="Host header pinned to [$old_host] so the CDN still routes to it."
            fi
            ;;
    esac

    case "$new_ip" in
        *:*) hostport="[$new_ip]" ;;
        *)   hostport="$new_ip" ;;
    esac
    [ -n "$port" ] && hostport="$hostport:$port"

    printf '%s://%s%s%s%s\n' "$scheme" "$userinfo" "$hostport" "${query:+?$query}" "$frag"
    return 0
}
