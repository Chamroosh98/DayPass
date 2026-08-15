#!/bin/sh
# ============================================================
# Download and parse subscription links
# ============================================================

PROXY_DIR="/etc/daypass/proxy"
CONFIG_DIR="$PROXY_DIR/configs"
SUBS_FILE="$PROXY_DIR/subscriptions.json"
mkdir -p "$CONFIG_DIR"

# ------------------------------------------------------------
# Add a new subscription
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
        log_error "Failed to download subscription : $sub_name"
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
            vless://*)             protocol="vless" ;;
            vmess://*)             protocol="vmess" ;;
            trojan://*)            protocol="trojan" ;;
            ss://*)                protocol="ss" ;;
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
    log_success "Subscription [$sub_name] updated!"
}

# ------------------------------------------------------------
# Update all saved subscriptions
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

    log_info "Updating $total subscription(s) ..."

    jq -c '.[]' "$SUBS_FILE" | while read -r sub; do
        name=$(echo "$sub" | jq -r '.name')
        url=$(echo "$sub" | jq -r '.url')
        update_subscription "$name" "$url"
    done

    log_success "All subscriptions processed!"
}