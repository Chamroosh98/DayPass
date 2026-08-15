#!/bin/sh
# ============================================================
# Detects Passwall1 / Passwall2 and pushes nodes properly
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
# Basic parser for share links (VLESS / VMess / Trojan / SS)
# Extracts: protocol, address, port, uuid/password, remarks
# Note: This is a lightweight parser. Full parsing of all
# query parameters is complex and can be improved later.
# ------------------------------------------------------------
parse_share_link() {
    local link="$1"

    # Reset variables
    PARSED_PROTOCOL=""
    PARSED_ADDRESS=""
    PARSED_PORT=""
    PARSED_UUID=""
    PARSED_REMARKS=""

    case "$link" in
        vless://*)
            PARSED_PROTOCOL="vless"
            # vless://uuid@host:port?...
            local main_part
            main_part=$(echo "$link" | sed 's|vless://||' | cut -d'?' -f1)
            PARSED_UUID=$(echo "$main_part" | cut -d'@' -f1)
            local hostport=$(echo "$main_part" | cut -d'@' -f2)
            PARSED_ADDRESS=$(echo "$hostport" | cut -d':' -f1)
            PARSED_PORT=$(echo "$hostport" | cut -d':' -f2 | cut -d'#' -f1)
            PARSED_REMARKS=$(echo "$link" | grep -o '#.*' | sed 's/^#//' | sed 's/%20/ /g')
            ;;

        vmess://*)
            PARSED_PROTOCOL="vmess"
            # VMess is usually base64 encoded JSON
            local b64
            b64=$(echo "$link" | sed 's|vmess://||')
            local json
            json=$(echo "$b64" | base64 -d 2>/dev/null)

            if [ -n "$json" ]; then
                PARSED_ADDRESS=$(echo "$json" | jq -r '.add // empty' 2>/dev/null)
                PARSED_PORT=$(echo "$json" | jq -r '.port // empty' 2>/dev/null)
                PARSED_UUID=$(echo "$json" | jq -r '.id // empty' 2>/dev/null)
                PARSED_REMARKS=$(echo "$json" | jq -r '.ps // empty' 2>/dev/null)
            fi
            ;;

        trojan://*)
            PARSED_PROTOCOL="trojan"
            # trojan://password@host:port?...
            local main_part
            main_part=$(echo "$link" | sed 's|trojan://||' | cut -d'?' -f1)
            PARSED_UUID=$(echo "$main_part" | cut -d'@' -f1)   # password
            local hostport=$(echo "$main_part" | cut -d'@' -f2)
            PARSED_ADDRESS=$(echo "$hostport" | cut -d':' -f1)
            PARSED_PORT=$(echo "$hostport" | cut -d':' -f2 | cut -d'#' -f1)
            PARSED_REMARKS=$(echo "$link" | grep -o '#.*' | sed 's/^#//' | sed 's/%20/ /g')
            ;;

        ss://*)
            PARSED_PROTOCOL="shadowsocks"
            # Basic SS support (simplified)
            PARSED_REMARKS=$(echo "$link" | grep -o '#.*' | sed 's/^#//' | sed 's/%20/ /g')
            ;;

        hysteria2://*|hy2://*)
            PARSED_PROTOCOL="hysteria2"
            PARSED_REMARKS=$(echo "$link" | grep -o '#.*' | sed 's/^#//' | sed 's/%20/ /g')
            ;;

        *)
            return 1
            ;;
    esac

    # Fallback remarks
    [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="DayPass-Node"

    return 0
}

# ------------------------------------------------------------
# Push one config into the detected Passwall
# ------------------------------------------------------------
push_config_to_passwall() {
    local conf_name="$1"
    local file="$CONFIG_DIR/${conf_name}.json"

    if [ ! -f "$file" ]; then
        log_error "Config not found : [$conf_name]"
        return 1
    fi

    local share_link protocol
    share_link=$(jq -r '.share_link // empty' "$file")
    protocol=$(jq -r '.protocol // empty' "$file")

    if [ -z "$share_link" ]; then
        log_error "No share_link found in config : [$conf_name]"
        return 1
    fi

    # Parse the share link
    if ! parse_share_link "$share_link"; then
        log_warn "Could not fully parse share link for [$conf_name]. Adding with limited info!"
    fi

    local pw_version
    pw_version=$(detect_passwall_version)

    case "$pw_version" in
        passwall2)
            log_info "Adding node to Passwall-2 → [$conf_name]"

            local section
            section=$(uci add passwall2 nodes 2>/dev/null)

            if [ -z "$section" ]; then
                log_error "Failed to create node section in Passwall-2 !"
                return 1
            fi

            uci set passwall2."$section".remarks="${PARSED_REMARKS:-$conf_name}"
            uci set passwall2."$section".type="${PARSED_PROTOCOL:-$protocol}"
            [ -n "$PARSED_ADDRESS" ] && uci set passwall2."$section".address="$PARSED_ADDRESS"
            [ -n "$PARSED_PORT" ]    && uci set passwall2."$section".port="$PARSED_PORT"
            [ -n "$PARSED_UUID" ]    && uci set passwall2."$section".uuid="$PARSED_UUID"
            uci set passwall2."$section".share_link="$share_link"
            uci set passwall2."$section".enabled="1"

            uci commit passwall2
            log_success "Node [$conf_name] added to Passwall-2 (section : $section)"
            ;;

        passwall)
            log_info "Adding node to Passwall1 → [$conf_name]"

            local section
            section=$(uci add passwall nodes 2>/dev/null)

            if [ -z "$section" ]; then
                log_error "Failed to create node section in Passwall-1 !"
                return 1
            fi

            uci set passwall."$section".remarks="${PARSED_REMARKS:-$conf_name}"
            uci set passwall."$section".type="${PARSED_PROTOCOL:-$protocol}"
            [ -n "$PARSED_ADDRESS" ] && uci set passwall."$section".address="$PARSED_ADDRESS"
            [ -n "$PARSED_PORT" ]    && uci set passwall."$section".port="$PARSED_PORT"
            [ -n "$PARSED_UUID" ]    && uci set passwall."$section".uuid="$PARSED_UUID"
            uci set passwall."$section".share_link="$share_link"
            uci set passwall."$section".enabled="1"

            uci commit passwall
            log_success "Node [$conf_name] added to Passwall1 (section : $section)"
            ;;

        none)
            log_error "Neither Passwall1 nor Passwall2 is installed!"
            log_info "Please install a Passwall package 1st!!"
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
        log_success "Finished : [$success] / [$count] config(s) pushed successfully!"
    fi
}