#!/bin/sh
# ============================================================
# DayPass - In-App Help Library
# Fetches JSON manuals on demand and caches them under
# $DAYPASS_DIR/help (default: /etc/daypass/help).
# ============================================================

HELP_REPO_SLUG="${DAYPASS_HELP_REPO:-Chamroosh98/DayPass}"

# ------------------------------------------------------------
# Cache directory (resolved on each call so DAYPASS_DIR wins)
# ------------------------------------------------------------
help_cache_dir() {
    echo "${DAYPASS_DIR:-/etc/daypass}/help"
}

# ------------------------------------------------------------
# Resolve the repository branch the manuals should come from
# ------------------------------------------------------------
help_branch() {
    if [ -n "${DAYPASS_HELP_BRANCH:-}" ]; then
        echo "$DAYPASS_HELP_BRANCH"
        return 0
    fi

    case "${REPO_URL%/}" in
        */beta) echo "beta" ;;
        *)      echo "main" ;;
    esac
}

# ------------------------------------------------------------
# Local cache path of a manual
# ------------------------------------------------------------
help_manual_path() {
    local cache
    cache=$(help_cache_dir)
    if [ -f "$cache/.managed/$1.json" ]; then
        printf '%s\n' "$cache/.managed/$1.json"
    else
        printf '%s\n' "$cache/$1.json"
    fi
}

# ------------------------------------------------------------
# Candidate download URLs (Pages -> jsDelivr CDN -> GitHub raw)
# ------------------------------------------------------------
help_manual_sources() {
    HELP_ID="$1"
    HELP_BRANCH="$(help_branch)"

    [ -n "${REPO_URL:-}" ] && echo "${REPO_URL%/}/help/${HELP_ID}.json"
    echo "https://cdn.jsdelivr.net/gh/${HELP_REPO_SLUG}@${HELP_BRANCH}/help/${HELP_ID}.json"
    echo "https://raw.githubusercontent.com/${HELP_REPO_SLUG}/${HELP_BRANCH}/help/${HELP_ID}.json"
    return 0
}

# ------------------------------------------------------------
# Download one URL using curl -> uclient-fetch -> wget
# ------------------------------------------------------------
help_download() {
    local HELP_URL="$1" HELP_DEST="$2" HELP_TMP HELP_DL_OK=0
    HELP_TMP=$(mktemp "${HELP_DEST%/*}/.download.XXXXXX") || return 1

    # Try the next client when the previous one is missing or the transfer fails.
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 5 --max-time 20 "$HELP_URL" -o "$HELP_TMP" 2>/dev/null && [ -s "$HELP_TMP" ] && HELP_DL_OK=1
    fi

    if [ "$HELP_DL_OK" -ne 1 ] && command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -q -T 20 -O "$HELP_TMP" "$HELP_URL" 2>/dev/null && [ -s "$HELP_TMP" ] && HELP_DL_OK=1
    fi

    if [ "$HELP_DL_OK" -ne 1 ] && command -v wget >/dev/null 2>&1; then
        wget -q -T 20 -O "$HELP_TMP" "$HELP_URL" 2>/dev/null && [ -s "$HELP_TMP" ] && HELP_DL_OK=1
    fi

    if [ "$HELP_DL_OK" -ne 1 ] || [ ! -s "$HELP_TMP" ]; then
        rm -f "$HELP_TMP" 2>/dev/null
        return 1
    fi

    # Reject empty or invalid JSON payloads (HTML error pages, etc.)
    if ! jq empty "$HELP_TMP" >/dev/null 2>&1; then
        rm -f "$HELP_TMP" 2>/dev/null
        return 1
    fi

    # Never replace a pre-existing cache path. Keep a second link as a receipt.
    if [ -e "$HELP_DEST" ] || [ -L "$HELP_DEST" ] ||
        [ -e "$HELP_DEST.owned" ] || [ -L "$HELP_DEST.owned" ]; then
        rm -f "$HELP_TMP"
        return 1
    fi
    ln "$HELP_TMP" "$HELP_DEST.owned" && ln "$HELP_TMP" "$HELP_DEST" || {
        if [ "$HELP_TMP" -ef "$HELP_DEST.owned" ]; then rm -f "$HELP_DEST.owned"; fi
        rm -f "$HELP_TMP" 2>/dev/null
        return 1
    }

    rm -f "$HELP_TMP"
}

# ------------------------------------------------------------
# Use the cached manual, otherwise fetch and cache it
# Returns 1 when jq is missing or every source failed
# ------------------------------------------------------------
help_ensure_manual() {
    local HELP_ID="$1" cache dest url
    case "$HELP_ID" in ''|*[!a-zA-Z0-9_-]*) return 1 ;; esac
    command -v jq >/dev/null 2>&1 || return 1
    cache=$(help_cache_dir)
    dest="$cache/.managed/$HELP_ID.json"
    [ ! -L "$cache" ] && [ ! -L "$cache/.managed" ] || return 1
    if [ -s "$dest" ]; then
        [ ! -L "$dest" ] && jq empty "$dest" >/dev/null 2>&1
        return $?
    fi
    mkdir -p "$cache/.managed" || return 1
    for url in $(help_manual_sources "$HELP_ID"); do
        help_download "$url" "$dest" && return 0
    done
    # Older installers left no ownership record. Keep these as offline fallback.
    [ ! -L "$cache/$HELP_ID.json" ] && [ -s "$cache/$HELP_ID.json" ] &&
        jq empty "$cache/$HELP_ID.json" >/dev/null 2>&1
}

help_cache_reset() {
    local cache dir receipt file
    cache=$(help_cache_dir)
    dir="$cache/.managed"
    [ ! -L "$cache" ] && [ ! -L "$dir" ] || return 1
    [ -e "$dir" ] || return 0
    [ -d "$dir" ] && [ -r "$dir" ] && [ -x "$dir" ] || return 1
    for receipt in "$dir"/*.json.owned; do
        [ -f "$receipt" ] && [ ! -L "$receipt" ] || continue
        file=${receipt%.owned}
        [ -f "$file" ] && [ ! -L "$file" ] && [ "$file" -ef "$receipt" ] || continue
        rm "$file" "$receipt" || return 1
    done
    return 0
}
