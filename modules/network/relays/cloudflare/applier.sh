#!/bin/sh

# ------------------------------------------------------------
# Apply clean IP to a stored config
# ------------------------------------------------------------
apply_clean_ip_to_config() {
    local conf_name="$1"
    local clean_ip="$2"
    local file="$CONFIG_DIR/${conf_name}.json"

    if [ ! -f "$file" ]; then
        log_error "Config not found: [$conf_name]"
        return 1
    fi

    if [ -z "$clean_ip" ]; then
        log_error "Clean IP is empty!"
        return 1
    fi

    local share_link new_link
    share_link=$(jq -r '.share_link // empty' "$file" 2>/dev/null)

    if [ -z "$share_link" ]; then
        log_error "No share_link in config : [$conf_name]"
        return 1
    fi

    new_link=$(replace_address_in_link "$share_link" "$clean_ip")
    if [ -z "$new_link" ] || [ "$new_link" = "$share_link" ]; then
        new_link=$(echo "$share_link" | sed "s/@[^:/]*/@${clean_ip}/")
    fi

    tmp=$(mktemp)
    if jq --arg link "$new_link" --arg ip "$clean_ip" \
        '.share_link = $link | .clean_ip = $ip' \
        "$file" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$file"
    else
        rm -f "$tmp"
        log_error "Failed to update config JSON!"
        return 1
    fi

    log_success "Config [$conf_name] updated with Clean IP : [$clean_ip]"
    log_info "SNI/Host/Path left unchanged!"
}