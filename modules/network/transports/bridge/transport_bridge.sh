#!/bin/sh
# ============================================================
# DayPass - Transport Bridge
# Engine-neutral control of proxy / VPN transports through driver hooks
# ============================================================
#
# Drivers (modules/network/transports/drivers/*.sh) implement tdrv_<engine>_<hook>.
#   Required : detect start stop status interception
#   Optional : reload apply_route_mode tproxy_port tunnel_device tunnel_network
#              dns_endpoint dns_configure list_nodes active_node select_node
#              push_node cleanup describe
#
# interception prints one of:
#   self   - the engine installs its own firewall interception (Passwall, Passwall2)
#   tproxy - DayPass steers LAN traffic to the engine's TPROXY inbound
#   tunnel - DayPass policy-routes LAN traffic into the engine's tunnel device
#
# transport_call returns 3 when a driver does not implement a hook.

PROXY_DIR="/etc/daypass/proxy"
CONFIG_DIR="$PROXY_DIR/configs"
TRANSPORT_DIR="${DAYPASS_DIR:-/etc/daypass}/transport"
TRANSPORT_ENGINES="passwall2 passwall singbox xray_direct wireguard openvpn"

transport_valid_engine() {
    [ -n "$1" ] || return 1
    case " $TRANSPORT_ENGINES " in
        *" $1 "*) return 0 ;;
    esac
    return 1
}

transport_has_hook() {
    command -v "tdrv_${1}_${2}" >/dev/null 2>&1
}

transport_call() {
    local engine="$1"
    local hook="$2"
    shift 2

    if ! transport_valid_engine "$engine"; then
        log_error "Unknown transport engine : [$engine]"
        return 1
    fi

    case "$hook" in
        ''|*[!a-z_]*)
            log_error "Invalid transport hook : [$hook]"
            return 1
            ;;
    esac

    transport_has_hook "$engine" "$hook" || return 3
    "tdrv_${engine}_${hook}" "$@"
}

# ------------------------------------------------------------
# Per-engine settings ($TRANSPORT_DIR/<engine>.conf, key=value)
# ------------------------------------------------------------
transport_opt_get() {
    local file="$TRANSPORT_DIR/$1.conf"
    local val=""

    [ -f "$file" ] && val=$(sed -n "s/^$2=//p" "$file" 2>/dev/null | tail -n 1)
    if [ -n "$val" ]; then
        echo "$val"
    else
        echo "${3:-}"
    fi
}

transport_opt_set() {
    local file="$TRANSPORT_DIR/$1.conf"

    case "$1$2" in
        *[!a-z0-9_]*) return 1 ;;
    esac
    mkdir -p "$TRANSPORT_DIR" 2>/dev/null || return 1

    {
        [ -f "$file" ] && grep -v "^$2=" "$file"
        [ -n "$3" ] && echo "$2=$3"
    } > "$file.tmp" && mv "$file.tmp" "$file"
}

# ------------------------------------------------------------
# Engine discovery & selection
# ------------------------------------------------------------
transport_engine_label() {
    case "$1" in
        passwall2)   echo "Passwall2" ;;
        passwall)    echo "Passwall" ;;
        singbox)     echo "sing-box (direct core)" ;;
        xray_direct) echo "Xray (direct core)" ;;
        wireguard)   echo "WireGuard" ;;
        openvpn)     echo "OpenVPN" ;;
        *)           echo "$1" ;;
    esac
}

transport_detect_engines() {
    local engine
    for engine in $TRANSPORT_ENGINES; do
        transport_call "$engine" detect >/dev/null 2>&1 && echo "$engine"
    done
}

# Saved engine if still installed, otherwise the first detected engine in priority order
get_active_engine() {
    local saved engine

    saved=$(cat "$TRANSPORT_DIR/active_engine" 2>/dev/null)
    if transport_valid_engine "$saved" && transport_call "$saved" detect >/dev/null 2>&1; then
        echo "$saved"
        return 0
    fi

    for engine in $TRANSPORT_ENGINES; do
        if transport_call "$engine" detect >/dev/null 2>&1; then
            echo "$engine"
            return 0
        fi
    done

    echo "none"
    return 1
}

