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
    ui_divider

    local count=0
    for file in "$CONFIG_DIR"/*.json; do
        [ -f "$file" ] || continue

        count=$((count + 1))
        name=$(basename "$file" .json)
        protocol=$(jq -r '.protocol // "unknown"' "$file" 2>/dev/null)
        enabled=$(jq -r 'if .enabled == false then "false" else "true" end' "$file" 2>/dev/null)
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
        ui_divider
        echo "  Total: $count config(s)"
    fi
    ui_divider
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
profile_valid_name() {
    case "$1" in ''|.*|*/*|*[[:cntrl:]]*) return 1 ;; esac
    return 0
}

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

    profile_valid_name "$conf_name" && [ ! -L "$CONFIG_DIR/$conf_name.json" ] || return 1
    [ ! -e "$CONFIG_DIR/$conf_name.json" ] || [ -f "$CONFIG_DIR/$conf_name.json" ] || return 1
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

    local tmp
    tmp=$(mktemp "$CONFIG_DIR/.manual.XXXXXX") || return 1
    if ! jq -n --arg name "$conf_name" --arg p "$protocol" --arg link "$share_link" --arg ts "$(date -Iseconds)" \
        '{name:$name,protocol:$p,share_link:$link,enabled:true,added_at:$ts}' > "$tmp" ||
        ! mv "$tmp" "$CONFIG_DIR/$conf_name.json"; then
        rm -f "$tmp"; return 1
    fi

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

    profile_valid_name "$del_name" && [ ! -L "$CONFIG_DIR/$del_name.json" ] || return 1
    if [ -f "$CONFIG_DIR/${del_name}.json" ]; then
        printf "  ⁉️ Are you sure you want to delete [$del_name]? [y/N] : "
        read -r confirm </dev/tty
        case "$confirm" in
            y|Y)
                rm "$CONFIG_DIR/${del_name}.json" || return 1
                log_success "Config [$del_name] removed!"
                ;;
            *)
                log_info "Cancelled."
                ;;
        esac
    else
        log_error "Config not found!"
        return 1
    fi
}

# ------------------------------------------------------------
# Enable / Disable a config
# ------------------------------------------------------------
toggle_config() {
    list_configs

    printf "  🔄 Enter config name to toggle enable/disable : "
    read -r conf_name </dev/tty

    profile_valid_name "$conf_name" || return 1
    local file="$CONFIG_DIR/${conf_name}.json" tmp
    [ ! -L "$file" ] || return 1
    if [ ! -f "$file" ]; then
        log_error "Config not found!"
        return 1
    fi

    local current
    current=$(jq -r 'if .enabled == false then "false" else "true" end' "$file" 2>/dev/null)

    local new_value
    if [ "$current" = "true" ]; then
        new_value="false"
    else
        new_value="true"
    fi

    tmp=$(mktemp "$CONFIG_DIR/.toggle.XXXXXX") || return 1
    jq --argjson val "$new_value" '.enabled = $val' "$file" > "$tmp" && mv "$tmp" "$file" || { rm -f "$tmp"; return 1; }

    if [ "$new_value" = "true" ]; then
        log_success "Config [$conf_name] enabled!"
    else
        log_warn "Config [$conf_name] disabled!"
    fi
}