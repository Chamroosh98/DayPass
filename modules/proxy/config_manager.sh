#!/bin/sh
# ============================================================
# DayPass - Config Manager (Nodes & Subscriptions)
# ============================================================

# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------
PROXY_DIR="/etc/daypass/proxy"
CONFIG_DIR="$PROXY_DIR/configs"
SUBS_FILE="$PROXY_DIR/subscriptions.json"
mkdir -p "$CONFIG_DIR"

# ------------------------------------------------------------
# List existing configs
# ------------------------------------------------------------
list_configs() {
    echo "  📋 Available Configs : \n"

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
    echo ""
}

# ------------------------------------------------------------
# Add config manually
# ------------------------------------------------------------
add_manual_config() {
    echo
    printf "  🎯 Config Name (example : MyVLESS) : "
    read -r conf_name </dev/tty
    [ -z "$conf_name" ] && { log_error "Name cannot be empty!"; return 1; }

    printf "  🤝 Protocol [vless/vmess/trojan/ss/hysteria2] : "
    read -r protocol </dev/tty
    protocol=$(echo "$protocol" | tr 'A-Z' 'a-z')

    printf "  🕊️ Paste full share link (vless:// | vmess:// | ...) : \n  "
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
# Add Subscription
# ------------------------------------------------------------
add_subscription() {
    echo
    printf "  💳 Subscription Name : "
    read -r sub_name </dev/tty
    [ -z "$sub_name" ] && { log_error "Name required!"; return 1; }

    printf "  🏦 Subscription URL : "
    read -r sub_url </dev/tty
    [ -z "$sub_url" ] && { log_error "URL required!"; return 1; }

    if [ ! -f "$SUBS_FILE" ]; then
        echo "[]" > "$SUBS_FILE"
    fi

    tmp=$(mktemp)
    jq --arg name "$sub_name" --arg url "$sub_url" \
       '. + [{"name": $name, "url": $url, "last_update": null}]' \
       "$SUBS_FILE" > "$tmp" && mv "$tmp" "$SUBS_FILE"

    log_success "Subscription [$sub_name] added!"
    log_info "Use 'Update Subscriptions' to fetch nodes!"
}

# ------------------------------------------------------------
# Update a single subscription
# ------------------------------------------------------------
update_subscription() {
    local sub_name="$1"
    local sub_url="$2"

    log_info "Updating subscription: $sub_name ..."

    local tmp_file=$(mktemp)
    local download_ok=0

    # Prefer curl, fallback to wget
    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL --connect-timeout 15 --max-time 30 -o "$tmp_file" "$sub_url" 2>/dev/null; then
            download_ok=1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -q -O "$tmp_file" "$sub_url" --timeout=15 2>/dev/null; then
            download_ok=1
        fi
    else
        log_error "Neither curl nor wget is available!"
        rm -f "$tmp_file"
        return 1
    fi

    if [ "$download_ok" -ne 1 ]; then
        log_error "Failed to download subscription: $sub_name"
        rm -f "$tmp_file"
        return 1
    fi

    local content
    if grep -q "://" "$tmp_file"; then
        content=$(cat "$tmp_file")
    else
        content=$(base64 -d "$tmp_file" 2>/dev/null || cat "$tmp_file")
    fi

    local count=0
    echo "$content" | while IFS= read -r line; do
        line=$(echo "$line" | tr -d '\r' | xargs)
        [ -z "$line" ] && continue

        case "$line" in
            vless://*)     protocol="vless" ;;
            vmess://*)     protocol="vmess" ;;
            trojan://*)    protocol="trojan" ;;
            ss://*)        protocol="ss" ;;
            hysteria2://*|hy2://*) protocol="hysteria2" ;;
            *) continue ;;
        esac

        count=$((count + 1))
        local conf_name="${sub_name}_${protocol}_${count}"

        cat > "$CONFIG_DIR/${conf_name}.json" << EOF
{
    "name": "$conf_name",
    "protocol": "$protocol",
    "share_link": "$line",
    "subscription": "$sub_name",
    "enabled": true,
    "added_at": "$(date -Iseconds)"
}
EOF
    done

    rm -f "$tmp_file"
    log_success "Subscription [$sub_name] updated."
}

# ------------------------------------------------------------
# Update All Subscriptions
# ------------------------------------------------------------
update_all_subscriptions() {
    if [ ! -f "$SUBS_FILE" ]; then
        log_warn "No subscriptions found!"
        return 1
    fi

    local total
    total=$(jq 'length' "$SUBS_FILE" 2>/dev/null || echo 0)

    if [ "$total" -eq 0 ]; then
        log_warn "No subscriptions to update!"
        return 1
    fi

    log_info "Updating [$total] subscription(s) ..."

    jq -c '.[]' "$SUBS_FILE" | while read -r sub; do
        name=$(echo "$sub" | jq -r '.name')
        url=$(echo "$sub" | jq -r '.url')
        update_subscription "$name" "$url"
    done

    log_success "All subscriptions processed!"
}

# ------------------------------------------------------------
# Main Config Manager Menu
# ------------------------------------------------------------
config_manager_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear

        echo "  📦 Config Manager (Nodes & Subscriptions)"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  📋 1) List Configs"
        echo "  🤏 2) Add Manual Config"
        echo "  🫰 3) Add Subscription"
        echo "  🔄 4) Update All Subscriptions"
        echo "  🗑️ 5) Remove Config"
        echo "  🚪 0) Back"
        echo "  ───────────────────────────────────────────────────────────"
        echo

        printf "  ⁉️ Select option [0-5] : "
        read -r choice </dev/tty

        case "$choice" in
            1)
                list_configs
                ;;
            2)
                add_manual_config
                ;;
            3)
                add_subscription
                ;;
            4)
                update_all_subscriptions
                ;;
            5)
                list_configs
                printf "  🧼 Enter config name to remove : "
                read -r del_name </dev/tty
                if [ -f "$CONFIG_DIR/${del_name}.json" ]; then
                    rm -f "$CONFIG_DIR/${del_name}.json"
                    log_success "Config [$del_name] removed!"
                else
                    log_error "Config not found!"
                fi
                ;;
            0)
                return 0
                ;;
            *)
                log_warn "Invalid option!"
                ;;
        esac

        printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
        read -r _ </dev/tty
    done
}