set_active_engine() {
    local engine="$1"

    if ! transport_valid_engine "$engine"; then
        log_error "Unknown transport engine : [$engine]"
        return 1
    fi

    if ! transport_call "$engine" detect >/dev/null 2>&1; then
        log_error "Engine [$engine] is not installed or not configured!"
        return 1
    fi

    mkdir -p "$TRANSPORT_DIR" 2>/dev/null || return 1
    echo "$engine" > "$TRANSPORT_DIR/active_engine"
    log_success "Active transport engine : [$(transport_engine_label "$engine")]"
}

_transport_target_engine() {
    local engine="${1:-}"

    [ -z "$engine" ] && engine=$(get_active_engine)
    if [ "$engine" = "none" ]; then
        log_error "No transport engine installed (Passwall, Passwall2, sing-box, Xray, WireGuard or OpenVPN)!"
        return 1
    fi
    if ! transport_valid_engine "$engine"; then
        log_error "Unknown transport engine : [$engine]"
        return 1
    fi
    if ! transport_call "$engine" detect >/dev/null 2>&1; then
        log_error "Engine [$engine] is not installed or not configured!"
        return 1
    fi
    echo "$engine"
}

# ------------------------------------------------------------
# Standard engine hooks
# ------------------------------------------------------------
start_engine() {
    local engine
    engine=$(_transport_target_engine "${1:-}") || return 1

    log_info "Starting transport engine [$engine] ..."
    if transport_call "$engine" start; then
        log_success "Engine [$engine] started."
        return 0
    fi
    log_error "Engine [$engine] failed to start!"
    return 1
}

stop_engine() {
    local engine
    engine=$(_transport_target_engine "${1:-}") || return 1

    log_info "Stopping transport engine [$engine] ..."
    if transport_call "$engine" stop; then
        log_success "Engine [$engine] stopped."
        if [ "$(transport_call "$engine" interception)" = "tproxy" ] && \
            nft list table inet daypass >/dev/null 2>&1; then
            log_warn "LAN traffic is still steered to [$engine]. Choose Direct Only in Traffic Routing to restore direct access."
        fi
        return 0
    fi
    log_error "Engine [$engine] failed to stop!"
    return 1
}

# Prints "<engine> : running|stopped (details)"; returns 0 only when running
status_engine() {
    local engine detail rc
    engine=$(_transport_target_engine "${1:-}") || return 1

    detail=$(transport_call "$engine" status 2>/dev/null)
    rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "$engine : running${detail:+ ($detail)}"
        return 0
    fi
    echo "$engine : stopped${detail:+ ($detail)}"
    return 1
}

reload_rules() {
    local engine intercept rc
    engine=$(_transport_target_engine "${1:-}") || return 1
    intercept=$(transport_call "$engine" interception)

    log_info "Reloading rules for [$engine] ($intercept) ..."

    transport_call "$engine" reload
    rc=$?
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 3 ]; then
        log_error "Engine [$engine] failed to reload!"
        return 1
    fi

    if [ "$intercept" != "self" ] && command -v routing_reapply >/dev/null 2>&1; then
        routing_reapply "$engine" || return 1
    fi

    log_success "Rules reloaded for [$engine]."
    return 0
}

# ------------------------------------------------------------
# Tunnel helpers shared by WireGuard / OpenVPN drivers, routing and DNS
# ------------------------------------------------------------

# Prints the netifd interface carrying the engine's tunnel device, creating
# network.daypass_vpn (proto none) when the device is not managed by netifd.
transport_tunnel_network() {
    local engine="$1"
    local dev net sect

    net=$(transport_call "$engine" tunnel_network 2>/dev/null)
    if [ -n "$net" ]; then
        echo "$net"
        return 0
    fi

    dev=$(transport_call "$engine" tunnel_device 2>/dev/null)
    [ -n "$dev" ] || return 1

    for sect in $(uci -q show network 2>/dev/null | sed -n "s/^network\.\([^.]*\)=interface$/\1/p"); do
        if [ "$(uci -q get "network.$sect.device")" = "$dev" ] || [ "$(uci -q get "network.$sect.ifname")" = "$dev" ]; then
            echo "$sect"
            return 0
        fi
    done

    uci -q delete network.daypass_vpn
    uci set network.daypass_vpn=interface
    uci set network.daypass_vpn.proto='none'
    uci set network.daypass_vpn.device="$dev"
    uci commit network
    echo "daypass_vpn"
}

