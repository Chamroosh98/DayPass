#!/bin/sh
# ============================================================
# DayPass - Passwall Bridge (Professional Edition)
# Detects Passwall1 / Passwall2 and pushes nodes with better parsing
# ============================================================

PROXY_DIR="/etc/daypass/proxy"
CONFIG_DIR="$PROXY_DIR/configs"

# ------------------------------------------------------------
# Detect installed Passwall version
# Returns: passwall2 | passwall | none
# ------------------------------------------------------------
detect_passwall_version() {
    if [ -f /etc/config/passwall2 ] || uci -q show passwall2 >/dev/null 2>&1; then
        echo "passwall2"
        return
    fi

    if [ -f /etc/config/passwall ] || uci -q show passwall >/dev/null 2>&1; then
        echo "passwall"
        return
    fi

    if command -v pkg_installed >/dev/null 2>&1; then
        if pkg_installed "luci-app-passwall2" || pkg_installed "passwall2"; then
            echo "passwall2"
            return
        fi
        if pkg_installed "luci-app-passwall" || pkg_installed "passwall"; then
            echo "passwall"
            return
        fi
    fi

    echo "none"
}

# ------------------------------------------------------------
# URL decode helper (basic)
# ------------------------------------------------------------
url_decode() {
    echo "$1" | sed 's/+/ /g;s/%/\\x/g' | xargs -0 printf "%b" 2>/dev/null || echo "$1"
}

