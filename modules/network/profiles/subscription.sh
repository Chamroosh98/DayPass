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
    profile_valid_name "$sub_name" || { log_error "Invalid subscription name."; return 1; }

    printf "  🏦 Subscription URL : "
    read -r sub_url </dev/tty
    [ -z "$sub_url" ] && { log_error "URL required!"; return 1; }

    [ ! -L "$SUBS_FILE" ] && [ ! -d "$SUBS_FILE" ] || return 1
    # Create subscriptions file if it does not exist
    if [ ! -f "$SUBS_FILE" ]; then
        echo "[]" > "$SUBS_FILE" || return 1
    fi

    # Check for duplicate subscription name
    if jq -e --arg name "$sub_name" '.[] | select(.name == $name)' "$SUBS_FILE" >/dev/null 2>&1; then
        log_warn "Subscription [$sub_name] already exists!"
        return 1
    fi

    local tmp
    tmp=$(mktemp "$PROXY_DIR/.subs.XXXXXX") || return 1
    jq --arg name "$sub_name" --arg url "$sub_url" \
       '. + [{"name": $name, "url": $url, "last_update": null}]' \
       "$SUBS_FILE" > "$tmp" && mv "$tmp" "$SUBS_FILE" || { rm -f "$tmp"; return 1; }

    log_success "Subscription [$sub_name] added!"
    log_info "Use 'Update Subscriptions' to fetch nodes!"
}

# ------------------------------------------------------------
# Keep the previous generation recoverable until publication succeeds.
update_subscription() (
    local name="$1" url="$2" work="$CONFIG_DIR/.subscription-refresh"
    local line proto id file base old count=0 ts mutating=0 target
    profile_valid_name "$name" || return 1
    case "$url" in http://*|https://*) ;; *) return 1 ;; esac
    umask 077
    mkdir "$work" || { log_error "Subscription refresh busy or interrupted: $work"; return 1; }
    trap 'if [ "$mutating" = 0 ]; then rm -rf "$work"; else log_error "Recovery files retained in $work"; fi' EXIT
    mkdir "$work/new" "$work/old" || return 1
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 15 --max-time 30 -o "$work/download" "$url" || return 1
    else
        wget -q -O "$work/download" --timeout=15 "$url" || return 1
    fi
    if grep -q '://' "$work/download"; then
        mv "$work/download" "$work/lines" || return 1
    else
        base64 -d "$work/download" > "$work/lines" || return 1
    fi
    ts=$(date -Iseconds) || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        line=${line%"$(printf '\r')"}
        [ -n "$line" ] || continue
        proto=$(detect_protocol_from_link "$line")
        [ "$proto" != unknown ] && parse_share_link "$line" &&
            [ -n "$PARSED_ADDRESS" ] && [ -n "$PARSED_PORT" ] ||
            { log_error "Incomplete or unsupported subscription record."; return 1; }
        case "$PARSED_PORT" in *[!0-9]*) return 1 ;; esac
        [ "$PARSED_PORT" -ge 1 ] && [ "$PARSED_PORT" -le 65535 ] || return 1
        case "$proto" in
            vmess|vless) [ -n "$PARSED_UUID" ] || return 1 ;;
            trojan|hysteria2) [ -n "$PARSED_PASSWORD" ] || return 1 ;;
        esac
        count=$((count + 1))
        id="${name}_${proto}_$count"
        target="$CONFIG_DIR/$id.json"
        [ ! -L "$target" ] || return 1
        if [ -e "$target" ]; then
            [ -f "$target" ] && jq -e --arg n "$name" '.subscription == $n' "$target" >/dev/null || return 1
        fi
        jq -n --arg n "$id" --arg p "$proto" --arg link "$line" --arg sub "$name" --arg ts "$ts" \
            '{name:$n, protocol:$p, share_link:$link, subscription:$sub, enabled:true, added_at:$ts}' > "$work/new/$id.json" || return 1
        if [ -f "$target" ]; then
            jq -s '.[1] + .[0] + {enabled:(.[1].enabled != false)}' "$work/new/$id.json" "$target" > "$work/merged" &&
                mv "$work/merged" "$work/new/$id.json" || return 1
        fi
    done < "$work/lines"
    [ "$count" -gt 0 ] || return 1
    [ -f "$SUBS_FILE" ] && [ ! -L "$SUBS_FILE" ] && cp "$SUBS_FILE" "$work/index.old" &&
        jq -e --arg n "$name" --arg u "$url" --arg ts "$ts" '
        if ([.[] | select(.name==$n and .url==$u)] | length)==1 then
            map(if .name==$n and .url==$u then .last_update=$ts else . end)
        else error("subscription changed") end' "$work/index.old" > "$work/index.new" || return 1

    local ok=1
    mutating=1
    for file in "$CONFIG_DIR"/*.json; do
        [ -f "$file" ] && [ ! -L "$file" ] || continue
        base=${file##*/}
        case "$base" in "${name}_"*) ;; *) continue ;; esac
        jq -e --arg n "$name" --arg id "${base%.json}" '.subscription==$n and .name==$id' "$file" >/dev/null || continue
        mv "$file" "$work/old/$base" || { ok=0; break; }
    done
    # Publish without clobbering files that appeared after preflight.
    for file in "$work/new/"*.json; do
        [ "$ok" = 1 ] || break
        ln "$file" "$CONFIG_DIR/${file##*/}" || { ok=0; break; }
    done
    if [ "$ok" = 1 ] && cmp -s "$SUBS_FILE" "$work/index.old" &&
        mv "$work/index.new" "$SUBS_FILE"; then
        mutating=0
        log_success "Subscription [$name] updated ($count nodes)."
        return 0
    fi
    for file in "$work/new/"*.json; do
        target="$CONFIG_DIR/${file##*/}"
        if [ "$file" -ef "$target" ]; then rm "$target" || return 1; fi
    done
    for old in "$work/old/"*.json; do
        [ -f "$old" ] || continue
        ln "$old" "$CONFIG_DIR/${old##*/}" || return 1
    done
    mutating=0
    return 1
)

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
    local failed=0 subs_tmp
    subs_tmp=$(mktemp) || return 1
    jq -c '.[]' "$SUBS_FILE" > "$subs_tmp" || { rm -f "$subs_tmp"; return 1; }

    while IFS= read -r sub; do
        name=$(printf '%s\n' "$sub" | jq -r '.name')
        url=$(printf '%s\n' "$sub" | jq -r '.url')
        update_subscription "$name" "$url" || failed=1
    done < "$subs_tmp"

    rm -f "$subs_tmp"
    [ "$failed" = 0 ] || return 1
    log_success "All subscriptions processed!"
}

# ------------------------------------------------------------
# List saved subscriptions
# ------------------------------------------------------------
list_subscriptions() {
    echo "  💳 Saved Subscriptions"
    ui_divider

    if [ ! -f "$SUBS_FILE" ]; then
        echo "  ${GRAY}No subscriptions found!${RESET}"
        ui_divider
        return 0
    fi

    local total
    total=$(jq 'length' "$SUBS_FILE" 2>/dev/null || echo 0)

    if [ "$total" -eq 0 ]; then
        echo "  ${GRAY}No subscriptions found!${RESET}"
        ui_divider
        return 0
    fi

    local i=1
    jq -c '.[]' "$SUBS_FILE" | while read -r sub; do
        name=$(printf '%s\n' "$sub" | jq -r '.name')
        last=$(printf '%s\n' "$sub" | jq -r '.last_update // "never"')
        echo "  $i) $name  ${GRAY}(last update: $last)${RESET}"
        i=$((i + 1))
    done

    ui_divider
}