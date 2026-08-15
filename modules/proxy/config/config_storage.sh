#!/bin/sh
# ============================================================
# Local storage management for proxy configs
# ============================================================

PROXY_DIR="/etc/daypass/proxy"
CONFIG_DIR="$PROXY_DIR/configs"
mkdir -p "$CONFIG_DIR"

# ------------------------------------------------------------
# List all locally stored configs
# ------------------------------------------------------------
list_configs() {
    echo "  📋 Available Configs (DayPass storage) :"
    echo "  ───────────────────────────────────────────────────────────"

    local count=0
    for file in "$CONFIG_DIR"/*.json; do
        [ -f "$file" ] || continue
        count=$((count + 1))
        name=$(basename "$file" .json)
        protocol=$(jq -r '.protocol // "unknown"' "$file" 2>/dev/null)
        echo "  $count) $name  ${GRAY}($protocol)${RESET}"
    done

    if [ "$count" -eq 0 ]; then
        echo "  ${GRAY}No configs found!${RESET}"
    fi
    echo "  ───────────────────────────────────────────────────────────"
}

# ------------------------------------------------------------
# Add a manual config to local storage
# ------------------------------------------------------------
add_manual_config() {
    echo
    printf "  🎯 Config Name (example : MyVLESS) : "
    read -r conf_name </dev/tty
    [ -z "$conf_name" ] && { log_error "Name cannot be empty!"; return 1; }

    printf "  🤝 Protocol [vless/vmess/trojan/ss/hysteria2] : "
    read -r protocol </dev/tty
    protocol=$(echo "$protocol" | tr 'A-Z' 'a-z')

    printf "  🕊️ Paste full share link :\n  "
    read -r share_link </dev/tty

    if [ -z "$share_link" ]; then
        log_error "Share link is required!"
        return 1
    fi

    cat > "$CONFIG_DIR/${conf_name}.json" << EOF
{
    "name": "$conf_name",
    "protocol": "$protocol",
    "share_link": "$share_link",
    "enabled": true,
    "added_at": "$(date -Iseconds)"
}
EOF

    log_success "Config [$conf_name] saved successfully!"
}

# ------------------------------------------------------------
# Remove a config from local storage
# ------------------------------------------------------------
remove_config() {
    list_configs
    printf "  🧼 Enter config name to remove : "
    read -r del_name </dev/tty

    if [ -f "$CONFIG_DIR/${del_name}.json" ]; then
        rm -f "$CONFIG_DIR/${del_name}.json"
        log_success "Config [$del_name] removed!"
    else
        log_error "Config not found!"
    fi
}