# ------------------------------------------------------------
# Parse share link (improved)
# Supports: vless / vmess / trojan / ss / hysteria2
# Extracts main fields + some common query params
# ------------------------------------------------------------
parse_share_link() {
    local link="$1"

    PARSED_PROTOCOL=""
    PARSED_ADDRESS=""
    PARSED_PORT=""
    PARSED_UUID=""
    PARSED_PASSWORD=""
    PARSED_REMARKS=""
    PARSED_NETWORK=""
    PARSED_SECURITY=""
    PARSED_SNI=""
    PARSED_FLOW=""
    PARSED_FP=""
    PARSED_PATH=""
    PARSED_HOST_HEADER=""

    case "$link" in
        vless://*)
            PARSED_PROTOCOL="vless"

            local body query fragment
            body=$(echo "$link" | sed 's|vless://||')
            fragment=$(echo "$body" | grep -o '#.*' | sed 's/^#//')
            body=$(echo "$body" | cut -d'#' -f1)
            query=$(echo "$body" | cut -d'?' -f2- -s)
            body=$(echo "$body" | cut -d'?' -f1)

            PARSED_UUID=$(echo "$body" | cut -d'@' -f1)
            local hostport=$(echo "$body" | cut -d'@' -f2)
            PARSED_ADDRESS=$(echo "$hostport" | cut -d':' -f1)
            PARSED_PORT=$(echo "$hostport" | cut -d':' -f2)

            PARSED_REMARKS=$(url_decode "$fragment")
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="VLESS-Node"

            # Parse common query parameters
            if [ -n "$query" ]; then
                PARSED_NETWORK=$(echo "$query" | tr '&' '\n' | grep -m1 '^type=' | cut -d'=' -f2)
                PARSED_SECURITY=$(echo "$query" | tr '&' '\n' | grep -m1 '^security=' | cut -d'=' -f2)
                PARSED_SNI=$(echo "$query" | tr '&' '\n' | grep -m1 '^sni=' | cut -d'=' -f2)
                PARSED_FLOW=$(echo "$query" | tr '&' '\n' | grep -m1 '^flow=' | cut -d'=' -f2)
                PARSED_FP=$(echo "$query" | tr '&' '\n' | grep -m1 '^fp=' | cut -d'=' -f2)
                PARSED_PATH=$(echo "$query" | tr '&' '\n' | grep -m1 '^path=' | cut -d'=' -f2)
                PARSED_HOST_HEADER=$(echo "$query" | tr '&' '\n' | grep -m1 '^host=' | cut -d'=' -f2)
            fi
            ;;

        vmess://*)
            PARSED_PROTOCOL="vmess"
            local b64 json
            b64=$(echo "$link" | sed 's|vmess://||' | tr '_-' '/+' )
            # pad base64 if needed
            local mod=$(( ${#b64} % 4 ))
            if [ "$mod" -eq 2 ]; then b64="${b64}=="; fi
            if [ "$mod" -eq 3 ]; then b64="${b64}="; fi

            json=$(echo "$b64" | base64 -d 2>/dev/null)

            if [ -n "$json" ]; then
                PARSED_ADDRESS=$(echo "$json" | jq -r '.add // empty' 2>/dev/null)
                PARSED_PORT=$(echo "$json" | jq -r '.port // empty' 2>/dev/null)
                PARSED_UUID=$(echo "$json" | jq -r '.id // empty' 2>/dev/null)
                PARSED_REMARKS=$(echo "$json" | jq -r '.ps // empty' 2>/dev/null)
                PARSED_NETWORK=$(echo "$json" | jq -r '.net // empty' 2>/dev/null)
                PARSED_PATH=$(echo "$json" | jq -r '.path // empty' 2>/dev/null)
                PARSED_HOST_HEADER=$(echo "$json" | jq -r '.host // empty' 2>/dev/null)
                PARSED_SECURITY=$(echo "$json" | jq -r '.tls // empty' 2>/dev/null)
                PARSED_SNI=$(echo "$json" | jq -r '.sni // empty' 2>/dev/null)
            fi

            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="VMess-Node"
            ;;

        trojan://*)
            PARSED_PROTOCOL="trojan"

            local body query fragment
            body=$(echo "$link" | sed 's|trojan://||')
            fragment=$(echo "$body" | grep -o '#.*' | sed 's/^#//')
            body=$(echo "$body" | cut -d'#' -f1)
            query=$(echo "$body" | cut -d'?' -f2- -s)
            body=$(echo "$body" | cut -d'?' -f1)

            PARSED_PASSWORD=$(echo "$body" | cut -d'@' -f1)
            local hostport=$(echo "$body" | cut -d'@' -f2)
            PARSED_ADDRESS=$(echo "$hostport" | cut -d':' -f1)
            PARSED_PORT=$(echo "$hostport" | cut -d':' -f2)

            PARSED_REMARKS=$(url_decode "$fragment")
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="Trojan-Node"

            if [ -n "$query" ]; then
                PARSED_SNI=$(echo "$query" | tr '&' '\n' | grep -m1 '^sni=' | cut -d'=' -f2)
                PARSED_SECURITY=$(echo "$query" | tr '&' '\n' | grep -m1 '^security=' | cut -d'=' -f2)
                PARSED_FP=$(echo "$query" | tr '&' '\n' | grep -m1 '^fp=' | cut -d'=' -f2)
            fi
            ;;

        ss://*)
            PARSED_PROTOCOL="shadowsocks"
            local fragment
            fragment=$(echo "$link" | grep -o '#.*' | sed 's/^#//')
            PARSED_REMARKS=$(url_decode "$fragment")
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="SS-Node"
            # Full SS parsing is complex (sip002 / legacy). Keep basic for now.
            ;;

        hysteria2://*|hy2://*)
            PARSED_PROTOCOL="hysteria2"
            local fragment
            fragment=$(echo "$link" | grep -o '#.*' | sed 's/^#//')
            PARSED_REMARKS=$(url_decode "$fragment")
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="Hysteria2-Node"
            ;;

        *)
            return 1
            ;;
    esac

    return 0
}

# ------------------------------------------------------------
# Check if a node with same remarks already exists
# ------------------------------------------------------------
node_exists() {
    local pw_ver="$1"
    local remarks="$2"

    case "$pw_ver" in
        passwall2)
            uci show passwall2 2>/dev/null | grep -q "remarks='$remarks'" && return 0
            ;;
        passwall)
            uci show passwall 2>/dev/null | grep -q "remarks='$remarks'" && return 0
            ;;
    esac
    return 1
}