# $1 engine, $2 resolver IP (empty removes). Routes the resolver through the tunnel.
transport_tunnel_dns_route() {
    local engine="$1"
    local resolver="$2"
    local net

    uci -q delete network.daypass_dns_route

    if [ -n "$resolver" ]; then
        net=$(transport_tunnel_network "$engine") || return 1
        uci set network.daypass_dns_route=route
        uci set network.daypass_dns_route.interface="$net"
        uci set network.daypass_dns_route.target="${resolver}/32"
    fi

    uci commit network
    transport_opt_set "$engine" dns_resolver "$resolver"
    /etc/init.d/network reload >/dev/null 2>&1 || true
    return 0
}

# ------------------------------------------------------------
# URL decode helper (basic)
# ------------------------------------------------------------
url_decode() {
    echo "$1" | sed 's/+/ /g;s/%/\\x/g' | xargs -0 printf "%b" 2>/dev/null || echo "$1"
}

# ------------------------------------------------------------
# Share link parser
# Supports: vless (incl. Reality), vmess, trojan, ss (legacy + SIP002),
#           ssr, hysteria, hysteria2, tuic, anytls, naive+https/quic
# Sets PARSED_* for the caller. Returns 1 for an unsupported scheme or
# when no server address could be extracted.
# ------------------------------------------------------------

# base64 decode tolerating the url-safe alphabet and missing padding
_sl_b64() {
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

# $1 query string, $2.. parameter names; prints the first one that is set
_sl_query() {
    local query="$1"
    local key val

    shift
    for key in "$@"; do
        val=$(printf '%s\n' "$query" | tr '&;' '\n\n' | sed -n "s/^${key}=//p" | head -n 1)
        if [ -n "$val" ]; then
            url_decode "$val"
            return 0
        fi
    done
    return 1
}

# $1 JSON document, $2 key
_sl_json() {
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$1" | jq -r --arg k "$2" '.[$k] // empty | tostring' 2>/dev/null
        return 0
    fi

    printf '%s' "$1" | tr ',{' '\n\n' | \
        sed -n "s/^[[:space:]]*\"$2\"[[:space:]]*:[[:space:]]*//p" | head -n 1 | \
        sed 's/^"//;s/"[[:space:]]*}*[[:space:]]*$//;s/[[:space:]]*}*[[:space:]]*$//'
}

# Sets SL_HOST / SL_PORT from host:port, [v6]:port, host:443,8443 or host:443-500
_sl_hostport() {
    local hp="${1%%/*}"

    SL_HOST=""
    SL_PORT=""

    case "$hp" in
        '['*)
            SL_HOST=${hp#\[}
            SL_HOST=${SL_HOST%%\]*}
            SL_PORT=${hp##*\]}
            SL_PORT=${SL_PORT#:}
            ;;
        *:*:*)
            # bare IPv6 literal (brackets are required to carry a port)
            SL_HOST="$hp"
            ;;
        *:*)
            SL_HOST=${hp%:*}
            SL_PORT=${hp##*:}
            ;;
        *)
            SL_HOST="$hp"
            ;;
    esac

    # hysteria2 / tuic may advertise a port list or range: keep the first port
    SL_PORT=${SL_PORT%%,*}
    SL_PORT=${SL_PORT%%-*}
    case "$SL_PORT" in
        ''|*[!0-9]*) SL_PORT="" ;;
    esac
}

# Splits a scheme-less "userinfo@host:port?query#fragment" body
_sl_uri() {
    local body="$1"

    SL_USERINFO=""
    SL_QUERY=""
    SL_FRAGMENT=""

    case "$body" in *'#'*) SL_FRAGMENT=${body#*#}; body=${body%%#*} ;; esac
    case "$body" in *'?'*) SL_QUERY=${body#*\?};   body=${body%%\?*} ;; esac
    case "$body" in *@*)   SL_USERINFO=${body%@*}; body=${body##*@}  ;; esac

    _sl_hostport "$body"
}

# Transport name -> PARSED_L4
_sl_l4_from_network() {
    case "$1" in
        kcp|mkcp|quic) PARSED_L4="udp" ;;
        *)             PARSED_L4="tcp" ;;
    esac
}

