#!/bin/sh
# ============================================================
# DayPass - Config Storage
# Local storage management for proxy configs
# ============================================================

PROXY_DIR="/etc/daypass/proxy"
CONFIG_DIR="$PROXY_DIR/configs"
mkdir -p "$CONFIG_DIR"

# ------------------------------------------------------------
# List all locally stored configs
# ------------------------------------------------------------
list_configs() {
    echo "  📋 Available Configs (DayPass storage)"
    echo "  ───────────────────────────────────────────────────────────"

    local count=0
    for file in "$CONFIG_DIR"/*.json; do
        [ -f "$file" ] || continue

        count=$((count + 1))
        name=$(basename "$file" .json)
        protocol=$(jq -r '.protocol // "unknown"' "$file" 2>/dev/null)
        enabled=$(jq -r '.enabled // true' "$file" 2>/dev/null)
        subscription=$(jq -r '.subscription // empty' "$file" 2>/dev/null)

        status="${GREEN}ON${RESET}"
        [ "$enabled" = "false" ] && status="${GRAY}OFF${RESET}"

        if [ -n "$subscription" ]; then
            echo "  $count) $name  ${GRAY}($protocol)${RESET}  [$status]  ${GRAY}← $subscription${RESET}"
        else
            echo "  $count) $name  ${GRAY}($protocol)${RESET}  [$status]"
        fi
    done

    if [ "$count" -eq 0 ]; then
        echo "  ${GRAY}No configs found!${RESET}"
    else
        echo "  ───────────────────────────────────────────────────────────"
        echo "  Total: $count config(s)"
    fi
    echo "  ───────────────────────────────────────────────────────────"
}

# ------------------------------------------------------------
# Validate share link format (basic)
# ------------------------------------------------------------
validate_share_link() {
    local link="$1"

    case "$link" in
        vless://*|vmess://*|trojan://*|ss://*|hysteria2://*|hy2://*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ------------------------------------------------------------
# Detect protocol from share link
# ------------------------------------------------------------
detect_protocol_from_link() {
    local link="$1"

    case "$link" in
        vless://*)             echo "vless" ;;
        vmess://*)             echo "vmess" ;;
        trojan://*)            echo "trojan" ;;
        ss://*)                echo "ss" ;;
        hysteria2://*|hy2://*) echo "hysteria2" ;;
        *)                     echo "unknown" ;;
    esac
}

# ------------------------------------------------------------
# Add a manual config to local storage
# ------------------------------------------------------------
add_manual_config() {
    echo
    printf "  🎯 Config Name (example: MyVLESS) : "
    read -r conf_name </dev/tty

    # Basic name validation
    if [ -z "$conf_name" ]; then
        log_error "Name cannot be empty!"
        return 1
    fi

    # Prevent path traversal / invalid characters
    case "$conf_name" in
        *..*|*/*|*\\*|*\;*|*\&*)
            log_error "Invalid characters in config name!"
            return 1
            ;;
    esac

    # Check duplicate
    if [ -f "$CONFIG_DIR/${conf_name}.json" ]; then
        log_warn "Config [$conf_name] already exists!"
        printf "  ⁉️ Overwrite it? [y/N] : "
        read -r overwrite </dev/tty
        case "$overwrite" in
            y|Y) ;;
            *) log_info "Cancelled."; return 0 ;;
        esac
    fi

    printf "  🕊️ Paste full share link:\n  "
    read -r share_link </dev/tty

    if [ -z "$share_link" ]; then
        log_error "Share link is required!"
        return 1
    fi

    if ! validate_share_link "$share_link"; then
        log_error "Unsupported or invalid share link format!"
        log_info "Supported: vless:// | vmess:// | trojan:// | ss:// | hysteria2://"
        return 1
    fi

    # Auto-detect protocol from link (more reliable)
    local protocol
    protocol=$(detect_protocol_from_link "$share_link")

    cat > "$CONFIG_DIR/${conf_name}.json" << EOF
{
    "name": "$conf_name",
    "protocol": "$protocol",
    "share_link": "$share_link",
    "enabled": true,
    "added_at": "$(date -Iseconds)"
}
EOF

    log_success "Config [$conf_name] saved successfully! ${GRAY}($protocol)${RESET}"
}

# ------------------------------------------------------------
# Remove a config from local storage
# ------------------------------------------------------------
remove_config() {
    list_configs

    local total
    total=$(ls -1 "$CONFIG_DIR"/*.json 2>/dev/null | wc -l)
    if [ "$total" -eq 0 ]; then
        return 0
    fi

    printf "  🧼 Enter config name to remove : "
    read -r del_name </dev/tty

    if [ -z "$del_name" ]; then
        log_warn "No name entered!"
        return 1
    fi

    if [ -f "$CONFIG_DIR/${del_name}.json" ]; then
        printf "  ⁉️ Are you sure you want to delete [$del_name]? [y/N] : "
        read -r confirm </dev/tty
        case "$confirm" in
            y|Y)
                rm -f "$CONFIG_DIR/${del_name}.json"
                log_success "Config [$del_name] removed!"
                ;;
            *)
                log_info "Cancelled."
                ;;
        esac
    else
        log_error "Config not found!"
    fi
}

# ------------------------------------------------------------
# Enable / Disable a config
# ------------------------------------------------------------
toggle_config() {
    list_configs

    printf "  🔄 Enter config name to toggle enable/disable : "
    read -r conf_name </dev/tty

    local file="$CONFIG_DIR/${conf_name}.json"
    if [ ! -f "$file" ]; then
        log_error "Config not found!"
        return 1
    fi

    local current
    current=$(jq -r '.enabled // true' "$file" 2>/dev/null)

    local new_value
    if [ "$current" = "true" ]; then
        new_value="false"
    else
        new_value="true"
    fi

    tmp=$(mktemp)
    jq --argjson val "$new_value" '.enabled = $val' "$file" > "$tmp" && mv "$tmp" "$file"

    if [ "$new_value" = "true" ]; then
        log_success "Config [$conf_name] enabled!"
    else
        log_warn "Config [$conf_name] disabled!"
    fi
}