# ------------------------------------------------------------
# Push one config into the detected Passwall
# ------------------------------------------------------------
push_config_to_passwall() {
    local conf_name="$1"
    local file="$CONFIG_DIR/${conf_name}.json"

    if [ ! -f "$file" ]; then
        log_error "Config not found: [$conf_name]"
        return 1
    fi

    local share_link protocol
    share_link=$(jq -r '.share_link // empty' "$file")
    protocol=$(jq -r '.protocol // empty' "$file")

    if [ -z "$share_link" ]; then
        log_error "No share_link in config: [$conf_name]"
        return 1
    fi

    if ! parse_share_link "$share_link"; then
        log_warn "Could not fully parse share link for [$conf_name]. Adding with limited info."
    fi

    local remarks="${PARSED_REMARKS:-$conf_name}"
    local pw_version
    pw_version=$(detect_passwall_version)

    # Skip duplicate
    if node_exists "$pw_version" "$remarks"; then
        log_warn "Node [$remarks] already exists in $pw_version. Skipped."
        return 0
    fi

    case "$pw_version" in
        passwall2)
            log_info "Adding node to Passwall2 → [$remarks]"

            local section
            section=$(uci add passwall2 nodes 2>/dev/null)
            if [ -z "$section" ]; then
                log_error "Failed to create node section in Passwall2"
                return 1
            fi

            uci set passwall2."$section".remarks="$remarks"
            uci set passwall2."$section".type="${PARSED_PROTOCOL:-$protocol}"
            [ -n "$PARSED_ADDRESS" ] && uci set passwall2."$section".address="$PARSED_ADDRESS"
            [ -n "$PARSED_PORT" ]    && uci set passwall2."$section".port="$PARSED_PORT"
            [ -n "$PARSED_UUID" ]    && uci set passwall2."$section".uuid="$PARSED_UUID"
            [ -n "$PARSED_PASSWORD" ] && uci set passwall2."$section".password="$PARSED_PASSWORD"
            [ -n "$PARSED_NETWORK" ] && uci set passwall2."$section".transport="$PARSED_NETWORK"
            [ -n "$PARSED_SECURITY" ] && uci set passwall2."$section".tls="$PARSED_SECURITY"
            [ -n "$PARSED_SNI" ]     && uci set passwall2."$section".tls_serverName="$PARSED_SNI"
            [ -n "$PARSED_FLOW" ]    && uci set passwall2."$section".flow="$PARSED_FLOW"
            [ -n "$PARSED_FP" ]      && uci set passwall2."$section".fingerprint="$PARSED_FP"
            [ -n "$PARSED_PATH" ]    && uci set passwall2."$section".ws_path="$PARSED_PATH"
            [ -n "$PARSED_HOST_HEADER" ] && uci set passwall2."$section".ws_host="$PARSED_HOST_HEADER"
            uci set passwall2."$section".share_link="$share_link"
            uci set passwall2."$section".enabled="1"

            uci commit passwall2
            log_success "Node [$remarks] added to Passwall2 ($section)"
            ;;

        passwall)
            log_info "Adding node to Passwall1 → [$remarks]"

            local section
            section=$(uci add passwall nodes 2>/dev/null)
            if [ -z "$section" ]; then
                log_error "Failed to create node section in Passwall1"
                return 1
            fi

            uci set passwall."$section".remarks="$remarks"
            uci set passwall."$section".type="${PARSED_PROTOCOL:-$protocol}"
            [ -n "$PARSED_ADDRESS" ] && uci set passwall."$section".address="$PARSED_ADDRESS"
            [ -n "$PARSED_PORT" ]    && uci set passwall."$section".port="$PARSED_PORT"
            [ -n "$PARSED_UUID" ]    && uci set passwall."$section".uuid="$PARSED_UUID"
            [ -n "$PARSED_PASSWORD" ] && uci set passwall."$section".password="$PARSED_PASSWORD"
            [ -n "$PARSED_NETWORK" ] && uci set passwall."$section".transport="$PARSED_NETWORK"
            [ -n "$PARSED_SECURITY" ] && uci set passwall."$section".tls="$PARSED_SECURITY"
            [ -n "$PARSED_SNI" ]     && uci set passwall."$section".tls_serverName="$PARSED_SNI"
            uci set passwall."$section".share_link="$share_link"
            uci set passwall."$section".enabled="1"

            uci commit passwall
            log_success "Node [$remarks] added to Passwall1 ($section)"
            ;;

        none)
            log_error "Neither Passwall1 nor Passwall2 is installed!"
            return 1
            ;;
    esac
}

# ------------------------------------------------------------
# Push all local configs to Passwall
# ------------------------------------------------------------
push_all_to_passwall() {
    local pw_version
    pw_version=$(detect_passwall_version)

    if [ "$pw_version" = "none" ]; then
        log_error "No Passwall installation detected!"
        return 1
    fi

    log_info "Pushing all configs to [$pw_version] ..."

    local count=0
    local success=0

    for file in "$CONFIG_DIR"/*.json; do
        [ -f "$file" ] || continue
        name=$(basename "$file" .json)
        count=$((count + 1))

        if push_config_to_passwall "$name"; then
            success=$((success + 1))
        fi
    done

    if [ "$count" -eq 0 ]; then
        log_warn "No configs to push!"
    else
        log_success "Finished: $success / $count config(s) processed."
    fi
}