parse_share_link() {
    local link="$1"
    local scheme body json creds decoded frag rest query hostpart
    local sr_host sr_port sr_proto sr_method sr_obfs sr_pass

    PARSED_PROTOCOL=""
    PARSED_ADDRESS=""
    PARSED_PORT=""
    PARSED_UUID=""
    PARSED_PASSWORD=""
    PARSED_METHOD=""
    PARSED_REMARKS=""
    PARSED_NETWORK=""
    PARSED_SECURITY=""
    PARSED_SNI=""
    PARSED_FLOW=""
    PARSED_FP=""
    PARSED_PBK=""
    PARSED_SID=""
    PARSED_SPX=""
    PARSED_PATH=""
    PARSED_HOST_HEADER=""
    PARSED_L4="tcp"

    case "$link" in
        *://*)
            scheme=${link%%://*}
            body=${link#*://}
            ;;
        *)
            return 1
            ;;
    esac

    case "$scheme" in
        vless)
            PARSED_PROTOCOL="vless"
            _sl_uri "$body"

            PARSED_UUID=$(url_decode "$SL_USERINFO")
            PARSED_ADDRESS="$SL_HOST"
            PARSED_PORT="$SL_PORT"
            PARSED_NETWORK=$(_sl_query "$SL_QUERY" type) || PARSED_NETWORK="tcp"
            PARSED_SECURITY=$(_sl_query "$SL_QUERY" security) || PARSED_SECURITY="none"
            PARSED_SNI=$(_sl_query "$SL_QUERY" sni peer servername)
            PARSED_FLOW=$(_sl_query "$SL_QUERY" flow)
            PARSED_FP=$(_sl_query "$SL_QUERY" fp fingerprint)
            PARSED_PBK=$(_sl_query "$SL_QUERY" pbk publicKey)
            PARSED_SID=$(_sl_query "$SL_QUERY" sid shortId)
            PARSED_SPX=$(_sl_query "$SL_QUERY" spx spiderX)
            PARSED_PATH=$(_sl_query "$SL_QUERY" path serviceName)
            PARSED_HOST_HEADER=$(_sl_query "$SL_QUERY" host authority)
            PARSED_REMARKS=$(url_decode "$SL_FRAGMENT")
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="VLESS-Node"
            _sl_l4_from_network "$PARSED_NETWORK"
            ;;

        vmess)
            PARSED_PROTOCOL="vmess"
            json=$(_sl_b64 "${body%%#*}")

            case "$json" in
                '{'*)
                    PARSED_ADDRESS=$(_sl_json "$json" add)
                    PARSED_PORT=$(_sl_json "$json" port)
                    PARSED_UUID=$(_sl_json "$json" id)
                    PARSED_REMARKS=$(_sl_json "$json" ps)
                    PARSED_NETWORK=$(_sl_json "$json" net)
                    PARSED_PATH=$(_sl_json "$json" path)
                    PARSED_HOST_HEADER=$(_sl_json "$json" host)
                    PARSED_SECURITY=$(_sl_json "$json" tls)
                    PARSED_SNI=$(_sl_json "$json" sni)
                    PARSED_FP=$(_sl_json "$json" fp)
                    PARSED_FLOW=$(_sl_json "$json" flow)
                    ;;
                *)
                    # Xray-style vmess URI: vmess://uuid@host:port?type=...
                    _sl_uri "$body"
                    PARSED_UUID=$(url_decode "$SL_USERINFO")
                    PARSED_ADDRESS="$SL_HOST"
                    PARSED_PORT="$SL_PORT"
                    PARSED_NETWORK=$(_sl_query "$SL_QUERY" type)
                    PARSED_SECURITY=$(_sl_query "$SL_QUERY" security)
                    PARSED_SNI=$(_sl_query "$SL_QUERY" sni peer)
                    PARSED_FP=$(_sl_query "$SL_QUERY" fp fingerprint)
                    PARSED_PATH=$(_sl_query "$SL_QUERY" path serviceName)
                    PARSED_HOST_HEADER=$(_sl_query "$SL_QUERY" host)
                    PARSED_REMARKS=$(url_decode "$SL_FRAGMENT")
                    ;;
            esac

            [ -z "$PARSED_NETWORK" ] && PARSED_NETWORK="tcp"
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="VMess-Node"
            _sl_l4_from_network "$PARSED_NETWORK"
            ;;

        trojan)
            PARSED_PROTOCOL="trojan"
            _sl_uri "$body"

            PARSED_PASSWORD=$(url_decode "$SL_USERINFO")
            PARSED_ADDRESS="$SL_HOST"
            PARSED_PORT="$SL_PORT"
            PARSED_NETWORK=$(_sl_query "$SL_QUERY" type) || PARSED_NETWORK="tcp"
            PARSED_SECURITY=$(_sl_query "$SL_QUERY" security) || PARSED_SECURITY="tls"
            PARSED_SNI=$(_sl_query "$SL_QUERY" sni peer servername)
            PARSED_FP=$(_sl_query "$SL_QUERY" fp fingerprint)
            PARSED_PBK=$(_sl_query "$SL_QUERY" pbk publicKey)
            PARSED_SID=$(_sl_query "$SL_QUERY" sid shortId)
            PARSED_SPX=$(_sl_query "$SL_QUERY" spx spiderX)
            PARSED_PATH=$(_sl_query "$SL_QUERY" path serviceName)
            PARSED_HOST_HEADER=$(_sl_query "$SL_QUERY" host authority)
            PARSED_REMARKS=$(url_decode "$SL_FRAGMENT")
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="Trojan-Node"
            _sl_l4_from_network "$PARSED_NETWORK"
            ;;

        ss)
            PARSED_PROTOCOL="shadowsocks"

            frag=""
            rest="$body"
            case "$rest" in *'#'*) frag=${rest#*#}; rest=${rest%%#*} ;; esac
            query=""
            case "$rest" in *'?'*) query=${rest#*\?}; rest=${rest%%\?*} ;; esac

            case "$rest" in
                *@*)
                    # SIP002: ss://base64(method:password)@host:port
                    creds=${rest%@*}
                    hostpart=${rest##*@}
                    decoded=$(_sl_b64 "$creds")
                    case "$decoded" in
                        *:*) creds="$decoded" ;;
                        *)   creds=$(url_decode "$creds") ;;
                    esac
                    _sl_hostport "$hostpart"
                    ;;
                *)
                    # legacy: ss://base64(method:password@host:port)
                    decoded=$(_sl_b64 "$rest")
                    case "$decoded" in
                        *@*)
                            creds=${decoded%@*}
                            _sl_hostport "${decoded##*@}"
                            ;;
                        *)
                            creds=""
                            ;;
                    esac
                    ;;
            esac

            PARSED_ADDRESS="$SL_HOST"
            PARSED_PORT="$SL_PORT"
            PARSED_METHOD=${creds%%:*}
            case "$creds" in
                *:*) PARSED_PASSWORD=${creds#*:} ;;
            esac
            PARSED_HOST_HEADER=$(_sl_query "$query" obfs-host)
            PARSED_REMARKS=$(url_decode "$frag")
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="SS-Node"
            ;;

        ssr)
            PARSED_PROTOCOL="ssr"
            # ssr://base64(host:port:protocol:method:obfs:base64(password)/?params)
            decoded=$(_sl_b64 "${body%%#*}")
            [ -n "$decoded" ] || return 1

            query=""
            case "$decoded" in *'?'*) query=${decoded#*\?}; decoded=${decoded%%\?*} ;; esac
            decoded=${decoded%/}

            IFS=':' read -r sr_host sr_port sr_proto sr_method sr_obfs sr_pass << EOF
$decoded
EOF
            PARSED_ADDRESS="$sr_host"
            PARSED_PORT="$sr_port"
            PARSED_METHOD="$sr_method"
            PARSED_PASSWORD=$(_sl_b64 "$sr_pass")
            # sr_proto / sr_obfs are SSR plugin names with no PARSED_* equivalent;
            # subscribe.lua reads them from the link itself when importing.
            PARSED_REMARKS=$(_sl_b64 "$(_sl_query "$query" remarks)")
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="SSR-Node"
            ;;

        hysteria)
            PARSED_PROTOCOL="hysteria"
            _sl_uri "$body"

            PARSED_ADDRESS="$SL_HOST"
            PARSED_PORT="$SL_PORT"
            PARSED_PASSWORD=$(_sl_query "$SL_QUERY" auth auth_str authStr)
            [ -z "$PARSED_PASSWORD" ] && PARSED_PASSWORD=$(url_decode "$SL_USERINFO")
            PARSED_SNI=$(_sl_query "$SL_QUERY" peer sni)
            PARSED_SECURITY="tls"
            PARSED_NETWORK=$(_sl_query "$SL_QUERY" protocol) || PARSED_NETWORK="udp"
            PARSED_REMARKS=$(url_decode "$SL_FRAGMENT")
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="Hysteria-Node"
            PARSED_L4="udp"
            ;;

        hysteria2|hy2)
            PARSED_PROTOCOL="hysteria2"
            _sl_uri "$body"

            PARSED_ADDRESS="$SL_HOST"
            PARSED_PORT="$SL_PORT"
            PARSED_PASSWORD=$(url_decode "$SL_USERINFO")
            PARSED_SNI=$(_sl_query "$SL_QUERY" sni peer)
            PARSED_SECURITY="tls"
            PARSED_REMARKS=$(url_decode "$SL_FRAGMENT")
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="Hysteria2-Node"
            PARSED_L4="udp"
            ;;

        tuic)
            PARSED_PROTOCOL="tuic"
            _sl_uri "$body"

            PARSED_ADDRESS="$SL_HOST"
            PARSED_PORT="$SL_PORT"
            PARSED_UUID=$(url_decode "${SL_USERINFO%%:*}")
            case "$SL_USERINFO" in
                *:*) PARSED_PASSWORD=$(url_decode "${SL_USERINFO#*:}") ;;
            esac
            PARSED_SNI=$(_sl_query "$SL_QUERY" sni peer)
            PARSED_SECURITY="tls"
            PARSED_REMARKS=$(url_decode "$SL_FRAGMENT")
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="TUIC-Node"
            PARSED_L4="udp"
            ;;

        anytls)
            PARSED_PROTOCOL="anytls"
            _sl_uri "$body"

            PARSED_ADDRESS="$SL_HOST"
            PARSED_PORT="$SL_PORT"
            case "$SL_USERINFO" in
                *:*)
                    PARSED_UUID=$(url_decode "${SL_USERINFO%%:*}")
                    PARSED_PASSWORD=$(url_decode "${SL_USERINFO#*:}")
                    ;;
                *)
                    PARSED_PASSWORD=$(url_decode "$SL_USERINFO")
                    ;;
            esac
            PARSED_SNI=$(_sl_query "$SL_QUERY" sni peer servername)
            PARSED_FP=$(_sl_query "$SL_QUERY" fp fingerprint)
            PARSED_SECURITY="tls"
            PARSED_REMARKS=$(url_decode "$SL_FRAGMENT")
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="AnyTLS-Node"
            ;;

        naive|naive+https|naive+quic)
            PARSED_PROTOCOL="naive"
            _sl_uri "$body"

            PARSED_ADDRESS="$SL_HOST"
            PARSED_PORT="$SL_PORT"
            PARSED_UUID=$(url_decode "${SL_USERINFO%%:*}")
            case "$SL_USERINFO" in
                *:*) PARSED_PASSWORD=$(url_decode "${SL_USERINFO#*:}") ;;
            esac
            PARSED_SNI=$(_sl_query "$SL_QUERY" sni peer)
            PARSED_SECURITY="tls"
            case "$scheme" in
                *quic) PARSED_NETWORK="quic"; PARSED_L4="udp" ;;
                *)     PARSED_NETWORK="https" ;;
            esac
            PARSED_REMARKS=$(url_decode "$SL_FRAGMENT")
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="Naive-Node"
            ;;

        *)
            return 1
            ;;
    esac

    [ -n "$PARSED_ADDRESS" ] || return 1
    return 0
}

