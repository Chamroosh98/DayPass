#!/bin/sh
# ============================================================
# DayPass - Shared helpers for JSON-configured cores (sing-box, Xray)
# ============================================================

# $1 service, $2 action
_jcore_service() {
    [ -x "/etc/init.d/$1" ] || return 1
    /etc/init.d/"$1" "$2" >/dev/null 2>&1
}

# $1 process pattern
_jcore_running() {
    pgrep -f "$1" >/dev/null 2>&1
}

# Applies a jq filter to a core config with backup and validation.
# $1 config file, $2 jq filter, $3 tag passed as $tag, $4.. validator command (config path appended)
_jcore_edit_config() {
    local file="$1"
    local filter="$2"
    local tag="$3"
    local tmp="/tmp/daypass-core-$$.json"
    shift 3

    [ -f "$file" ] || return 1

    if ! jq --arg tag "$tag" "$filter" "$file" > "$tmp" 2>/dev/null || [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        log_error "Could not update core config [$file]!"
        return 1
    fi

    if [ "$#" -gt 0 ] && command -v "$1" >/dev/null 2>&1; then
        if ! "$@" "$tmp" >/dev/null 2>&1; then
            rm -f "$tmp"
            log_error "Updated core config failed validation; original kept."
            return 1
        fi
    fi

    cp -f "$file" "$file.daypass.bak" 2>/dev/null
    cp -f "$tmp" "$file" && rm -f "$tmp"
}
