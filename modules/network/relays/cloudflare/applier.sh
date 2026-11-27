#!/bin/sh

# ------------------------------------------------------------
# Apply clean IP to a stored config
# ------------------------------------------------------------
apply_clean_ip_to_config() {
    local conf_name="$1"
    local clean_ip="$2"
    local file="$CONFIG_DIR/${conf_name}.json"

    case "$conf_name" in ''|.*|*/*) return 1 ;; esac
    if [ ! -f "$file" ] || [ -L "$file" ]; then
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

    # A refusal means the swap would break the connection (Reality, QUIC, ss):
    # leave the stored config exactly as it is.
    if ! new_link=$(replace_address_in_link "$share_link" "$clean_ip"); then
        log_error "Clean IP not applied to [$conf_name]."
        return 1
    fi

    if [ -z "$new_link" ] || [ "$new_link" = "$share_link" ]; then
        log_error "Share link of [$conf_name] was left unchanged; Clean IP not applied."
        return 1
    fi

    local tmp rc
    tmp=$(mktemp "$CONFIG_DIR/.clean-ip.XXXXXX") || return 1
    if jq -e --arg old "$share_link" --arg link "$new_link" --arg ip "$clean_ip" \
        'if .share_link == $old then .share_link = $link | .clean_ip = $ip else error("endpoint changed") end' \
        "$file" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$file" || { rc=$?; rm -f "$tmp"; log_error "Failed to replace config."; return "$rc"; }
    else
        rm -f "$tmp"
        log_error "Failed to update config JSON!"
        return 1
    fi

    log_success "Config [$conf_name] updated with Clean IP : [$clean_ip]"
    if [ -n "${CF_REPLACE_NOTE:-}" ]; then
        log_info "$CF_REPLACE_NOTE"
    else
        log_info "SNI / Host / Path left unchanged!"
    fi
}