# ------------------------------------------------------------
# Push local share-link configs into the active engine
# ------------------------------------------------------------
transport_push_config() {
    local conf_name="$1"
    local file="$CONFIG_DIR/${conf_name}.json"
    local engine rc

    if [ ! -f "$file" ]; then
        log_error "Config not found: [$conf_name]"
        return 1
    fi

    engine=$(_transport_target_engine "") || return 1

    transport_call "$engine" push_node "$file" "$conf_name"
    rc=$?
    if [ "$rc" -eq 3 ]; then
        log_error "Engine [$engine] cannot import share links. Add the node in its own configuration."
        return 1
    fi
    return "$rc"
}

transport_push_all() {
    local engine name file
    local count=0
    local success=0

    engine=$(_transport_target_engine "") || return 1
    if ! transport_has_hook "$engine" push_node; then
        log_error "Engine [$engine] cannot import share links. Add the node in its own configuration."
        return 1
    fi

    log_info "Pushing all configs to [$engine] ..."

    for file in "$CONFIG_DIR"/*.json; do
        [ -f "$file" ] || continue
        name=$(basename "$file" .json)
        count=$((count + 1))

        if transport_push_config "$name"; then
            success=$((success + 1))
        fi
    done

    if [ "$count" -eq 0 ]; then
        log_warn "No configs to push!"
    else
        log_success "Finished: $success / $count config(s) processed."
    fi
}

push_config_to_passwall() {
    transport_push_config "$@"
}

push_all_to_passwall() {
    transport_push_all "$@"
}

# ------------------------------------------------------------
# Endpoint probing (engine-neutral)
# Sets PROBE_STATE (up|down|unknown), PROBE_MS, PROBE_METHOD
# Returns 0 up, 1 down, 2 unknown (UDP endpoint without ICMP reply)
# ------------------------------------------------------------
_transport_now_ms() {
    local ns up
    ns=$(date +%s%N 2>/dev/null)
    case "$ns" in
        ''|*[!0-9]*) ;;
        *)
            if [ "${#ns}" -ge 13 ]; then
                echo $((ns / 1000000))
                return 0
            fi
            ;;
    esac

    up=$(cut -d' ' -f1 /proc/uptime 2>/dev/null)
    case "$up" in
        *.*) echo $(( ${up%.*} * 1000 + $(echo "${up#*.}0" | cut -c1-2 | sed 's/^0*//;s/^$/0/') * 10 )) ;;
        *)   return 1 ;;
    esac
}

