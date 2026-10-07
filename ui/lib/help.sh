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
    echo "$(help_cache_dir)/$1.json"
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
    HELP_URL="$1"
    HELP_DEST="$2"
    HELP_TMP="${HELP_DEST}.part"

    rm -f "$HELP_TMP" 2>/dev/null
    HELP_DL_OK=0

    # Try the next client when the previous one is missing or the transfer fails.
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 5 --max-time 20 "$HELP_URL" -o "$HELP_TMP" 2>/dev/null && [ -s "$HELP_TMP" ] && HELP_DL_OK=1
    fi

    if [ "$HELP_DL_OK" -ne 1 ] && command -v uclient-fetch >/dev/null 2>&1; then
        rm -f "$HELP_TMP" 2>/dev/null
        uclient-fetch -q -T 20 -O "$HELP_TMP" "$HELP_URL" 2>/dev/null && [ -s "$HELP_TMP" ] && HELP_DL_OK=1
    fi

    if [ "$HELP_DL_OK" -ne 1 ] && command -v wget >/dev/null 2>&1; then
        rm -f "$HELP_TMP" 2>/dev/null
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

    mv "$HELP_TMP" "$HELP_DEST" 2>/dev/null || {
        rm -f "$HELP_TMP" 2>/dev/null
        return 1
    }

    return 0
}

# ------------------------------------------------------------
# Use the cached manual, otherwise fetch and cache it
# Returns 1 when jq is missing or every source failed
# ------------------------------------------------------------
help_ensure_manual() {
    HELP_ID="$1"
    [ -z "$HELP_ID" ] && return 1

    command -v jq >/dev/null 2>&1 || return 1

    HELP_DEST="$(help_manual_path "$HELP_ID")"

    if [ -s "$HELP_DEST" ] && jq empty "$HELP_DEST" >/dev/null 2>&1; then
        return 0
    fi

    mkdir -p "$(help_cache_dir)" 2>/dev/null || return 1

    for HELP_URL in $(help_manual_sources "$HELP_ID"); do
        if help_download "$HELP_URL" "$HELP_DEST"; then
            return 0
        fi
    done

    rm -f "$HELP_DEST" 2>/dev/null
    return 1
}

# ------------------------------------------------------------
# Drop cached manuals so the next screen re-downloads them
# ------------------------------------------------------------
help_cache_reset() {
    rm -f "$(help_cache_dir)"/*.json 2>/dev/null
    rmdir "$(help_cache_dir)" 2>/dev/null
    return 0
}
