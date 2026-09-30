#!/bin/sh
# ============================================================
# DayPass - Subscription Manager
# Download, parse and store nodes from subscription links
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

    # Create subscriptions file if it does not exist
    if [ ! -f "$SUBS_FILE" ]; then
        echo "[]" > "$SUBS_FILE"
    fi

    # Check for duplicate subscription name
    if jq -e --arg name "$sub_name" '.[] | select(.name == $name)' "$SUBS_FILE" >/dev/null 2>&1; then
        log_warn "Subscription [$sub_name] already exists!"
        return 1
    fi

    tmp=$(mktemp)
    jq --arg name "$sub_name" --arg url "$sub_url" \
       '. + [{"name": $name, "url": $url, "last_update": null}]' \
       "$SUBS_FILE" > "$tmp" && mv "$tmp" "$SUBS_FILE"

    log_success "Subscription [$sub_name] added!"
    log_info "Use 'Update Subscriptions' to fetch nodes!"
}

# ------------------------------------------------------------
# Remove old nodes belonging to a subscription before update
# ------------------------------------------------------------
clean_old_subscription_nodes() {
    local sub_name="$1"

    for file in "$CONFIG_DIR"/*.json; do
        [ -f "$file" ] || continue

        local sub
        sub=$(jq -r '.subscription // empty' "$file" 2>/dev/null)

        if [ "$sub" = "$sub_name" ]; then
            rm -f "$file"
        fi
    done
}

# ------------------------------------------------------------
# Update a single subscription
# ------------------------------------------------------------
update_subscription() {
    local sub_name="$1"
    local sub_url="$2"

    log_info "🔄 Updating subscription: $sub_name ..."

    local tmp_file
    tmp_file=$(mktemp)
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

    # Detect plain text or base64 content
    local content
    if grep -q "://" "$tmp_file"; then
        content=$(cat "$tmp_file")
    else
        content=$(base64 -d "$tmp_file" 2>/dev/null || cat "$tmp_file")
    fi

    # Remove previous nodes of this subscription
    clean_old_subscription_nodes "$sub_name"

    local count=0
    local line protocol conf_name

    # Use temporary file to avoid subshell count problem
    local parsed_file
    parsed_file=$(mktemp)

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
        conf_name="${sub_name}_${protocol}_${count}"

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
        echo "$count" > "$parsed_file"
    done

    count=$(cat "$parsed_file" 2>/dev/null || echo 0)
    rm -f "$tmp_file" "$parsed_file"

    # Update last_update timestamp in subscriptions file
    if [ -f "$SUBS_FILE" ]; then
        tmp=$(mktemp)
        jq --arg name "$sub_name" --arg ts "$(date -Iseconds)" \
           'map(if .name == $name then .last_update = $ts else . end)' \
           "$SUBS_FILE" > "$tmp" && mv "$tmp" "$SUBS_FILE"
    fi

    if [ "$count" -gt 0 ]; then
        log_success "Subscription [$sub_name] updated! ($count nodes)"
    else
        log_warn "Subscription [$sub_name] updated, but no valid nodes found!"
    fi
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

    log_info "🔄 Updating $total subscription(s) ..."

    # Read subscriptions into a temp list to avoid subshell issues
    local subs_tmp
    subs_tmp=$(mktemp)
    jq -c '.[]' "$SUBS_FILE" > "$subs_tmp"

    while IFS= read -r sub; do
        name=$(echo "$sub" | jq -r '.name')
        url=$(echo "$sub" | jq -r '.url')
        update_subscription "$name" "$url"
    done < "$subs_tmp"

    rm -f "$subs_tmp"
    log_success "All subscriptions processed!"
}

# ------------------------------------------------------------
# List saved subscriptions
# ------------------------------------------------------------
list_subscriptions() {
    echo "  💳 Saved Subscriptions"
    echo "  ───────────────────────────────────────────────────────────"

    if [ ! -f "$SUBS_FILE" ]; then
        echo "  ${GRAY}No subscriptions found!${RESET}"
        echo "  ───────────────────────────────────────────────────────────"
        return 0
    fi

    local total
    total=$(jq 'length' "$SUBS_FILE" 2>/dev/null || echo 0)

    if [ "$total" -eq 0 ]; then
        echo "  ${GRAY}No subscriptions found!${RESET}"
        echo "  ───────────────────────────────────────────────────────────"
        return 0
    fi

    local i=1
    jq -c '.[]' "$SUBS_FILE" | while read -r sub; do
        name=$(echo "$sub" | jq -r '.name')
        last=$(echo "$sub" | jq -r '.last_update // "never"')
        echo "  $i) $name  ${GRAY}(last update: $last)${RESET}"
        i=$((i + 1))
    done

    echo "  ───────────────────────────────────────────────────────────"
}