_transport_tcp_connect() {
    if [ -z "${_TRANSPORT_NC_Z:-}" ]; then
        if nc -z 127.0.0.1 1 2>&1 </dev/null | grep -qiE 'invalid|unrecognized|illegal|usage'; then
            _TRANSPORT_NC_Z=0
        else
            _TRANSPORT_NC_Z=1
        fi
    fi

    if [ "$_TRANSPORT_NC_Z" = "1" ]; then
        nc -z -w 3 "$1" "$2" </dev/null >/dev/null 2>&1
    else
        nc -w 3 "$1" "$2" </dev/null >/dev/null 2>&1
    fi
}

transport_probe() {
    local host="$1"
    local port="$2"
    local l4="${3:-tcp}"
    local t0 t1 ms

    PROBE_STATE="down"
    PROBE_MS=""
    PROBE_METHOD=""

    [ -n "$host" ] || return 1

    if [ "$l4" != "udp" ] && [ -n "$port" ] && command -v nc >/dev/null 2>&1; then
        t0=$(_transport_now_ms)
        if _transport_tcp_connect "$host" "$port"; then
            t1=$(_transport_now_ms)
            PROBE_STATE="up"
            PROBE_METHOD="tcp"
            [ -n "$t0" ] && [ -n "$t1" ] && PROBE_MS=$((t1 - t0))
            return 0
        fi
        PROBE_METHOD="tcp"
        return 1
    fi

    if command -v ping >/dev/null 2>&1; then
        ms=$(ping -c 1 -W 2 "$host" 2>/dev/null | sed -n 's/.*time[=<]\([0-9.]*\).*/\1/p' | head -n 1)
        if [ -n "$ms" ]; then
            PROBE_STATE="up"
            PROBE_METHOD="icmp"
            PROBE_MS="${ms%%.*}"
            [ -z "$PROBE_MS" ] && PROBE_MS=0
            return 0
        fi
    fi

    if [ "$l4" = "udp" ]; then
        PROBE_STATE="unknown"
        PROBE_METHOD="icmp"
        return 2
    fi
    return 1
}
