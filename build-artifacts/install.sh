#!/bin/sh

###############################################################################
# DayPass Installer (Auto-generated via Go Action)
###############################################################################

# Dynamic REPO_URL configuration
if [ -z "${REPO_URL:-}" ]; then
    REPO_URL="https://chamroosh98.github.io/DayPass/beta"
fi
export REPO_URL


# 📄 Source : globals.sh

export DAYPASS_DIR="/etc/daypass"
export INSTALL_LOG="$DAYPASS_DIR/install.log"
export DAYPASS_MANIFEST="$DAYPASS_DIR/installed_manifest.json"
export TRANSACTION_LOG="/tmp/daypass/transaction.log" 

# 📄 Source : styles.sh

ESC="$(printf '\033')"

RESET="${ESC}[0m"
BOLD="${ESC}[1m"
DIM="${ESC}[2m"

BLACK="${ESC}[30m"
RED="${ESC}[31m"
GREEN="${ESC}[32m"
ORANGE="${ESC}[33m"
YELLOW="${ESC}[1;33m"
BLUE="${ESC}[34m"
PURPLE="${ESC}[35m"
PINK="${ESC}[1;35m"
CYAN="${ESC}[36m"
WHITE="${ESC}[37m"
GRAY="${ESC}[90m"
COLOR_MUTED="${ESC}[90m"

export RESET BOLD DIM CYAN GREEN YELLOW RED BLUE BLACK WHITE GRAY COLOR_MUTED PURPLE ORANGE PINK


# 📄 Source : box_utils.sh

draw_bar()
{
    PCT="$1"
    BW="${2:-20}"
    MODE="${3:-usage}"
    
    [ "$PCT" -gt 100 ] && PCT=100
    [ "$PCT" -lt 0 ] && PCT=0

    FILLED=$(( PCT * BW / 100 ))

    if [ "$MODE" = "score" ]; then
        if [ "$PCT" -ge 80 ]; then COLOR="$GREEN"
        elif [ "$PCT" -ge 50 ]; then COLOR="$YELLOW"
        else COLOR="$RED"
        fi
    else
        if [ "$PCT" -ge 85 ]; then COLOR="$RED"
        elif [ "$PCT" -ge 60 ]; then COLOR="$YELLOW"
        else COLOR="$GREEN"
        fi
    fi

    BAR=""
    i=0
    while [ "$i" -lt "$FILLED" ]; do 
        BAR="${BAR}█"
        i=$((i+1))
    done
    while [ "$i" -lt "$BW" ]; do 
        BAR="${BAR}░"
        i=$((i+1))
    done

    printf "${COLOR}%s${RESET}" "$BAR"
}

log_warn()    { printf "  ${YELLOW}⚠️ %s${RESET}\n" "$1" >&2; }
log_info()    { printf "  ${CYAN}ℹ️ %s${RESET}\n" "$1"; }
log_success() { printf "  ${GREEN}✅ %s${RESET}\n" "$1"; }
log_error()   { printf "  ${RED}❌ %s${RESET}\n" "$1" >&2; }


# 📄 Source : header.sh

# Start every UI screen the same way: clear, then the DayPass banner.
render_persistent_header()
{
    clear
    if command -v show_banner >/dev/null 2>&1; then
        show_banner
    fi
    echo
}


# 📄 Source : progress.sh

# -----------------------------------------------------------------------------
# 1. Timer + Animated Progress (For Async background tasks like opkg/apk update)
# -----------------------------------------------------------------------------
show_timer_progress()
{
    pid="$1"
    message="$2"
    
    start_time=$(date +%s)
    bar_width=30
    current_step=0

    # Hide Cursor
    printf "\033[?25l" 2>/dev/null

    echo "  🖐️ Please wait, $message ..."

    while kill -0 "$pid" 2>/dev/null; do
        now=$(date +%s)
        elapsed=$((now - start_time))
        
        # Simulate smooth progress loop up to 95% until task finishes
        current_step=$(( (current_step + 1) % (bar_width + 1) ))
        percent=$((current_step * 100 / bar_width))
        [ "$percent" -gt 95 ] && percent=95

        # Build [====>    ] ASCII Bar
        arrow_pos=$current_step
        bar=""
        i=0
        while [ "$i" -lt "$bar_width" ]; do
            if [ "$i" -lt "$arrow_pos" ]; then
                bar="${bar}="
            elif [ "$i" -eq "$arrow_pos" ]; then
                bar="${bar}>"
            else
                bar="${bar} "
            fi
            i=$((i + 1))
        done

        # Line 1: Timer line
        # Line 2: Progress bar line
        printf "  \033[K⏰ DayPass is working in the background, timer : ${BOLD}%d seconds${RESET}\n" "$elapsed"
        printf "  \033[K[${CYAN}%s${RESET}] ${BOLD}%3d%%${RESET}\033[1A\r" "$bar" "$percent"

        if command -v usleep >/dev/null 2>&1; then
            usleep 150000 2>/dev/null
        else
            sleep 1
        fi
    done

    # Finish Line on Complete (100%)
    now=$(date +%s)
    elapsed=$((now - start_time))
    
    # Render Full Bar [==============================] 100%
    full_bar=""
    i=0
    while [ "$i" -lt "$bar_width" ]; do
        full_bar="${full_bar}="
        i=$((i + 1))
    done

    printf "  \033[K✌️ Task finished! total time : ${GREEN}%d seconds${RESET}\n" "$elapsed"
    printf "  \033[K[${GREEN}%s${RESET}] ${BOLD}100%%${RESET}\n" "$full_bar"

    # Restore Cursor
    printf "\033[?25h" 2>/dev/null
}

# -----------------------------------------------------------------------------
# 2. Strict Real-Time Step Progress (For File downloads / Batch Package items)
# -----------------------------------------------------------------------------
show_ascii_progress()
{
    title="$1"
    current="$2"
    total="$3"
    bar_width="${4:-30}"

    [ "$total" -le 0 ] && return

    percent=$((current * 100 / total))
    [ "$percent" -gt 100 ] && percent=100

    filled=$((percent * bar_width / 100))

    bar=""
    i=0
    while [ "$i" -lt "$bar_width" ]; do
        if [ "$i" -lt "$filled" ]; then
            bar="${bar}="
        elif [ "$i" -eq "$filled" ] && [ "$percent" -lt 100 ]; then
            bar="${bar}>"
        else
            bar="${bar} "
        fi
        i=$((i + 1))
    done

    COLOR="${YELLOW}"
    [ "$percent" -ge 50 ] && COLOR="${CYAN}"
    [ "$percent" -eq 100 ] && COLOR="${GREEN}"

    printf "\r  ⏳ %-20s [${COLOR}%s${RESET}] ${BOLD}%3d%%${RESET} (%s/%s)" \
            "$title" "$bar" "$percent" "$current" "$total"

    [ "$current" -ge "$total" ] && echo
}

log_step()
{
    status="$1"
    message="$2"

    case "$status" in
        ok)   printf "  ${GREEN}✔ ${RESET} %s\n" "$message" ;;
        fail) printf "  ${RED}✖ ${RESET} %s\n" "$message" >&2 ;;
        warn) printf "  ${YELLOW}! ${RESET} %s\n" "$message" ;;
        *)    printf "  ${CYAN}ℹ ${RESET} %s\n" "$message" ;;
    esac
}

# 📄 Source : help.sh
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


# 📄 Source : nav.sh
# ============================================================
# DayPass - Menu navigation contract
#   0 : Back (sub-menus) / Exit (root menu)
#   q : Quit DayPass from any screen
#   h : Contextual help of the current screen
# ============================================================

daypass_quit() {
    echo
    printf "  ${GRAY}TNX for using DayPass! =)${RESET}\n"
    stty sane 2>/dev/null
    exit 0
}

# Ctrl-C leaves the terminal usable and ends the session cleanly
daypass_interrupt() {
    trap - INT TERM
    echo
    log_warn "Interrupted."
    daypass_quit
}

# Reads one answer from the terminal into UI_CHOICE. A closed terminal (EOF)
# ends the session instead of looping on empty input forever.
# $1 prompt text
ui_read() {
    printf "  ⁉️ %s : " "$1"
    if ! read -r UI_CHOICE </dev/tty; then
        UI_CHOICE=""
        daypass_quit
    fi
}

# $1 highest option number
ui_prompt() {
    ui_read "Select option [0-$1]"
}

ui_pause() {
    printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
    read -r _ </dev/tty || daypass_quit
}

# $1 "root" | "main" (back to main menu) | anything else (back one level)
ui_nav_footer() {
    _nav_muted="${COLOR_MUTED:-${GRAY:-\033[90m}}"
    case "${1:-}" in
        root) _nav_back="0) Exit DayPass" ;;
        main) _nav_back="0) Back to Main Menu" ;;
        *)    _nav_back="0) Back / Skip" ;;
    esac
    if [ "${1:-}" != "root" ]; then
        _nav_line="$_nav_back   q) Quit DayPass   h) Help"
    else
        _nav_line="$_nav_back   h) Help"
    fi
    _nav_rule=""
    _nav_i=0
    while [ "$_nav_i" -lt "${#_nav_line}" ]; do
        _nav_rule="${_nav_rule}─"
        _nav_i=$((_nav_i + 1))
    done
    echo
    echo "  $_nav_rule"
    printf "  ${_nav_muted}%s${RESET}\n" "$_nav_line"
    echo
}

ui_title() {
    echo "  $1"
    echo "  ───────────────────────────────────────────────────────────"
}

ui_show_help() {
    if command -v show_help >/dev/null 2>&1; then
        show_help "$1"
    else
        log_warn "Help module not loaded!"
        sleep 1
    fi
}

# Runs a menu/action function when it is loaded; a failing action never
# ends the calling menu loop. $1 function, $2 label for the error message.
ui_run() {
    local fn="$1"
    local label="${2:-$1}"
    if [ "$#" -ge 2 ]; then shift 2; else shift "$#"; fi

    if command -v "$fn" >/dev/null 2>&1; then
        "$fn" "$@" || true
        return 0
    fi
    log_error "$label module not found!"
    sleep 2
    return 1
}

# Handles the shared keys. Returns 0 when the key was consumed, 1 otherwise.
# $1 choice, $2 help module id
ui_nav_common() {
    case "$1" in
        q|Q) daypass_quit ;;
        h|H) ui_show_help "$2"; return 0 ;;
    esac
    return 1
}


# 📄 Source : http_request.sh
# ============================================================
# DayPass - HTTP client wrapper
# Order: curl, then uclient-fetch, then wget.
# Stock OpenWrt has uclient-fetch and usually no curl.
#
# daypass_http_request METHOD URL OUTFILE [BODYFILE] [HEADERFILE]
#   HEADERFILE is "Name: value" lines (Authorization, Content-Type, ...).
#   Prints the HTTP status code (000 when nothing answered).
#   Returns 0 when a status was captured, 1 otherwise.
#   A short reason is written to ${DAYPASS_HTTP_ERR:-/tmp/daypass_http.err}.
# ============================================================

DAYPASS_HTTP_ERR="${DAYPASS_HTTP_ERR:-/tmp/daypass_http.err}"

daypass_http_available() {
    command -v curl >/dev/null 2>&1 \
        || command -v uclient-fetch >/dev/null 2>&1 \
        || command -v wget >/dev/null 2>&1 \
        || command -v openssl >/dev/null 2>&1
}

_dh_fail() {
    printf '%s\n' "$1" > "$DAYPASS_HTTP_ERR" 2>/dev/null
    printf '%s\n' "000"
    return 1
}

_dh_tool_help() {
    "$1" --help 2>&1 || true
}

# $1 method $2 url $3 outfile $4 body $5 headerfile
_dh_via_curl() {
    _dh_cfg="${DAYPASS_HTTP_ERR}.curl.cfg"
    _dh_umask="$(umask)"
    umask 077
    {
        printf '%s\n' "silent" "show-error"
        printf 'output = "%s"\n' "$3"
        printf 'request = "%s"\n' "$1"
        printf '%s\n' "connect-timeout = 15" "max-time = 180"
        printf '%s\n' 'write-out = "%{http_code}"'
        if [ -n "$4" ] && [ -f "$4" ]; then
            printf 'data-binary = "@%s"\n' "$4"
        fi
        if [ -n "$5" ] && [ -f "$5" ]; then
            while IFS= read -r _dh_line || [ -n "$_dh_line" ]; do
                [ -n "$_dh_line" ] || continue
                printf 'header = "%s"\n' "$_dh_line"
            done < "$5"
        fi
    } > "$_dh_cfg" 2>/dev/null || { umask "$_dh_umask"; return 1; }
    umask "$_dh_umask"

    _dh_code="$(curl -K "$_dh_cfg" "$2" 2>"$DAYPASS_HTTP_ERR")"
    rm -f "$_dh_cfg" 2>/dev/null
    case "$_dh_code" in
        [0-9][0-9][0-9]) printf '%s\n' "$_dh_code"; return 0 ;;
    esac
    return 1
}

# Copy headers and, for a faked PUT, add the override lines BusyBox can send.
# $1 source header file (optional), $2 dest, $3 real method or empty
_dh_prepare_headers() {
    : > "$2" 2>/dev/null || return 1
    if [ -n "$1" ] && [ -f "$1" ]; then
        cat "$1" >> "$2" 2>/dev/null || return 1
    fi
    if [ -n "$3" ] && [ "$3" != "POST" ] && [ "$3" != "GET" ] && [ "$3" != "HEAD" ]; then
        printf 'X-HTTP-Method-Override: %s\n' "$3" >> "$2"
        printf 'X-Method: %s\n' "$3" >> "$2"
    fi
    return 0
}

# $1 method $2 url $3 outfile $4 body $5 headerfile
# Prints a status and returns 0, or returns 2 when this client cannot do the method.
_dh_via_uclient() {
    _dh_m="$1"
    _dh_u="$2"
    _dh_o="$3"
    _dh_b="$4"
    _dh_h="$5"
    _dh_help="$(_dh_tool_help uclient-fetch)"
    _dh_send="$_dh_m"
    _dh_hdrs="$_dh_h"

    if [ "$_dh_m" != "GET" ] && [ "$_dh_m" != "HEAD" ] && [ "$_dh_m" != "POST" ] \
        && ! printf '%s\n' "$_dh_help" | grep -q -- '--method'; then
        if [ -n "$_dh_b" ] && printf '%s\n' "$_dh_help" | grep -q -e '--post-file' -e '--post-data'; then
            _dh_send="POST"
            _dh_hdrs="${DAYPASS_HTTP_ERR}.override.hdr"
            _dh_prepare_headers "$_dh_h" "$_dh_hdrs" "$_dh_m" || return 2
        else
            return 2
        fi
    fi

    set -- uclient-fetch -O "$_dh_o" -T 180

    if [ -n "$_dh_hdrs" ] && [ -f "$_dh_hdrs" ]; then
        while IFS= read -r _dh_line || [ -n "$_dh_line" ]; do
            [ -n "$_dh_line" ] || continue
            set -- "$@" --header="$_dh_line"
        done < "$_dh_hdrs"
    fi

    if [ -n "$_dh_b" ] && [ -f "$_dh_b" ]; then
        if printf '%s\n' "$_dh_help" | grep -q -- '--method'; then
            set -- "$@" --method="$_dh_send" --body-file="$_dh_b"
        elif [ "$_dh_send" = "POST" ] && printf '%s\n' "$_dh_help" | grep -q -- '--post-file'; then
            set -- "$@" --post-file="$_dh_b"
        elif [ "$_dh_send" = "POST" ] && printf '%s\n' "$_dh_help" | grep -q -- '--post-data'; then
            set -- "$@" --post-data="$(cat "$_dh_b")"
        else
            return 2
        fi
    elif [ "$_dh_send" != "GET" ] && [ "$_dh_send" != "HEAD" ]; then
        if printf '%s\n' "$_dh_help" | grep -q -- '--method'; then
            set -- "$@" --method="$_dh_send"
        else
            return 2
        fi
    fi

    _dh_err="$( "$@" "$_dh_u" 2>&1 )"
    _dh_rc=$?
    printf '%s\n' "$_dh_err" > "$DAYPASS_HTTP_ERR" 2>/dev/null

    _dh_code="$(printf '%s\n' "$_dh_err" | sed -n 's/.*HTTP error \([0-9][0-9][0-9]\).*/\1/p' | sed -n '$p')"
    if [ -z "$_dh_code" ] && [ "$_dh_rc" -eq 0 ]; then
        _dh_code="200"
    fi
    [ -n "$_dh_code" ] || return 1

    # A POST that only pretends to be PUT is not a real upload unless it succeeded.
    if [ "$_dh_send" = "POST" ] && [ "$_dh_m" != "POST" ]; then
        case "$_dh_code" in
            2[0-9][0-9]) ;;
            *) return 2 ;;
        esac
    fi

    printf '%s\n' "$_dh_code"
    return 0
}

# $1 method $2 url $3 outfile $4 body $5 headerfile
# Prints a status and returns 0, or returns 2 when this client cannot do the method.
_dh_via_wget() {
    _dh_m="$1"
    _dh_u="$2"
    _dh_o="$3"
    _dh_b="$4"
    _dh_h="$5"
    _dh_help="$(_dh_tool_help wget)"
    _dh_send="$_dh_m"
    _dh_hdrs="$_dh_h"

    if [ "$_dh_m" != "GET" ] && [ "$_dh_m" != "HEAD" ] && [ "$_dh_m" != "POST" ] \
        && ! printf '%s\n' "$_dh_help" | grep -q -- '--method'; then
        if [ -n "$_dh_b" ] && printf '%s\n' "$_dh_help" | grep -q -e '--post-file' -e '--post-data'; then
            _dh_send="POST"
            _dh_hdrs="${DAYPASS_HTTP_ERR}.override.hdr"
            _dh_prepare_headers "$_dh_h" "$_dh_hdrs" "$_dh_m" || return 2
        else
            return 2
        fi
    fi

    set -- wget -O "$_dh_o" -T 180 -S

    if printf '%s\n' "$_dh_help" | grep -q -- '--no-check-certificate'; then
        set -- "$@" --no-check-certificate
    fi

    if [ -n "$_dh_hdrs" ] && [ -f "$_dh_hdrs" ]; then
        while IFS= read -r _dh_line || [ -n "$_dh_line" ]; do
            [ -n "$_dh_line" ] || continue
            set -- "$@" --header="$_dh_line"
        done < "$_dh_hdrs"
    fi

    if [ -n "$_dh_b" ] && [ -f "$_dh_b" ]; then
        if [ "$_dh_send" = "$_dh_m" ] && printf '%s\n' "$_dh_help" | grep -q -- '--method' \
            && printf '%s\n' "$_dh_help" | grep -q -- '--body-file'; then
            set -- "$@" --method="$_dh_send" --body-file="$_dh_b"
        elif [ "$_dh_send" = "POST" ] && printf '%s\n' "$_dh_help" | grep -q -- '--post-file'; then
            set -- "$@" --post-file="$_dh_b"
        elif [ "$_dh_send" = "POST" ] && printf '%s\n' "$_dh_help" | grep -q -- '--post-data'; then
            set -- "$@" --post-data="$(cat "$_dh_b")"
        else
            return 2
        fi
    elif [ "$_dh_send" != "GET" ] && [ "$_dh_send" != "HEAD" ]; then
        if printf '%s\n' "$_dh_help" | grep -q -- '--method'; then
            set -- "$@" --method="$_dh_send"
        else
            return 2
        fi
    fi

    _dh_err="$( "$@" "$_dh_u" 2>&1 )"
    _dh_rc=$?
    printf '%s\n' "$_dh_err" > "$DAYPASS_HTTP_ERR" 2>/dev/null

    _dh_code="$(printf '%s\n' "$_dh_err" | sed -n 's|.*HTTP/[0-9.][0-9.]* \([0-9][0-9][0-9]\).*|\1|p' | sed -n '$p')"
    if [ -z "$_dh_code" ] && [ "$_dh_rc" -eq 0 ]; then
        _dh_code="200"
    fi
    [ -n "$_dh_code" ] || return 1

    if [ "$_dh_send" = "POST" ] && [ "$_dh_m" != "POST" ]; then
        case "$_dh_code" in
            2[0-9][0-9]) ;;
            *) return 2 ;;
        esac
    fi

    printf '%s\n' "$_dh_code"
    return 0
}

# Raw HTTP/1.1 over TLS. openssl s_client, or ncat --ssl.
# $1 method $2 url $3 outfile $4 body $5 headerfile
_dh_via_tls() {
    _dh_m="$1"
    _dh_u="$2"
    _dh_o="$3"
    _dh_b="$4"
    _dh_h="$5"
    _dh_rest="${_dh_u#*://}"
    _dh_host="${_dh_rest%%/*}"
    _dh_path="/${_dh_rest#*/}"
    [ "$_dh_path" = "/$_dh_rest" ] && _dh_path="/"
    _dh_host="${_dh_host%%:*}"
    [ -n "$_dh_host" ] || return 2

    if command -v openssl >/dev/null 2>&1; then
        _dh_tls_cmd="openssl s_client -quiet -connect ${_dh_host}:443 -servername ${_dh_host}"
    elif command -v ncat >/dev/null 2>&1 && _dh_tool_help ncat | grep -q -- '--ssl'; then
        _dh_tls_cmd="ncat --ssl ${_dh_host} 443"
    else
        return 2
    fi

    _dh_req="${DAYPASS_HTTP_ERR}.raw.req"
    _dh_resp="${DAYPASS_HTTP_ERR}.raw.resp"
    _dh_len=0
    if [ -n "$_dh_b" ] && [ -f "$_dh_b" ]; then
        _dh_len="$(wc -c < "$_dh_b" | tr -d ' ')"
    fi

    _dh_umask="$(umask)"
    umask 077
    {
        printf '%s %s HTTP/1.1\r\n' "$_dh_m" "$_dh_path"
        printf 'Host: %s\r\n' "$_dh_host"
        printf 'Content-Length: %s\r\n' "${_dh_len:-0}"
        printf 'Connection: close\r\n'
        if [ -n "$_dh_h" ] && [ -f "$_dh_h" ]; then
            while IFS= read -r _dh_line || [ -n "$_dh_line" ]; do
                [ -n "$_dh_line" ] || continue
                printf '%s\r\n' "$_dh_line"
            done < "$_dh_h"
        fi
        printf '\r\n'
        if [ -n "$_dh_b" ] && [ -f "$_dh_b" ]; then
            cat "$_dh_b"
        fi
    } > "$_dh_req" 2>/dev/null || { umask "$_dh_umask"; return 2; }
    umask "$_dh_umask"

    rm -f "$_dh_resp" 2>/dev/null
    if command -v timeout >/dev/null 2>&1; then
        timeout 25 $_dh_tls_cmd < "$_dh_req" > "$_dh_resp" 2>"$DAYPASS_HTTP_ERR" || true
    else
        $_dh_tls_cmd < "$_dh_req" > "$_dh_resp" 2>"$DAYPASS_HTTP_ERR" &
        _dh_tls_pid=$!
        _dh_tls_n=0
        while [ "$_dh_tls_n" -lt 25 ]; do
            kill -0 "$_dh_tls_pid" 2>/dev/null || break
            sleep 1
            _dh_tls_n=$((_dh_tls_n + 1))
        done
        kill "$_dh_tls_pid" 2>/dev/null || true
        wait "$_dh_tls_pid" 2>/dev/null || true
    fi
    rm -f "$_dh_req" 2>/dev/null

    _dh_code="$(tr -d '\r' < "$_dh_resp" 2>/dev/null | sed -n 's/^HTTP\/[0-9.][0-9.]* \([0-9][0-9][0-9]\).*/\1/p' | sed -n '1p')"
    [ -n "$_dh_code" ] || return 1

    awk 'BEGIN { body = 0 }
        { sub(/\r$/, "") }
        body { print }
        $0 == "" { body = 1 }' "$_dh_resp" > "$_dh_o" 2>/dev/null
    rm -f "$_dh_resp" 2>/dev/null
    printf '%s\n' "$_dh_code"
    return 0
}

_dh_put_unsupported() {
    printf '%s\n' "PUT_UNSUPPORTED" > "$DAYPASS_HTTP_ERR" 2>/dev/null
    printf '%s\n' "000"
    return 1
}

daypass_http_request() {
    _dh_method="$1"
    _dh_url="$2"
    _dh_out="$3"
    _dh_body="$4"
    _dh_hdr="$5"

    : > "$DAYPASS_HTTP_ERR" 2>/dev/null
    rm -f "$_dh_out" 2>/dev/null

    case "$_dh_method" in
        GET|POST|PUT|HEAD|DELETE|PATCH) ;;
        *)
            _dh_fail "Unsupported HTTP method [${_dh_method}]."
            return 1
            ;;
    esac

    if [ -z "$_dh_url" ] || [ -z "$_dh_out" ]; then
        _dh_fail "HTTP request is missing a URL or output file."
        return 1
    fi

    if command -v curl >/dev/null 2>&1; then
        if _dh_via_curl "$_dh_method" "$_dh_url" "$_dh_out" "$_dh_body" "$_dh_hdr"; then
            return 0
        fi
        _dh_fail "curl could not complete the request."
        return 1
    fi

    if command -v uclient-fetch >/dev/null 2>&1; then
        if _dh_via_uclient "$_dh_method" "$_dh_url" "$_dh_out" "$_dh_body" "$_dh_hdr"; then
            return 0
        fi
    fi

    if command -v wget >/dev/null 2>&1; then
        if _dh_via_wget "$_dh_method" "$_dh_url" "$_dh_out" "$_dh_body" "$_dh_hdr"; then
            return 0
        fi
    fi

    case "$_dh_method" in
        PUT|PATCH|DELETE)
            if _dh_via_tls "$_dh_method" "$_dh_url" "$_dh_out" "$_dh_body" "$_dh_hdr"; then
                return 0
            fi
            _dh_put_unsupported
            return 1
            ;;
    esac

    if [ ! -s "$DAYPASS_HTTP_ERR" ]; then
        printf '%s\n' "No HTTP client found (curl, uclient-fetch or wget)." > "$DAYPASS_HTTP_ERR"
    fi
    printf '%s\n' "000"
    return 1
}


# 📄 Source : reverse_tunnel.sh

# Purpose:
#   Offer the user (once, at the very beginning) to route package-manager
#   traffic through a local HTTP proxy, typically delivered via an SSH
#   reverse tunnel. This helps bypass ISP filtering and broken feeds.

# ---------- defaults ----------
PROXY_DEFAULT_PORT="2585"
PROXY_HOST="127.0.0.1"

# ---------- banner ----------
_pb_banner() {
    echo
    echo "  ${CYAN}${RESET}${BOLD}🌐 Optional Network Proxy Bootstrap${RESET}"
    echo "  ${CYAN}─────────────────────────────────────────────────────────${RESET}"
    echo "  ${CYAN}${RESET}Routing DayPass traffic through a local proxy helps"
    echo "  ${CYAN}${RESET}avoid ISP filtering and broken package downloads!  "
    echo "  ${CYAN}─────────────────────────────────────────────────────────${RESET}"
    echo
}

# ---------- manual ----------
_pb_manual() {
    render_persistent_header
    echo
    echo "  ${BOLD}${WHITE}📖 Manual Setup${RESET}"
    echo "  ${DIM}──────────────────────────────────────────────────────────${RESET}"
    echo
    echo "  ${BOLD}${CYAN}🪟 Windows users :${RESET}"
    echo "  ${WHITE}1) Open your VPN / proxy client and enable a local${RESET}"
    echo "  ${WHITE}   SOCKS/HTTP listener on port ${YELLOW}[${PROXY_DEFAULT_PORT}]${WHITE}.${RESET}"
    echo "  ${WHITE}2) In Windows Settings → Proxy, set:${RESET}"
    echo "  ${GREEN}   Address : ${PROXY_HOST}${RESET}"
    echo "  ${GREEN}   Port    : ${PROXY_DEFAULT_PORT}${RESET}"
    echo "  ${WHITE}3) Re-run DayPass! it will use that proxy.${RESET}"
    echo
    echo "  ${BOLD}${CYAN}🐧 Linux / macOS users :${RESET}"
    echo "  ${WHITE}Open a reverse SSH tunnel from your machine to the router :${RESET}"
    echo
    echo "  ${YELLOW}        ssh -R ${PROXY_DEFAULT_PORT}:${PROXY_HOST}:<VPN_PORT_ON_PC> root@<ROUTER_IP> -N${RESET}"
    echo
    echo "  ${GRAY}Replace <VPN_PORT_ON_PC> with the local port your VPN${RESET}"
    echo "  ${GRAY}client listens on (e.g. 10810}), and <ROUTER_IP> with${RESET}"
    echo "  ${GRAY}your router address (e.g.192.168.1.1).${RESET}"
    echo
    echo "  ${GRAY}ℹ️  Once the tunnel is up, all package downloads will${RESET}"
    echo "  ${GRAY}flow through ${PROXY_HOST}:${PROXY_DEFAULT_PORT}.${RESET}"
    echo "  ${DIM}──────────────────────────────────────────────────────────${RESET}"
    echo
}

# ---------- detect existing proxy env ----------
_pb_detect_existing() {
    _existing="${http_proxy:-${https_proxy:-${HTTP_PROXY:-${HTTPS_PROXY:-}}}}"
    [ -n "$_existing" ] && echo "$_existing" || echo ""
}

# ---------- apply proxy env ----------
_pb_apply() {
    _port="$1"

    case "$_port" in
        ''|*[!0-9]*)
            echo "${RED}  [x] Invalid port : [${_port}]${RESET}"
            return 1
            ;;
    esac

    if [ "$_port" -lt 1 ] || [ "$_port" -gt 65535 ]; then
        echo "${RED}  [x] Port out of range : [${_port}]${RESET}"
        return 1
    fi

    PROXY_PORT="$_port"
    PROXY_URL="http://${PROXY_HOST}:${PROXY_PORT}"

    export http_proxy="$PROXY_URL"
    export https_proxy="$PROXY_URL"
    export HTTP_PROXY="$PROXY_URL"
    export HTTPS_PROXY="$PROXY_URL"
    export no_proxy="localhost,127.0.0.1,::1"
    export NO_PROXY="$no_proxy"

    echo "${GREEN}  [+] Proxy exported → ${BOLD}${PROXY_URL}${RESET}"
    return 0
}

# Public — interactive offer (NEVER blocks pipeline)
proxy_bootstrap_offer() {
    local _existing
    local _ans
    local _choice
    local _c2

    _existing="$(_pb_detect_existing)"

    # ---- already configured? just confirm ----
    if [ -n "$_existing" ]; then
        echo
        echo "${CYAN}  [i]${RESET} Proxy already configured : ${YELLOW}[${_existing}]${RESET}"
        printf "  Re-configure proxy? ${DIM}[y/N]${RESET} : "
        read -r _ans </dev/tty
        case "$_ans" in
            [yY]|[yY][eE][sS]) ;;   # fall through to setup
            *) return 0 ;;
        esac
    fi

    render_persistent_header
    _pb_banner

    printf "  Route DayPass traffic through a local proxy? ${DIM}[y/N/help]${RESET} : "
    read -r _choice </dev/tty

    case "$_choice" in
        [yY]|[yY][eE][sS])
            ;;  # proceed to port prompt
        [hH]|[hH][eE][lL][pP])
            _pb_manual
            printf "  Continue with proxy setup? ${DIM}[y/N]${RESET} : "
            read -r _c2 </dev/tty
            case "$_c2" in
                [yY]|[yY][eE][sS]) ;;  # proceed
                *)
                    echo "${DIM}  [i] Skipped — continuing without proxy.${RESET}"
                    return 0
                    ;;
            esac
            ;;
        *)
            # empty / n / no / anything else → skip
            echo "${DIM}  [i] Skipped — continuing without proxy.${RESET}"
            return 0
            ;;
    esac

    proxy_bootstrap_setup
    return 0
}

# Public — prompt for port and export proxy env (used by the bootstrap wizard)
proxy_bootstrap_setup() {
    local _port

    while true; do
        if command -v ui_nav_footer >/dev/null 2>&1; then
            ui_nav_footer
        fi
        printf "  Proxy port on router side [default ${PROXY_DEFAULT_PORT}] : "
        if ! read -r _port </dev/tty; then
            echo "${CYAN}  [i]${RESET} Local proxy setup skipped. Proceeding with execution..."
            return 0
        fi

        case "$_port" in
            '')
                _port="$PROXY_DEFAULT_PORT"
                break
                ;;
            0|[bB]|[bB][aA][cC][kK]|[cC]|[cC][aA][nN][cC][eE][lL])
                echo "${CYAN}  [i]${RESET} Local proxy setup skipped. Proceeding with execution..."
                return 0
                ;;
            q|Q)
                command -v daypass_quit >/dev/null 2>&1 && daypass_quit
                return 0
                ;;
            h|H)
                if command -v ui_show_help >/dev/null 2>&1; then
                    ui_show_help "local_proxy_bootstrap"
                fi
                ;;
            *)
                break
                ;;
        esac
    done

    # ---- apply (never fails the caller; cancel leaves existing proxies alone) ----
    if _pb_apply "$_port"; then
        echo "${GREEN}  [i] All subsequent downloads will use this proxy.${RESET}"
    else
        echo "${YELLOW}  [!] Proxy setup failed — continuing without proxy.${RESET}"
    fi

    return 0
}

# Public — helpers (optional use elsewhere)

proxy_bootstrap_status() {
    _p="$(_pb_detect_existing)"
    if [ -n "$_p" ]; then
        echo "${GREEN}  [+] Proxy active : [${_p}]${RESET}"
    else
        echo "${YELLOW}  [!] No proxy configured.${RESET}"
    fi
}

proxy_bootstrap_clear() {
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
    unset no_proxy NO_PROXY
    unset PROXY_PORT PROXY_URL
    echo "${GREEN}  [+] Proxy environment cleared!${RESET}"
}

# 📄 Source : worker.sh

# Purpose:
#   Point OpenWrt package feeds (opkg / apk) at a Cloudflare Worker
#   reverse-proxy so downloads.openwrt.org can be reached through the
#   Cloudflare edge.
#
#   Three ways in:
#     1. paste config/worker.js into the Cloudflare dashboard editor,
#     2. import the *.workers.dev hostname Cloudflare showed,
#     3. roll the feed files back to the OpenWrt defaults.
#
#   Feed files are never touched before the target host is confirmed, so a
#   cancelled prompt always leaves the router working.

# ---------- defaults ----------
WORKER_DEFAULT_HOST="openwrt.daypass.workers.dev"
WORKER_UPSTREAM_HOST="downloads.openwrt.org"
WORKER_OPKG_FEEDS="/etc/opkg/distfeeds.conf"
WORKER_APK_REPOS="/etc/apk/repositories"

# ---------- Worker identity (must match config/worker.js) ----------
WORKER_HEALTH_PATH="/daypass-health"
WORKER_HEALTH_ID="daypass-openwrt"
WORKER_REPO_SLUG="${DAYPASS_HELP_REPO:-Chamroosh98/DayPass}"

# ---------- scratch ----------
WORKER_TMP="/tmp/daypass_worker.$$"
WORKER_STATE_DIR="${DAYPASS_DIR:-/etc/daypass}/worker"

# ------------------------------------------------------------
# UI helpers (printf keeps the art and user input literal)
# ------------------------------------------------------------
_wb_ok()   { printf '  %s[+] %s%s\n' "$GREEN"  "$1" "$RESET"; }
_wb_err()  { printf '  %s[x] %s%s\n' "$RED"    "$1" "$RESET"; }
_wb_info() { printf '  %s[i] %s%s\n' "$CYAN"   "$1" "$RESET"; }
_wb_warn() { printf '  %s[!] %s%s\n' "$YELLOW" "$1" "$RESET"; }
_wb_hint() { printf '      %s%s%s\n' "$GRAY"   "$1" "$RESET"; }

_wb_banner() {
    printf '  %s%s☁️ Cloudflare Worker Mirror%s\n' "$CYAN" "$BOLD" "$RESET"
    printf '  %s─────────────────────────────────────────────────────────%s\n' "$CYAN" "$RESET"
    printf '  %sPackage feeds are rewritten from %s%s\n' "$CYAN" "$WORKER_UPSTREAM_HOST" "$RESET"
    printf '  %sto your Worker so opkg / apk fetch through Cloudflare.%s\n' "$CYAN" "$RESET"
    printf '  %s─────────────────────────────────────────────────────────%s\n' "$CYAN" "$RESET"
    printf '\n'
}

_wb_header() {
    if command -v render_persistent_header >/dev/null 2>&1; then
        render_persistent_header
    fi
    _wb_banner
}

# $1 question — returns 0 only on an explicit yes
_wb_confirm() {
    local _answer=""

    printf '  %s⁉️ %s [y/N] :%s ' "$YELLOW" "$1" "$RESET"
    read -r _answer </dev/tty || return 1

    case "$_answer" in
        [yY]|[yY][eE][sS]) return 0 ;;
    esac
    return 1
}

# ------------------------------------------------------------
# Hostname handling
# ------------------------------------------------------------

# Strip scheme, path, port punctuation; keep a hostname suitable for sed.
_wb_normalize_host() {
    local _raw="$1"
    local _host

    _host="$_raw"
    _host="${_host#http://}"
    _host="${_host#https://}"
    _host="${_host%%/*}"
    _host="${_host%%:*}"
    _host="${_host#\[}"
    _host="${_host%\]}"

    printf '%s' "$_host"
}

# Reject empty / unsafe hostnames (sed delimiter and shell metacharacters).
_wb_valid_host() {
    local _host="$1"

    [ -n "$_host" ] || return 1

    case "$_host" in
        *[!A-Za-z0-9._-]*) return 1 ;;
        .*|*.|*..*)        return 1 ;;
        -*|*-)             return 1 ;;
        *.*)               ;;
        *)                 return 1 ;;
    esac

    return 0
}

_wb_default_host() {
    local _host

    _host="${WORKER_MIRROR_HOST:-$WORKER_DEFAULT_HOST}"
    _host="$(_wb_normalize_host "$_host")"

    if _wb_valid_host "$_host"; then
        printf '%s' "$_host"
    else
        printf '%s' "$WORKER_DEFAULT_HOST"
    fi
}

# ------------------------------------------------------------
# Feed files
# ------------------------------------------------------------

# Backup live config once; subsequent runs keep the original .bak intact.
_wb_backup_file() {
    local _src="$1"
    local _bak="$2"

    if [ ! -f "$_src" ]; then
        return 1
    fi

    if [ -f "$_bak" ]; then
        return 0
    fi

    if cp "$_src" "$_bak" 2>/dev/null; then
        _wb_ok "Backup saved → ${_bak}"
        return 0
    fi

    _wb_err "Failed to backup : [${_src}]"
    return 1
}

# Rewrite from the original backup (when present) so re-runs stay idempotent.
# http:// upstream entries become https:// because workers.dev is TLS only.
_wb_rewrite_file() {
    local _src="$1"
    local _host="$2"
    local _bak="${_src}.bak"
    local _base
    local _tmp

    if [ ! -f "$_src" ]; then
        return 1
    fi

    _base="$_src"
    [ -f "$_bak" ] && _base="$_bak"

    _tmp="${_src}.daypass.tmp"
    # BusyBox sed: '|' delimiter, no GNU-only flags.
    if ! sed -e "s|http://${WORKER_UPSTREAM_HOST}|https://${_host}|g" \
             -e "s|https://${WORKER_UPSTREAM_HOST}|https://${_host}|g" \
             "$_base" >"$_tmp" 2>/dev/null; then
        rm -f "$_tmp" 2>/dev/null
        _wb_err "Failed to rewrite : [${_src}]"
        return 1
    fi

    if ! mv "$_tmp" "$_src" 2>/dev/null; then
        rm -f "$_tmp" 2>/dev/null
        _wb_err "Failed to install rewritten : [${_src}]"
        return 1
    fi

    _wb_ok "Feeds updated → [${_src}]"
    return 0
}

_wb_restore_file() {
    local _src="$1"
    local _bak="${_src}.bak"

    if [ ! -f "$_bak" ]; then
        return 1
    fi

    if cp "$_bak" "$_src" 2>/dev/null; then
        _wb_ok "Restored default feeds → [${_src}]"
        return 0
    fi

    _wb_err "Failed to restore : [${_src}]"
    return 1
}

_wb_state_save() {
    local _host="$1"
    local _how="$2"

    mkdir -p "$WORKER_STATE_DIR" 2>/dev/null || return 0
    printf '%s\n' "$_host" > "$WORKER_STATE_DIR/host" 2>/dev/null
    printf '%s\n' "$_how"  > "$WORKER_STATE_DIR/source" 2>/dev/null
    return 0
}

# ------------------------------------------------------------
# HTTP helpers
# ------------------------------------------------------------
_wb_have_downloader() {
    command -v curl >/dev/null 2>&1 \
        || command -v wget >/dev/null 2>&1 \
        || command -v uclient-fetch >/dev/null 2>&1
}

# $1 url, $2 destination — curl, then wget, then uclient-fetch
_wb_http_fetch() {
    local _url="$1"
    local _dst="$2"

    rm -f "$_dst" 2>/dev/null

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 10 --max-time 60 "$_url" -o "$_dst" 2>/dev/null \
            && [ -s "$_dst" ] && return 0
    fi

    if command -v wget >/dev/null 2>&1; then
        rm -f "$_dst" 2>/dev/null
        wget -q -T 60 -O "$_dst" "$_url" 2>/dev/null && [ -s "$_dst" ] && return 0
    fi

    if command -v uclient-fetch >/dev/null 2>&1; then
        rm -f "$_dst" 2>/dev/null
        uclient-fetch -q -T 60 -O "$_dst" "$_url" 2>/dev/null && [ -s "$_dst" ] && return 0
    fi

    rm -f "$_dst" 2>/dev/null
    return 1
}

# Probe the Worker identity endpoint.
#   0 = genuine DayPass mirror, 2 = answered but not ours, 1 = no answer
_wb_health_probe() {
    local _host="$1"
    local _body="${WORKER_TMP}.health"
    local _rc=1

    if _wb_http_fetch "https://${_host}${WORKER_HEALTH_PATH}" "$_body"; then
        if tr -d ' \t\n\r' < "$_body" 2>/dev/null \
            | grep -qF "\"mirror\":\"${WORKER_HEALTH_ID}\""; then
            _rc=0
        else
            _rc=2
        fi
    elif _wb_http_fetch "https://${_host}/" "$_body"; then
        # Something is serving the host, just not our health endpoint.
        _rc=2
    fi

    rm -f "$_body" 2>/dev/null
    return "$_rc"
}

# Confirms a host BEFORE any feed file is touched.
_wb_gate_host() {
    local _host="$1"

    if ! _wb_have_downloader; then
        _wb_warn "No curl / wget / uclient-fetch — health check skipped."
        return 0
    fi

    _wb_info "Probing https://${_host}${WORKER_HEALTH_PATH} ..."
    _wb_health_probe "$_host"

    case "$?" in
        0)
            _wb_ok "Verified DayPass mirror (health check passed)."
            return 0
            ;;
        2)
            _wb_warn "Host answered, but it is not a DayPass mirror."
            _wb_hint "Use Deploy to Cloudflare, or continue if you"
            _wb_hint "know this host proxies ${WORKER_UPSTREAM_HOST}."
            _wb_confirm "Use [${_host}] anyway?" || return 1
            return 0
            ;;
        *)
            _wb_err "No answer from [${_host}] (network, TLS, or DNS)."
            _wb_hint "Feed files have not been touched."
            _wb_confirm "Rewrite the feeds anyway?" || return 1
            return 0
            ;;
    esac
}

# ------------------------------------------------------------
# Branch used for the raw worker.js link
# ------------------------------------------------------------
_wb_mirror_branch() {
    if command -v help_branch >/dev/null 2>&1; then
        help_branch
    else
        echo "main"
    fi
}

# Plain-text config/worker.js on the same branch as this installer.
_wb_worker_raw_url() {
    printf 'https://raw.githubusercontent.com/%s/%s/config/worker.js' \
        "$WORKER_REPO_SLUG" "$(_wb_mirror_branch)"
}

# ------------------------------------------------------------
# Public — roll feeds back to the backed-up OpenWrt endpoints
# ------------------------------------------------------------
worker_bootstrap_restore() {
    local _restored=0

    if [ -f "${WORKER_OPKG_FEEDS}.bak" ]; then
        _wb_restore_file "$WORKER_OPKG_FEEDS" && _restored=1
    fi

    if [ -f "${WORKER_APK_REPOS}.bak" ]; then
        _wb_restore_file "$WORKER_APK_REPOS" && _restored=1
    fi

    if [ "$_restored" -eq 1 ]; then
        rm -f "$WORKER_STATE_DIR/host" "$WORKER_STATE_DIR/source" 2>/dev/null
        _wb_ok "OpenWrt default endpoints restored (${WORKER_UPSTREAM_HOST})."
        return 0
    fi

    _wb_warn "No feed backups found — nothing to restore."
    _wb_hint "Feeds already point at ${WORKER_UPSTREAM_HOST} unless they were"
    _wb_hint "changed by hand."
    return 1
}

# ------------------------------------------------------------
# Public — apply a hostname to whichever feed files exist
# $1 host, $2 "verified" to skip the probe (already health-checked)
# ------------------------------------------------------------
worker_bootstrap_apply() {
    local _host="$1"
    local _mode="$2"
    local _changed=0
    local _failed=0

    _host="$(_wb_normalize_host "$_host")"

    if ! _wb_valid_host "$_host"; then
        _wb_err "Invalid Worker domain : [${_host}]"
        return 1
    fi

    if [ "$_mode" != "verified" ]; then
        if ! _wb_gate_host "$_host"; then
            _wb_warn "Cancelled — package feeds are unchanged."
            return 1
        fi
    fi

    if [ ! -f "$WORKER_OPKG_FEEDS" ] && [ ! -f "$WORKER_APK_REPOS" ]; then
        _wb_warn "No feed files found (${WORKER_OPKG_FEEDS} / ${WORKER_APK_REPOS})."
        return 1
    fi

    if [ -f "$WORKER_OPKG_FEEDS" ]; then
        if _wb_backup_file "$WORKER_OPKG_FEEDS" "${WORKER_OPKG_FEEDS}.bak" \
            && _wb_rewrite_file "$WORKER_OPKG_FEEDS" "$_host"; then
            _changed=1
        else
            _failed=1
        fi
    fi

    if [ -f "$WORKER_APK_REPOS" ]; then
        if _wb_backup_file "$WORKER_APK_REPOS" "${WORKER_APK_REPOS}.bak" \
            && _wb_rewrite_file "$WORKER_APK_REPOS" "$_host"; then
            _changed=1
        else
            _failed=1
        fi
    fi

    if [ "$_changed" -eq 0 ]; then
        _wb_err "No feed file could be updated."
        return 1
    fi

    if [ "$_failed" -eq 1 ]; then
        _wb_warn "Some feed files could not be updated."
        _wb_hint "Use option 3 to restore the OpenWrt defaults."
        return 1
    fi

    _wb_state_save "$_host" "${_mode:-import}"
    _wb_ok "Mirror host set → ${BOLD}https://${_host}/${RESET}"
    _wb_enqueue_curl
    return 0
}

# Feeds are reachable now, so pick up a full curl without blocking the menu.
_wb_enqueue_curl() {
    command -v curl >/dev/null 2>&1 && return 0

    if command -v opkg >/dev/null 2>&1; then
        (
            opkg update && opkg install curl ca-certificates
        ) </dev/null >/tmp/daypass_curl_setup.log 2>&1 &
        return 0
    fi

    if command -v apk >/dev/null 2>&1; then
        (
            apk add --no-progress curl ca-certificates
        ) </dev/null >/tmp/daypass_curl_setup.log 2>&1 &
    fi
    return 0
}

# ------------------------------------------------------------
# Menu 1 — import an existing Worker domain / URL
# ------------------------------------------------------------
worker_import_domain() {
    local _default
    local _input
    local _host

    _default="$(_wb_default_host)"

    printf '  %s🔗 Import Worker domain%s\n' "$BOLD" "$RESET"
    printf '  %s─────────────────────────────────────────────────────────%s\n' "$GRAY" "$RESET"
    _wb_hint "Accepted: my-worker.account.workers.dev, https://mirror.example.com"
    _wb_hint "The scheme, port and path are stripped automatically."
    printf '\n'
    printf '  %sWorker domain%s %s[default %s]%s : ' "$CYAN" "$RESET" "$GRAY" "$_default" "$RESET"
    read -r _input </dev/tty || return 1

    if [ -z "$_input" ]; then
        _host="$_default"
        _wb_info "Using default Worker domain : [${_host}]"
    else
        _host="$(_wb_normalize_host "$_input")"
    fi

    if ! _wb_valid_host "$_host"; then
        _wb_err "Invalid Worker domain : [${_input}]"
        _wb_hint "Expected a hostname such as daypass-mirror.acct.workers.dev"
        return 1
    fi

    if worker_bootstrap_apply "$_host"; then
        _wb_info "Package updates will now go through this mirror."
        return 0
    fi

    return 1
}

# ------------------------------------------------------------
# Menu 1 — paste the Worker in the Cloudflare dashboard. No network call.
# ------------------------------------------------------------
worker_browser_deploy() {
    local _url
    _url="$(_wb_worker_raw_url)"

    if command -v render_persistent_header >/dev/null 2>&1; then
        render_persistent_header
    fi

    printf '  %sDeploy to Cloudflare%s\n' "$BOLD" "$RESET"
    printf '\n'
    printf '  DayPass does not contact Cloudflare from this screen.\n'
    printf '\n'
    printf '  %s[i]%s 1. Dashboard → Workers & Pages → Create Application\n' "$CYAN" "$RESET"
    printf '          → Start with Hello World → Deploy.\n'
    printf '\n'
    printf '  %s[i]%s 2. Edit Code opens in the browser.\n' "$CYAN" "$RESET"
    printf '          Delete the Hello World placeholder, paste DayPass worker.js,\n'
    printf '          then Save and Deploy.\n'
    printf '\n'
    printf '  %s[i]%s 3. Cloudflare shows a *.workers.dev hostname.\n' "$CYAN" "$RESET"
    printf '\n'
    printf '  %s[i]%s 4. Come back here and choose Import Worker Domain / URL.\n' "$CYAN" "$RESET"
    printf '          Paste that hostname.\n'
    printf '\n'
    printf '  %s[i]%s Copy the script from this plain-text link (phone or PC):\n' "$CYAN" "$RESET"
    printf '\n'
    printf '  %s%s%s\n' "$CYAN" "$_url" "$RESET"
    printf '\n'
    return 0
}

# ------------------------------------------------------------
# Public — current state of the feed files
# ------------------------------------------------------------
worker_bootstrap_status() {
    local _file=""
    local _hit=""

    if [ -f "$WORKER_OPKG_FEEDS" ]; then
        _file="$WORKER_OPKG_FEEDS"
    elif [ -f "$WORKER_APK_REPOS" ]; then
        _file="$WORKER_APK_REPOS"
    fi

    if [ -z "$_file" ]; then
        _wb_warn "No package feed files present."
        return 0
    fi

    _hit="$(sed -n "s|.*https\{0,1\}://\([^/]*\)/.*|\1|p" "$_file" 2>/dev/null | head -n 1)"

    if [ -n "$_hit" ] && [ "$_hit" != "$WORKER_UPSTREAM_HOST" ]; then
        _wb_ok "Worker mirror active : [${_hit}]"
    else
        _wb_warn "Feeds still point at ${WORKER_UPSTREAM_HOST}."
    fi

    return 0
}

# ------------------------------------------------------------
# Public — interactive menu (never aborts the installer)
# ------------------------------------------------------------
worker_mirror_menu() {
    local _choice

    while true; do
        _wb_header
        worker_bootstrap_status
        printf '  %s─────────────────────────────────────────────────────────%s\n' "$GRAY" "$RESET"
        printf '  %s🔗 1)%s Deploy to Cloudflare\n' "$WHITE" "$RESET"
        printf '  %s📥 2)%s Import Worker Domain / URL\n' "$WHITE" "$RESET"
        printf '  %s🔄 3)%s Restore Default OpenWrt Feeds\n' "$WHITE" "$RESET"
        if command -v ui_nav_footer >/dev/null 2>&1; then
            ui_nav_footer
        fi
        printf '  ⁉️ Select option [0-3] : '

        if ! read -r _choice </dev/tty; then
            printf '\n'
            return 0
        fi

        printf '\n'

        case "$_choice" in
            1) worker_browser_deploy || true ;;
            2) worker_import_domain  || true ;;
            3) worker_bootstrap_restore || true ;;
            0|'') return 0 ;;
            q|Q)
                command -v daypass_quit >/dev/null 2>&1 && daypass_quit
                return 0
                ;;
            h|H)
                if command -v ui_show_help >/dev/null 2>&1; then
                    ui_show_help "worker_mirror"
                fi
                continue
                ;;
            *)
                _wb_warn "Invalid option!"
                ;;
        esac

        printf '\n  %sPress [Enter] to continue ...%s' "$GRAY" "$RESET"
        read -r _choice </dev/tty || return 0
    done
}

# Public — entry point used by the bootstrap wizard
worker_bootstrap_offer() {
    worker_mirror_menu
    return 0
}


# 📄 Source : wizard.sh

# Purpose:
#   Reach OpenWrt feeds through a local HTTP proxy, a Cloudflare Worker
#   mirror, or a direct connection. Startup skips this wizard when a
#   custom feed host or http_proxy is already set. The main menu can
#   open it later, and asks before overwriting that configuration.

# ---------- banner ----------
_nb_banner() {
    echo
    echo "  ${CYAN}${RESET}${BOLD}🌐 Network Bootstrap Wizard${RESET}"
    echo "  ${CYAN}─────────────────────────────────────────────────────────${RESET}"
    echo "  ${CYAN}${RESET}Choose how DayPass should reach package mirrors"
    echo "  ${CYAN}${RESET}before updating or installing software.          "
    echo "  ${CYAN}─────────────────────────────────────────────────────────${RESET}"
    echo
}

_nb_menu() {
    echo "  ${WHITE}🔌 1)${RESET} Configure Local HTTP/HTTPS Proxy"
    echo "  ${WHITE}☁️ 2)${RESET} Use Cloudflare Worker Mirror"
    echo "  ${WHITE}➡️ 3)${RESET} Proceed with Direct Connection ${DIM}(default)${RESET}"
    echo
}

# Official OpenWrt feed host. Anything else in the feed files is a custom mirror.
_BS_UPSTREAM_HOST="downloads.openwrt.org"

# $1 feed file. Prints the first non-official host.
_bs_custom_host_from() {
    _bs_file="$1"
    [ -f "$_bs_file" ] || return 1

    while IFS= read -r _bs_line || [ -n "$_bs_line" ]; do
        case "$_bs_line" in
            ''|'#'*) continue ;;
        esac
        case "$_bs_line" in
            *://*) ;;
            *) continue ;;
        esac
        _bs_host="${_bs_line#*://}"
        _bs_host="${_bs_host%%/*}"
        _bs_host="${_bs_host%% *}"
        case "$_bs_host" in
            ''|"$_BS_UPSTREAM_HOST") continue ;;
        esac
        printf '%s' "$_bs_host"
        return 0
    done < "$_bs_file"
    return 1
}

# Sets BOOTSTRAP_ACTIVE_URL (shown on skip) and BOOTSTRAP_ACTIVE_HOST (shown on overwrite).
bootstrap_detect_active() {
    BOOTSTRAP_ACTIVE_URL=""
    BOOTSTRAP_ACTIVE_HOST=""

    for _bs_feed in /etc/opkg/distfeeds.conf /etc/apk/repositories; do
        if _bs_host="$(_bs_custom_host_from "$_bs_feed")"; then
            BOOTSTRAP_ACTIVE_HOST="$_bs_host"
            BOOTSTRAP_ACTIVE_URL="https://${_bs_host}"
            return 0
        fi
    done

    _bs_proxy="${http_proxy:-${https_proxy:-${HTTP_PROXY:-${HTTPS_PROXY:-}}}}"
    if [ -n "$_bs_proxy" ]; then
        BOOTSTRAP_ACTIVE_URL="$_bs_proxy"
        _bs_host="${_bs_proxy#*://}"
        BOOTSTRAP_ACTIVE_HOST="${_bs_host%%/*}"
        return 0
    fi

    return 1
}

# Startup: skip the wizard when a mirror or proxy is already in place.
network_bootstrap_startup() {
    if bootstrap_detect_active; then
        return 0
    fi
    network_bootstrap_offer
    return 0
}

# Main-menu entry. Confirms before replacing a mirror or proxy that already works.
network_bootstrap_from_menu() {
    local _answer=""

    if bootstrap_detect_active; then
        render_persistent_header
        printf '  %s[!] Active configuration found: [%s]%s\n' "$YELLOW" "$BOOTSTRAP_ACTIVE_HOST" "$RESET"
        printf '  %s⁉️ Overwrite existing mirror settings?%s %s[y/N]%s : ' "$YELLOW" "$RESET" "$GRAY" "$RESET"
        if ! read -r _answer </dev/tty; then
            return 0
        fi
        case "$_answer" in
            y|Y) ;;
            *)
                printf '  %s[i] Current mirror kept.%s\n' "$GRAY" "$RESET"
                sleep 1
                return 0
                ;;
        esac
    fi

    network_bootstrap_offer
    return 0
}

# Public — interactive dispatcher (NEVER blocks / fails the pipeline)
network_bootstrap_offer() {
    local _choice

    while true; do
        render_persistent_header
        _nb_banner
        _nb_menu
        if command -v ui_nav_footer >/dev/null 2>&1; then
            ui_nav_footer
        fi
        printf "  How should package downloads be prepared? [1-3] : "
        if ! read -r _choice </dev/tty; then
            return 0
        fi

        case "$_choice" in
            h|H)
                if command -v ui_show_help >/dev/null 2>&1; then
                    ui_show_help "bootstrap_wizard"
                fi
                continue
                ;;
            q|Q)
                command -v daypass_quit >/dev/null 2>&1 && daypass_quit
                return 0
                ;;
            0)
                return 0
                ;;
        esac
        break
    done

    case "$_choice" in
        1)
            render_persistent_header
            _pb_banner
            proxy_bootstrap_setup
            ;;
        2)
            worker_bootstrap_offer
            ;;
        3|"")
            echo "${DIM}  [i] Direct connection — official OpenWrt endpoints unchanged.${RESET}"
            ;;
        *)
            echo "${YELLOW}  [!] Unknown choice — continuing with a direct connection.${RESET}"
            ;;
    esac

    return 0
}


# 📄 Source : arch_detector.sh

detect_system_architecture()
{
    log_info "Detecting system architecture and target platform ..."

    ARCH=""
    OPENWRT_VER=""
    PKG_MGR="${PKG_MANAGER:-opkg}"

    # 1. Fetch official OpenWrt architecture and release version
    if [ -f /etc/openwrt_release ]; then
        . /etc/openwrt_release
        ARCH="$DISTRIB_ARCH"
        OPENWRT_VER="$DISTRIB_RELEASE"
    elif [ -f /etc/os-release ]; then
        OPENWRT_VER=$(grep "BUILD_ID=" /etc/os-release | cut -d'"' -f2)
    fi

    # 2. Fallback to package manager native check
    if [ -z "$ARCH" ]; then
        if [ "$PKG_MGR" = "apk" ] && command -v apk >/dev/null 2>&1; then
            ARCH=$(apk --print-arch 2>/dev/null)
        elif command -v opkg >/dev/null 2>&1; then
            ARCH=$(opkg print-architecture 2>/dev/null | awk 'END {print $2}')
        fi
    fi

    # 3. Final Fallback
    if [ -z "$ARCH" ]; then
        ARCH=$(uname -m)
        log_warn "Standard OpenWrt release file unreadable! Fallback architecture : [$ARCH]"
    fi

    # 4. Extract MAJOR Version (24 vs 25)
    OW_MAJOR_VER="24"
    if echo "$OPENWRT_VER" | grep -q "^25" || [ "$PKG_MGR" = "apk" ]; then
        OW_MAJOR_VER="25"
    fi

    log_success "System architecture resolved : [$ARCH]"
    [ -n "$OPENWRT_VER" ] && log_info "OpenWrt Release version : [$OPENWRT_VER] (Major: v$OW_MAJOR_VER)"

    export ARCH
    export OPENWRT_VER
    export OW_MAJOR_VER
}

# Standalone execution handler for testing
case "$0" in
    *arch_detector.sh)
        detect_system_architecture
        ;;
esac

# 📄 Source : manager.sh

# Detect and initialize the active package manager engine (apk or opkg)
detect_package_manager()
{
    # Clear lock files across all supported OpenWrt releases
    rm -f /var/lock/opkg.lock /lib/apk/db/lock /var/run/apk.lock /run/apk/db.lock 2>/dev/null
    
    # 1. Identify standard package manager binary
    if command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
        log_info "Package manager identified : [apk] (Alpine/OpenWrt NextGen)" 2>/dev/null || echo "[INFO] Package manager: apk"
    elif command -v opkg >/dev/null 2>&1; then
        PKG_MANAGER="opkg"
        log_info "Package manager identified : [opkg] (Legacy OpenWrt)" 2>/dev/null || echo "[INFO] Package manager: opkg"
    else
        log_error "Critical Error : Neither 'apk' nor 'opkg' package manager was found!" 2>/dev/null || echo "[ERROR] No package manager found!"
        exit 1
    fi

    export PKG_MANAGER
}

# Update package index with fallback logic for network/mirror failures
pkg_update()
{
    [ -z "${PKG_MANAGER:-}" ] && detect_package_manager

    log_info "Updating package indexes using [$PKG_MANAGER] ..." 2>/dev/null || echo "[INFO] Updating package indexes..."

    if [ "$PKG_MANAGER" = "apk" ]; then
        # Standard update first; if IPv6/DNS issues occur, fall back to IPv4
        if ! apk update --network-timeout 5 >/dev/null 2>&1; then
            log_warn "Standard APK update failed/timed out! Attempting fallback via IPv4 ..." 2>/dev/null
            if ! apk update --force-ipv4 --network-timeout 5 >/dev/null 2>&1; then
                log_warn "APK update encountered repository warnings. Proceeding with local cache ..." 2>/dev/null
            else
                log_success "APK indexes updated successfully using IPv4 fallback." 2>/dev/null
            fi
        else
            log_success "APK package indexes updated successfully." 2>/dev/null
        fi

    elif [ "$PKG_MANAGER" = "opkg" ]; then
        if ! opkg update >/dev/null 2>&1; then
            log_warn "OPKG update encountered minor mirror warnings. Proceeding anyway ..." 2>/dev/null
        else
            log_success "OPKG package indexes updated successfully." 2>/dev/null
        fi
    fi
}

# Get currently installed version string of a specific package
pkg_get_installed_version()
{
    pkg="$1"
    [ -z "$pkg" ] && echo "" && return 1
    [ -z "${PKG_MANAGER:-}" ] && detect_package_manager

    if [ "$PKG_MANAGER" = "apk" ]; then
        if ! apk info -e "$pkg" >/dev/null 2>&1; then
            echo ""
            return 0
        fi
        ver=$(apk list --installed "$pkg" 2>/dev/null | awk '{print $1}' | sed "s/^$pkg-//")
        [ -z "$ver" ] && ver=$(apk info -v "$pkg" 2>/dev/null | sed -e "s/^$pkg-//" -e 's/ WARNING:.*//')
        echo "$ver"
    elif [ "$PKG_MANAGER" = "opkg" ]; then
        opkg status "$pkg" 2>/dev/null | awk '/^Version:/ {print $2}'
    fi
}

# 0 = a payload download is required, 1 = already installed and current.
# Concrete manifest versions that differ still download; unknown/"Latest"
# versions do not force a re-download of a package opkg/apk already has.
pkg_payload_required()
{
    _pp_pkg="$1"
    [ -n "$_pp_pkg" ] || return 0

    pkg_installed "$_pp_pkg" || return 0

    _pp_inst=$(pkg_get_installed_version "$_pp_pkg" 2>/dev/null | awk 'NR==1 { print $1 }')
    _pp_man=""
    if command -v manifest_lookup >/dev/null 2>&1 \
        && [ -n "${MANIFEST_FILE:-}" ] && [ -f "$MANIFEST_FILE" ]; then
        _pp_man=$(manifest_lookup "version" "$_pp_pkg" 2>/dev/null)
    fi

    case "$_pp_man" in
        ""|null|Latest|N/A) return 1 ;;
    esac

    [ "$_pp_inst" = "$_pp_man" ] && return 1
    case "$_pp_inst" in
        "${_pp_man}"-[0-9]*) return 1 ;;
    esac
    case "$_pp_man" in
        "${_pp_inst}"-[0-9]*) return 1 ;;
    esac
    return 0
}

# Check if target package is currently installed on host system
pkg_installed()
{
    PACKAGE_NAME="$1"
    [ -z "$PACKAGE_NAME" ] && return 1
    [ -z "${PKG_MANAGER:-}" ] && detect_package_manager

    if [ "$PKG_MANAGER" = "apk" ]; then
        apk info -e "$PACKAGE_NAME" >/dev/null 2>&1
    elif [ "$PKG_MANAGER" = "opkg" ]; then
        opkg status "$PACKAGE_NAME" 2>/dev/null | grep -q "Status: .* installed"
    fi
}

# Install a specific single package via system package manager
pkg_install()
{
    PACKAGE_NAME="$1"
    [ -z "$PACKAGE_NAME" ] && return 1
    [ -z "${PKG_MANAGER:-}" ] && detect_package_manager

    # log_info "Executing package installation : [$PACKAGE_NAME]" 2>/dev/null || echo "[INFO] Installing: $PACKAGE_NAME"

    if [ "$PKG_MANAGER" = "apk" ]; then
        # 1. Try standard installation with untrusted keyring bypass
        if apk add --no-cache --allow-untrusted "$PACKAGE_NAME" >/dev/null 2>&1; then
            log_success "[$PACKAGE_NAME]" 2>/dev/null
            return 0
        fi

        # 2. Fallback attempt using IPv4 explicit routing if network fails
        log_warn "Standard APK installation failed for [$PACKAGE_NAME]. Trying IPv4 fallback ..." 2>/dev/null
        if apk add --force-ipv4 --no-cache --allow-untrusted "$PACKAGE_NAME" >/dev/null 2>&1; then
            log_success "Package [$PACKAGE_NAME] installed successfully via APK (IPv4 fallback)." 2>/dev/null
            return 0
        fi

        log_error "APK failed to install package : [$PACKAGE_NAME]" 2>/dev/null
        return 1

    elif [ "$PKG_MANAGER" = "opkg" ]; then
        # Install with opkg bypassing unverified signature warnings
        if opkg install --force-checksum "$PACKAGE_NAME" >/dev/null 2>&1; then
            log_success "Package [$PACKAGE_NAME] installed successfully via OPKG!" 2>/dev/null
            return 0
        fi

        log_error "OPKG failed to install package : [$PACKAGE_NAME]" 2>/dev/null
        return 1
    fi
}

# 📄 Source : zero_deps.sh

# ---------------------------------------------------------------------------
# Required tool / package validation map :  "<package>:<binary-it-provides>"
#
# A binary probe lets us validate a tool even when the package database is
# unusable, and it is what decides "this tool is already here - do not install
# it again". Packages without an entry are validated through the package
# database only. Adding an entry makes the check stricter (and can skip more work).
# ---------------------------------------------------------------------------
TOOL_PROBE_MAP="curl:curl jq:jq unzip:unzip lua:lua"

# 1 when the package database can be queried, 0 when we must rely on probes only
PKG_DB_OK=0

# Echo the binary that provides a given package (empty when unknown)
tool_probe_for()
{
    for mapping in $TOOL_PROBE_MAP; do
        case "$mapping" in
            "$1:"*) echo "${mapping#*:}" ; return 0 ;;
        esac
    done
    echo ""
}

# Decide whether a single tool/package is already usable on this system.
# Returns 0 = present, 1 = missing ; TOOL_REASON explains the verdict to the user.
tool_is_available()
{
    TOOL_REASON=""
    probe="$(tool_probe_for "$1")"

    if [ -n "$probe" ] && command -v "$probe" >/dev/null 2>&1; then
        TOOL_REASON="present (binary [$probe] found)"
        return 0
    fi

    if [ "$PKG_DB_OK" -eq 1 ] && pkg_installed "$1"; then
        TOOL_REASON="present (package database)"
        return 0
    fi

    if [ -n "$probe" ]; then
        TOOL_REASON="missing (no [$probe] binary)"
    else
        TOOL_REASON="missing (not in package database)"
    fi
    return 1
}

# Scan every required package, print the validation table for the user and build
# MISSING_PACKAGES (only what actually has to be fetched from the network).
scan_required_tools()
{
    MISSING_PACKAGES=""
    PRESENT_COUNT=0
    MISSING_COUNT=0

    echo "  🔎 Required Tool Validation"
    echo "  ──────────────────────────────────────────────────────────"

    for pkg in $TARGET_PACKAGES; do
        if tool_is_available "$pkg"; then
            PRESENT_COUNT=$((PRESENT_COUNT + 1))
            printf "   ${GREEN}✔${RESET} %-26s ${GRAY}%s${RESET}\n" "$pkg" "$TOOL_REASON"
        else
            MISSING_COUNT=$((MISSING_COUNT + 1))
            MISSING_PACKAGES="$MISSING_PACKAGES $pkg"
            printf "   ${RED}✖${RESET} %-26s ${YELLOW}%s -> will install${RESET}\n" "$pkg" "$TOOL_REASON"
        fi
    done

    echo "  ───────────────────────────────────────────────────────────"
    printf "  Summary : %d tool(s) ready, %d missing\n" "$PRESENT_COUNT" "$MISSING_COUNT"
    echo
}

deploy_system_dependencies()
{
    detect_package_manager
    
    if [ -z "$OW_MAJOR_VER" ]; then
        if [ "$PKG_MANAGER" = "apk" ]; then
            OW_MAJOR_VER="25"
        else
            OW_MAJOR_VER="24"
        fi
    fi

    COMMON_DEPS="ca-bundle ca-certificates curl jq "
    OW24_EXTRA_DEPS="coreutils coreutils-base64 coreutils-nohup coreutils-timeout ip-full unzip resolveip lua libuci-lua luci-compat luci-lib-jsonc luci-lua-runtime lyaml"

    TARGET_PACKAGES="$COMMON_DEPS"

    if [ "$OW_MAJOR_VER" = "24" ] && [ "$PKG_MANAGER" = "opkg" ]; then
        log_info "OpenWrt v24 detected : adding core system & LuCI dependencies ..."
        TARGET_PACKAGES="$TARGET_PACKAGES $OW24_EXTRA_DEPS"
    else
        log_info "OpenWrt v$OW_MAJOR_VER detected : using the minimal base tool set."
    fi

    # The package-database helper decides HOW tools are validated : with it we can
    # also recognise packages that ship no binary (ca-bundle, luci-* modules...).
    PKG_DB_OK=0
    if command -v pkg_installed >/dev/null 2>&1; then
        PKG_DB_OK=1
    else
        log_warn "Package database helper [pkg_installed] unavailable : validating with binary probes only!"
    fi

    log_info "Checking which required tools are already installed ..."
    scan_required_tools

    DNSMASQ_FULL_MISSING=0
    if [ -f /etc/openwrt_release ] && [ "$PKG_DB_OK" -eq 1 ]; then
        if ! pkg_installed "dnsmasq-full"; then
            DNSMASQ_FULL_MISSING=1
        fi
    fi

    # Fast path : every required tool is already usable, so skip the index refresh
    # and the whole installation attempt.
    if [ -z "$MISSING_PACKAGES" ] && [ "$DNSMASQ_FULL_MISSING" -eq 0 ]; then
        log_success "All required tools are already installed - skipping installation!"
        return 0
    fi

    log_info "Setting up required system components for DayPass (OpenWrt v$OW_MAJOR_VER) ..."
    log_info "Tools queued for installation : [${MISSING_PACKAGES# }]"

    # Package manager output is kept (instead of being thrown away) so a failed
    # install can actually be diagnosed by the user.
    DEP_LOG="/tmp/daypass_deps_install.log"
    : > "$DEP_LOG" 2>/dev/null || DEP_LOG="/dev/null"

    (pkg_update >/dev/null 2>&1) &
    BG_PID=$!
    if command -v show_timer_progress >/dev/null 2>&1; then
        show_timer_progress "$BG_PID" "refreshing package index"
    fi
    wait "$BG_PID"

    if [ -n "$MISSING_PACKAGES" ]; then
        for pkg in $MISSING_PACKAGES; do
            (pkg_install "$pkg" >> "$DEP_LOG" 2>&1) &
            BG_PID=$!

            if command -v show_timer_progress >/dev/null 2>&1; then
                show_timer_progress "$BG_PID" "installing core tool [$pkg]"
            fi

            wait "$BG_PID"
            INSTALL_STATUS=$?

            if [ "$INSTALL_STATUS" -eq 0 ]; then
                log_success "Package [$pkg] installed successfully."
            else
                log_warn "Package [$pkg] failed or finished with warnings (exit $INSTALL_STATUS)."
                log_warn "Package manager log : [$DEP_LOG]"
            fi
        done
    fi

    # Post-install verification : never report success for a tool we cannot use.
    UNVERIFIED_TOOLS=""
    VERIFY_FAILED=0
    for pkg in $MISSING_PACKAGES; do
        if tool_is_available "$pkg"; then
            log_success "Verified : [$pkg] is ready! ($TOOL_REASON)"
        else
            probe="$(tool_probe_for "$pkg")"
            if [ -n "$probe" ]; then
                VERIFY_FAILED=1
                UNVERIFIED_TOOLS="$UNVERIFIED_TOOLS $pkg"
                log_error "Unverified : [$pkg] still has no [$probe] binary! ($TOOL_REASON)"
            else
                log_warn "Could not verify [$pkg] (no binary probe) - continuing anyway."
            fi
        fi
    done

    if [ "$DNSMASQ_FULL_MISSING" -eq 1 ]; then
        log_info "Checking dnsmasq installation status ..."
        (
            case "$PKG_MANAGER" in
                opkg)
                    opkg remove dnsmasq --force-depends >/dev/null 2>&1 || true
                    opkg install dnsmasq-full  --force-overwrite >/dev/null 2>&1 || true
                    ;;
                apk)
                    apk del dnsmasq >/dev/null 2>&1 || true
                    apk add --allow-untrusted dnsmasq-full  >/dev/null 2>&1 || true
                    ;;
            esac
        ) &
        
        BG_PID=$!
        if command -v show_timer_progress >/dev/null 2>&1; then
            show_timer_progress "$BG_PID" "optimizing DNS engine (dnsmasq-full)"
        fi
        wait "$BG_PID"
        
        echo "nameserver 8.8.8.8" > /tmp/resolv.conf.auto 2>/dev/null || true
        /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
        /etc/init.d/network reload >/dev/null 2>&1 || true
        sleep 2

        log_success "dnsmasq-full installed and DNS engine restarted successfully."
    elif [ "$PKG_DB_OK" -eq 1 ]; then
        log_success "dnsmasq-full is already present."
    fi

    # Final verdict : a required tool that still has no binary is a real failure,
    # not something to report as a success.
    if [ "$VERIFY_FAILED" -eq 1 ]; then
        log_warn "Some required tools could not be verified after installation :${UNVERIFIED_TOOLS}"
        log_warn "DayPass may not work correctly until they are installed."
        return 1
    fi

    log_success "All system dependencies configured successfully!"
}

# 📄 Source : arch_check.sh

check_version() {
    # Detect package manager
    PKG_MANAGER=""
    if command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
    elif command -v opkg >/dev/null 2>&1; then
        PKG_MANAGER="opkg"
    else
        log_error "No supported package manager (opkg/apk) found!"
        return 1
    fi
    export PKG_MANAGER

    # Read OpenWrt system version details
    OPENWRT_VERSION="$(
        . /etc/openwrt_release 2>/dev/null
        echo "$DISTRIB_RELEASE"
    )"

    # Extract major release number (e.g., 24 or 25)
    OPENWRT_MAJOR="$(echo "$OPENWRT_VERSION" | cut -d'.' -f1)"
    
    # Fallback detection for major version based on package manager if release parsing fails
    if [ -z "$OPENWRT_MAJOR" ]; then
        if [ "$PKG_MANAGER" = "apk" ]; then
            OPENWRT_MAJOR="25"
        else
            OPENWRT_MAJOR="24"
        fi
    fi
    export OPENWRT_MAJOR

    if [ -z "$OPENWRT_VERSION" ]; then
        log_warn "Unable to detect exact OpenWrt version!"
    else
        log_info "OpenWrt Version : ${OPENWRT_VERSION} (Engine : ${PKG_MANAGER})"
    fi
}

# 📄 Source : discover.sh
# DayPass - WAN interface discovery for the network info screen.

# $1 interface name. 0 when the name is a WAN (not wan6).
_net_name_is_wan() {
    case "$1" in
        wan6) return 1 ;;
        wan|wan_*|wwan|wwan_*) return 0 ;;
    esac
    return 1
}

# Record $1 once when it is an enabled IPv4 network interface.
_net_note_iface() {
    _ni="$1"
    [ -n "$_ni" ] || return 1
    case " $NET_SEEN " in
        *" $_ni "*) return 1 ;;
    esac
    [ "$(uci -q get "network.$_ni")" = "interface" ] || return 1
    [ "$(uci -q get "network.$_ni.disabled")" = "1" ] && return 1
    case "$(uci -q get "network.$_ni.proto")" in
        dhcpv6) return 1 ;;
    esac
    case "$_ni" in
        wan6) return 1 ;;
    esac
    NET_SEEN="$NET_SEEN $_ni"
    printf '%s\n' "$_ni"
    return 0
}

# Enabled WAN interfaces, one name per line.
# Firewall zone "wan", then wan / wan_* / wwan (wan_usb, wan_usb2, wan_lan2).
net_get_active_ifaces() {
    local i name nets net iface

    if command -v mwan_discover_ifaces >/dev/null 2>&1; then
        for iface in $(mwan_discover_ifaces); do
            [ "$(uci -q get "network.$iface.disabled")" = "1" ] && continue
            case "$(uci -q get "network.$iface.proto")" in
                dhcpv6) continue ;;
            esac
            printf '%s\n' "$iface"
        done
        return 0
    fi

    NET_SEEN=""
    i=0
    while uci -q get "firewall.@zone[$i]" >/dev/null 2>&1; do
        name=$(uci -q get "firewall.@zone[$i].name")
        if [ "$name" = "wan" ]; then
            nets=$(uci -q get "firewall.@zone[$i].network")
            for net in $nets; do
                _net_note_iface "$net" || true
            done
        fi
        i=$((i + 1))
        [ "$i" -gt 64 ] && break
    done

    for iface in $(uci show network 2>/dev/null | sed -n 's/^network\.\([A-Za-z0-9_]*\)=interface$/\1/p'); do
        _net_name_is_wan "$iface" || continue
        _net_note_iface "$iface" || true
    done
}

# Linux device for a UCI interface (pppoe l3 device, else UCI device).
# Prints the name. Returns 1 when none is known.
net_linux_dev() {
    local iface="$1"
    local dev=""

    if command -v ubus >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        dev=$(ubus call "network.interface.$iface" status 2>/dev/null | jq -r '.l3_device // .device // empty' 2>/dev/null)
    fi
    if [ -z "$dev" ] || [ "$dev" = "null" ]; then
        dev=$(uci -q get "network.$iface.device")
    fi
    if [ -z "$dev" ]; then
        dev=$(uci -q get "network.$iface.ifname")
    fi
    dev=${dev%% *}
    case "$dev" in
        ""|@*) return 1 ;;
    esac
    printf '%s\n' "$dev"
    return 0
}

# online / offline / unknown / n/a
net_mwan3_state() {
    local iface="$1"
    local line=""

    if ! command -v mwan3 >/dev/null 2>&1; then
        printf '%s\n' "n/a"
        return 0
    fi
    line=$(mwan3 status 2>/dev/null | grep -i "interface ${iface} is" | head -n 1)
    case "$line" in
        *[Oo]nline*) printf '%s\n' "online" ;;
        *[Oo]ffline*|*[Dd]own*) printf '%s\n' "offline" ;;
        *) printf '%s\n' "unknown" ;;
    esac
}


# 📄 Source : fetch.sh
# DayPass - Public IP lookup. curl only, bound to one Linux device.

# $1 country code
country_flag() {
    case "$1" in
        IR) printf '%s\n' "🦁☀️" ;;
        IL) printf '%s\n' "🇮🇱" ;;
        AZ) printf '%s\n' "🇦🇿" ;;
        DE) printf '%s\n' "🇩🇪" ;;
        US) printf '%s\n' "🇺🇸" ;;
        NL) printf '%s\n' "🇳🇱" ;;
        RU) printf '%s\n' "🇷🇺" ;;
        CN) printf '%s\n' "🇨🇳" ;;
        JP) printf '%s\n' "🇯🇵" ;;
        SG) printf '%s\n' "🇸🇬" ;;
        TR) printf '%s\n' "🇹🇷" ;;
        GB) printf '%s\n' "🇬🇧" ;;
        FR) printf '%s\n' "🇫🇷" ;;
        FI) printf '%s\n' "🇫🇮" ;;
        SE) printf '%s\n' "🇸🇪" ;;
        PL) printf '%s\n' "🇵🇱" ;;
        *)  printf '%s\n' "🌐" ;;
    esac
}

# $1 linux device. Prints success|ip|country|code|flag|city|isp|asn
# Bound to that device so mwan3 cannot move the query.
net_fetch_iface_ip() {
    local dev="$1"
    local json=""

    if [ -z "$dev" ] || [ ! -e "/sys/class/net/$dev" ]; then
        printf '%s\n' "false|||||||"
        return 1
    fi
    if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        printf '%s\n' "false|||||||"
        return 1
    fi

    json=$(curl -fsS --connect-timeout 2 --max-time 4 --interface "$dev" "https://ipwho.is/" 2>/dev/null || true)
    if printf '%s' "$json" | jq -e '.success == true' >/dev/null 2>&1; then
        printf '%s\n' "$json" | jq -r '"true|\(.ip // "")|\(.country // "")|\(.country_code // "")|\(.flag.emoji // "")|\(.city // "")|\(.connection.isp // "")|\(.connection.asn // "")"'
        return 0
    fi

    json=$(curl -fsS --connect-timeout 2 --max-time 4 --interface "$dev" "https://ipapi.co/json/" 2>/dev/null || true)
    if printf '%s' "$json" | jq -e '.ip != null and .ip != ""' >/dev/null 2>&1; then
        printf '%s\n' "$json" | jq -r '"true|\(.ip // "")|\(.country_name // "")|\(.country_code // "")||\(.city // "")|\(.org // "")|\(.asn // "")"'
        return 0
    fi

    printf '%s\n' "false|||||||"
    return 1
}


# 📄 Source : network_ip.sh
# DayPass - Network info screens. Printing only; no HTTP here.

# Display columns of $1. Emoji (4-byte UTF-8) count as 2. Never truncates.
_net_disp_width() {
    local s="$1" w=0 b n=0

    [ -n "$s" ] || { printf '%s\n' "0"; return 0; }
    for b in $(printf '%s' "$s" | od -An -tu1); do
        if [ "$n" -gt 0 ]; then
            n=$((n - 1))
            continue
        fi
        if [ "$b" -lt 128 ]; then
            w=$((w + 1))
        elif [ "$b" -lt 224 ]; then
            w=$((w + 1))
            n=1
        elif [ "$b" -lt 240 ]; then
            w=$((w + 1))
            n=2
        else
            w=$((w + 2))
            n=3
        fi
    done
    printf '%s\n' "$w"
}

# Append spaces so $1 reaches display width $2. Longer lines are kept whole.
_net_pad() {
    local s="$1" width="$2" w=0

    w=$(_net_disp_width "$s")
    while [ "$w" -lt "$width" ]; do
        s="$s "
        w=$((w + 1))
    done
    printf '%s\n' "$s"
}

# $1 uci name
_net_iface_icon() {
    case "$1" in
        wan_usb*) printf '%s\n' "📱" ;;
        wwan*)    printf '%s\n' "📶" ;;
        wan|wan_*) printf '%s\n' "🔌" ;;
        *)        printf '%s\n' "🌐" ;;
    esac
}

# One emoji, display width 2, so the tree colons stay aligned.
_net_provider_icon() {
    case "$1" in
        IR) printf '%s\n' "🦁" ;;
        "") printf '%s\n' "📶" ;;
        *)  country_flag "$1" ;;
    esac
}

# $1 interface count. Operations only; the shared footer is printed by the menu.
net_render_left_menu() {
    local count="${1:-0}"

    echo "  📋 Operations"
    echo "  ─────────────"
    echo "  📊 1) Live Speed Monitor"
    echo "  🔄 2) Refresh Information"
    if [ "$count" -gt 1 ]; then
        echo
        echo "  ⚖️ Multi-WAN"
        echo "  ─────────────"
        echo "  $count interfaces"
    fi
}

# $1 snapshot file. Each line:
# iface|dev|metric|mwan|success|ip|country|code|flag|city|isp|asn
net_render_right_tree() {
    local file="$1"
    local iface dev metric mwan success ip country code flag city isp asn
    local icon picon st_icon st_txt prov first=1

    if [ ! -s "$file" ]; then
        echo "  No WAN interface detected."
        return 0
    fi

    while IFS='|' read -r iface dev metric mwan success ip country code flag city isp asn; do
        [ -n "$iface" ] || continue
        if [ "$first" -eq 0 ]; then
            echo "  ─────────────"
        fi
        first=0

        icon=$(_net_iface_icon "$iface")
        picon=$(_net_provider_icon "$code")
        [ -n "$dev" ] || dev="-"
        [ -n "$metric" ] || metric="default"
        if [ "$success" = "true" ] && [ -n "$ip" ]; then
            :
        else
            ip="unavailable"
        fi
        [ -n "$isp" ] || isp="—"
        [ -n "$asn" ] || asn="—"
        prov="$isp [$asn]"

        case "$mwan" in
            online)  st_icon="🟢"; st_txt="Online" ;;
            offline) st_icon="🔴"; st_txt="Offline" ;;
            unknown) st_icon="🟡"; st_txt="Unknown" ;;
            *)       st_icon="⚪"; st_txt="Not tracked" ;;
        esac

        echo "  $icon $iface ($dev)"
        echo "  ├── 📍 IP       : $ip"
        echo "  ├── $picon Provider : $prov"
        echo "  └── $st_icon Status   : $st_txt (Metric $metric)"
    done < "$file"

    if [ "$first" -eq 1 ]; then
        echo "  No WAN interface detected."
    fi
}

# $1 left file  $2 right file  $3 display width of the left column
_net_zip_columns() {
    local leftf="$1" rightf="$2" width="$3"
    local l r gotl gotr

    while true; do
        l=""; r=""; gotl=0; gotr=0
        if IFS= read -r l <&3; then gotl=1; else l=""; fi
        if IFS= read -r r <&4; then gotr=1; else r=""; fi
        [ "$gotl" -eq 0 ] && [ "$gotr" -eq 0 ] && break
        l=$(_net_pad "$l" "$width")
        printf '%s │ %s\n' "$l" "$r"
    done 3<"$leftf" 4<"$rightf"
}

# $1 snapshot  $2 interface count  $3 optional note shown instead of the tree
net_render_columns() {
    local snap="$1" count="$2" note="$3"
    local left right

    left="/tmp/daypass_netleft.$$"
    right="/tmp/daypass_netright.$$"
    net_render_left_menu "$count" > "$left"
    if [ -n "$note" ]; then
        printf '  %s\n' "$note" > "$right"
    else
        net_render_right_tree "$snap" > "$right"
    fi
    _net_zip_columns "$left" "$right" 32
    rm -f "$left" "$right"
}


# 📄 Source : panel.sh
# DayPass - Collect WAN lookups, then draw the open two-column screen.
# The menu prints the global header and footer. This file does not.

# Fetch every active WAN into $1 (snapshot path). $2 is the interface count.
_net_fill_snapshot() {
    local snap="$1" count="$2" list="$3"
    local iface dev metric mwan data _net_pids _net_pid

    : > "$snap"
    [ "$count" -gt 0 ] || return 0

    if [ "$count" -le 1 ]; then
        iface=$(printf '%s\n' "$list" | head -n 1)
        dev=$(net_linux_dev "$iface" 2>/dev/null || true)
        metric=$(uci -q get "network.$iface.metric")
        [ -n "$metric" ] || metric="default"
        mwan=$(net_mwan3_state "$iface")
        data=$(net_fetch_iface_ip "$dev" 2>/dev/null || printf '%s\n' "false|||||||")
        printf '%s|%s|%s|%s|%s\n' "$iface" "$dev" "$metric" "$mwan" "$data" >> "$snap"
        return 0
    fi

    _net_pids=""
    for iface in $list; do
        dev=$(net_linux_dev "$iface" 2>/dev/null || true)
        metric=$(uci -q get "network.$iface.metric")
        [ -n "$metric" ] || metric="default"
        mwan=$(net_mwan3_state "$iface")
        printf '%s|%s|%s\n' "$dev" "$metric" "$mwan" > "/tmp/daypass_netsnap.$$.$iface.meta"
        net_fetch_iface_ip "$dev" > "/tmp/daypass_netsnap.$$.$iface" 2>/dev/null &
        _net_pids="$_net_pids $!"
    done
    for _net_pid in $_net_pids; do
        wait "$_net_pid" 2>/dev/null || true
    done
    for iface in $list; do
        IFS='|' read -r dev metric mwan <<EOF
$(cat "/tmp/daypass_netsnap.$$.$iface.meta" 2>/dev/null)
EOF
        data=$(cat "/tmp/daypass_netsnap.$$.$iface" 2>/dev/null)
        [ -n "$data" ] || data="false|||||||"
        printf '%s|%s|%s|%s|%s\n' "$iface" "$dev" "$metric" "$mwan" "$data" >> "$snap"
        rm -f "/tmp/daypass_netsnap.$$.$iface" "/tmp/daypass_netsnap.$$.$iface.meta"
    done
}

# Fetch every active WAN, then draw operations beside the tree.
net_show_panel() {
    local list count iface snap

    snap="/tmp/daypass_netsnap.$$"
    : > "$snap"

    if ! command -v curl >/dev/null 2>&1; then
        net_render_columns "$snap" 0 "curl is required for interface queries."
        rm -f "$snap"
        return 0
    fi
    if ! command -v jq >/dev/null 2>&1; then
        net_render_columns "$snap" 0 "jq is required to read provider details."
        rm -f "$snap"
        return 0
    fi

    list=$(net_get_active_ifaces)
    count=0
    for iface in $list; do
        count=$((count + 1))
    done

    _net_fill_snapshot "$snap" "$count" "$list"
    net_render_columns "$snap" "$count"
    rm -f "$snap"
}


# 📄 Source : speed.sh
# DayPass - Live download/upload rate on the first active WAN device.

net_monitor_live_speed() {
    local iface="" dev="" rx_prev tx_prev rx_now tx_now rx_speed tx_speed rx_fmt tx_fmt

    for iface in $(net_get_active_ifaces); do
        dev=$(net_linux_dev "$iface" 2>/dev/null || true)
        [ -n "$dev" ] && [ -d "/sys/class/net/$dev" ] && break
        dev=""
    done
    if [ -z "$dev" ]; then
        dev=$(ip route show default 2>/dev/null | awk '/default/ { print $5; exit }')
    fi
    if [ -z "$dev" ] || [ ! -d "/sys/class/net/$dev" ]; then
        echo "  📊 No WAN device to monitor."
        return 1
    fi

    echo
    echo "  📊 Live speed on $dev"
    echo "  Press Ctrl+C to stop."
    echo

    rx_prev=$(cat "/sys/class/net/$dev/statistics/rx_bytes" 2>/dev/null || echo 0)
    tx_prev=$(cat "/sys/class/net/$dev/statistics/tx_bytes" 2>/dev/null || echo 0)
    trap 'echo ""; trap - INT; return 0' INT

    while true; do
        sleep 1
        rx_now=$(cat "/sys/class/net/$dev/statistics/rx_bytes" 2>/dev/null || echo 0)
        tx_now=$(cat "/sys/class/net/$dev/statistics/tx_bytes" 2>/dev/null || echo 0)
        rx_speed=$(( (rx_now - rx_prev) / 1024 ))
        tx_speed=$(( (tx_now - tx_prev) / 1024 ))
        [ "$rx_speed" -lt 0 ] && rx_speed=0
        [ "$tx_speed" -lt 0 ] && tx_speed=0

        if [ "$rx_speed" -gt 1024 ]; then
            rx_fmt=$(awk "BEGIN { printf \"%.2f MB/s\", $rx_speed/1024 }")
        else
            rx_fmt="${rx_speed} KB/s"
        fi
        if [ "$tx_speed" -gt 1024 ]; then
            tx_fmt=$(awk "BEGIN { printf \"%.2f MB/s\", $tx_speed/1024 }")
        else
            tx_fmt="${tx_speed} KB/s"
        fi

        printf '\r  📥 Down: %s    📤 Up: %s   ' "$rx_fmt" "$tx_fmt"
        rx_prev=$rx_now
        tx_prev=$tx_now
    done
}


# 📄 Source : network_info.sh
# DayPass - Network info menu.
# Discovery, queries, screens, and the speed monitor live in
# discover.sh, fetch.sh, ui.sh, panel.sh, and speed.sh.

show_full_network_info() {
    net_show_panel
}

show_live_speed() {
    net_monitor_live_speed
}

network_info_menu() {
    local HELP_MODULE_ID="network_info"

    while true; do
        if command -v render_persistent_header >/dev/null 2>&1; then
            render_persistent_header
        fi
        show_full_network_info
        ui_nav_footer
        ui_prompt 2

        case "$UI_CHOICE" in
            q|Q) daypass_quit ;;
            h|H)
                if command -v show_help >/dev/null 2>&1; then
                    show_help "$HELP_MODULE_ID"
                else
                    log_warn "Help module not loaded!"
                    sleep 1
                fi
                continue
                ;;
            1) show_live_speed ;;
            2) continue ;;
            0) break ;;
            *)
                if command -v log_warn >/dev/null 2>&1; then
                    log_warn "Invalid choice!"
                else
                    echo "  Invalid choice!"
                fi
                ;;
        esac
    done
}

case "$0" in
    *network_info.sh)
        command -v ui_prompt >/dev/null 2>&1 || { echo "Run this menu from DayPass (install.sh)."; exit 1; }
        network_info_menu
        ;;
esac


# 📄 Source : recovery.sh

BACKUP_DNS_FILE="/etc/resolv.conf.daypass.bak"

# Apply temporary DNS fix for package managers (opkg/apk) and system resolution
apply_dns()
{
    NEW_DNS="${1:-1.1.1.1}"
    log_info "Setting temporary DNS to : [$NEW_DNS]"

    if [ -f /etc/resolv.conf ] || [ -L /etc/resolv.conf ]; then
        # Backup original resolv.conf structure if not already backed up
        if [ ! -f "$BACKUP_DNS_FILE" ]; then
            cp -a /etc/resolv.conf "$BACKUP_DNS_FILE" 2>/dev/null
            log_success "Original DNS backed up to : [$BACKUP_DNS_FILE]"
        fi

        # Unlink if /etc/resolv.conf is a symlink to prevent overwriting targets unexpectedly
        if [ -L /etc/resolv.conf ]; then
            rm -f /etc/resolv.conf
        fi

        # Write new nameserver directly for immediate resolution
        echo "nameserver $NEW_DNS" > /etc/resolv.conf
        
        # Optionally apply to UCI network configuration for persistence during setup
        if command -v uci >/dev/null 2>&1; then
            uci -q delete network.wan.dns 2>/dev/null || true
            uci -q add_list network.wan.dns="$NEW_DNS" 2>/dev/null || true
        fi

        log_success "DNS changed to : [$NEW_DNS]"
    fi
}

# Restore original DNS configuration from backup
restore_dns()
{
    if [ -f "$BACKUP_DNS_FILE" ]; then
        rm -f /etc/resolv.conf 2>/dev/null
        cp -a "$BACKUP_DNS_FILE" /etc/resolv.conf 2>/dev/null
        rm -f "$BACKUP_DNS_FILE" 2>/dev/null
        
        # Revert UCI changes if needed
        if command -v uci >/dev/null 2>&1; then
            uci -q delete network.wan.dns 2>/dev/null || true
        fi

        log_success "Original DNS restored successfully!"
    else
        log_warn "No DNS backup found to restore!"
    fi
}

# Interactive DNS resolution recovery menu
dns_fix_menu()
{
    local HELP_MODULE_ID="network_dns_recovery"

    while true; do
        render_persistent_header

        echo "  ───────────────────────────────────────────────────────────"
        echo "   📡 DNS Resolution Recovery                                "
        echo "  ───────────────────────────────────────────────────────────"
        echo "   ☁️ 1) Cloudflare DNS   (1.1.1.1)                          "
        echo "   🔍 2) Google DNS       (8.8.8.8)                          "
        echo "   🛡️ 3) Quad9 DNS        (9.9.9.9)                          "

        if [ -f "$BACKUP_DNS_FILE" ]; then
            echo "   4) 🔄 Restore Original DNS                           "
            echo "   5) 🚫 Skip                                           "
            MAX_OPT="5"
        else
            echo "   4) 🚫 Skip                                           "
            MAX_OPT="4"
        fi
        if command -v ui_nav_footer >/dev/null 2>&1; then
            ui_nav_footer
        fi

        printf "  ⁉️ Select option [1-%s] : " "$MAX_OPT"
        read -r dns_choice </dev/tty

        case "$dns_choice" in
            0) return 0 ;;
            q|Q)
                command -v daypass_quit >/dev/null 2>&1 && daypass_quit
                return 0
                ;;
            h|H)
                if command -v show_help >/dev/null 2>&1; then
                    show_help "$HELP_MODULE_ID"
                else
                    log_warn "Help module not loaded!"
                    sleep 1
                fi
                continue
                ;;
            1|"")
                apply_dns "1.1.1.1"
                ;;
            2)
                apply_dns "8.8.8.8"
                ;;
            3)
                apply_dns "9.9.9.9"
                ;;
            4)
                if [ -f "$BACKUP_DNS_FILE" ]; then
                    restore_dns
                else
                    log_info "Skipping DNS fix!"
                fi
                ;;
            5)
                log_info "Skipping DNS fix!"
                ;;
            *)
                log_info "Skipping DNS fix!"
                ;;
        esac
        return 0
    done
}

# Standalone execution handler
case "$0" in
    *dns_fix.sh) dns_fix_menu ;;
esac

# 📄 Source : lan_ip.sh

validate_ip()
{
    ip="$1"
    case "$ip" in
        ""|*[!0-9.]*) return 1 ;;
    esac

    O1=$(echo "$ip" | cut -d. -f1)
    O2=$(echo "$ip" | cut -d. -f2)
    O3=$(echo "$ip" | cut -d. -f3)
    O4=$(echo "$ip" | cut -d. -f4)

    [ -z "$O1" ] || [ -z "$O2" ] || [ -z "$O3" ] || [ -z "$O4" ] && return 1
    [ "$O1" -gt 255 ] || [ "$O2" -gt 255 ] || [ "$O3" -gt 255 ] || [ "$O4" -ge 255 ] && return 1
    [ "$O4" -le 0 ] && return 1

    return 0
}

change_lan_ip_menu()
{
    render_persistent_header

    CURRENT_IP=$(uci -q get network.lan.ipaddr || echo "192.168.1.1")
    CURRENT_NETMASK=$(uci -q get network.lan.netmask || echo "255.255.255.0")

    echo "  🌐 Local LAN IP Subnet Configuration"
    echo "  ───────────────────────────────────────────────────────────"
    echo "  ➡️ Current Router LAN IP : ${CYAN}${CURRENT_IP}${RESET}"
    echo "  ➡️ Current Netmask       : ${CYAN}${CURRENT_NETMASK}${RESET}"
    echo "  ───────────────────────────────────────────────────────────"
    echo "  ${GRAY}💡 Note : Changing LAN IP prevents IP Conflicts if your${RESET}"
    echo "  ${GRAY}upstream ISP Modem is also using 192.168.1.1 .${RESET}"
    echo "  ───────────────────────────────────────────────────────────"
    echo

    printf "  ⁉️ Do you want to change the Router LAN IP? [y/N] : "
    read -r confirm </dev/tty

    case "$confirm" in
        y|Y) ;;
        *)
            log_warn "LAN IP change cancelled!"
            sleep 1
            return 0
            ;;
    esac

    echo
    while true; do
        printf "  ✏️ Enter New LAN IP Address [e.g. 192.168.10.1] : "
        read -r NEW_IP </dev/tty

        if validate_ip "$NEW_IP"; then
            break
        else
            log_error "Invalid IP address format! Please try again!"
        fi
    done

    if [ "$NEW_IP" = "$CURRENT_IP" ]; then
        log_warn "New IP is identical to current IP. Nothing changed!"
        sleep 2
        return 0
    fi

    # Extract network prefix (first 3 octets)
    PREFIX=$(echo "$NEW_IP" | cut -d. -f1-3)

    log_info "Updating LAN IP address to [$NEW_IP] ..."

    # 1. Change LAN IP
    uci set network.lan.ipaddr="$NEW_IP"
    uci set network.lan.netmask="255.255.255.0"

    # 2. Update DHCP settings (important!)
    # Start from .100 and give 150 addresses (up to .249)
    uci set dhcp.lan.start="100"
    uci set dhcp.lan.limit="150"
    uci set dhcp.lan.leasetime="12h"

    # Make sure DHCP is enabled on lan
    uci set dhcp.lan.interface="lan"
    uci set dhcp.lan.ignore="0"

    uci commit network
    uci commit dhcp

    echo
    log_warn "NETWORK RESTART REQUIRED!"
    log_warn "After applying, your terminal/SSH session will disconnect!"
    log_warn "Reconnect using the new IP : ${GREEN}http://${NEW_IP}${RESET}"
    echo
    log_info "DHCP Pool will be : ${CYAN}${PREFIX}.100 - ${PREFIX}.249${RESET}"
    echo

    printf "  ⁉️ Apply changes now and restart network + DHCP? [y/N] : "
    read -r apply_confirm </dev/tty

    case "$apply_confirm" in
        y|Y)
            log_info "Clearing old DHCP leases ..."
            rm -f /tmp/dhcp.leases /tmp/hosts/dhcp* 2>/dev/null

            log_info "Restarting network and dnsmasq ..."
            (
                /etc/init.d/network restart >/dev/null 2>&1
                sleep 2
                /etc/init.d/dnsmasq restart >/dev/null 2>&1
            ) &

            log_success "LAN IP updated to $NEW_IP"
            log_success "DHCP pool set to ${PREFIX}.100 - ${PREFIX}.249"
            log_warn "Please reconnect your devices to get new IPv4 address!"
            exit 0
            ;;
        *)
            log_warn "Changes saved to UCI, but services were not restarted!"
            log_info "You can apply later with ==> /etc/init.d/network restart!"
            sleep 2
            ;;
    esac
}

# 📄 Source : deps.sh
# ============================================================
# DayPass - USB tethering package dependencies
# Checks and installs the kernel drivers and usbmuxd.
# Safe to source. Never calls exit.
# ============================================================

# "<package>:<lsmod name or binary>"
# usbmuxd is a userspace daemon; the others are kernel modules.
USB_TETHER_DEP_MAP="kmod-usb-net-rndis:rndis_host kmod-usb-net-cdc-ether:cdc_ether kmod-usb-net-ipheth:ipheth usbmuxd:usbmuxd"

# 0 when the package is installed, its module is loaded, or (usbmuxd) its binary exists.
# $1 package  $2 module or binary name
usb_dep_present() {
    _ud_pkg="$1"
    _ud_mod="$2"

    if [ "$_ud_pkg" = "usbmuxd" ] && command -v usbmuxd >/dev/null 2>&1; then
        return 0
    fi

    if command -v pkg_installed >/dev/null 2>&1 && pkg_installed "$_ud_pkg"; then
        return 0
    fi

    if [ "$_ud_pkg" != "usbmuxd" ] && [ -n "$_ud_mod" ] \
        && lsmod 2>/dev/null | grep -q "^${_ud_mod} "; then
        return 0
    fi

    return 1
}

# Prints missing package names, one per line. Returns 1 when any are missing.
usb_deps_missing() {
    _ud_missing=0

    for _ud_spec in $USB_TETHER_DEP_MAP; do
        _ud_pkg="${_ud_spec%%:*}"
        _ud_mod="${_ud_spec#*:}"
        if usb_dep_present "$_ud_pkg" "$_ud_mod"; then
            continue
        fi
        printf '%s\n' "$_ud_pkg"
        _ud_missing=1
    done

    return "$_ud_missing"
}

_usb_dep_update() {
    if command -v pkg_update >/dev/null 2>&1; then
        pkg_update >/dev/null 2>&1 || true
        return 0
    fi
    if command -v opkg >/dev/null 2>&1; then
        opkg update >/dev/null 2>&1 || true
        return 0
    fi
    if command -v apk >/dev/null 2>&1; then
        apk update >/dev/null 2>&1 || true
        return 0
    fi
    return 1
}

# $1 package. Returns 0 on install, 1 when every installer failed.
_usb_dep_install_one() {
    _ud_pkg="$1"

    if command -v pkg_install >/dev/null 2>&1; then
        pkg_install "$_ud_pkg" >/dev/null 2>&1 && return 0
    fi
    if command -v opkg >/dev/null 2>&1; then
        opkg install "$_ud_pkg" >/dev/null 2>&1 && return 0
    fi
    if command -v apk >/dev/null 2>&1; then
        apk add --allow-untrusted "$_ud_pkg" >/dev/null 2>&1 && return 0
    fi
    return 1
}

# $1 android | ios | modem | full
usb_driver_packages() {
    case "$1" in
        android)
            printf '%s\n' "kmod-usb-net-rndis kmod-usb-net-cdc-ether kmod-usb-net-cdc-ncm"
            ;;
        ios)
            printf '%s\n' "kmod-usb-net-ipheth usbmuxd"
            ;;
        modem)
            printf '%s\n' "kmod-usb-net-qmi-wwan kmod-usb-net-cdc-mbim kmod-usb-net-huawei-cdc-ncm usb-modeswitch usbutils"
            ;;
        full)
            printf '%s %s %s\n' \
                "$(usb_driver_packages android)" \
                "$(usb_driver_packages ios)" \
                "$(usb_driver_packages modem)"
            ;;
        *)
            return 1
            ;;
    esac
}

# Install one named set. Returns 1 when any package is still missing.
usb_install_driver_set() {
    _ud_set="$1"
    _ud_list=$(usb_driver_packages "$_ud_set") || return 1
    _ud_failed=0

    _usb_dep_update || true
    for _ud_pkg in $_ud_list; do
        _ud_mod=""
        case "$_ud_pkg" in
            usbmuxd) _ud_mod="usbmuxd" ;;
            kmod-usb-net-rndis) _ud_mod="rndis_host" ;;
            kmod-usb-net-cdc-ether) _ud_mod="cdc_ether" ;;
            kmod-usb-net-cdc-ncm) _ud_mod="cdc_ncm" ;;
            kmod-usb-net-ipheth) _ud_mod="ipheth" ;;
        esac
        usb_dep_present "$_ud_pkg" "$_ud_mod" && continue
        _usb_dep_install_one "$_ud_pkg" || _ud_failed=1
    done
    [ "$_ud_failed" -eq 0 ]
}

_usb_dep_remove_one() {
    _ud_pkg="$1"
    if command -v pkg_installed >/dev/null 2>&1 && ! pkg_installed "$_ud_pkg"; then
        return 0
    fi
    if command -v opkg >/dev/null 2>&1 && opkg remove "$_ud_pkg" >/dev/null 2>&1; then
        return 0
    fi
    if command -v apk >/dev/null 2>&1 && apk del "$_ud_pkg" >/dev/null 2>&1; then
        return 0
    fi
    command -v pkg_installed >/dev/null 2>&1 && ! pkg_installed "$_ud_pkg"
}

# Remove the Android, iOS and modem packages. Missing packages are fine.
usb_purge_driver_packages() {
    _ud_failed=0
    for _ud_pkg in $(usb_driver_packages full); do
        _usb_dep_remove_one "$_ud_pkg" || _ud_failed=1
    done
    [ "$_ud_failed" -eq 0 ]
}

usb_driver_menu() {
    while true; do
        if command -v render_persistent_header >/dev/null 2>&1; then
            render_persistent_header
        fi
        echo "  📌 USB drivers"
        echo "  📱 1) Android Drivers (RNDIS / CDC-Ether / NCM) "
        echo "  🍏 2) iPhone/iOS Drivers (ipheth & usbmuxd)"
        echo "  📦 3) Full Hardware Suite (Android + iOS + Modems)"
        if command -v ui_nav_footer >/dev/null 2>&1; then
            ui_nav_footer
        fi
        if command -v ui_read >/dev/null 2>&1; then
            ui_read "Select option"
        else
            printf "  Select option : "
            read -r UI_CHOICE </dev/tty || return 0
        fi
        case "$UI_CHOICE" in
            1)
                usb_install_driver_set android \
                    && log_success "Android USB drivers are installed." \
                    || log_warn "Some Android USB drivers could not be installed."
                ;;
            2)
                usb_install_driver_set ios \
                    && log_success "iPhone USB drivers are installed." \
                    || log_warn "Some iPhone USB drivers could not be installed."
                ;;
            3)
                usb_install_driver_set full \
                    && log_success "Full USB hardware suite is installed." \
                    || log_warn "Some USB packages could not be installed."
                ;;
            0|'') return 0 ;;
            q|Q)
                command -v daypass_quit >/dev/null 2>&1 && daypass_quit
                return 0
                ;;
            h|H)
                command -v ui_show_help >/dev/null 2>&1 && ui_show_help "hardware"
                ;;
            *) log_warn "Invalid option!" ;;
        esac
        command -v ui_pause >/dev/null 2>&1 && ui_pause
    done
}

# Silent check. Installs only what is missing.
# Returns 0 when every dependency is present afterwards, 1 otherwise.
# Does not exit the caller.
ensure_usb_tether_deps() {
    _ud_missing=""
    _ud_failed=0

    for _ud_spec in $USB_TETHER_DEP_MAP; do
        _ud_pkg="${_ud_spec%%:*}"
        _ud_mod="${_ud_spec#*:}"
        usb_dep_present "$_ud_pkg" "$_ud_mod" && continue
        _ud_missing="$_ud_missing $_ud_pkg"
    done

    [ -n "$_ud_missing" ] || return 0

    _usb_dep_update || true

    for _ud_pkg in $_ud_missing; do
        _usb_dep_install_one "$_ud_pkg" || _ud_failed=1
    done

    for _ud_spec in $USB_TETHER_DEP_MAP; do
        _ud_pkg="${_ud_spec%%:*}"
        _ud_mod="${_ud_spec#*:}"
        usb_dep_present "$_ud_pkg" "$_ud_mod" || _ud_failed=1
    done

    [ "$_ud_failed" -eq 0 ]
}


# 📄 Source : detect.sh
# ============================================================
# DayPass - USB network interface detection
# Scans /sys/class/net and dmesg. Safe to source. Never calls exit.
# ============================================================

# Kernel driver bound to a network device. Returns 1 when not USB-backed.
usb_net_driver() {
    local dev="$1"
    local path

    path=$(readlink -f "/sys/class/net/$dev/device" 2>/dev/null)
    case "$path" in
        */usb*) ;;
        *) return 1 ;;
    esac

    path=$(readlink -f "/sys/class/net/$dev/device/driver" 2>/dev/null)
    [ -n "$path" ] || return 1
    printf '%s\n' "${path##*/}"
}

# Lines: device|driver|kind   (kind: tether | modem | usbnet)
usb_net_interfaces() {
    local path dev driver kind

    for path in /sys/class/net/*; do
        [ -e "$path" ] || continue
        dev="${path##*/}"
        driver=$(usb_net_driver "$dev") || continue

        case "$driver" in
            rndis_host|cdc_ether|cdc_ncm|cdc_eem|cdc_subset|ipheth) kind="tether" ;;
            qmi_wwan|cdc_mbim|huawei_cdc_ncm|sierra_net)            kind="modem" ;;
            *)                                                        kind="usbnet" ;;
        esac
        printf '%s|%s|%s\n' "$dev" "$driver" "$kind"
    done
}

# Tethering devices from sysfs, one per line. Returns 1 when none exist.
usb_tether_interfaces() {
    local dev

    dev=$(usb_net_interfaces | awk -F'|' '$3 == "tether" { print $1 }')
    [ -n "$dev" ] || return 1
    printf '%s\n' "$dev"
    return 0
}

# Interface names dmesg registered under a USB network driver.
# Returns 1 when dmesg has no usable USB net device.
usb_dmesg_interfaces() {
    local line word out=""

    while IFS= read -r line; do
        case "$line" in
            *rndis_host*|*cdc_ether*|*cdc_ncm*|*cdc_eem*|*ipheth*) ;;
            *) continue ;;
        esac
        for word in $line; do
            word="${word%%:*}"
            word="${word%%,*}"
            case "$word" in
                usb[0-9]*|eth[0-9]*|rndis[0-9]*|enx*)
                    [ -e "/sys/class/net/$word" ] || continue
                    case " $out " in
                        *" $word "*) ;;
                        *) out="$out $word" ;;
                    esac
                    ;;
            esac
        done
    done <<EOF
$(dmesg 2>/dev/null)
EOF

    out=${out# }
    [ -n "$out" ] || return 1
    for word in $out; do
        printf '%s\n' "$word"
    done
    return 0
}

# First tethering device: sysfs, then dmesg, then well-known names.
# Prints the name and returns 0, or returns 1 when nothing is present.
detect_usb_device() {
    local dev

    dev=$(usb_tether_interfaces 2>/dev/null | head -n 1)
    if [ -n "$dev" ]; then
        printf '%s\n' "$dev"
        return 0
    fi

    dev=$(usb_dmesg_interfaces 2>/dev/null | head -n 1)
    if [ -n "$dev" ]; then
        printf '%s\n' "$dev"
        return 0
    fi

    for dev in usb0 usb1 rndis0; do
        if [ -e "/sys/class/net/$dev" ]; then
            printf '%s\n' "$dev"
            return 0
        fi
    done

    return 1
}

# Lines: "vid:pid name" for every non-hub USB device
usb_device_list() {
    local d vid pid name

    if command -v lsusb >/dev/null 2>&1; then
        lsusb 2>/dev/null | grep -v "1d6b:" | sed 's/^Bus [0-9]* Device [0-9]*: ID //'
        return 0
    fi

    for d in /sys/bus/usb/devices/*; do
        [ -f "$d/idVendor" ] || continue
        vid=$(cat "$d/idVendor")
        [ "$vid" = "1d6b" ] && continue
        pid=$(cat "$d/idProduct" 2>/dev/null)
        name="$(cat "$d/manufacturer" 2>/dev/null) $(cat "$d/product" 2>/dev/null)"
        printf '%s:%s %s\n' "$vid" "$pid" "${name# }"
    done
}

# 0 when a phone is attached as MTP/PTP and no tethering interface exists.
usb_mtp_waiting() {
    local cls drv

    if usb_tether_interfaces >/dev/null 2>&1; then
        return 1
    fi
    if [ -e /sys/class/net/usb0 ]; then
        return 1
    fi

    for cls in /sys/bus/usb/devices/*/bInterfaceClass; do
        [ -f "$cls" ] || continue
        case "$(cat "$cls" 2>/dev/null)" in
            06|6) return 0 ;;
        esac
    done

    for drv in /sys/bus/usb/devices/*/driver; do
        [ -L "$drv" ] || continue
        case "$(readlink "$drv" 2>/dev/null)" in
            *mtp*|*f_mtp*) return 0 ;;
        esac
    done
    return 1
}

# Modem control / serial ports (QMI, MBIM, AT)
usb_modem_ports() {
    ls /dev/cdc-wdm* /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | tr '\n' ' '
}


# 📄 Source : usb_wan.sh
# ============================================================
# DayPass - USB WAN network handler
# Loads deps.sh and detect.sh, then binds the detected USB
# device as a WAN interface in /etc/config/network.
# Safe to source. Never calls exit.
# ============================================================

USB_WAN_IFACE="wan_usb"
USB_WAN_DEFAULT_METRIC="20"

# Directory of this file when it is sourced on its own.
# The generated installer already defined the functions, so the
# lookup is skipped in that case.
_usb_module_dir() {
    local dir

    if [ -n "${DAYPASS_USB_DIR:-}" ] && [ -f "$DAYPASS_USB_DIR/deps.sh" ]; then
        printf '%s\n' "$DAYPASS_USB_DIR"
        return 0
    fi

    dir=$(CDPATH= cd -- "$(dirname "$0")" >/dev/null 2>&1 && pwd)
    if [ -n "$dir" ] && [ -f "$dir/deps.sh" ]; then
        printf '%s\n' "$dir"
        return 0
    fi

    for dir in modules/network/interfaces/usb "$(pwd)/modules/network/interfaces/usb"; do
        if [ -f "$dir/deps.sh" ]; then
            printf '%s\n' "$dir"
            return 0
        fi
    done
    return 1
}

# $1 function that proves the module is loaded, $2 filename
_usb_require() {
    local fn="$1"
    local file="$2"
    local dir

    command -v "$fn" >/dev/null 2>&1 && return 0
    dir=$(_usb_module_dir) || return 1
    [ -f "$dir/$file" ] || return 1
    # shellcheck source=/dev/null
    . "$dir/$file"
}

_usb_require ensure_usb_tether_deps deps.sh || true
_usb_require detect_usb_device detect.sh || true

_usb_wan_zone() {
    uci -q show firewall | sed -n "s/^firewall\.\([^.]*\)\.name='wan'$/\1/p" | head -n 1
}

usb_wan_exists() {
    [ "$(uci -q get network.$USB_WAN_IFACE)" = "interface" ]
}

# enabled | disabled | absent
usb_wan_state() {
    usb_wan_exists || { echo "absent"; return 0; }
    if [ "$(uci -q get network.$USB_WAN_IFACE.disabled)" = "1" ]; then
        echo "disabled"
    else
        echo "enabled"
    fi
}

# Create or update USB tethering WAN interface.
# Usage: setup_usb_wan [device] [metric]
# Returns 0 when the UCI interface is written, 1 when UCI is unavailable.
setup_usb_wan() {
    local usb_dev="${1:-}"
    local metric="${2:-$USB_WAN_DEFAULT_METRIC}"
    local zone
    local usb_guessed=0

    log_info "Setting up USB Tethering WAN interface ..."

    if command -v ensure_usb_tether_deps >/dev/null 2>&1; then
        ensure_usb_tether_deps || log_warn "Some USB tethering packages could not be installed."
    else
        log_warn "USB dependency module is not loaded."
    fi

    if [ -z "$usb_dev" ]; then
        if command -v detect_usb_device >/dev/null 2>&1; then
            usb_dev=$(detect_usb_device) || usb_dev=""
        fi
    fi

    if [ -z "$usb_dev" ]; then
        log_warn "No USB tethering device detected."
        log_warn "Connect your phone and enable USB Tethering first."
        usb_dev="usb0"
        usb_guessed=1
    else
        log_success "Using USB device : $usb_dev"
    fi

    command -v uci >/dev/null 2>&1 || { log_error "uci is not available."; return 1; }

    uci set network.$USB_WAN_IFACE=interface
    uci set network.$USB_WAN_IFACE.proto='dhcp'
    uci set network.$USB_WAN_IFACE.device="$usb_dev"
    uci set network.$USB_WAN_IFACE.metric="$metric"
    uci -q delete network.$USB_WAN_IFACE.disabled
    uci commit network || return 1

    zone=$(_usb_wan_zone)
    if [ -n "$zone" ]; then
        uci -q del_list firewall.$zone.network="$USB_WAN_IFACE"
        uci add_list firewall.$zone.network="$USB_WAN_IFACE"
        uci commit firewall
        /etc/init.d/firewall reload >/dev/null 2>&1 || true
    else
        log_warn "Firewall zone [wan] not found; add [$USB_WAN_IFACE] to your WAN zone manually."
    fi

    ifup $USB_WAN_IFACE >/dev/null 2>&1 || true
    if [ "$usb_guessed" -eq 1 ]; then
        log_warn "USB WAN interface [$USB_WAN_IFACE] configured for device [$usb_dev], but no USB device is connected yet. Plug in your phone with tethering enabled, then re-run Setup (or use Refresh) to pick it up."
    else
        log_success "USB WAN interface [$USB_WAN_IFACE] is ready (device $usb_dev, metric $metric)!"
    fi
    return 0
}

# Usage: usb_wan_set_enabled 1|0
usb_wan_set_enabled() {
    usb_wan_exists || { log_warn "USB WAN [$USB_WAN_IFACE] is not configured."; return 1; }

    if [ "$1" = "1" ]; then
        uci -q delete network.$USB_WAN_IFACE.disabled
        uci commit network || return 1
        ifup $USB_WAN_IFACE >/dev/null 2>&1 || true
        log_success "USB WAN [$USB_WAN_IFACE] enabled."
    else
        ifdown $USB_WAN_IFACE >/dev/null 2>&1 || true
        uci set network.$USB_WAN_IFACE.disabled='1'
        uci commit network || return 1
        log_success "USB WAN [$USB_WAN_IFACE] disabled."
    fi
    return 0
}

# Right column. Hardware, interfaces, and metrics as one tree.
# No header, footer, or outer border; the hardware menu prints those.
usb_render_status_tree() {
    local hw ifs list line dev driver kind metric icon
    local n total i name

    echo "  🔌 Hardware"
    hw=$(usb_device_list 2>/dev/null | head -n 3)
    n=0
    if [ -n "$hw" ]; then
        n=$(printf '%s\n' "$hw" | grep -c .)
    fi
    total=$n
    if command -v usb_mtp_waiting >/dev/null 2>&1 && usb_mtp_waiting; then
        total=$((total + 1))
    fi
    if [ "$total" -eq 0 ]; then
        echo "  └── 🔌 none"
    else
        i=0
        if [ -n "$hw" ]; then
            printf '%s\n' "$hw" | while IFS= read -r line; do
                [ -n "$line" ] || continue
                i=$((i + 1))
                if [ "$i" -eq "$total" ]; then
                    echo "  └── 🔌 $line"
                else
                    echo "  ├── 🔌 $line"
                fi
            done
        fi
        if [ "$total" -gt "$n" ]; then
            echo "  └── 📶 Enable USB tethering on the phone"
        fi
    fi

    echo "  ─────────────"
    echo "  📱 Interfaces"
    ifs=$(usb_net_interfaces 2>/dev/null | head -n 4)
    n=0
    if [ -n "$ifs" ]; then
        n=$(printf '%s\n' "$ifs" | grep -c .)
    fi
    if [ "$n" -eq 0 ]; then
        echo "  └── 📱 none"
    else
        i=0
        printf '%s\n' "$ifs" | while IFS='|' read -r dev driver kind; do
            [ -n "$dev" ] || continue
            i=$((i + 1))
            case "$kind" in
                modem) icon="📟" ;;
                *)     icon="📱" ;;
            esac
            if [ "$i" -eq "$n" ]; then
                echo "  └── $icon $dev"
                echo "      ├── 🔧 Driver : $driver"
                echo "      └── 📶 Kind   : $kind"
            else
                echo "  ├── $icon $dev"
                echo "  │   ├── 🔧 Driver : $driver"
                echo "  │   └── 📶 Kind   : $kind"
            fi
        done
    fi

    echo "  ─────────────"
    echo "  ⚖️ Metrics"
    list=""
    if command -v usb_metric_ifaces >/dev/null 2>&1; then
        list=$(usb_metric_ifaces 2>/dev/null | head -n 6)
    fi
    n=0
    if [ -n "$list" ]; then
        n=$(printf '%s\n' "$list" | grep -c .)
    fi
    if [ "$n" -eq 0 ]; then
        echo "  └── ⚖️ none"
    else
        i=0
        for line in $list; do
            i=$((i + 1))
            metric=$(uci -q get "network.$line.metric")
            [ -n "$metric" ] || metric="-"
            if command -v _net_iface_icon >/dev/null 2>&1; then
                icon=$(_net_iface_icon "$line")
            else
                icon="🌐"
            fi
            name="$line"
            while [ "${#name}" -lt 12 ]; do
                name="$name "
            done
            if [ "$i" -eq "$n" ]; then
                echo "  └── $icon $name : $metric"
            else
                echo "  ├── $icon $name : $metric"
            fi
            [ "$i" -ge 6 ] && break
        done
    fi
}

# WAN-like UCI interfaces, one name per line.
usb_metric_ifaces() {
    local iface

    uci show network 2>/dev/null | sed -n 's/^network\.\([A-Za-z0-9_]*\)=interface$/\1/p' | while IFS= read -r iface; do
        case "$iface" in
            wan*|wwan*) printf '%s\n' "$iface" ;;
        esac
    done
}

# Interactive metric editor. Lower metric is preferred. Never calls exit.
usb_metric_menu() {
    local list count i iface metric current

    while true; do
        if command -v render_persistent_header >/dev/null 2>&1; then
            render_persistent_header
        fi
        echo "  WAN metrics"
        echo "  Lower metric is preferred."
        echo
        list=$(usb_metric_ifaces)
        count=0
        if [ -n "$list" ]; then
            i=1
            for iface in $list; do
                metric=$(uci -q get "network.$iface.metric")
                [ -n "$metric" ] || metric="default"
                if [ "$(uci -q get "network.$iface.disabled")" = "1" ]; then
                    printf "  %s) %-12s metric %-8s disabled\n" "$i" "$iface" "$metric"
                else
                    printf "  %s) %-12s metric %-8s enabled\n" "$i" "$iface" "$metric"
                fi
                i=$((i + 1))
                count=$((count + 1))
            done
        else
            echo "  No WAN interfaces found."
        fi
        if command -v ui_nav_footer >/dev/null 2>&1; then
            ui_nav_footer
        fi
        if command -v ui_read >/dev/null 2>&1; then
            ui_read "Select option"
        else
            printf "  Select option : "
            read -r UI_CHOICE </dev/tty || return 0
        fi

        case "$UI_CHOICE" in
            0|'') return 0 ;;
            q|Q)
                command -v daypass_quit >/dev/null 2>&1 && daypass_quit
                return 0
                ;;
            h|H)
                command -v ui_show_help >/dev/null 2>&1 && ui_show_help "hardware"
                continue
                ;;
        esac

        case "$UI_CHOICE" in
            *[!0-9]*) log_warn "Invalid option!"; continue ;;
        esac
        [ "$UI_CHOICE" -ge 1 ] && [ "$UI_CHOICE" -le "$count" ] || { log_warn "Invalid option!"; continue; }

        i=1
        iface=""
        for iface in $list; do
            [ "$i" = "$UI_CHOICE" ] && break
            i=$((i + 1))
        done

        current=$(uci -q get "network.$iface.metric")
        if command -v ui_read >/dev/null 2>&1; then
            ui_read "Metric for $iface [${current:-20}]"
        else
            printf "  Metric for %s : " "$iface"
            read -r UI_CHOICE </dev/tty || return 0
        fi
        case "$UI_CHOICE" in
            0|'') continue ;;
            q|Q)
                command -v daypass_quit >/dev/null 2>&1 && daypass_quit
                return 0
                ;;
            '') UI_CHOICE="${current:-20}" ;;
        esac
        usb_wan_set_metric "$iface" "$UI_CHOICE" || true
        command -v ui_pause >/dev/null 2>&1 && ui_pause
    done
}

# Usage: usb_wan_set_metric <interface> <metric>
usb_wan_set_metric() {
    local iface="$1"
    local metric="$2"

    case "$metric" in
        ''|*[!0-9]*) log_error "Invalid metric [$metric]!"; return 1 ;;
    esac
    [ "$(uci -q get network.$iface)" = "interface" ] || { log_error "Interface [$iface] not found!"; return 1; }

    uci set network.$iface.metric="$metric"
    uci commit network || return 1
    if [ "$(uci -q get network.$iface.disabled)" != "1" ]; then
        ifup "$iface" >/dev/null 2>&1 || true
    fi
    log_success "Metric of [$iface] set to $metric."
    return 0
}

remove_usb_wan() {
    local zone

    usb_wan_exists || { log_warn "USB WAN [$USB_WAN_IFACE] is not configured."; return 0; }

    ifdown $USB_WAN_IFACE >/dev/null 2>&1 || true
    uci -q delete network.$USB_WAN_IFACE
    uci commit network || return 1

    zone=$(_usb_wan_zone)
    if [ -n "$zone" ]; then
        uci -q del_list firewall.$zone.network="$USB_WAN_IFACE"
        uci commit firewall || true
        /etc/init.d/firewall reload >/dev/null 2>&1 || true
    fi
    log_success "USB WAN [$USB_WAN_IFACE] removed."
    return 0
}


# 📄 Source : restore.sh
# ============================================================
# DayPass - Restore / reset USB tethering
# Removes wan_usb from network and firewall, restarts the
# network service, and can uninstall the USB driver packages.
# Safe to source. Never calls exit.
# ============================================================

# 0 only on an explicit yes. Enter is No.
usb_restore_confirm() {
    local answer=""

    printf "  ⁉️ Are you sure you want to restore all USB network configurations to default? [y/N] : "
    if ! read -r answer </dev/tty; then
        return 1
    fi
    case "$answer" in
        y|Y|yes|YES) return 0 ;;
    esac
    return 1
}

# Drop wan_usb, its device binding, and its firewall zone membership.
# Returns 0 when the sections are gone, 1 when uci commit fails.
usb_restore_uci() {
    local zone dev

    dev=""
    if [ "$(uci -q get network.wan_usb)" = "interface" ]; then
        dev=$(uci -q get network.wan_usb.device)
        ifdown wan_usb >/dev/null 2>&1 || true
        uci -q delete network.wan_usb
    fi

    if [ -n "$dev" ]; then
        for zone in $(uci -q show network | sed -n "s/^network\.\([^.]*\)=device$/\1/p"); do
            if [ "$(uci -q get network.$zone.name)" = "$dev" ]; then
                uci -q delete network.$zone
            fi
        done
    fi

    uci commit network || return 1

    for zone in $(uci -q show firewall | sed -n "s/^firewall\.\([^.]*\)=zone$/\1/p"); do
        uci -q del_list firewall.$zone.network="wan_usb"
    done
    uci commit firewall || return 1
    return 0
}

usb_restore_network() {
    if [ -x /etc/init.d/network ]; then
        /etc/init.d/network restart >/dev/null 2>&1 || return 1
    fi
    return 0
}

# Asks, then removes UCI state and restarts networking.
# A second prompt optionally uninstalls the driver packages.
# Returns 1 when the user declines or a step fails.
usb_restore_settings() {
    local answer=""

    usb_restore_confirm || return 1

    if ! usb_restore_uci; then
        log_error "Could not clear USB network configuration."
        return 1
    fi

    if usb_restore_network; then
        log_success "USB network configuration restored. Network service restarted."
    else
        log_warn "Configuration was cleared, but the network service did not restart."
    fi

    printf "  ⁉️ Uninstall USB tethering and modem drivers to free flash space? [y/N] : "
    if ! read -r answer </dev/tty; then
        return 0
    fi
    case "$answer" in
        y|Y|yes|YES) ;;
        *) return 0 ;;
    esac

    if command -v usb_purge_driver_packages >/dev/null 2>&1 && usb_purge_driver_packages; then
        log_success "USB driver packages removed."
        return 0
    fi
    log_warn "Some USB driver packages could not be removed."
    return 1
}


# 📄 Source : dashboard.sh
# DayPass - USB tethering dashboard.
# Open two columns: operations on the left, hardware tree on the right.
# The hardware menu prints the shared header and footer.

# $1 interface state (enabled | disabled | absent)
usb_render_left_menu() {
    local state="${1:-absent}"

    echo "  🛠️ Operations"
    echo "  ─────────────"
    echo "  📱 1) Setup USB Tethering"
    echo "  🔀 2) Toggle Interface ($state)"
    echo "  📶 3) Failover & Metrics"
    echo "  📌 4) Install Drivers"
    echo "  ♻️ 5) Restore / Reset USB"
    echo "  📟 6) Modem Mode Switch"
    echo "  🔄 7) Refresh"
    echo "  📊 8) System Resources"
}

# Prints the dashboard. Returns 0.
usb_render_dashboard() {
    local state left right

    state="absent"
    if command -v usb_wan_state >/dev/null 2>&1; then
        state=$(usb_wan_state)
    fi

    left="/tmp/daypass_usbleft.$$"
    right="/tmp/daypass_usbright.$$"
    usb_render_left_menu "$state" > "$left"
    if command -v usb_render_status_tree >/dev/null 2>&1; then
        usb_render_status_tree > "$right"
    else
        echo "  └── 🔌 USB status is not loaded." > "$right"
    fi
    if command -v _net_zip_columns >/dev/null 2>&1; then
        _net_zip_columns "$left" "$right" 38
    else
        cat "$left"
        echo
        cat "$right"
    fi
    rm -f "$left" "$right"
    return 0
}


# 📄 Source : wifi_wan.sh
# ============================================================
# DayPass - Wi-Fi WAN (Station / Client Mode)
# Connects the router to an external hotspot for internet
# Does NOT touch any Access Point interfaces
# ============================================================

setup_wifi_wan() {
    render_persistent_header

    echo "  📡 Wi-Fi WAN (Station Mode)"
    echo "  ───────────────────────────────────────────────────────────"
    echo "  ${GRAY:-}Connect this router to a phone hotspot or another Wi-Fi${RESET}"
    echo "  ${GRAY:-}network to use it as an internet source (WWAN)!${RESET}"
    echo "  ───────────────────────────────────────────────────────────"
    echo

    # List radios
    local radios idx=1 radio_list=""
    radios=$(uci show wireless 2>/dev/null | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1)

    if [ -z "$radios" ]; then
        log_error "No wireless radio found."
        return 1
    fi

    echo "  📻 Available Radios :"
    for r in $radios; do
        band=$(uci -q get wireless.$r.band || uci -q get wireless.$r.hwmode || echo "unknown")
        echo "     $idx) $r ($band)"
        radio_list="$radio_list $r"
        idx=$((idx + 1))
    done
    echo

    printf "  📋 Select radio [1] : "
    read -r choice </dev/tty
    [ -z "$choice" ] && choice=1

    local chosen="" i=1
    for r in $radio_list; do
        [ "$i" -eq "$choice" ] && chosen="$r" && break
        i=$((i + 1))
    done
    [ -z "$chosen" ] && chosen=$(echo $radio_list | awk '{print $1}')

    printf "  📶 Hotspot SSID : "
    read -r ssid </dev/tty
    [ -z "$ssid" ] && { log_error "SSID is required!"; return 1; }

    printf "  🔒 Password (leave empty if open) : "
    read -r pass </dev/tty

    # Logical interface
    uci set network.wwan=interface
    uci set network.wwan.proto='dhcp'
    uci set network.wwan.metric='30'
    uci commit network

    # Station interface (never touches AP)
    uci set wireless.wwan_sta=wifi-iface
    uci set wireless.wwan_sta.device="$chosen"
    uci set wireless.wwan_sta.mode='sta'
    uci set wireless.wwan_sta.network='wwan'
    uci set wireless.wwan_sta.ssid="$ssid"
    uci set wireless.wwan_sta.disabled='0'

    if [ -n "$pass" ]; then
        uci set wireless.wwan_sta.encryption='psk2'
        uci set wireless.wwan_sta.key="$pass"
    else
        uci set wireless.wwan_sta.encryption='none'
    fi

    uci commit wireless

    # Firewall
    local zone
    zone=$(uci show firewall | grep "=zone" | while read -r l; do
        s=$(echo "$l" | cut -d'.' -f2 | cut -d'=' -f1)
        [ "$(uci -q get firewall.$s.name)" = "wan" ] && echo "$s" && break
    done)
    if [ -n "$zone" ]; then
        uci -q del_list firewall.$zone.network='wwan'
        uci add_list firewall.$zone.network='wwan'
        uci commit firewall
    fi

    wifi reload >/dev/null 2>&1
    log_success "Wi-Fi WAN connected to [$ssid] on radio [$chosen]!"
}

# 📄 Source : wifi_ap.sh
# ============================================================
# DayPass - Wi-Fi Access Point Module
# Manages Home Wi-Fi (AP Mode only)
# Never touches Station / WWAN interfaces
# ============================================================

# ------------------------------------------------------------
# Show current Access Point status
# ------------------------------------------------------------
show_ap_status() {
    echo "  📶 Current Access Point Status"
    echo "  ───────────────────────────────────────────────────────────"

    local found=0
    for sec in $(uci show wireless 2>/dev/null | grep "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
        mode=$(uci -q get wireless.$sec.mode)
        [ "$mode" != "ap" ] && continue

        ssid=$(uci -q get wireless.$sec.ssid)
        disabled=$(uci -q get wireless.$sec.disabled || echo "0")
        device=$(uci -q get wireless.$sec.device)
        encryption=$(uci -q get wireless.$sec.encryption)
        network=$(uci -q get wireless.$sec.network)

        if [ "$disabled" = "1" ]; then
            status="${GRAY}Disabled${RESET}"
        else
            status="${GREEN}Enabled${RESET}"
        fi

        echo "  • SSID       : ${YELLOW}${ssid}${RESET}"
        echo "  • Device     : $device"
        echo "  • Network    : $network"
        echo "  • Encryption : $encryption"
        echo "  • Status     : $status"
        echo
        found=1
    done

    [ "$found" -eq 0 ] && echo "  ${GRAY}No Access Point configured yet!${RESET}"
    echo "  ───────────────────────────────────────────────────────────"
}

# ------------------------------------------------------------
# Main Setup Function
# ------------------------------------------------------------
setup_wifi_ap() {
    render_persistent_header

    echo "  📡 Wi-Fi Access Point Configuration"
    echo "  ───────────────────────────────────────────────────────────"
    echo "  ${GRAY}This module only manages Access Point (home Wi-Fi).${RESET}"
    echo "  ${GRAY}Station / WWAN interfaces will not be modified.${RESET}"
    echo "  ───────────────────────────────────────────────────────────"
    echo

    # Detect radios
    local RADIOS
    RADIOS=$(uci show wireless 2>/dev/null | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1)

    if [ -z "$RADIOS" ]; then
        wifi config 2>/dev/null
        RADIOS=$(uci show wireless 2>/dev/null | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1)
    fi

    if [ -z "$RADIOS" ]; then
        log_error "No wireless radio detected on this device."
        return 1
    fi

    show_ap_status

    # Check if any AP already exists
    local has_ap=0
    for sec in $(uci show wireless | grep "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
        [ "$(uci -q get wireless.$sec.mode)" = "ap" ] && has_ap=1 && break
    done

    if [ "$has_ap" -eq 1 ]; then
        printf "  ⁉️ Existing Access Points found. Reconfigure? [y/N] : "
        read -r reconf </dev/tty
        case "$reconf" in
            y|Y) ;;
            *)
                printf "  ${GRAY}>> Keeping current AP settings.${RESET}\n"
                sleep 1
                return 0
                ;;
        esac
    fi

    # SSID Strategy
    echo
    echo "  ⚙️ SSID Naming Strategy :"
    echo "     1) Unified SSID for all bands (Smart Connect)"
    echo "     2) Separate SSID per band (2.4G + 5G)"
    echo "  ───────────────────────────────────────────────────────────"
    printf "  ⁉️ Select [1/2] (default: 1) : "
    read -r ssid_mode </dev/tty
    [ -z "$ssid_mode" ] && ssid_mode=1

    local SSID_2G SSID_5G

    if [ "$ssid_mode" = "2" ]; then
        printf "  🛜 2.4GHz SSID [DayPass-2.4G] : "
        read -r SSID_2G </dev/tty
        [ -z "$SSID_2G" ] && SSID_2G="DayPass-2.4G"

        printf "  🛜 5GHz SSID [DayPass-5G] : "
        read -r SSID_5G </dev/tty
        [ -z "$SSID_5G" ] && SSID_5G="DayPass-5G"
    else
        printf "  🛜 Unified SSID [DayPass] : "
        read -r unified </dev/tty
        [ -z "$unified" ] && unified="DayPass"
        SSID_2G="$unified"
        SSID_5G="$unified"
    fi

    # Password
    local password=""
    while true; do
        printf "  🔒 WiFi Password (min 8 characters) : "
        read -r password </dev/tty
        if [ ${#password} -ge 8 ]; then
            break
        fi
        log_error "Password must be at least 8 characters!"
    done

    # Apply configuration to all radios
    log_info "Applying Access Point configuration ..."

    for radio in $RADIOS; do
        uci set wireless.$radio.disabled='0'

        local band
        band=$(uci -q get wireless.$radio.band || uci -q get wireless.$radio.hwmode || echo "")

        local iface="ap_${radio}"
        uci set wireless.$iface=wifi-iface
        uci set wireless.$iface.device="$radio"
        uci set wireless.$iface.mode='ap'
        uci set wireless.$iface.network='lan'
        uci set wireless.$iface.disabled='0'
        uci set wireless.$iface.encryption='psk2'
        uci set wireless.$iface.key="$password"

        case "$band" in
            *5g*|*a*|*ac*|*ax*) 
                uci set wireless.$iface.ssid="$SSID_5G"
                log_success "Configured 5GHz AP on $radio → $SSID_5G"
                ;;
            *)
                uci set wireless.$iface.ssid="$SSID_2G"
                log_success "Configured 2.4GHz AP on $radio → $SSID_2G"
                ;;
        esac
    done

    uci commit wireless
    wifi reload >/dev/null 2>&1 || /etc/init.d/network restart >/dev/null 2>&1

    echo
    log_success "Access Point configuration completed successfully!"
}

# ------------------------------------------------------------
# Main Menu
# ------------------------------------------------------------
wifi_ap_menu() {
    local HELP_MODULE_ID="network_wifi_ap"

    while true; do
        render_persistent_header

        echo "  📡 Wi-Fi Access Point Manager"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  👀 1) Show current AP status"
        echo "  🛜 2) Create / Update Access Point (AP)"
        ui_nav_footer
        ui_prompt 2
        choice="$UI_CHOICE"

        case "$choice" in
            1)
                show_ap_status
                printf "  ${GRAY:-}Press [Enter] to continue ... ${RESET:-}\n"
                read -r _ </dev/tty || daypass_quit
                ;;
            2)
                setup_wifi_ap
                printf "  ${GRAY:-}Press [Enter] to continue ... ${RESET:-}\n"
                read -r _ </dev/tty || daypass_quit
                ;;
            q|Q) daypass_quit ;;
            h|H)
                if command -v show_help >/dev/null 2>&1; then
                    show_help "$HELP_MODULE_ID"
                else
                    log_warn "Help module not loaded!"
                    sleep 1
                fi
                continue
                ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac
    done
}

# Allow direct execution
case "$0" in
    *wifi_ap.sh)
        command -v ui_prompt >/dev/null 2>&1 || { echo "Run this menu from DayPass (install.sh)."; exit 1; }
        wifi_ap_menu
        ;;
esac

# 📄 Source : load_balancer.sh
# ============================================================
# DayPass - Dynamic Multi-WAN Load Balancer (mwan3)
# Discovers every WAN (firewall wan zone, plus wan / wan_* /
# wwan), then builds an N-way balanced policy. Echo only on
# menu lines so emoji are not clipped by column widths.
# ============================================================

# $1 interface name. 0 when it is a WAN-style name (not wan6).
mwan_iface_is_wan() {
    case "$1" in
        wan6) return 1 ;;
        wan|wan_*|wwan|wwan_*) return 0 ;;
    esac
    return 1
}

# Record $1 if it is a real IPv4-capable network interface.
# Uses MWAN_SEEN. Prints the name once.
_mwan_note_iface() {
    _mi="$1"
    [ -n "$_mi" ] || return 1
    case " $MWAN_SEEN " in
        *" $_mi "*) return 1 ;;
    esac
    [ "$(uci -q get "network.$_mi")" = "interface" ] || return 1
    case "$(uci -q get "network.$_mi.proto")" in
        dhcpv6) return 1 ;;
    esac
    case "$_mi" in
        wan6) return 1 ;;
    esac
    MWAN_SEEN="$MWAN_SEEN $_mi"
    printf '%s\n' "$_mi"
    return 0
}

# Every WAN interface, one name per line.
# Firewall zone "wan", then any wan / wan_* / wwan interface
# that is not already listed (wan_usb, wan_usb2, wan_lan2, wwan).
mwan_discover_ifaces() {
    local i name nets net iface

    MWAN_SEEN=""
    i=0
    while uci -q get "firewall.@zone[$i]" >/dev/null 2>&1; do
        name=$(uci -q get "firewall.@zone[$i].name")
        if [ "$name" = "wan" ]; then
            nets=$(uci -q get "firewall.@zone[$i].network")
            for net in $nets; do
                _mwan_note_iface "$net" || true
            done
        fi
        i=$((i + 1))
        [ "$i" -gt 64 ] && break
    done

    for iface in $(uci show network 2>/dev/null | sed -n 's/^network\.\([A-Za-z0-9_]*\)=interface$/\1/p'); do
        mwan_iface_is_wan "$iface" || continue
        _mwan_note_iface "$iface" || true
    done
}

# $1 interface. 0 when it is not administratively disabled.
mwan_iface_enabled() {
    [ "$(uci -q get "network.$1.disabled")" != "1" ]
}

# Enabled WAN interfaces only.
mwan_active_ifaces() {
    local iface

    for iface in $(mwan_discover_ifaces); do
        mwan_iface_enabled "$iface" || continue
        printf '%s\n' "$iface"
    done
}

# Install mwan3 with opkg (OpenWrt 24) or apk (OpenWrt 25).
install_mwan3_deps() {
    if command -v pkg_installed >/dev/null 2>&1 && pkg_installed mwan3; then
        log_success "mwan3 is already installed."
        return 0
    fi
    if command -v mwan3 >/dev/null 2>&1 || [ -x /etc/init.d/mwan3 ]; then
        log_success "mwan3 is already installed."
        return 0
    fi

    log_info "Installing mwan3 ..."
    if command -v pkg_update >/dev/null 2>&1; then
        pkg_update >/dev/null 2>&1 || true
    elif command -v opkg >/dev/null 2>&1; then
        opkg update >/dev/null 2>&1 || true
    elif command -v apk >/dev/null 2>&1; then
        apk update >/dev/null 2>&1 || true
    fi

    if command -v pkg_install >/dev/null 2>&1 && pkg_install mwan3; then
        log_success "mwan3 installed."
        return 0
    fi
    if command -v opkg >/dev/null 2>&1 && opkg install mwan3 >/dev/null 2>&1; then
        log_success "mwan3 installed."
        return 0
    fi
    if command -v apk >/dev/null 2>&1 && apk add --allow-untrusted mwan3 >/dev/null 2>&1; then
        log_success "mwan3 installed."
        return 0
    fi

    log_error "Could not install mwan3."
    return 1
}

# Drop previous interface and member sections so a smaller WAN
# set does not leave stale members in the policies.
_mwan_clear_links() {
    local sec kind

    uci show mwan3 2>/dev/null | sed -n 's/^mwan3\.\([^=]*\)=\(interface\|member\)$/\1 \2/p' | \
    while read -r sec kind; do
        [ -n "$sec" ] || continue
        uci -q delete "mwan3.$sec"
    done
}

# Build mwan3 for every enabled WAN. Balanced uses weight 1 on
# every member. Failover orders members by network metric.
configure_mwan3_engine() {
    local list count iface metric rank member

    log_info "Scanning WAN interfaces ..."
    list=$(mwan_active_ifaces)
    count=0
    for iface in $list; do
        count=$((count + 1))
        metric=$(uci -q get "network.$iface.metric")
        [ -n "$metric" ] || metric="default"
        echo "  🌐 $iface  metric $metric"
    done

    if [ "$count" -eq 0 ]; then
        log_warn "No active WAN interfaces found. Create wan, wan_usb, wwan, or wan_lan2 first."
        return 1
    fi

    log_info "Configuring mwan3 for $count WAN interface(s) ..."

    uci set mwan3.globals=globals
    uci set mwan3.globals.mmx_mask='0x3f00'
    _mwan_clear_links

    for iface in $list; do
        uci set "mwan3.$iface"=interface
        uci set "mwan3.$iface.enabled"='1'
        uci set "mwan3.$iface.family"='ipv4'
        uci -q delete "mwan3.$iface.track_ip"
        uci add_list "mwan3.$iface.track_ip"='1.1.1.1'
        uci add_list "mwan3.$iface.track_ip"='8.8.8.8'
        uci set "mwan3.$iface.reliability"='1'
        uci set "mwan3.$iface.timeout"='2'
        uci set "mwan3.$iface.interval"='5'

        member="${iface}_m"
        uci set "mwan3.$member"=member
        uci set "mwan3.$member.interface"="$iface"
        uci set "mwan3.$member.metric"='1'
        uci set "mwan3.$member.weight"='1'
    done

    uci set mwan3.balanced=policy
    uci -q delete mwan3.balanced.use_member
    for iface in $list; do
        uci add_list mwan3.balanced.use_member="${iface}_m"
    done

    uci set mwan3.failover=policy
    uci -q delete mwan3.failover.use_member
    rank=1
    for iface in $(
        for iface in $list; do
            metric=$(uci -q get "network.$iface.metric")
            case "$metric" in
                ''|*[!0-9]*) metric=1000 ;;
            esac
            printf '%s %s\n' "$metric" "$iface"
        done | sort -n | awk '{ print $2 }'
    ); do
        member="${iface}_fo"
        uci set "mwan3.$member"=member
        uci set "mwan3.$member.interface"="$iface"
        uci set "mwan3.$member.metric"="$rank"
        uci set "mwan3.$member.weight"='1'
        uci add_list mwan3.failover.use_member="$member"
        rank=$((rank + 1))
    done

    uci set mwan3.default_rule_v4=rule
    uci set mwan3.default_rule_v4.dest_ip='0.0.0.0/0'
    uci set mwan3.default_rule_v4.family='ipv4'
    uci set mwan3.default_rule_v4.use_policy='balanced'

    uci commit mwan3 || { log_error "Could not save mwan3."; return 1; }

    if [ -x /etc/init.d/mwan3 ]; then
        /etc/init.d/mwan3 enable >/dev/null 2>&1 || true
        /etc/init.d/mwan3 restart >/dev/null 2>&1 || log_warn "mwan3 did not restart. Install it from option 1 if it is missing."
    else
        log_warn "mwan3 is not installed yet. The config is saved. Use option 1, then apply again."
    fi

    log_success "mwan3 balanced policy now shares traffic across $count WAN interface(s)."
    return 0
}

# View and set network.<iface>.metric for every discovered WAN.
mwan_metric_menu() {
    local list count i iface metric current

    while true; do
        if command -v render_persistent_header >/dev/null 2>&1; then
            render_persistent_header
        fi
        echo "  🧭 WAN Metrics"
        echo "  A lower metric is preferred."
        echo
        list=$(mwan_discover_ifaces)
        count=0
        i=1
        if [ -n "$list" ]; then
            for iface in $list; do
                metric=$(uci -q get "network.$iface.metric")
                [ -n "$metric" ] || metric="default"
                if mwan_iface_enabled "$iface"; then
                    echo "  $i) $iface  metric $metric  enabled"
                else
                    echo "  $i) $iface  metric $metric  disabled"
                fi
                i=$((i + 1))
                count=$((count + 1))
            done
        else
            echo "  No WAN interfaces found."
        fi
        if command -v ui_nav_footer >/dev/null 2>&1; then
            ui_nav_footer
        fi
        if command -v ui_read >/dev/null 2>&1; then
            ui_read "Select option"
        else
            printf '  Select option : '
            read -r UI_CHOICE </dev/tty || return 0
        fi

        case "$UI_CHOICE" in
            0|'') return 0 ;;
            q|Q)
                command -v daypass_quit >/dev/null 2>&1 && daypass_quit
                return 0
                ;;
            h|H)
                command -v ui_show_help >/dev/null 2>&1 && ui_show_help "network_multiwan"
                continue
                ;;
        esac

        case "$UI_CHOICE" in
            *[!0-9]*) log_warn "Invalid option!"; continue ;;
        esac
        [ "$UI_CHOICE" -ge 1 ] && [ "$UI_CHOICE" -le "$count" ] || {
            log_warn "Invalid option!"
            continue
        }

        i=1
        iface=""
        for iface in $list; do
            [ "$i" = "$UI_CHOICE" ] && break
            i=$((i + 1))
        done

        current=$(uci -q get "network.$iface.metric")
        if command -v ui_read >/dev/null 2>&1; then
            ui_read "Metric for $iface [${current:-20}]"
        else
            printf '  Metric for %s : ' "$iface"
            read -r UI_CHOICE </dev/tty || return 0
        fi
        case "$UI_CHOICE" in
            0|'') continue ;;
            q|Q)
                command -v daypass_quit >/dev/null 2>&1 && daypass_quit
                return 0
                ;;
        esac
        if command -v usb_wan_set_metric >/dev/null 2>&1; then
            usb_wan_set_metric "$iface" "$UI_CHOICE" || true
        else
            case "$UI_CHOICE" in
                ''|*[!0-9]*) log_error "Invalid metric [$UI_CHOICE]!"; continue ;;
            esac
            uci set "network.$iface.metric"="$UI_CHOICE"
            uci commit network || { log_error "Could not save the metric."; continue; }
            if [ "$(uci -q get "network.$iface.disabled")" != "1" ]; then
                ifup "$iface" >/dev/null 2>&1 || true
            fi
            log_success "Metric of [$iface] set to $UI_CHOICE."
        fi
        command -v ui_pause >/dev/null 2>&1 && ui_pause
    done
}

load_balancer_menu() {
    local HELP_MODULE_ID="network_multiwan"
    local iface metric list

    while true; do
        render_persistent_header
        echo "  ⚖️ Multi-WAN Load Balancer"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  🌐 Detected WAN interfaces"
        list=$(mwan_discover_ifaces)
        if [ -z "$list" ]; then
            echo "     none"
        else
            for iface in $list; do
                metric=$(uci -q get "network.$iface.metric")
                [ -n "$metric" ] || metric="default"
                echo "     $iface  metric $metric"
            done
        fi
        echo
        echo "  📌 1) Install Dependencies"
        echo "  📲 2) Setup USB Tethering WAN"
        echo "  📶 3) Setup Wi-Fi Hotspot WAN"
        echo "  ⚖️ 4) Apply Dynamic Load Balancing"
        echo "  👀 5) Show mwan3 Status"
        echo "  🧭 6) WAN Metrics"
        ui_nav_footer
        ui_prompt 6
        c="$UI_CHOICE"

        case "$c" in
            1) install_mwan3_deps || true ;;
            2) setup_usb_wan 2>/dev/null || log_warn "USB module not loaded." ;;
            3) setup_wifi_wan 2>/dev/null || log_warn "Wi-Fi WAN module not loaded." ;;
            4) configure_mwan3_engine || true ;;
            5) command -v mwan3 >/dev/null 2>&1 && mwan3 status || log_error "mwan3 not installed!" ;;
            6) mwan_metric_menu; continue ;;
            q|Q) daypass_quit ;;
            h|H)
                if command -v show_help >/dev/null 2>&1; then
                    show_help "$HELP_MODULE_ID"
                else
                    log_warn "Help module not loaded!"
                    sleep 1
                fi
                continue
                ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        echo
        echo "  ${GRAY:-}Press [Enter] to continue ...${RESET:-}"
        read -r _ </dev/tty || daypass_quit
    done
}


# 📄 Source : network_checker.sh

# Cross-platform sleeping utility for UI spinner rendering
spin_sleep() {
    if command -v usleep >/dev/null 2>&1; then
        usleep 100000
    else
        sleep 1
    fi
}

GREEN_COUNT=0
YELLOW_COUNT=0
RED_COUNT=0
TOTAL_CHECKS=0
DNS_FAILED=0

ROW_HOST=""
ROW_DNS_ICON="·"
ROW_PING_ICON="·"
ROW_HTTPS_ICON="·"
ROW_ACTIVE=""

# Redraw the current table row with updated status icons / spinner
redraw_row()
{
    spin="$1"
    d="$ROW_DNS_ICON"
    p="$ROW_PING_ICON"
    h="$ROW_HTTPS_ICON"

    case "$ROW_ACTIVE" in
        dns)   d="$spin" ;;
        ping)  p="$spin" ;;
        https) h="$spin" ;;
    esac

    printf "\r  %-16s %-6s %-7s %-6s\033[K" "$ROW_HOST" "$d" "$p" "$h"
}

# Run execution cell asynchronously while displaying animated CLI spinner
run_cell()
{
    ROW_ACTIVE="$1"
    tmp="$2"
    shift 2

    "$@" >"$tmp" 2>&1 &
    pid=$!

    trap 'kill -9 "$pid" 2>/dev/null; rm -f "$tmp" 2>/dev/null; exit 130' INT TERM

    spin_chars='-\|/'
    i=0
    while kill -0 "$pid" 2>/dev/null; do
        c="$(printf '%s' "$spin_chars" | cut -c$(( (i % 4) + 1 )))"

        if [ -n "${CYAN:-}" ] && [ -n "${RESET:-}" ]; then
            redraw_row "${CYAN}${c}${RESET}"
        else
            redraw_row "$c"
        fi
        i=$((i + 1))
        spin_sleep
    done

    wait "$pid" 2>/dev/null
    CELL_EXIT=$?
    CELL_OUTPUT="$(cat "$tmp" 2>/dev/null)"
    rm -f "$tmp"
}

# Execute health diagnostics for a single target hostname
process_host()
{
    ROW_HOST="$1"
    ROW_DNS_ICON="·"
    ROW_PING_ICON="·"
    ROW_HTTPS_ICON="·"
    ROW_ACTIVE=""
    redraw_row "·"

    # 1. DNS Resolution Check
    if command -v nslookup >/dev/null 2>&1; then
        run_cell "dns" "/tmp/.nc_dns_$$" nslookup "$ROW_HOST"
    elif command -v host >/dev/null 2>&1; then
        run_cell "dns" "/tmp/.nc_dns_$$" host "$ROW_HOST"
    else
        # Fallback using ping host resolution
        run_cell "dns" "/tmp/.nc_dns_$$" ping -c 1 -W 2 "$ROW_HOST"
    fi

    if [ "$CELL_EXIT" -eq 0 ]; then
        ROW_DNS_ICON="🟢"
    else
        ROW_DNS_ICON="🔴"
        DNS_FAILED=1
    fi

    # 2. ICMP Ping / Latency Check
    run_cell "ping" "/tmp/.nc_ping_$$" ping -c 2 -W 2 "$ROW_HOST"
    LOSS="$(printf '%s' "$CELL_OUTPUT" | grep -o '[0-9]*% packet loss' | grep -o '^[0-9]*')"
    [ -z "$LOSS" ] && LOSS=100

    if [ "$LOSS" -eq 0 ]; then
        ROW_PING_ICON="🟢"
    elif [ "$LOSS" -lt 100 ]; then
        ROW_PING_ICON="🟡"
    else
        ROW_PING_ICON="🔴"
    fi

    # 3. HTTPS Reachability & Performance Check
    if command -v curl >/dev/null 2>&1; then
        run_cell "https" "/tmp/.nc_https_$$" curl -fsS -o /dev/null -w '%{time_total}' --connect-timeout 5 "https://$ROW_HOST"
    elif command -v uclient-fetch >/dev/null 2>&1; then
        run_cell "https" "/tmp/.nc_https_$$" uclient-fetch -q -T 5 -O /dev/null "https://$ROW_HOST"
    else
        run_cell "https" "/tmp/.nc_https_$$" wget -q --spider --timeout=5 "https://$ROW_HOST"
    fi

    if [ "$CELL_EXIT" -ne 0 ]; then
        ROW_HTTPS_ICON="🔴"
    else
        if command -v curl >/dev/null 2>&1; then
            IS_FAST="$(awk -v t="$CELL_OUTPUT" 'BEGIN { print (t < 2) ? "1" : "0" }' 2>/dev/null)"
            if [ "$IS_FAST" = "1" ]; then
                ROW_HTTPS_ICON="🟢"
            else
                ROW_HTTPS_ICON="🟡"
            fi
        else
            ROW_HTTPS_ICON="🟢"
        fi
    fi

    ROW_ACTIVE=""
    redraw_row " "
    printf "\n"

    for icon in "$ROW_DNS_ICON" "$ROW_PING_ICON" "$ROW_HTTPS_ICON"; do
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        case "$icon" in
            🟢) GREEN_COUNT=$((GREEN_COUNT + 1)) ;;
            🟡) YELLOW_COUNT=$((YELLOW_COUNT + 1)) ;;
            🔴) RED_COUNT=$((RED_COUNT + 1)) ;;
        esac
    done
}

# Master execution function for system network checks
network_check()
{
    GREEN_COUNT=0
    YELLOW_COUNT=0
    RED_COUNT=0
    TOTAL_CHECKS=0
    DNS_FAILED=0

    render_persistent_header
    printf "  ${BOLD:-}${CYAN:-}🩺 Network Health Check${RESET:-}\n"
    
    printf "  ${GRAY:-}──────────────────────────────────────────${RESET:-}\n"

    printf "  ${BOLD:-}%-16s %-6s %-7s %-6s${RESET:-}\n" "Host" "DNS" "Ping" "HTTPS"
    printf "  ${GRAY:-}──────────────────────────────────────────${RESET:-}\n"

    process_host "google.com"
    process_host "github.com"
    process_host "openwrt.org"
    process_host "cloudflare.com"

    printf "  ${GRAY:-}──────────────────────────────────────────${RESET:-}\n\n"

    PCT=0
    [ "$TOTAL_CHECKS" -gt 0 ] && PCT=$((GREEN_COUNT * 100 / TOTAL_CHECKS))

    printf "  ${BOLD:-}Overall Score :${RESET:-} "
    if command -v draw_bar >/dev/null 2>&1; then
        draw_bar "$PCT" 12 "score"
    fi
    printf " %s%% (🟢 %s  🟡 %s  🔴 %s)\n\n" "$PCT" "$GREEN_COUNT" "$YELLOW_COUNT" "$RED_COUNT"

    printf "  ${BOLD:-}Diagnostic Report :${RESET:-}"
    if [ "$DNS_FAILED" -eq 1 ]; then
        if command -v log_error >/dev/null 2>&1; then
            log_error "DNS resolution is failing! Router cannot translate domain names."
        else
            printf "❌${RED:-}DNS resolution failed! Domain name lookup is broken.${RESET:-}\n"
        fi
        
        if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
            if command -v dns_fix_menu >/dev/null 2>&1; then
                dns_fix_menu
            fi
        fi
    elif [ "$RED_COUNT" -gt 0 ]; then
        if command -v log_warn >/dev/null 2>&1; then
            log_warn "HTTPS connections are blocked or filtered (Possible Censorship/DPI)."
        else
            printf "⚠️${YELLOW:-}HTTPS traffic is blocked or severely interfered with.${RESET:-}\n"
        fi
    elif [ "$YELLOW_COUNT" -gt 0 ]; then
        if command -v log_warn >/dev/null 2>&1; then
            log_warn "Network is active but experiencing high packet loss/latency (>2s)."
        else
            printf "⚠️${YELLOW:-}High latency or degraded response time detected!${RESET:-}\n"
        fi
    else
        if command -v log_success >/dev/null 2>&1; then
            log_success "Network is fully functional with clean connectivity!"
        else
            printf "✅${GREEN:-}Network is fully functional!${RESET:-}\n"
        fi
    fi

    echo
    printf "  ${GRAY:-}Press [Enter] to continue ... ${RESET:-}\n"
    read -r _ </dev/tty || daypass_quit
    echo
    return 0
}

# Standalone execution handler
case "$0" in
    *network_check.sh|*network_checker.sh) network_check ;;
esac

# 📄 Source : core.sh
# DNS Core — shared paths, active transport engine DNS hooks, dnsmasq apply

DNS_DIR="${DAYPASS_DIR:-/etc/daypass}/dns"
DNS_MODE_FILE="$DNS_DIR/mode"
DNS_DOH_URL="https://cloudflare-dns.com/dns-query"
DNS_CF="1.1.1.1"
DNS_CF2="1.0.0.1"
DNS_GOOGLE="8.8.8.8"

# Active transport engine (see transports/transport_bridge.sh), or "none"
dns_engine() {
    if command -v get_active_engine >/dev/null 2>&1; then
        get_active_engine
    else
        echo "none"
    fi
}

dns_engine_available() {
    local engine
    engine=$(dns_engine)
    [ "$engine" != "none" ] && transport_has_hook "$engine" dns_configure
}

# $1 mode: doh | tunnel | hybrid | off. Returns 3 when the engine lacks that mode.
dns_engine_configure() {
    local engine
    engine=$(dns_engine)
    [ "$engine" = "none" ] && return 3
    transport_call "$engine" dns_configure "$1"
}

# dnsmasq upstream served by the engine (e.g. 127.0.0.1#7913 or a tunnel-routed resolver)
dns_engine_endpoint() {
    local engine
    engine=$(dns_engine)
    [ "$engine" = "none" ] && return 1
    transport_call "$engine" dns_endpoint 2>/dev/null
}

dns_engine_label() {
    local engine
    engine=$(dns_engine)
    if [ "$engine" = "none" ]; then
        echo "none"
    else
        transport_engine_label "$engine"
    fi
}

# Stops engine DNS hijack / tunnel DNS routes
dns_engine_release() {
    dns_engine_available || return 0
    dns_engine_configure off >/dev/null 2>&1 || true
    return 0
}

get_dns_mode() {
    if [ -f "$DNS_MODE_FILE" ]; then
        cat "$DNS_MODE_FILE"
    else
        echo "system"
    fi
}

set_dns_mode() {
    mkdir -p "$DNS_DIR" 2>/dev/null || {
        log_error "Cannot create DNS state dir [$DNS_DIR]"
        return 1
    }
    echo "$1" > "$DNS_MODE_FILE"
}

dns_restart_dnsmasq() {
    if [ -x /etc/init.d/dnsmasq ]; then
        /etc/init.d/dnsmasq reload >/dev/null 2>&1 || \
            /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
    fi
}

dns_https_proxy_port() {
    local port
    port=$(uci -q get https-dns-proxy.@https-dns-proxy[0].listen_port 2>/dev/null) || true
    if [ -n "$port" ]; then
        echo "$port"
        return 0
    fi
    if [ -f /etc/config/https-dns-proxy ]; then
        echo "5053"
        return 0
    fi
    return 1
}

dns_stubby_port() {
    if command -v stubby >/dev/null 2>&1 || [ -f /etc/stubby/stubby.yml ]; then
        echo "5453"
        return 0
    fi
    return 1
}

dns_dnsmasq_reset() {
    uci -q delete dhcp.@dnsmasq[0].noresolv
    uci -q delete dhcp.@dnsmasq[0].server
    uci -q delete dhcp.@dnsmasq[0].strictorder
}

dns_dnsmasq_forward_only() {
    local addr
    dns_dnsmasq_reset
    uci set dhcp.@dnsmasq[0].noresolv='1'
    for addr in "$@"; do
        [ -n "$addr" ] && uci add_list dhcp.@dnsmasq[0].server="$addr"
    done
}

dns_dnsmasq_commit() {
    uci commit dhcp 2>/dev/null || true
    dns_restart_dnsmasq
}

show_dns_status() {
    local mode upstream
    mode=$(get_dns_mode)

    echo "  🧭 Current DNS Status"
    echo "  ───────────────────────────────────────────────────────────"
    echo "  🫀 Active Mode : ${GREEN}${mode}${RESET}"
    echo "  🛡️  Engine     : ${CYAN}$(dns_engine_label)${RESET}"

    upstream=$(uci -q get dhcp.@dnsmasq[0].server 2>/dev/null | tr '\n' ' ')
    if [ -n "$upstream" ]; then
        echo "  📡 dnsmasq    : ${upstream}"
    else
        echo "  📡 dnsmasq    : ${GRAY}system / WAN resolvers${RESET}"
    fi
    echo "  ───────────────────────────────────────────────────────────"
}


# 📄 Source : system.sh

# DNS Mode: System Default — WAN / ISP resolvers, no hijack

apply_dns_system() {
    log_info "Applying DNS mode: system default ..."

    dns_dnsmasq_reset
    dns_dnsmasq_commit
    dns_engine_release

    log_info "LAN clients use the router WAN/ISP DNS path."
    return 0
}


# 📄 Source : secure.sh

# DNS Mode: encrypted resolvers (DoT/DoH stub, transport engine DoH, or public DNS)

apply_dns_secure() {
    local stub encrypted=0
    log_info "Applying DNS mode: secure (DoT/DoH) ..."

    if stub=$(dns_stubby_port); then
        log_info "Using Stubby DoT stub on 127.0.0.1#${stub}"
        dns_dnsmasq_forward_only "127.0.0.1#${stub}"
        dns_engine_release
        encrypted=1
    elif stub=$(dns_https_proxy_port); then
        log_info "Using https-dns-proxy DoH stub on 127.0.0.1#${stub}"
        dns_dnsmasq_forward_only "127.0.0.1#${stub}"
        dns_engine_release
        encrypted=1
    elif dns_engine_configure doh && stub=$(dns_engine_endpoint) && [ -n "$stub" ]; then
        log_info "Using $(dns_engine_label) DoH (Cloudflare) as encrypted resolver ..."
        dns_dnsmasq_forward_only "$stub"
        encrypted=1
    else
        log_warn "No DoT/DoH stub or DoH-capable transport engine found. Falling back to public DNS (plaintext)."
        dns_dnsmasq_forward_only "$DNS_CF" "$DNS_CF2" "$DNS_GOOGLE"
        dns_engine_release
    fi

    dns_dnsmasq_commit

    if [ "$encrypted" -eq 1 ]; then
        log_info "Queries are forwarded to an encrypted resolver, not ISP DNS."
    fi
    return 0
}


# 📄 Source : tunnel.sh

# DNS Mode: all DNS through the active transport engine (proxy DNS or VPN tunnel)

apply_dns_tunnel() {
    local endpoint label
    log_info "Applying DNS mode: through tunnel ..."

    if ! dns_engine_available; then
        log_error "No transport engine found. Cannot force tunnel DNS."
        return 1
    fi
    label=$(dns_engine_label)

    if ! dns_engine_configure tunnel; then
        log_error "Engine [$label] cannot route DNS through its tunnel."
        return 1
    fi

    endpoint=$(dns_engine_endpoint)
    if [ -z "$endpoint" ]; then
        log_error "Engine [$label] has no DNS endpoint (add a dns-in inbound or set dns_port)."
        return 1
    fi

    dns_dnsmasq_forward_only "$endpoint"
    dns_dnsmasq_commit

    log_info "dnsmasq forwards to $label ($endpoint); LAN DNS goes through the tunnel."
    return 0
}


# 📄 Source : hybrid.sh

# DNS Mode: Hybrid — transport engine / DoH first, public resolvers as ordered fallback

apply_dns_hybrid() {
    local port primary=""
    log_info "Applying DNS mode: hybrid ..."

    dns_dnsmasq_reset
    uci set dhcp.@dnsmasq[0].noresolv='1'
    uci set dhcp.@dnsmasq[0].strictorder='1'

    if dns_engine_configure hybrid && primary=$(dns_engine_endpoint) && [ -n "$primary" ]; then
        uci add_list dhcp.@dnsmasq[0].server="$primary"
        log_info "Primary resolver: $(dns_engine_label) (DoH / tunnel). Fallback: Cloudflare + Google."
    elif port=$(dns_stubby_port); then
        primary=""
        dns_engine_release
        uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#${port}"
        log_info "Primary resolver: Stubby DoT. Fallback: public DNS."
    elif port=$(dns_https_proxy_port); then
        primary=""
        dns_engine_release
        uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#${port}"
        log_info "Primary resolver: https-dns-proxy. Fallback: public DNS."
    else
        primary=""
        dns_engine_release
        log_warn "No transport engine DNS found. Hybrid uses public resolvers only."
    fi

    [ "$primary" = "$DNS_CF" ] || uci add_list dhcp.@dnsmasq[0].server="$DNS_CF"
    uci add_list dhcp.@dnsmasq[0].server="$DNS_GOOGLE"
    dns_dnsmasq_commit
    return 0
}


# 📄 Source : apply.sh

# DNS Apply Dispatcher — persist mode only after a successful apply

apply_dns_mode() {
    local mode="$1"
    local rc=0

    case "$mode" in
        system) apply_dns_system; rc=$? ;;
        secure) apply_dns_secure; rc=$? ;;
        tunnel) apply_dns_tunnel; rc=$? ;;
        hybrid) apply_dns_hybrid; rc=$? ;;
        *)
            log_error "Unknown DNS mode: $mode"
            return 1
            ;;
    esac

    [ "$rc" -eq 0 ] || return "$rc"

    set_dns_mode "$mode" || return 1
    log_success "DNS mode set to [${mode}]"
    return 0
}


# 📄 Source : network.sh
# ============================================================
# DayPass - Guest Network Module
# Creates isolated Guest network with firewall rules & DHCP
# ============================================================

# ------------------------------------------------------------
# Create Guest Network + Firewall + DHCP
# ------------------------------------------------------------
setup_guest_network() {
    log_info "Configuring isolated Guest Network..."

    # 1. Network Interface
    uci set network.guest=interface
    uci set network.guest.proto='static'
    uci set network.guest.ipaddr='192.168.200.1'
    uci set network.guest.netmask='255.255.255.0'
    uci set network.guest.force_link='0'

    # 2. DHCP Server for Guest
    uci set dhcp.guest=dhcp
    uci set dhcp.guest.interface='guest'
    uci set dhcp.guest.start='100'
    uci set dhcp.guest.limit='150'
    uci set dhcp.guest.leasetime='12h'
    uci set dhcp.guest.force='1'

    # 3. Firewall Zone (Isolated)
    uci set firewall.guest=zone
    uci set firewall.guest.name='guest'
    uci set firewall.guest.network='guest'
    uci set firewall.guest.input='REJECT'
    uci set firewall.guest.output='ACCEPT'
    uci set firewall.guest.forward='REJECT'
    uci set firewall.guest.masq='0'

    # 4. Allow Guest -> WAN (Internet only)
    uci set firewall.guest_to_wan=forwarding
    uci set firewall.guest_to_wan.src='guest'
    uci set firewall.guest_to_wan.dest='wan'

    # 5. Essential Rules: DNS + DHCP
    uci set firewall.guest_dns=rule
    uci set firewall.guest_dns.name='Allow-Guest-DNS'
    uci set firewall.guest_dns.src='guest'
    uci set firewall.guest_dns.dest_port='53'
    uci set firewall.guest_dns.proto='tcp udp'
    uci set firewall.guest_dns.target='ACCEPT'

    uci set firewall.guest_dhcp=rule
    uci set firewall.guest_dhcp.name='Allow-Guest-DHCP'
    uci set firewall.guest_dhcp.src='guest'
    uci set firewall.guest_dhcp.dest_port='67-68'
    uci set firewall.guest_dhcp.proto='udp'
    uci set firewall.guest_dhcp.target='ACCEPT'

    # 6. Block Guest from accessing main LAN
    uci set firewall.guest_block_lan=rule
    uci set firewall.guest_block_lan.name='Block-Guest-to-LAN'
    uci set firewall.guest_block_lan.src='guest'
    uci set firewall.guest_block_lan.dest='lan'
    uci set firewall.guest_block_lan.target='REJECT'

    uci commit network
    uci commit dhcp
    uci commit firewall

    /etc/init.d/network reload >/dev/null 2>&1
    /etc/init.d/firewall reload >/dev/null 2>&1
    /etc/init.d/dnsmasq restart >/dev/null 2>&1

    log_success "Guest Network ready → 192.168.200.0/24 (Isolated)"
}

# ------------------------------------------------------------
# Remove Guest Network completely
# ------------------------------------------------------------
remove_guest_network() {
    log_warn "Removing Guest Network configuration..."

    uci -q delete network.guest
    uci -q delete dhcp.guest
    uci -q delete firewall.guest
    uci -q delete firewall.guest_to_wan
    uci -q delete firewall.guest_dns
    uci -q delete firewall.guest_dhcp
    uci -q delete firewall.guest_block_lan

    # Remove related wireless interfaces
    for sec in $(uci show wireless | grep "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
        network=$(uci -q get wireless.$sec.network)
        if [ "$network" = "guest" ]; then
            uci -q delete wireless.$sec
        fi
    done

    uci commit network
    uci commit dhcp
    uci commit firewall
    uci commit wireless

    wifi reload >/dev/null 2>&1
    /etc/init.d/firewall reload >/dev/null 2>&1

    log_success "Guest Network removed."
}

# ------------------------------------------------------------
# Create Guest WiFi (AP on Guest network)
# ------------------------------------------------------------
setup_guest_wifi() {
    render_persistent_header

    echo "  👥 Guest WiFi Configuration"
    echo "  ───────────────────────────────────────────────────────────"

    # Make sure guest network exists
    if ! uci -q get network.guest >/dev/null; then
        setup_guest_network
    fi

    local RADIOS
    RADIOS=$(uci show wireless 2>/dev/null | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1)

    if [ -z "$RADIOS" ]; then
        log_error "No wireless radio found!"
        return 1
    fi

    printf "  🛜 Guest SSID [DayPass-Guest] : "
    read -r guest_ssid </dev/tty
    [ -z "$guest_ssid" ] && guest_ssid="DayPass-Guest"

    local guest_pass=""
    while true; do
        printf "  🔒 Guest Password (min 8 chars) : "
        read -r guest_pass </dev/tty
        [ ${#guest_pass} -ge 8 ] && break
        log_error "Password must be at least 8 characters!"
    done

    for radio in $RADIOS; do
        local band
        band=$(uci -q get wireless.$radio.band || echo "")
        local iface="guest_${radio}"

        uci set wireless.$iface=wifi-iface
        uci set wireless.$iface.device="$radio"
        uci set wireless.$iface.mode='ap'
        uci set wireless.$iface.network='guest'
        uci set wireless.$iface.ssid="$guest_ssid"
        uci set wireless.$iface.encryption='psk2'
        uci set wireless.$iface.key="$guest_pass"
        uci set wireless.$iface.isolate='1'
        uci set wireless.$iface.disabled='0'

        log_success "Guest WiFi created on [$radio] → [$guest_ssid]"
    done

    uci commit wireless
    wifi reload >/dev/null 2>&1

    log_success "Guest WiFi is now active!"
}

# ------------------------------------------------------------
# Menu
# ------------------------------------------------------------
guest_network_menu() {
    while true; do
        render_persistent_header

        echo "  👥 Guest Network Manager"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  1) Setup Guest Network (Interface + Firewall)"
        echo "  2) Setup Guest WiFi"
        echo "  3) Remove Guest Network completely"
        ui_nav_footer
        ui_prompt 3
        choice="$UI_CHOICE"

        case "$choice" in
            1) setup_guest_network ;;
            2) setup_guest_wifi ;;
            3) remove_guest_network ;;
            0) return 0 ;;
            q|Q) daypass_quit ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press ENTER ...${RESET}"
        read -r _ </dev/tty || daypass_quit
    done
}

# 📄 Source : qos.sh
# ============================================================
# DayPass - Guest QoS / Bandwidth Control
# Supports both Simple (tc) and Advanced (SQM) modes
# ============================================================

# ------------------------------------------------------------
# Simple Bandwidth Limit using tc (HTB)
# ------------------------------------------------------------
setup_simple_qos() {
    log_info "Setting up Simple QoS with tc ..."

    # Check if guest interface exists
    if ! uci -q get network.guest >/dev/null; then
        log_error "Guest network not found. Please setup Guest Network first!"
        return 1
    fi

    printf "  📥 Download limit for Guests (Mbps) [e.g. 10] : "
    read -r dl_limit </dev/tty
    [ -z "$dl_limit" ] && dl_limit=10

    printf "  📤 Upload limit for Guests (Mbps) [e.g. 5] : "
    read -r ul_limit </dev/tty
    [ -z "$ul_limit" ] && ul_limit=5

    # Convert to kbps
    local dl_kbit=$((dl_limit * 1000))
    local ul_kbit=$((ul_limit * 1000))

    # Install tc if needed
    if ! command -v tc >/dev/null 2>&1; then
        if [ "${PKG_MANAGER:-opkg}" = "apk" ]; then
            apk add kmod-sched tc >/dev/null 2>&1
        else
            opkg update >/dev/null 2>&1
            opkg install kmod-sched tc >/dev/null 2>&1
        fi
    fi

    # Apply tc rules on guest interface (after it comes up)
    cat > /etc/guest_qos.sh << EOF
# DayPass Guest Simple QoS
IFACE="br-guest"
[ -d /sys/class/net/\$IFACE ] || IFACE="guest"

tc qdisc del dev \$IFACE root 2>/dev/null
tc qdisc del dev \$IFACE ingress 2>/dev/null

# Download limit (ingress)
tc qdisc add dev \$IFACE handle ffff: ingress
tc filter add dev \$IFACE parent ffff: protocol ip prio 1 \\
    u32 match ip src 0.0.0.0/0 police rate ${dl_kbit}kbit burst 100k drop

# Upload limit (egress)
tc qdisc add dev \$IFACE root handle 1: htb default 10
tc class add dev \$IFACE parent 1: classid 1:1 htb rate ${ul_kbit}kbit
tc class add dev \$IFACE parent 1:1 classid 1:10 htb rate ${ul_kbit}kbit ceil ${ul_kbit}kbit
tc qdisc add dev \$IFACE parent 1:10 handle 10: sfq perturb 10
EOF

    chmod +x /etc/guest_qos.sh

    # Run now
    /etc/guest_qos.sh

    # Make persistent
    if ! grep -q "guest_qos.sh" /etc/rc.local 2>/dev/null; then
        sed -i -e '$i /etc/guest_qos.sh &' /etc/rc.local
    fi

    log_success "Simple QoS applied → Download: ${dl_limit}Mbps | Upload: ${ul_limit}Mbps"
}

# ------------------------------------------------------------
# Advanced QoS using SQM (Recommended)
# ------------------------------------------------------------
setup_sqm_qos() {
    log_info "Setting up Advanced QoS with SQM ..."

    if ! uci -q get network.guest >/dev/null; then
        log_error "Guest network not found. Please setup Guest Network first!"
        return 1
    fi

    # Install SQM if needed
    if [ "${PKG_MANAGER:-opkg}" = "apk" ]; then
        apk add sqm-scripts >/dev/null 2>&1 || true
    else
        opkg update >/dev/null 2>&1
        opkg install sqm-scripts luci-app-sqm >/dev/null 2>&1 || true
    fi

    printf "  📥 Download limit for Guests (Mbps) [e.g. 15] : "
    read -r dl_limit </dev/tty
    [ -z "$dl_limit" ] && dl_limit=15

    printf "  📤 Upload limit for Guests (Mbps) [e.g. 5] : "
    read -r ul_limit </dev/tty
    [ -z "$ul_limit" ] && ul_limit=5

    local dl_kbit=$((dl_limit * 1000))
    local ul_kbit=$((ul_limit * 1000))

    # Configure SQM on guest interface
    uci set sqm.guest=queue
    uci set sqm.guest.enabled='1'
    uci set sqm.guest.interface='guest'
    uci set sqm.guest.download="$dl_kbit"
    uci set sqm.guest.upload="$ul_kbit"
    uci set sqm.guest.qdisc='cake'
    uci set sqm.guest.script='piece_of_cake.qos'
    uci set sqm.guest.linklayer='none'

    uci commit sqm
    /etc/init.d/sqm enable >/dev/null 2>&1
    /etc/init.d/sqm restart >/dev/null 2>&1

    log_success "SQM QoS applied → Download: ${dl_limit}Mbps | Upload: ${ul_limit}Mbps (Cake)"
}

# ------------------------------------------------------------
# Remove all Guest QoS
# ------------------------------------------------------------
remove_guest_qos() {
    log_info "Removing Guest QoS rules ..."

    # Remove simple tc
    rm -f /etc/guest_qos.sh
    sed -i '/guest_qos.sh/d' /etc/rc.local 2>/dev/null

    # Remove SQM config
    uci -q delete sqm.guest
    uci commit sqm
    /etc/init.d/sqm restart >/dev/null 2>&1

    # Clear tc rules
    for iface in br-guest guest; do
        tc qdisc del dev $iface root 2>/dev/null
        tc qdisc del dev $iface ingress 2>/dev/null
    done

    log_success "Guest QoS removed!"
}

# ------------------------------------------------------------
# Menu
# ------------------------------------------------------------
guest_qos_menu() {
    local HELP_MODULE_ID="network_guest_qos"

    while true; do
        render_persistent_header

        echo "  🚦 Guest Bandwidth Control (QoS)"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  1) Simple Limit (tc) - Lightweight"
        echo "  2) Advanced Limit (SQM + Cake) - Better quality"
        echo "  3) Remove all Guest QoS"
        ui_nav_footer
        ui_prompt 3
        choice="$UI_CHOICE"

        case "$choice" in
            1) setup_simple_qos ;;
            2) setup_sqm_qos ;;
            3) remove_guest_qos ;;
            q|Q) daypass_quit ;;
            h|H)
                if command -v show_help >/dev/null 2>&1; then
                    show_help "$HELP_MODULE_ID"
                else
                    log_warn "Help module not loaded!"
                    sleep 1
                fi
                continue
                ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press ENTER ...${RESET}"
        read -r _ </dev/tty || daypass_quit
    done
}

# 📄 Source : storage.sh
# ============================================================
# DayPass - Config Storage
# Local storage management for proxy configs
# ============================================================

PROXY_DIR="/etc/daypass/proxy"
CONFIG_DIR="$PROXY_DIR/configs"
mkdir -p "$CONFIG_DIR"

# ------------------------------------------------------------
# List all locally stored configs
# ------------------------------------------------------------
list_configs() {
    echo "  📋 Available Configs (DayPass storage)"
    echo "  ───────────────────────────────────────────────────────────"

    local count=0
    for file in "$CONFIG_DIR"/*.json; do
        [ -f "$file" ] || continue

        count=$((count + 1))
        name=$(basename "$file" .json)
        protocol=$(jq -r '.protocol // "unknown"' "$file" 2>/dev/null)
        enabled=$(jq -r 'if .enabled == false then "false" else "true" end' "$file" 2>/dev/null)
        subscription=$(jq -r '.subscription // empty' "$file" 2>/dev/null)

        status="${GREEN}ON${RESET}"
        [ "$enabled" = "false" ] && status="${GRAY}OFF${RESET}"

        if [ -n "$subscription" ]; then
            echo "  $count) $name  ${GRAY}($protocol)${RESET}  [$status]  ${GRAY}← $subscription${RESET}"
        else
            echo "  $count) $name  ${GRAY}($protocol)${RESET}  [$status]"
        fi
    done

    if [ "$count" -eq 0 ]; then
        echo "  ${GRAY}No configs found!${RESET}"
    else
        echo "  ───────────────────────────────────────────────────────────"
        echo "  Total: $count config(s)"
    fi
    echo "  ───────────────────────────────────────────────────────────"
}

# ------------------------------------------------------------
# Validate share link format (basic)
# ------------------------------------------------------------
validate_share_link() {
    local link="$1"

    case "$link" in
        vless://*|vmess://*|trojan://*|ss://*|hysteria2://*|hy2://*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ------------------------------------------------------------
# Detect protocol from share link
# ------------------------------------------------------------
detect_protocol_from_link() {
    local link="$1"

    case "$link" in
        vless://*)             echo "vless" ;;
        vmess://*)             echo "vmess" ;;
        trojan://*)            echo "trojan" ;;
        ss://*)                echo "ss" ;;
        hysteria2://*|hy2://*) echo "hysteria2" ;;
        *)                     echo "unknown" ;;
    esac
}

# ------------------------------------------------------------
# Add a manual config to local storage
# ------------------------------------------------------------
add_manual_config() {
    echo
    printf "  🎯 Config Name (example: MyVLESS) : "
    read -r conf_name </dev/tty

    # Basic name validation
    if [ -z "$conf_name" ]; then
        log_error "Name cannot be empty!"
        return 1
    fi

    # Prevent path traversal / invalid characters
    case "$conf_name" in
        *..*|*/*|*\\*|*\;*|*\&*)
            log_error "Invalid characters in config name!"
            return 1
            ;;
    esac

    # Check duplicate
    if [ -f "$CONFIG_DIR/${conf_name}.json" ]; then
        log_warn "Config [$conf_name] already exists!"
        printf "  ⁉️ Overwrite it? [y/N] : "
        read -r overwrite </dev/tty
        case "$overwrite" in
            y|Y) ;;
            *) log_info "Cancelled."; return 0 ;;
        esac
    fi

    printf "  🕊️ Paste full share link:\n  "
    read -r share_link </dev/tty

    if [ -z "$share_link" ]; then
        log_error "Share link is required!"
        return 1
    fi

    if ! validate_share_link "$share_link"; then
        log_error "Unsupported or invalid share link format!"
        log_info "Supported: vless:// | vmess:// | trojan:// | ss:// | hysteria2://"
        return 1
    fi

    # Auto-detect protocol from link (more reliable)
    local protocol
    protocol=$(detect_protocol_from_link "$share_link")

    cat > "$CONFIG_DIR/${conf_name}.json" << EOF
{
    "name": "$conf_name",
    "protocol": "$protocol",
    "share_link": "$share_link",
    "enabled": true,
    "added_at": "$(date -Iseconds)"
}
EOF

    log_success "Config [$conf_name] saved successfully! ${GRAY}($protocol)${RESET}"
}

# ------------------------------------------------------------
# Remove a config from local storage
# ------------------------------------------------------------
remove_config() {
    list_configs

    local total
    total=$(ls -1 "$CONFIG_DIR"/*.json 2>/dev/null | wc -l)
    if [ "$total" -eq 0 ]; then
        return 0
    fi

    printf "  🧼 Enter config name to remove : "
    read -r del_name </dev/tty

    if [ -z "$del_name" ]; then
        log_warn "No name entered!"
        return 1
    fi

    if [ -f "$CONFIG_DIR/${del_name}.json" ]; then
        printf "  ⁉️ Are you sure you want to delete [$del_name]? [y/N] : "
        read -r confirm </dev/tty
        case "$confirm" in
            y|Y)
                rm -f "$CONFIG_DIR/${del_name}.json"
                log_success "Config [$del_name] removed!"
                ;;
            *)
                log_info "Cancelled."
                ;;
        esac
    else
        log_error "Config not found!"
    fi
}

# ------------------------------------------------------------
# Enable / Disable a config
# ------------------------------------------------------------
toggle_config() {
    list_configs

    printf "  🔄 Enter config name to toggle enable/disable : "
    read -r conf_name </dev/tty

    local file="$CONFIG_DIR/${conf_name}.json"
    if [ ! -f "$file" ]; then
        log_error "Config not found!"
        return 1
    fi

    local current
    current=$(jq -r 'if .enabled == false then "false" else "true" end' "$file" 2>/dev/null)

    local new_value
    if [ "$current" = "true" ]; then
        new_value="false"
    else
        new_value="true"
    fi

    tmp=$(mktemp)
    jq --argjson val "$new_value" '.enabled = $val' "$file" > "$tmp" && mv "$tmp" "$file"

    if [ "$new_value" = "true" ]; then
        log_success "Config [$conf_name] enabled!"
    else
        log_warn "Config [$conf_name] disabled!"
    fi
}

# 📄 Source : subscription.sh
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

# 📄 Source : transport_bridge.sh
# ============================================================
# DayPass - Transport Bridge
# Engine-neutral control of proxy / VPN transports through driver hooks
# ============================================================
#
# Drivers (modules/network/transports/drivers/*.sh) implement tdrv_<engine>_<hook>.
#   Required : detect start stop status interception
#   Optional : reload apply_route_mode tproxy_port tunnel_device tunnel_network
#              dns_endpoint dns_configure list_nodes active_node select_node
#              push_node cleanup describe
#
# interception prints one of:
#   self   - the engine installs its own firewall interception (Passwall, Passwall2)
#   tproxy - DayPass steers LAN traffic to the engine's TPROXY inbound
#   tunnel - DayPass policy-routes LAN traffic into the engine's tunnel device
#
# transport_call returns 3 when a driver does not implement a hook.

PROXY_DIR="/etc/daypass/proxy"
CONFIG_DIR="$PROXY_DIR/configs"
TRANSPORT_DIR="${DAYPASS_DIR:-/etc/daypass}/transport"
TRANSPORT_ENGINES="passwall2 passwall singbox xray_direct wireguard openvpn"

transport_valid_engine() {
    [ -n "$1" ] || return 1
    case " $TRANSPORT_ENGINES " in
        *" $1 "*) return 0 ;;
    esac
    return 1
}

transport_has_hook() {
    command -v "tdrv_${1}_${2}" >/dev/null 2>&1
}

transport_call() {
    local engine="$1"
    local hook="$2"
    shift 2

    if ! transport_valid_engine "$engine"; then
        log_error "Unknown transport engine : [$engine]"
        return 1
    fi

    case "$hook" in
        ''|*[!a-z_]*)
            log_error "Invalid transport hook : [$hook]"
            return 1
            ;;
    esac

    transport_has_hook "$engine" "$hook" || return 3
    "tdrv_${engine}_${hook}" "$@"
}

# ------------------------------------------------------------
# Per-engine settings ($TRANSPORT_DIR/<engine>.conf, key=value)
# ------------------------------------------------------------
transport_opt_get() {
    local file="$TRANSPORT_DIR/$1.conf"
    local val=""

    [ -f "$file" ] && val=$(sed -n "s/^$2=//p" "$file" 2>/dev/null | tail -n 1)
    if [ -n "$val" ]; then
        echo "$val"
    else
        echo "${3:-}"
    fi
}

transport_opt_set() {
    local file="$TRANSPORT_DIR/$1.conf"

    case "$1$2" in
        *[!a-z0-9_]*) return 1 ;;
    esac
    mkdir -p "$TRANSPORT_DIR" 2>/dev/null || return 1

    {
        [ -f "$file" ] && grep -v "^$2=" "$file"
        [ -n "$3" ] && echo "$2=$3"
    } > "$file.tmp" && mv "$file.tmp" "$file"
}

# ------------------------------------------------------------
# Engine discovery & selection
# ------------------------------------------------------------
transport_engine_label() {
    case "$1" in
        passwall2)   echo "Passwall2" ;;
        passwall)    echo "Passwall" ;;
        singbox)     echo "sing-box (direct core)" ;;
        xray_direct) echo "Xray (direct core)" ;;
        wireguard)   echo "WireGuard" ;;
        openvpn)     echo "OpenVPN" ;;
        *)           echo "$1" ;;
    esac
}

transport_detect_engines() {
    local engine
    for engine in $TRANSPORT_ENGINES; do
        transport_call "$engine" detect >/dev/null 2>&1 && echo "$engine"
    done
}

# Saved engine if still installed, otherwise the first detected engine in priority order
get_active_engine() {
    local saved engine

    saved=$(cat "$TRANSPORT_DIR/active_engine" 2>/dev/null)
    if transport_valid_engine "$saved" && transport_call "$saved" detect >/dev/null 2>&1; then
        echo "$saved"
        return 0
    fi

    for engine in $TRANSPORT_ENGINES; do
        if transport_call "$engine" detect >/dev/null 2>&1; then
            echo "$engine"
            return 0
        fi
    done

    echo "none"
    return 1
}

set_active_engine() {
    local engine="$1"

    if ! transport_valid_engine "$engine"; then
        log_error "Unknown transport engine : [$engine]"
        return 1
    fi

    if ! transport_call "$engine" detect >/dev/null 2>&1; then
        log_error "Engine [$engine] is not installed or not configured!"
        return 1
    fi

    mkdir -p "$TRANSPORT_DIR" 2>/dev/null || return 1
    echo "$engine" > "$TRANSPORT_DIR/active_engine"
    log_success "Active transport engine : [$(transport_engine_label "$engine")]"
}

_transport_target_engine() {
    local engine="${1:-}"

    [ -z "$engine" ] && engine=$(get_active_engine)
    if [ "$engine" = "none" ]; then
        log_error "No transport engine installed (Passwall, Passwall2, sing-box, Xray, WireGuard or OpenVPN)!"
        return 1
    fi
    if ! transport_valid_engine "$engine"; then
        log_error "Unknown transport engine : [$engine]"
        return 1
    fi
    if ! transport_call "$engine" detect >/dev/null 2>&1; then
        log_error "Engine [$engine] is not installed or not configured!"
        return 1
    fi
    echo "$engine"
}

# ------------------------------------------------------------
# Standard engine hooks
# ------------------------------------------------------------
start_engine() {
    local engine
    engine=$(_transport_target_engine "${1:-}") || return 1

    log_info "Starting transport engine [$engine] ..."
    if transport_call "$engine" start; then
        log_success "Engine [$engine] started."
        return 0
    fi
    log_error "Engine [$engine] failed to start!"
    return 1
}

stop_engine() {
    local engine
    engine=$(_transport_target_engine "${1:-}") || return 1

    log_info "Stopping transport engine [$engine] ..."
    if transport_call "$engine" stop; then
        log_success "Engine [$engine] stopped."
        if [ "$(transport_call "$engine" interception)" = "tproxy" ] && \
            nft list table inet daypass >/dev/null 2>&1; then
            log_warn "LAN traffic is still steered to [$engine]. Choose Direct Only in Traffic Routing to restore direct access."
        fi
        return 0
    fi
    log_error "Engine [$engine] failed to stop!"
    return 1
}

# Prints "<engine> : running|stopped (details)"; returns 0 only when running
status_engine() {
    local engine detail rc
    engine=$(_transport_target_engine "${1:-}") || return 1

    detail=$(transport_call "$engine" status 2>/dev/null)
    rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "$engine : running${detail:+ ($detail)}"
        return 0
    fi
    echo "$engine : stopped${detail:+ ($detail)}"
    return 1
}

reload_rules() {
    local engine intercept rc
    engine=$(_transport_target_engine "${1:-}") || return 1
    intercept=$(transport_call "$engine" interception)

    log_info "Reloading rules for [$engine] ($intercept) ..."

    transport_call "$engine" reload
    rc=$?
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 3 ]; then
        log_error "Engine [$engine] failed to reload!"
        return 1
    fi

    if [ "$intercept" != "self" ] && command -v routing_reapply >/dev/null 2>&1; then
        routing_reapply "$engine" || return 1
    fi

    log_success "Rules reloaded for [$engine]."
    return 0
}

# ------------------------------------------------------------
# Tunnel helpers shared by WireGuard / OpenVPN drivers, routing and DNS
# ------------------------------------------------------------

# Prints the netifd interface carrying the engine's tunnel device, creating
# network.daypass_vpn (proto none) when the device is not managed by netifd.
transport_tunnel_network() {
    local engine="$1"
    local dev net sect

    net=$(transport_call "$engine" tunnel_network 2>/dev/null)
    if [ -n "$net" ]; then
        echo "$net"
        return 0
    fi

    dev=$(transport_call "$engine" tunnel_device 2>/dev/null)
    [ -n "$dev" ] || return 1

    for sect in $(uci -q show network 2>/dev/null | sed -n "s/^network\.\([^.]*\)=interface$/\1/p"); do
        if [ "$(uci -q get "network.$sect.device")" = "$dev" ] || [ "$(uci -q get "network.$sect.ifname")" = "$dev" ]; then
            echo "$sect"
            return 0
        fi
    done

    uci -q delete network.daypass_vpn
    uci set network.daypass_vpn=interface
    uci set network.daypass_vpn.proto='none'
    uci set network.daypass_vpn.device="$dev"
    uci commit network
    echo "daypass_vpn"
}

# $1 engine, $2 resolver IP (empty removes). Routes the resolver through the tunnel.
transport_tunnel_dns_route() {
    local engine="$1"
    local resolver="$2"
    local net

    uci -q delete network.daypass_dns_route

    if [ -n "$resolver" ]; then
        net=$(transport_tunnel_network "$engine") || return 1
        uci set network.daypass_dns_route=route
        uci set network.daypass_dns_route.interface="$net"
        uci set network.daypass_dns_route.target="${resolver}/32"
    fi

    uci commit network
    transport_opt_set "$engine" dns_resolver "$resolver"
    /etc/init.d/network reload >/dev/null 2>&1 || true
    return 0
}

# ------------------------------------------------------------
# URL decode helper (basic)
# ------------------------------------------------------------
url_decode() {
    echo "$1" | sed 's/+/ /g;s/%/\\x/g' | xargs -0 printf "%b" 2>/dev/null || echo "$1"
}

# ------------------------------------------------------------
# Share link parser
# Supports: vless (incl. Reality), vmess, trojan, ss (legacy + SIP002),
#           ssr, hysteria, hysteria2, tuic, anytls, naive+https/quic
# Sets PARSED_* for the caller. Returns 1 for an unsupported scheme or
# when no server address could be extracted.
# ------------------------------------------------------------

# base64 decode tolerating the url-safe alphabet and missing padding
_sl_b64() {
    local data pad

    data=$(printf '%s' "$1" | tr -d '\r\n' | tr '_-' '/+')
    [ -n "$data" ] || return 1

    pad=$(( ${#data} % 4 ))
    case "$pad" in
        2) data="${data}==" ;;
        3) data="${data}=" ;;
        1) return 1 ;;
    esac

    printf '%s' "$data" | base64 -d 2>/dev/null
}

# $1 query string, $2.. parameter names; prints the first one that is set
_sl_query() {
    local query="$1"
    local key val

    shift
    for key in "$@"; do
        val=$(printf '%s\n' "$query" | tr '&;' '\n\n' | sed -n "s/^${key}=//p" | head -n 1)
        if [ -n "$val" ]; then
            url_decode "$val"
            return 0
        fi
    done
    return 1
}

# $1 JSON document, $2 key
_sl_json() {
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$1" | jq -r --arg k "$2" '.[$k] // empty | tostring' 2>/dev/null
        return 0
    fi

    printf '%s' "$1" | tr ',{' '\n\n' | \
        sed -n "s/^[[:space:]]*\"$2\"[[:space:]]*:[[:space:]]*//p" | head -n 1 | \
        sed 's/^"//;s/"[[:space:]]*}*[[:space:]]*$//;s/[[:space:]]*}*[[:space:]]*$//'
}

# Sets SL_HOST / SL_PORT from host:port, [v6]:port, host:443,8443 or host:443-500
_sl_hostport() {
    local hp="${1%%/*}"

    SL_HOST=""
    SL_PORT=""

    case "$hp" in
        '['*)
            SL_HOST=${hp#\[}
            SL_HOST=${SL_HOST%%\]*}
            SL_PORT=${hp##*\]}
            SL_PORT=${SL_PORT#:}
            ;;
        *:*:*)
            # bare IPv6 literal (brackets are required to carry a port)
            SL_HOST="$hp"
            ;;
        *:*)
            SL_HOST=${hp%:*}
            SL_PORT=${hp##*:}
            ;;
        *)
            SL_HOST="$hp"
            ;;
    esac

    # hysteria2 / tuic may advertise a port list or range: keep the first port
    SL_PORT=${SL_PORT%%,*}
    SL_PORT=${SL_PORT%%-*}
    case "$SL_PORT" in
        ''|*[!0-9]*) SL_PORT="" ;;
    esac
}

# Splits a scheme-less "userinfo@host:port?query#fragment" body
_sl_uri() {
    local body="$1"

    SL_USERINFO=""
    SL_QUERY=""
    SL_FRAGMENT=""

    case "$body" in *'#'*) SL_FRAGMENT=${body#*#}; body=${body%%#*} ;; esac
    case "$body" in *'?'*) SL_QUERY=${body#*\?};   body=${body%%\?*} ;; esac
    case "$body" in *@*)   SL_USERINFO=${body%@*}; body=${body##*@}  ;; esac

    _sl_hostport "$body"
}

# Transport name -> PARSED_L4
_sl_l4_from_network() {
    case "$1" in
        kcp|mkcp|quic) PARSED_L4="udp" ;;
        *)             PARSED_L4="tcp" ;;
    esac
}

parse_share_link() {
    local link="$1"
    local scheme body json creds decoded frag rest query hostpart
    local sr_host sr_port sr_proto sr_method sr_obfs sr_pass

    PARSED_PROTOCOL=""
    PARSED_ADDRESS=""
    PARSED_PORT=""
    PARSED_UUID=""
    PARSED_PASSWORD=""
    PARSED_METHOD=""
    PARSED_REMARKS=""
    PARSED_NETWORK=""
    PARSED_SECURITY=""
    PARSED_SNI=""
    PARSED_FLOW=""
    PARSED_FP=""
    PARSED_PBK=""
    PARSED_SID=""
    PARSED_SPX=""
    PARSED_PATH=""
    PARSED_HOST_HEADER=""
    PARSED_L4="tcp"

    case "$link" in
        *://*)
            scheme=${link%%://*}
            body=${link#*://}
            ;;
        *)
            return 1
            ;;
    esac

    case "$scheme" in
        vless)
            PARSED_PROTOCOL="vless"
            _sl_uri "$body"

            PARSED_UUID=$(url_decode "$SL_USERINFO")
            PARSED_ADDRESS="$SL_HOST"
            PARSED_PORT="$SL_PORT"
            PARSED_NETWORK=$(_sl_query "$SL_QUERY" type) || PARSED_NETWORK="tcp"
            PARSED_SECURITY=$(_sl_query "$SL_QUERY" security) || PARSED_SECURITY="none"
            PARSED_SNI=$(_sl_query "$SL_QUERY" sni peer servername)
            PARSED_FLOW=$(_sl_query "$SL_QUERY" flow)
            PARSED_FP=$(_sl_query "$SL_QUERY" fp fingerprint)
            PARSED_PBK=$(_sl_query "$SL_QUERY" pbk publicKey)
            PARSED_SID=$(_sl_query "$SL_QUERY" sid shortId)
            PARSED_SPX=$(_sl_query "$SL_QUERY" spx spiderX)
            PARSED_PATH=$(_sl_query "$SL_QUERY" path serviceName)
            PARSED_HOST_HEADER=$(_sl_query "$SL_QUERY" host authority)
            PARSED_REMARKS=$(url_decode "$SL_FRAGMENT")
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="VLESS-Node"
            _sl_l4_from_network "$PARSED_NETWORK"
            ;;

        vmess)
            PARSED_PROTOCOL="vmess"
            json=$(_sl_b64 "${body%%#*}")

            case "$json" in
                '{'*)
                    PARSED_ADDRESS=$(_sl_json "$json" add)
                    PARSED_PORT=$(_sl_json "$json" port)
                    PARSED_UUID=$(_sl_json "$json" id)
                    PARSED_REMARKS=$(_sl_json "$json" ps)
                    PARSED_NETWORK=$(_sl_json "$json" net)
                    PARSED_PATH=$(_sl_json "$json" path)
                    PARSED_HOST_HEADER=$(_sl_json "$json" host)
                    PARSED_SECURITY=$(_sl_json "$json" tls)
                    PARSED_SNI=$(_sl_json "$json" sni)
                    PARSED_FP=$(_sl_json "$json" fp)
                    PARSED_FLOW=$(_sl_json "$json" flow)
                    ;;
                *)
                    # Xray-style vmess URI: vmess://uuid@host:port?type=...
                    _sl_uri "$body"
                    PARSED_UUID=$(url_decode "$SL_USERINFO")
                    PARSED_ADDRESS="$SL_HOST"
                    PARSED_PORT="$SL_PORT"
                    PARSED_NETWORK=$(_sl_query "$SL_QUERY" type)
                    PARSED_SECURITY=$(_sl_query "$SL_QUERY" security)
                    PARSED_SNI=$(_sl_query "$SL_QUERY" sni peer)
                    PARSED_FP=$(_sl_query "$SL_QUERY" fp fingerprint)
                    PARSED_PATH=$(_sl_query "$SL_QUERY" path serviceName)
                    PARSED_HOST_HEADER=$(_sl_query "$SL_QUERY" host)
                    PARSED_REMARKS=$(url_decode "$SL_FRAGMENT")
                    ;;
            esac

            [ -z "$PARSED_NETWORK" ] && PARSED_NETWORK="tcp"
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="VMess-Node"
            _sl_l4_from_network "$PARSED_NETWORK"
            ;;

        trojan)
            PARSED_PROTOCOL="trojan"
            _sl_uri "$body"

            PARSED_PASSWORD=$(url_decode "$SL_USERINFO")
            PARSED_ADDRESS="$SL_HOST"
            PARSED_PORT="$SL_PORT"
            PARSED_NETWORK=$(_sl_query "$SL_QUERY" type) || PARSED_NETWORK="tcp"
            PARSED_SECURITY=$(_sl_query "$SL_QUERY" security) || PARSED_SECURITY="tls"
            PARSED_SNI=$(_sl_query "$SL_QUERY" sni peer servername)
            PARSED_FP=$(_sl_query "$SL_QUERY" fp fingerprint)
            PARSED_PBK=$(_sl_query "$SL_QUERY" pbk publicKey)
            PARSED_SID=$(_sl_query "$SL_QUERY" sid shortId)
            PARSED_SPX=$(_sl_query "$SL_QUERY" spx spiderX)
            PARSED_PATH=$(_sl_query "$SL_QUERY" path serviceName)
            PARSED_HOST_HEADER=$(_sl_query "$SL_QUERY" host authority)
            PARSED_REMARKS=$(url_decode "$SL_FRAGMENT")
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="Trojan-Node"
            _sl_l4_from_network "$PARSED_NETWORK"
            ;;

        ss)
            PARSED_PROTOCOL="shadowsocks"

            frag=""
            rest="$body"
            case "$rest" in *'#'*) frag=${rest#*#}; rest=${rest%%#*} ;; esac
            query=""
            case "$rest" in *'?'*) query=${rest#*\?}; rest=${rest%%\?*} ;; esac

            case "$rest" in
                *@*)
                    # SIP002: ss://base64(method:password)@host:port
                    creds=${rest%@*}
                    hostpart=${rest##*@}
                    decoded=$(_sl_b64 "$creds")
                    case "$decoded" in
                        *:*) creds="$decoded" ;;
                        *)   creds=$(url_decode "$creds") ;;
                    esac
                    _sl_hostport "$hostpart"
                    ;;
                *)
                    # legacy: ss://base64(method:password@host:port)
                    decoded=$(_sl_b64 "$rest")
                    case "$decoded" in
                        *@*)
                            creds=${decoded%@*}
                            _sl_hostport "${decoded##*@}"
                            ;;
                        *)
                            creds=""
                            ;;
                    esac
                    ;;
            esac

            PARSED_ADDRESS="$SL_HOST"
            PARSED_PORT="$SL_PORT"
            PARSED_METHOD=${creds%%:*}
            case "$creds" in
                *:*) PARSED_PASSWORD=${creds#*:} ;;
            esac
            PARSED_HOST_HEADER=$(_sl_query "$query" obfs-host)
            PARSED_REMARKS=$(url_decode "$frag")
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="SS-Node"
            ;;

        ssr)
            PARSED_PROTOCOL="ssr"
            # ssr://base64(host:port:protocol:method:obfs:base64(password)/?params)
            decoded=$(_sl_b64 "${body%%#*}")
            [ -n "$decoded" ] || return 1

            query=""
            case "$decoded" in *'?'*) query=${decoded#*\?}; decoded=${decoded%%\?*} ;; esac
            decoded=${decoded%/}

            IFS=':' read -r sr_host sr_port sr_proto sr_method sr_obfs sr_pass << EOF
$decoded
EOF
            PARSED_ADDRESS="$sr_host"
            PARSED_PORT="$sr_port"
            PARSED_METHOD="$sr_method"
            PARSED_PASSWORD=$(_sl_b64 "$sr_pass")
            # sr_proto / sr_obfs are SSR plugin names with no PARSED_* equivalent;
            # subscribe.lua reads them from the link itself when importing.
            PARSED_REMARKS=$(_sl_b64 "$(_sl_query "$query" remarks)")
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="SSR-Node"
            ;;

        hysteria)
            PARSED_PROTOCOL="hysteria"
            _sl_uri "$body"

            PARSED_ADDRESS="$SL_HOST"
            PARSED_PORT="$SL_PORT"
            PARSED_PASSWORD=$(_sl_query "$SL_QUERY" auth auth_str authStr)
            [ -z "$PARSED_PASSWORD" ] && PARSED_PASSWORD=$(url_decode "$SL_USERINFO")
            PARSED_SNI=$(_sl_query "$SL_QUERY" peer sni)
            PARSED_SECURITY="tls"
            PARSED_NETWORK=$(_sl_query "$SL_QUERY" protocol) || PARSED_NETWORK="udp"
            PARSED_REMARKS=$(url_decode "$SL_FRAGMENT")
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="Hysteria-Node"
            PARSED_L4="udp"
            ;;

        hysteria2|hy2)
            PARSED_PROTOCOL="hysteria2"
            _sl_uri "$body"

            PARSED_ADDRESS="$SL_HOST"
            PARSED_PORT="$SL_PORT"
            PARSED_PASSWORD=$(url_decode "$SL_USERINFO")
            PARSED_SNI=$(_sl_query "$SL_QUERY" sni peer)
            PARSED_SECURITY="tls"
            PARSED_REMARKS=$(url_decode "$SL_FRAGMENT")
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="Hysteria2-Node"
            PARSED_L4="udp"
            ;;

        tuic)
            PARSED_PROTOCOL="tuic"
            _sl_uri "$body"

            PARSED_ADDRESS="$SL_HOST"
            PARSED_PORT="$SL_PORT"
            PARSED_UUID=$(url_decode "${SL_USERINFO%%:*}")
            case "$SL_USERINFO" in
                *:*) PARSED_PASSWORD=$(url_decode "${SL_USERINFO#*:}") ;;
            esac
            PARSED_SNI=$(_sl_query "$SL_QUERY" sni peer)
            PARSED_SECURITY="tls"
            PARSED_REMARKS=$(url_decode "$SL_FRAGMENT")
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="TUIC-Node"
            PARSED_L4="udp"
            ;;

        anytls)
            PARSED_PROTOCOL="anytls"
            _sl_uri "$body"

            PARSED_ADDRESS="$SL_HOST"
            PARSED_PORT="$SL_PORT"
            case "$SL_USERINFO" in
                *:*)
                    PARSED_UUID=$(url_decode "${SL_USERINFO%%:*}")
                    PARSED_PASSWORD=$(url_decode "${SL_USERINFO#*:}")
                    ;;
                *)
                    PARSED_PASSWORD=$(url_decode "$SL_USERINFO")
                    ;;
            esac
            PARSED_SNI=$(_sl_query "$SL_QUERY" sni peer servername)
            PARSED_FP=$(_sl_query "$SL_QUERY" fp fingerprint)
            PARSED_SECURITY="tls"
            PARSED_REMARKS=$(url_decode "$SL_FRAGMENT")
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="AnyTLS-Node"
            ;;

        naive|naive+https|naive+quic)
            PARSED_PROTOCOL="naive"
            _sl_uri "$body"

            PARSED_ADDRESS="$SL_HOST"
            PARSED_PORT="$SL_PORT"
            PARSED_UUID=$(url_decode "${SL_USERINFO%%:*}")
            case "$SL_USERINFO" in
                *:*) PARSED_PASSWORD=$(url_decode "${SL_USERINFO#*:}") ;;
            esac
            PARSED_SNI=$(_sl_query "$SL_QUERY" sni peer)
            PARSED_SECURITY="tls"
            case "$scheme" in
                *quic) PARSED_NETWORK="quic"; PARSED_L4="udp" ;;
                *)     PARSED_NETWORK="https" ;;
            esac
            PARSED_REMARKS=$(url_decode "$SL_FRAGMENT")
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="Naive-Node"
            ;;

        *)
            return 1
            ;;
    esac

    [ -n "$PARSED_ADDRESS" ] || return 1
    return 0
}

# ------------------------------------------------------------
# Push local share-link configs into the active engine
# ------------------------------------------------------------
transport_push_config() {
    local conf_name="$1"
    local file="$CONFIG_DIR/${conf_name}.json"
    local engine rc

    if [ ! -f "$file" ]; then
        log_error "Config not found: [$conf_name]"
        return 1
    fi

    engine=$(_transport_target_engine "") || return 1

    transport_call "$engine" push_node "$file" "$conf_name"
    rc=$?
    if [ "$rc" -eq 3 ]; then
        log_error "Engine [$engine] cannot import share links. Add the node in its own configuration."
        return 1
    fi
    return "$rc"
}

transport_push_all() {
    local engine name file
    local count=0
    local success=0

    engine=$(_transport_target_engine "") || return 1
    if ! transport_has_hook "$engine" push_node; then
        log_error "Engine [$engine] cannot import share links. Add the node in its own configuration."
        return 1
    fi

    log_info "Pushing all configs to [$engine] ..."

    for file in "$CONFIG_DIR"/*.json; do
        [ -f "$file" ] || continue
        name=$(basename "$file" .json)
        count=$((count + 1))

        if transport_push_config "$name"; then
            success=$((success + 1))
        fi
    done

    if [ "$count" -eq 0 ]; then
        log_warn "No configs to push!"
    else
        log_success "Finished: $success / $count config(s) processed."
    fi
}

push_config_to_passwall() {
    transport_push_config "$@"
}

push_all_to_passwall() {
    transport_push_all "$@"
}

# ------------------------------------------------------------
# Endpoint probing (engine-neutral)
# Sets PROBE_STATE (up|down|unknown), PROBE_MS, PROBE_METHOD
# Returns 0 up, 1 down, 2 unknown (UDP endpoint without ICMP reply)
# ------------------------------------------------------------
_transport_now_ms() {
    local ns up
    ns=$(date +%s%N 2>/dev/null)
    case "$ns" in
        ''|*[!0-9]*) ;;
        *)
            if [ "${#ns}" -ge 13 ]; then
                echo $((ns / 1000000))
                return 0
            fi
            ;;
    esac

    up=$(cut -d' ' -f1 /proc/uptime 2>/dev/null)
    case "$up" in
        *.*) echo $(( ${up%.*} * 1000 + $(echo "${up#*.}0" | cut -c1-2 | sed 's/^0*//;s/^$/0/') * 10 )) ;;
        *)   return 1 ;;
    esac
}

_transport_tcp_connect() {
    if [ -z "${_TRANSPORT_NC_Z:-}" ]; then
        if nc -z 127.0.0.1 1 2>&1 </dev/null | grep -qiE 'invalid|unrecognized|illegal|usage'; then
            _TRANSPORT_NC_Z=0
        else
            _TRANSPORT_NC_Z=1
        fi
    fi

    if [ "$_TRANSPORT_NC_Z" = "1" ]; then
        nc -z -w 3 "$1" "$2" </dev/null >/dev/null 2>&1
    else
        nc -w 3 "$1" "$2" </dev/null >/dev/null 2>&1
    fi
}

transport_probe() {
    local host="$1"
    local port="$2"
    local l4="${3:-tcp}"
    local t0 t1 ms

    PROBE_STATE="down"
    PROBE_MS=""
    PROBE_METHOD=""

    [ -n "$host" ] || return 1

    if [ "$l4" != "udp" ] && [ -n "$port" ] && command -v nc >/dev/null 2>&1; then
        t0=$(_transport_now_ms)
        if _transport_tcp_connect "$host" "$port"; then
            t1=$(_transport_now_ms)
            PROBE_STATE="up"
            PROBE_METHOD="tcp"
            [ -n "$t0" ] && [ -n "$t1" ] && PROBE_MS=$((t1 - t0))
            return 0
        fi
        PROBE_METHOD="tcp"
        return 1
    fi

    if command -v ping >/dev/null 2>&1; then
        ms=$(ping -c 1 -W 2 "$host" 2>/dev/null | sed -n 's/.*time[=<]\([0-9.]*\).*/\1/p' | head -n 1)
        if [ -n "$ms" ]; then
            PROBE_STATE="up"
            PROBE_METHOD="icmp"
            PROBE_MS="${ms%%.*}"
            [ -z "$PROBE_MS" ] && PROBE_MS=0
            return 0
        fi
    fi

    if [ "$l4" = "udp" ]; then
        PROBE_STATE="unknown"
        PROBE_METHOD="icmp"
        return 2
    fi
    return 1
}


# 📄 Source : core_common.sh
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


# 📄 Source : passwall.sh
# ============================================================
# DayPass - Transport driver : Passwall / Passwall2
# Both apps install their own nftables/iptables interception (interception=self)
# ============================================================

# Returns: passwall2 | passwall | none
detect_passwall_version() {
    if [ -f /etc/config/passwall2 ] || uci -q show passwall2 >/dev/null 2>&1; then
        echo "passwall2"
        return
    fi

    if [ -f /etc/config/passwall ] || uci -q show passwall >/dev/null 2>&1; then
        echo "passwall"
        return
    fi

    if command -v pkg_installed >/dev/null 2>&1; then
        if pkg_installed "luci-app-passwall2" || pkg_installed "passwall2"; then
            echo "passwall2"
            return
        fi
        if pkg_installed "luci-app-passwall" || pkg_installed "passwall"; then
            echo "passwall"
            return
        fi
    fi

    echo "none"
}

_pw_detect() {
    [ -f "/etc/config/$1" ] || uci -q show "$1" >/dev/null 2>&1 || [ -x "/etc/init.d/$1" ]
}

# ------------------------------------------------------------
# Sections DayPass owns inside the Passwall config
# ------------------------------------------------------------
PW_SHUNT_ID="daypass_shunt"
PW_SHUNT_RULE_ID="daypass_ir_rule"
PW_BALANCER_ID="daypass_balancer"
PW_SUBSCRIBE_GROUP="DayPass"

# Node ids DayPass generates itself; these never point at a real server
_pw_is_synthetic_node() {
    case "$1" in
        "$PW_SHUNT_ID"|"$PW_BALANCER_ID") return 0 ;;
    esac
    return 1
}

_pw_node_ids() {
    uci -q show "$1" 2>/dev/null | sed -n "s/^$1\.\([^.]*\)=nodes$/\1/p"
}

_pw_is_node() {
    [ "$(uci -q get "$1.$2" 2>/dev/null)" = "nodes" ]
}

_pw_node_id_by_remarks() {
    local pkg="$1"
    local want="$2"
    local sect

    [ -n "$want" ] || return 1
    for sect in $(_pw_node_ids "$pkg"); do
        if [ "$(uci -q get "$pkg.$sect.remarks" 2>/dev/null)" = "$want" ]; then
            echo "$sect"
            return 0
        fi
    done
    return 1
}

# Prints the real server node the user picked. When @global[0].node points at
# one of DayPass's synthetic nodes, the real one is recovered from it.
_pw_real_node() {
    local pkg="$1"
    local cur cand

    cur=$(uci -q get "$pkg.@global[0].node" 2>/dev/null)
    [ -z "$cur" ] && cur=$(uci -q get "$pkg.@global[0].tcp_node" 2>/dev/null)
    if [ -n "$cur" ] && ! _pw_is_synthetic_node "$cur" && _pw_is_node "$pkg" "$cur"; then
        echo "$cur"
        return 0
    fi

    for cand in \
        "$(uci -q get "$pkg.$PW_SHUNT_ID.default_node" 2>/dev/null)" \
        "$(transport_opt_get "$pkg" real_node)" \
        "$(uci -q get "$pkg.$PW_BALANCER_ID.fallback_node" 2>/dev/null)" \
        "$(uci -q get "$pkg.$PW_BALANCER_ID.balancing_node" 2>/dev/null | cut -d' ' -f1)"
    do
        if [ -n "$cand" ] && ! _pw_is_synthetic_node "$cand" && _pw_is_node "$pkg" "$cand"; then
            echo "$cand"
            return 0
        fi
    done
    return 1
}

# Points Passwall at a node id (v2 uses 'node', v1 uses tcp_node / udp_node)
_pw_set_global_node() {
    local pkg="$1"
    local id="$2"
    local udp

    uci set "$pkg.@global[0].node=$id"
    if uci -q get "$pkg.@global[0].tcp_node" >/dev/null 2>&1; then
        uci set "$pkg.@global[0].tcp_node=$id"
    fi

    udp=$(uci -q get "$pkg.@global[0].udp_node" 2>/dev/null)
    case "$udp" in
        ''|nil|tcp) ;;   # unset, disabled or "same as TCP": leave the user's choice
        *) uci set "$pkg.@global[0].udp_node=$id" ;;
    esac
}

# Moves @global[0].node off a synthetic node back onto the real one
_pw_restore_real_node() {
    local pkg="$1"
    local cur real

    cur=$(uci -q get "$pkg.@global[0].node" 2>/dev/null)
    [ -z "$cur" ] && cur=$(uci -q get "$pkg.@global[0].tcp_node" 2>/dev/null)
    _pw_is_synthetic_node "$cur" || return 0

    if real=$(_pw_real_node "$pkg"); then
        _pw_set_global_node "$pkg" "$real"
        return 0
    fi

    log_warn "Could not work out which real node to restore in $pkg; pick one from its node list."
    return 1
}

_pw_service() {
    [ -x "/etc/init.d/$1" ] || return 1
    /etc/init.d/"$1" "$2" >/dev/null 2>&1
}

_pw_reload() {
    _pw_service "$1" reload || _pw_service "$1" restart || true
}

# Set a UCI option on the first matching Passwall section that already exists.
_pw_set() {
    local pkg="$1"
    local key="$2"
    local val="$3"
    local sect

    for sect in global global_dns global_forwarding global_other; do
        if uci -q get "${pkg}.@${sect}[0]" >/dev/null 2>&1; then
            uci set "${pkg}.@${sect}[0].${key}=${val}" 2>/dev/null && return 0
        fi
    done
    uci set "${pkg}.@global[0].${key}=${val}" 2>/dev/null || return 1
}

_pw_get() {
    local pkg="$1"
    local key="$2"
    local sect val

    for sect in global global_dns global_forwarding global_other; do
        val=$(uci -q get "${pkg}.@${sect}[0].${key}" 2>/dev/null) || true
        if [ -n "$val" ]; then
            echo "$val"
            return 0
        fi
    done
    return 1
}

_pw_start() {
    uci set "$1.@global[0].enabled=1" 2>/dev/null
    uci commit "$1"
    _pw_service "$1" restart || _pw_service "$1" start
}

_pw_stop() {
    _pw_service "$1" stop
}

_pw_status() {
    local enabled
    enabled=$(uci -q get "$1.@global[0].enabled" 2>/dev/null)

    if nft list table inet "$1" >/dev/null 2>&1 || iptables -t mangle -S 2>/dev/null | grep -qi "$1"; then
        echo "interception active, enabled=${enabled:-0}"
        return 0
    fi
    if pgrep -f "/usr/share/$1/" >/dev/null 2>&1; then
        echo "processes running, enabled=${enabled:-0}"
        return 0
    fi
    echo "enabled=${enabled:-0}"
    return 1
}

# Iran-direct routing the way Passwall really does it: a _shunt node that sends
# Iranian domains / IPs straight out and everything else to the chosen node.
# tcp_proxy_mode / udp_proxy_mode only accept "disable" or "proxy".
_pw_apply_iran_direct() {
    local pkg="$1"
    local node rule core domains

    if ! node=$(_pw_real_node "$pkg"); then
        log_error "No proxy node is selected in $pkg. Pick a node first (Transport Engines -> Show Nodes, or Config Manager)."
        return 1
    fi

    core=$(uci -q get "$pkg.$node.type" 2>/dev/null)
    [ -n "$core" ] || core="Xray"

    domains="geosite:category-ir
geosite:ir"

    rule="$PW_SHUNT_RULE_ID"
    uci -q delete "$pkg.$rule"
    uci set "$pkg.$rule=shunt_rules"
    uci set "$pkg.$rule.remarks=DayPass Iran Direct"
    uci set "$pkg.$rule.network=tcp,udp"
    uci set "$pkg.$rule.domain_list=$domains"
    uci set "$pkg.$rule.ip_list=geoip:ir"

    uci -q delete "$pkg.$PW_SHUNT_ID"
    uci set "$pkg.$PW_SHUNT_ID=nodes"
    uci set "$pkg.$PW_SHUNT_ID.remarks=DayPass Iran Direct"
    uci set "$pkg.$PW_SHUNT_ID.type=$core"
    uci set "$pkg.$PW_SHUNT_ID.protocol=_shunt"
    uci set "$pkg.$PW_SHUNT_ID.default_node=$node"
    # Per-rule option: the shunt_rules section id carries the target
    uci set "$pkg.$PW_SHUNT_ID.$rule=_direct"

    transport_opt_set "$pkg" real_node "$node"

    uci set "$pkg.@global[0].enabled=1"
    _pw_set_global_node "$pkg" "$PW_SHUNT_ID"
    uci set "$pkg.@global[0].tcp_proxy_mode=proxy"
    uci set "$pkg.@global[0].udp_proxy_mode=proxy"
    if [ "$pkg" = "passwall2" ]; then
        uci set "$pkg.@global[0].localhost_proxy=0" 2>/dev/null || true
    fi
    return 0
}

_pw_apply_route_mode() {
    local pkg="$1"

    case "$2" in
        iran_direct)
            _pw_apply_iran_direct "$pkg" || return 1
            ;;
        global_proxy)
            _pw_restore_real_node "$pkg"
            uci set "$pkg.@global[0].enabled=1" 2>/dev/null
            uci set "$pkg.@global[0].tcp_proxy_mode=proxy" 2>/dev/null
            uci set "$pkg.@global[0].udp_proxy_mode=proxy" 2>/dev/null
            ;;
        direct_only)
            _pw_restore_real_node "$pkg"
            uci set "$pkg.@global[0].enabled=0" 2>/dev/null
            uci set "$pkg.@global[0].tcp_proxy_mode=disable" 2>/dev/null
            uci set "$pkg.@global[0].udp_proxy_mode=disable" 2>/dev/null
            ;;
        *)
            return 1
            ;;
    esac

    uci commit "$pkg"
    _pw_reload "$pkg"
    return 0
}

# Port Passwall listens on for local DNS (dnsmasq upstream).
_pw_dns_listen_port() {
    local pkg="$1"
    local raw port

    port=$(_pw_get "$pkg" dns_listen_port 2>/dev/null) || true
    [ -z "$port" ] && port=$(_pw_get "$pkg" dns_port 2>/dev/null) || true
    [ -z "$port" ] && port=$(_pw_get "$pkg" listen_port 2>/dev/null) || true
    if [ -z "$port" ]; then
        raw=$(_pw_get "$pkg" dns_listen 2>/dev/null) || true
        port=$(echo "$raw" | sed -n 's/.*[#:]\([0-9][0-9]*\)$/\1/p')
    fi
    if [ -n "$port" ]; then
        echo "$port"
        return
    fi
    if [ "$pkg" = "passwall" ]; then
        echo "7913"
    else
        echo "15353"
    fi
}

# dns_mode exists on Passwall v1 only and accepts udp / tcp / dns2socks /
# sing-box / xray - never "doh". Passwall2 has no dns_mode, no v2ray_dns_mode
# and no dns_doh at all; there the DoH URL lives in remote_dns_doh.
_pw_set_v1_dns_mode() {
    local pkg="$1"

    [ "$pkg" = "passwall" ] || return 0
    case "$2" in
        udp|tcp|dns2socks|sing-box|xray) _pw_set "$pkg" "dns_mode" "$2" || true ;;
    esac
}

# Core that resolves DoH on Passwall v1, following the active node's own core
_pw_dns_core() {
    local pkg="$1"
    local node type=""

    node=$(_pw_real_node "$pkg" 2>/dev/null) && \
        type=$(uci -q get "$pkg.$node.type" 2>/dev/null)

    case "$type" in
        *[Ss]ing*) echo "sing-box" ;;
        *)         echo "xray" ;;
    esac
}

_pw_dns_configure() {
    local pkg="$1"
    local doh="${DNS_DOH_URL:-https://cloudflare-dns.com/dns-query}"
    local remote="${DNS_CF:-1.1.1.1}"

    case "$2" in
        off)
            _pw_set "$pkg" "dns_redirect" "0" || true
            uci commit "$pkg" 2>/dev/null || true
            _pw_reload "$pkg"
            return 0
            ;;
        doh)
            _pw_set "$pkg" "enabled" "1" || true
            _pw_set "$pkg" "dns_redirect" "1" || true
            _pw_set "$pkg" "remote_dns" "$remote" || true
            _pw_set "$pkg" "remote_dns_protocol" "doh" || true
            _pw_set "$pkg" "remote_dns_doh" "$doh" || true
            _pw_set_v1_dns_mode "$pkg" "$(_pw_dns_core "$pkg")"
            ;;
        tunnel)
            _pw_set "$pkg" "enabled" "1" || true
            _pw_set "$pkg" "dns_redirect" "1" || true
            _pw_set "$pkg" "remote_dns" "$remote" || true
            _pw_set "$pkg" "remote_dns_protocol" "tcp" || true
            _pw_set_v1_dns_mode "$pkg" "tcp"
            ;;
        hybrid)
            _pw_set "$pkg" "enabled" "1" || true
            _pw_set "$pkg" "dns_redirect" "1" || true
            _pw_set "$pkg" "direct_dns" "$remote" || true
            _pw_set "$pkg" "direct_dns_protocol" "doh" || true
            _pw_set "$pkg" "direct_dns_doh" "$doh" || true
            _pw_set "$pkg" "remote_dns" "$remote" || true
            _pw_set "$pkg" "remote_dns_protocol" "doh" || true
            _pw_set "$pkg" "remote_dns_doh" "$doh" || true
            _pw_set_v1_dns_mode "$pkg" "$(_pw_dns_core "$pkg")"
            ;;
        *)
            return 3
            ;;
    esac

    uci commit "$pkg" 2>/dev/null || true
    _pw_reload "$pkg"
    return 0
}

# id|name|protocol|host|port|l4
_pw_list_nodes() {
    local pkg="$1"
    local sect name proto host port l4

    for sect in $(uci -q show "$pkg" 2>/dev/null | sed -n "s/^$pkg\.\([^.]*\)=nodes$/\1/p"); do
        host=$(uci -q get "$pkg.$sect.address")
        [ -n "$host" ] || continue
        port=$(uci -q get "$pkg.$sect.port")
        name=$(uci -q get "$pkg.$sect.remarks" | tr '|' '/')
        proto=$(uci -q get "$pkg.$sect.protocol")
        [ -z "$proto" ] && proto=$(uci -q get "$pkg.$sect.type")
        case "$proto" in
            hysteria*|tuic|wireguard|WireGuard) l4="udp" ;;
            *) l4="tcp" ;;
        esac
        printf '%s|%s|%s|%s|%s|%s\n' "$sect" "${name:-$sect}" "${proto:-unknown}" "$host" "$port" "$l4"
    done
}

# Reports the real server node, resolving through the Iran-direct shunt
_pw_active_node() {
    local cur

    cur=$(uci -q get "$1.@global[0].node" 2>/dev/null)
    [ -z "$cur" ] && cur=$(uci -q get "$1.@global[0].tcp_node" 2>/dev/null)

    if [ "$cur" = "$PW_SHUNT_ID" ]; then
        uci -q get "$1.$PW_SHUNT_ID.default_node" 2>/dev/null
        return 0
    fi

    [ -n "$cur" ] && echo "$cur"
}

_pw_select_node() {
    local pkg="$1"
    local sect="$2"
    local cur

    _pw_is_node "$pkg" "$sect" || return 1

    cur=$(uci -q get "$pkg.@global[0].node" 2>/dev/null)
    [ -z "$cur" ] && cur=$(uci -q get "$pkg.@global[0].tcp_node" 2>/dev/null)

    if [ "$cur" = "$PW_SHUNT_ID" ]; then
        # Iran-direct routing is active: retarget the shunt so its direct rules survive
        uci set "$pkg.$PW_SHUNT_ID.default_node=$sect"
        transport_opt_set "$pkg" real_node "$sect"
    else
        _pw_set_global_node "$pkg" "$sect"
    fi

    uci commit "$pkg"
    _pw_reload "$pkg"
}

# remarks may contain regex metacharacters, so match them literally
_pw_node_exists() {
    uci show "$1" 2>/dev/null | grep -qF "remarks='$2'"
}

# Imports a share link with Passwall's own parser (/usr/share/<pkg>/subscribe.lua),
# which is the only way Reality (pbk/sid/spx), ssr, hysteria, hysteria2, tuic,
# anytls and naive nodes get built with every field Passwall expects.
# $1 pkg, $2 config file, $3 config name
_pw_push_node() {
    local pkg="$1"
    local file="$2"
    local conf_name="$3"
    local share_link script label remarks existing before after new count

    share_link=$(jq -r '.share_link // empty' "$file" 2>/dev/null)
    if [ -z "$share_link" ]; then
        log_error "No share_link in config: [$conf_name]"
        return 1
    fi

    script="/usr/share/$pkg/subscribe.lua"
    if [ ! -f "$script" ]; then
        log_error "Passwall's own link importer is missing: [$script]"
        return 1
    fi
    if ! command -v lua >/dev/null 2>&1; then
        log_error "lua is required to import share links into $pkg!"
        return 1
    fi

    if [ "$pkg" = "passwall2" ]; then
        label="Passwall2"
    else
        label="Passwall1"
    fi

    remarks=""
    existing=""
    if parse_share_link "$share_link"; then
        remarks="$PARSED_REMARKS"
        existing=$(_pw_node_id_by_remarks "$pkg" "$remarks") || existing=""
    else
        log_warn "Could not read the share link of [$conf_name]; letting $label name the node."
    fi

    log_info "Importing node into $label -> [${remarks:-$conf_name}]"

    before=$(_pw_node_ids "$pkg")

    printf '%s\n' "$share_link" > /tmp/links.conf
    lua "$script" add "$PW_SUBSCRIBE_GROUP" >/dev/null 2>&1
    rm -f /tmp/links.conf

    after=$(_pw_node_ids "$pkg")

    if [ -z "$before" ]; then
        # busybox grep with an empty pattern list matches nothing, so the very
        # first imported node has to be handled without a diff.
        new="$after"
    else
        new=$(printf '%s\n' "$after" | grep -vxF -- "$before")
    fi
    new=$(printf '%s\n' "$new" | sed '/^$/d')

    count=0
    [ -n "$new" ] && count=$(printf '%s\n' "$new" | grep -c .)

    if [ "$count" -eq 0 ]; then
        if [ -n "$existing" ]; then
            uci commit "$pkg"
            log_success "$label refreshed the existing node [$remarks] ($existing)"
            return 0
        fi
        log_error "$label did not accept the share link of [$conf_name]."
        return 1
    fi

    if [ "$count" -gt 1 ]; then
        log_info "$label created $count nodes from this link."
    elif [ -n "$existing" ] && [ "$new" != "$existing" ]; then
        # Reuse the old section id so @global[0].node, the shunt's default_node
        # and the balancer's saved ids keep pointing at this node.
        case "$existing" in
            *[!A-Za-z0-9_]*)
                log_warn "Node id [$existing] cannot be reused; [$remarks] now lives in [$new]."
                ;;
            *)
                uci -q delete "$pkg.$existing"
                if uci rename "$pkg.$new=$existing" 2>/dev/null; then
                    new="$existing"
                else
                    log_warn "Could not reuse node id [$existing]; [$remarks] now lives in [$new]."
                fi
                ;;
        esac
    fi

    uci commit "$pkg"

    if [ -n "$existing" ]; then
        log_success "Node [$remarks] updated in $label ($(printf '%s' "$new" | tr '\n' ' '))"
    else
        log_success "Node [${remarks:-$conf_name}] added to $label ($(printf '%s' "$new" | tr '\n' ' '))"
    fi
    return 0
}

# Removes the unused daypass_balancer section written by older DayPass releases
_pw_cleanup() {
    uci -q get "$1.daypass_balancer" >/dev/null 2>&1 || return 0
    uci -q delete "$1.daypass_balancer"
    uci commit "$1"
}

# ------------------------------------------------------------
# Hook table
# ------------------------------------------------------------
tdrv_passwall2_detect()           { _pw_detect passwall2; }
tdrv_passwall2_start()            { _pw_start passwall2; }
tdrv_passwall2_stop()             { _pw_stop passwall2; }
tdrv_passwall2_status()           { _pw_status passwall2; }
tdrv_passwall2_reload()           { _pw_reload passwall2; }
tdrv_passwall2_interception()     { echo "self"; }
tdrv_passwall2_apply_route_mode() { _pw_apply_route_mode passwall2 "$1"; }
tdrv_passwall2_dns_endpoint()     { echo "127.0.0.1#$(_pw_dns_listen_port passwall2)"; }
tdrv_passwall2_dns_configure()    { _pw_dns_configure passwall2 "$1"; }
tdrv_passwall2_list_nodes()       { _pw_list_nodes passwall2; }
tdrv_passwall2_active_node()      { _pw_active_node passwall2; }
tdrv_passwall2_select_node()      { _pw_select_node passwall2 "$1"; }
tdrv_passwall2_push_node()        { _pw_push_node passwall2 "$1" "$2"; }
tdrv_passwall2_cleanup()          { _pw_cleanup passwall2; }
tdrv_passwall2_describe()         { echo "config /etc/config/passwall2, DNS port $(_pw_dns_listen_port passwall2)"; }

tdrv_passwall_detect()            { _pw_detect passwall; }
tdrv_passwall_start()             { _pw_start passwall; }
tdrv_passwall_stop()              { _pw_stop passwall; }
tdrv_passwall_status()            { _pw_status passwall; }
tdrv_passwall_reload()            { _pw_reload passwall; }
tdrv_passwall_interception()      { echo "self"; }
tdrv_passwall_apply_route_mode()  { _pw_apply_route_mode passwall "$1"; }
tdrv_passwall_dns_endpoint()      { echo "127.0.0.1#$(_pw_dns_listen_port passwall)"; }
tdrv_passwall_dns_configure()     { _pw_dns_configure passwall "$1"; }
tdrv_passwall_list_nodes()        { _pw_list_nodes passwall; }
tdrv_passwall_active_node()       { _pw_active_node passwall; }
tdrv_passwall_select_node()       { _pw_select_node passwall "$1"; }
tdrv_passwall_push_node()         { _pw_push_node passwall "$1" "$2"; }
tdrv_passwall_cleanup()           { _pw_cleanup passwall; }
tdrv_passwall_describe()          { echo "config /etc/config/passwall, DNS port $(_pw_dns_listen_port passwall)"; }


# 📄 Source : manager.sh
# ============================================================
# Orchestrates storage, subscription and the transport bridge
# ============================================================

config_manager_menu() {
    local HELP_MODULE_ID="proxy_config_manager"

    while true; do
        render_persistent_header

        local engine_label="unknown"
        if command -v get_active_engine >/dev/null 2>&1; then
            engine_label=$(transport_engine_label "$(get_active_engine)")
        fi

        echo "  📦 Config Manager (Nodes & Subscriptions)"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  🛡️ Detected Engine : ${CYAN}$engine_label${RESET}"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  📋 1) List Configs"
        echo "  🤏 2) Add Manual Config"
        echo "  🎲 3) Toggle Enable/Disable Config"
        echo "  💳 4) Add Subscription"
        echo "  🏧 5) List Subscriptions"
        echo "  🔄 6) Update All Subscriptions"
        echo "  🫸 7) Push Config to Active Engine"
        echo "  🤜 8) Push All Configs to Active Engine"
        echo "  🗑️ 9) Remove Config"
        ui_nav_footer

        ui_prompt 9
        choice="$UI_CHOICE"

        case "$choice" in
            1)
                if command -v list_configs >/dev/null 2>&1; then
                    list_configs
                else
                    log_error "list_configs() not found!"
                fi
                ;;
            2)
                if command -v add_manual_config >/dev/null 2>&1; then
                    add_manual_config
                else
                    log_error "add_manual_config() not found!"
                fi
                ;;
            3)
                if command -v toggle_config >/dev/null 2>&1; then
                    toggle_config
                else
                    log_error "toggle_config() not found!"
                fi
                ;;
            4)
                if command -v add_subscription >/dev/null 2>&1; then
                    add_subscription
                else
                    log_error "add_subscription() not found!"
                fi
                ;;
            5)
                if command -v list_subscriptions >/dev/null 2>&1; then
                    list_subscriptions
                else
                    log_error "list_subscriptions() not found!"
                fi
                ;;
            6)
                if command -v update_all_subscriptions >/dev/null 2>&1; then
                    update_all_subscriptions
                else
                    log_error "update_all_subscriptions() not found!"
                fi
                ;;
            7)
                if command -v list_configs >/dev/null 2>&1; then
                    list_configs
                fi
                printf "  ✊🏻 Enter config name to push : "
                read -r push_name </dev/tty
                if [ -n "$push_name" ] && command -v transport_push_config >/dev/null 2>&1; then
                    transport_push_config "$push_name"
                else
                    log_error "Invalid name or push function not found!"
                fi
                ;;
            8)
                if command -v transport_push_all >/dev/null 2>&1; then
                    transport_push_all
                else
                    log_error "transport_push_all() not found!"
                fi
                ;;
            9)
                if command -v remove_config >/dev/null 2>&1; then
                    remove_config
                else
                    log_error "remove_config() not found!"
                fi
                ;;
            q|Q) daypass_quit ;;
            h|H)
                if command -v show_help >/dev/null 2>&1; then
                    show_help "$HELP_MODULE_ID"
                else
                    log_warn "Help module not loaded!"
                    sleep 1
                fi
                continue
                ;;
            0)
                return 0
                ;;
            *)
                log_warn "Invalid option!"
                ;;
        esac

        printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
        read -r _ </dev/tty || daypass_quit
    done
}

# 📄 Source : core.sh
# ============================================================
# DayPass - Traffic Routing / Shunt Rules
# Engine-neutral routing modes on top of the transport bridge
#   self   engines (Passwall, Passwall2) : mode applied through the driver
#   tproxy engines (sing-box, Xray)      : DayPass nft TPROXY chain + policy route
#   tunnel engines (WireGuard, OpenVPN)  : DayPass fwmark + policy route into tunnel
# ============================================================

# ------------------------------------------------------------
# Paths & constants
# ------------------------------------------------------------
PROXY_DIR="/etc/daypass/proxy"
ROUTING_DIR="$PROXY_DIR/routing"
mkdir -p "$ROUTING_DIR"

# Mark bits 16-23 are DayPass-owned (mwan3 uses 0x3f00, Passwall uses its own table)
RT_NFT_TABLE="daypass"
RT_NFT_FILE="$ROUTING_DIR/daypass.nft"
RT_MARK_MASK="0x00ff0000"
RT_MARK_KEEP="0xff00ffff"
RT_MARK_TPROXY="0x00010000"
RT_MARK_TUNNEL="0x00020000"
RT_TABLE_TPROXY="2585"
RT_TABLE_TUNNEL="2586"
RT_RULE_PRIORITY="900"

# ------------------------------------------------------------
# Options ($ROUTING_DIR/routing.conf, key=value)
#   ipv6=1                  intercept IPv6 as well
#   lan_devices=br-lan ...  ingress devices to steer
# ------------------------------------------------------------
_rt_opt() {
    local val=""
    [ -f "$ROUTING_DIR/routing.conf" ] && val=$(sed -n "s/^$1=//p" "$ROUTING_DIR/routing.conf" | tail -n 1)
    echo "${val:-${2:-}}"
}

_rt_lan_devices() {
    local devs dev out=""

    devs=$(_rt_opt lan_devices)
    [ -z "$devs" ] && devs=$(uci -q get network.lan.device 2>/dev/null)
    [ -z "$devs" ] && devs=$(uci -q get network.lan.ifname 2>/dev/null)
    [ -z "$devs" ] && devs="br-lan"

    for dev in $devs; do
        case "$dev" in
            *[!A-Za-z0-9._@-]*) continue ;;
        esac
        out="${out:+$out, }\"$dev\""
    done
    echo "$out"
}

_rt_mode_title() {
    case "$1" in
        iran_direct)  echo "Iran Direct + Foreign Proxy" ;;
        global_proxy) echo "Global Proxy" ;;
        direct_only)  echo "Direct Only" ;;
        *)            return 1 ;;
    esac
}

_rt_mode_label() {
    case "$1" in
        iran_direct)  echo "🦁☀️ IRAN Direct" ;;
        global_proxy) echo "🌏 Global Proxy" ;;
        direct_only)  echo "🎯 Direct Only" ;;
    esac
}

# Prints comma-joined CIDRs from a list file (comments / invalid lines skipped)
_rt_list_elements() {
    [ -f "$1" ] || return 0
    sed 's/#.*//; s/[[:space:]]//g' "$1" | grep -E "$2" | tr '\n' ',' | sed 's/,$//; s/,/, /g'
}

# ------------------------------------------------------------
# nftables ruleset (idempotent: loaded by fw4 include and directly)
# ------------------------------------------------------------
_rt_render_nft() {
    local intercept="$1"
    local port="$2"
    local mode="$3"
    local ipv6 lan d4="" d6="" mark

    ipv6=$(_rt_opt ipv6 0)
    lan=$(_rt_lan_devices)

    if [ "$mode" = "iran_direct" ]; then
        d4=$(_rt_list_elements "$ROUTING_DIR/direct_v4.list" '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$')
        d6=$(_rt_list_elements "$ROUTING_DIR/direct_v6.list" '^[0-9A-Fa-f:]+(/[0-9]+)?$')
    fi

    [ -n "$d4" ] && d4="        elements = { $d4 }"
    [ -n "$d6" ] && d6="        elements = { $d6 }"

    if [ "$intercept" = "tproxy" ]; then
        mark="$RT_MARK_TPROXY"
    else
        mark="$RT_MARK_TUNNEL"
    fi

    cat << EOF
# DayPass transport interception - generated, do not edit
table inet $RT_NFT_TABLE
delete table inet $RT_NFT_TABLE

table inet $RT_NFT_TABLE {
    set bypass_v4 {
        type ipv4_addr
        flags interval
        auto-merge
        elements = { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.168.0.0/16, 198.18.0.0/15, 224.0.0.0/4, 240.0.0.0/4 }
    }

    set bypass_v6 {
        type ipv6_addr
        flags interval
        auto-merge
        elements = { ::/128, ::1/128, 64:ff9b::/96, fc00::/7, fe80::/10, ff00::/8 }
    }

    set direct_v4 {
        type ipv4_addr
        flags interval
        auto-merge
$d4
    }

    set direct_v6 {
        type ipv6_addr
        flags interval
        auto-merge
$d6
    }

    chain prerouting {
        type filter hook prerouting priority mangle; policy accept;
        iifname != { $lan } return
        fib daddr type local return
        ip daddr @bypass_v4 return
        ip daddr @direct_v4 return
        ip6 daddr @bypass_v6 return
        ip6 daddr @direct_v6 return
EOF

    [ "$ipv6" = "1" ] || echo "        meta nfproto ipv6 return"

    if [ "$intercept" = "tproxy" ]; then
        echo "        meta nfproto ipv4 meta l4proto { tcp, udp } meta mark set meta mark & $RT_MARK_KEEP | $mark tproxy ip to 127.0.0.1:$port accept"
        [ "$ipv6" = "1" ] && \
        echo "        meta nfproto ipv6 meta l4proto { tcp, udp } meta mark set meta mark & $RT_MARK_KEEP | $mark tproxy ip6 to [::1]:$port accept"
    else
        echo "        meta mark set meta mark & $RT_MARK_KEEP | $mark"
    fi

    echo "    }"
    echo "}"
}

# ------------------------------------------------------------
# Managed rules (UCI network / firewall, persistent through fw4)
# ------------------------------------------------------------
_rt_managed_active() {
    uci -q get firewall.daypass_transport >/dev/null 2>&1 || \
    nft list table inet "$RT_NFT_TABLE" >/dev/null 2>&1
}

_rt_net_in_zone() {
    uci -q show firewall 2>/dev/null | grep -q "^firewall\.[^.]*\.network=.*'$1'"
}

_rt_clear_managed() {
    local sect net_changed=0 fw_changed=0

    for sect in daypass_rule4 daypass_rule6 daypass_route4 daypass_route6; do
        if uci -q get "network.$sect" >/dev/null 2>&1; then
            uci -q delete "network.$sect"
            net_changed=1
        fi
    done
    for sect in daypass_transport daypass_vpn daypass_vpn_fwd; do
        if uci -q get "firewall.$sect" >/dev/null 2>&1; then
            uci -q delete "firewall.$sect"
            fw_changed=1
        fi
    done

    [ "$net_changed" -eq 1 ] && uci commit network
    [ "$fw_changed" -eq 1 ] && uci commit firewall

    command -v nft >/dev/null 2>&1 && nft delete table inet "$RT_NFT_TABLE" >/dev/null 2>&1
    rm -f "$RT_NFT_FILE"

    [ "$net_changed" -eq 1 ] && { /etc/init.d/network reload >/dev/null 2>&1 || true; }
    [ "$fw_changed" -eq 1 ] && { /etc/init.d/firewall reload >/dev/null 2>&1 || true; }
    return 0
}

_rt_apply_managed() {
    local engine="$1"
    local intercept="$2"
    local mode="$3"
    local port="" net="" mark table ipv6

    if ! command -v nft >/dev/null 2>&1; then
        log_error "nftables (nft) not found. firewall4 is required for [$engine] routing!"
        return 1
    fi

    ipv6=$(_rt_opt ipv6 0)

    if [ "$intercept" = "tproxy" ]; then
        port=$(transport_call "$engine" tproxy_port 2>/dev/null)
        case "$port" in
            ''|*[!0-9]*)
                log_error "No TPROXY inbound found for [$engine]. Add a tproxy inbound to its config or set tproxy_port in $TRANSPORT_DIR/$engine.conf"
                return 1
                ;;
        esac
        mark="$RT_MARK_TPROXY"
        table="$RT_TABLE_TPROXY"
    else
        net=$(transport_tunnel_network "$engine")
        if [ -z "$net" ]; then
            log_error "Tunnel interface for [$engine] not found!"
            return 1
        fi
        mark="$RT_MARK_TUNNEL"
        table="$RT_TABLE_TUNNEL"
    fi

    if [ "$mode" = "iran_direct" ] && [ ! -s "$ROUTING_DIR/direct_v4.list" ]; then
        if [ "$intercept" = "tunnel" ]; then
            log_warn "No direct list [$ROUTING_DIR/direct_v4.list]: all LAN traffic will use the tunnel."
        else
            log_info "No direct list found; Iran-direct routing is left to the [$engine] core rules."
        fi
    fi

    if ! _rt_render_nft "$intercept" "$port" "$mode" > "$RT_NFT_FILE.tmp"; then
        rm -f "$RT_NFT_FILE.tmp"
        log_error "Could not write nftables rules!"
        return 1
    fi
    if ! nft -c -f "$RT_NFT_FILE.tmp" >/dev/null 2>&1; then
        rm -f "$RT_NFT_FILE.tmp"
        if [ "$intercept" = "tproxy" ]; then
            log_error "nftables rejected the TPROXY rules. Is kmod-nft-tproxy installed?"
        else
            log_error "nftables rejected the routing rules!"
        fi
        return 1
    fi
    mv "$RT_NFT_FILE.tmp" "$RT_NFT_FILE"

    # Policy routing
    uci -q delete network.daypass_rule4
    uci -q delete network.daypass_rule6
    uci -q delete network.daypass_route4
    uci -q delete network.daypass_route6

    uci set network.daypass_rule4=rule
    uci set network.daypass_rule4.mark="$mark/$RT_MARK_MASK"
    uci set network.daypass_rule4.lookup="$table"
    uci set network.daypass_rule4.priority="$RT_RULE_PRIORITY"

    uci set network.daypass_route4=route
    uci set network.daypass_route4.target='0.0.0.0/0'
    uci set network.daypass_route4.table="$table"

    if [ "$ipv6" = "1" ]; then
        uci set network.daypass_rule6=rule6
        uci set network.daypass_rule6.mark="$mark/$RT_MARK_MASK"
        uci set network.daypass_rule6.lookup="$table"
        uci set network.daypass_rule6.priority="$RT_RULE_PRIORITY"

        uci set network.daypass_route6=route6
        uci set network.daypass_route6.target='::/0'
        uci set network.daypass_route6.table="$table"
    fi

    if [ "$intercept" = "tproxy" ]; then
        uci set network.daypass_route4.type='local'
        uci set network.daypass_route4.interface='loopback'
        if [ "$ipv6" = "1" ]; then
            uci set network.daypass_route6.type='local'
            uci set network.daypass_route6.interface='loopback'
        fi
    else
        uci set network.daypass_route4.interface="$net"
        [ "$ipv6" = "1" ] && uci set network.daypass_route6.interface="$net"
    fi
    uci commit network

    # Firewall include + tunnel zone
    uci -q delete firewall.daypass_transport
    uci set firewall.daypass_transport=include
    uci set firewall.daypass_transport.type='nftables'
    uci set firewall.daypass_transport.path="$RT_NFT_FILE"
    uci set firewall.daypass_transport.position='ruleset-post'

    uci -q delete firewall.daypass_vpn
    uci -q delete firewall.daypass_vpn_fwd
    if [ "$intercept" = "tunnel" ] && ! _rt_net_in_zone "$net"; then
        uci set firewall.daypass_vpn=zone
        uci set firewall.daypass_vpn.name='dp_vpn'
        uci set firewall.daypass_vpn.input='REJECT'
        uci set firewall.daypass_vpn.output='ACCEPT'
        uci set firewall.daypass_vpn.forward='REJECT'
        uci set firewall.daypass_vpn.masq='1'
        uci set firewall.daypass_vpn.mtu_fix='1'
        uci add_list firewall.daypass_vpn.network="$net"

        uci set firewall.daypass_vpn_fwd=forwarding
        uci set firewall.daypass_vpn_fwd.src='lan'
        uci set firewall.daypass_vpn_fwd.dest='dp_vpn'
    fi
    uci commit firewall

    /etc/init.d/network reload >/dev/null 2>&1 || true
    /etc/init.d/firewall reload >/dev/null 2>&1 || true

    if ! nft list table inet "$RT_NFT_TABLE" >/dev/null 2>&1; then
        nft -f "$RT_NFT_FILE" >/dev/null 2>&1
    fi
    if ! nft list table inet "$RT_NFT_TABLE" >/dev/null 2>&1; then
        log_error "DayPass nftables table could not be loaded!"
        return 1
    fi
    return 0
}

# ------------------------------------------------------------
# Apply a routing mode to the active (or given) transport engine
# ------------------------------------------------------------
apply_routing_mode() {
    local mode="$1"
    local engine intercept title rc

    if ! title=$(_rt_mode_title "$mode"); then
        log_error "Unknown routing mode : [$mode]"
        return 1
    fi

    engine=$(_transport_target_engine "${2:-}") || return 1
    intercept=$(transport_call "$engine" interception)

    log_info "Applying mode : $title ..."

    case "$intercept" in
        self)
            _rt_managed_active && _rt_clear_managed
            transport_call "$engine" apply_route_mode "$mode"
            rc=$?
            if [ "$rc" -eq 3 ]; then
                log_error "Engine [$engine] does not support routing modes!"
                return 1
            fi
            [ "$rc" -eq 0 ] || return 1
            ;;
        tproxy|tunnel)
            transport_call "$engine" apply_route_mode "$mode"
            rc=$?
            if [ "$rc" -ne 0 ] && [ "$rc" -ne 3 ]; then
                return 1
            fi

            if [ "$mode" = "direct_only" ]; then
                _rt_clear_managed
            else
                _rt_apply_managed "$engine" "$intercept" "$mode" || return 1
            fi
            ;;
        *)
            log_error "Engine [$engine] reported unknown interception [$intercept]!"
            return 1
            ;;
    esac

    echo "$mode" > "$ROUTING_DIR/current_mode"
    echo "$engine" > "$ROUTING_DIR/current_engine"

    case "$mode" in
        iran_direct)
            cat > "$ROUTING_DIR/iran_direct.rules" << EOF
# DayPass Routing Rule - Iran Direct
# Engine : $engine ($intercept)
# 1. Iranian domains & IPs → Direct
# 2. Everything else → Proxy
EOF
            ;;
        global_proxy)
            cat > "$ROUTING_DIR/global_proxy.rules" << EOF
# DayPass Routing Rule - Global Proxy
# Engine : $engine ($intercept)
# All traffic → Proxy
EOF
            ;;
        direct_only)
            cat > "$ROUTING_DIR/direct_only.rules" << EOF
# DayPass Routing Rule - Direct Only
# Engine : $engine ($intercept)
# All traffic → Direct (Proxy disabled)
EOF
            ;;
    esac

    if [ "$mode" = "direct_only" ]; then
        log_success "Mode [$(_rt_mode_label "$mode")] applied. Proxy disabled!"
    else
        log_success "Mode [$(_rt_mode_label "$mode")] applied to $engine!"
    fi
}

apply_iran_direct()  { apply_routing_mode iran_direct "$@"; }
apply_global_proxy() { apply_routing_mode global_proxy "$@"; }
apply_direct_only()  { apply_routing_mode direct_only "$@"; }

# Re-applies the saved mode (after engine switch / reload). No saved mode: nothing to do.
routing_reapply() {
    local mode
    mode=$(cat "$ROUTING_DIR/current_mode" 2>/dev/null)
    _rt_mode_title "$mode" >/dev/null || return 0
    apply_routing_mode "$mode" "${1:-}"
}

# ------------------------------------------------------------
# Show current routing status
# ------------------------------------------------------------
show_routing_status() {
    local mode engine intercept managed

    echo "  🚦 Current Routing Status"
    echo "  ───────────────────────────────────────────────────────────"

    if [ -f "$ROUTING_DIR/current_mode" ]; then
        mode=$(cat "$ROUTING_DIR/current_mode")
        echo "  🫀 Active Mode : ${GREEN}$mode${RESET}"
    else
        echo "  🫀 Active Mode : ${GRAY}Not configured${RESET}"
    fi

    engine=$(get_active_engine)
    if [ "$engine" = "none" ]; then
        echo "  🛡️  Engine      : ${GRAY}none${RESET}"
    else
        intercept=$(transport_call "$engine" interception)
        echo "  🛡️  Engine      : ${CYAN}$(transport_engine_label "$engine")${RESET}  ${GRAY}[$intercept]${RESET}"
        if [ "$intercept" != "self" ]; then
            if nft list table inet "$RT_NFT_TABLE" >/dev/null 2>&1; then
                managed="${GREEN}loaded${RESET}"
            else
                managed="${GRAY}not loaded${RESET}"
            fi
            echo "  🧱 DayPass Rules: $managed  ${GRAY}(IPv6 : $(_rt_opt ipv6 0))${RESET}"
        fi
    fi
    echo "  ───────────────────────────────────────────────────────────"
}

# ------------------------------------------------------------
# Main Routing Menu
# ------------------------------------------------------------
routing_menu() {
    local HELP_MODULE_ID="proxy_routing"

    while true; do
        render_persistent_header

        echo "  🚦 Traffic Routing / Shunt Rules"
        echo "  ───────────────────────────────────────────────────────────"
        show_routing_status
        echo
        echo "  👑 1) Iran Direct + Foreign Proxy   (Recommended)"
        echo "  🌏 2) Global Proxy                  (All traffic via proxy)"
        echo "  🎯 3) Direct Only                   (Disable proxy)"
        echo "  👀 4) Show current rules"
        echo "  🚀 5) Transport Engine              (Select / start / stop)"
        ui_nav_footer

        ui_prompt 5
        choice="$UI_CHOICE"

        case "$choice" in
            1) apply_iran_direct ;;
            2) apply_global_proxy ;;
            3) apply_direct_only ;;
            4)
                echo
                if [ -f "$ROUTING_DIR/current_mode" ]; then
                    mode=$(cat "$ROUTING_DIR/current_mode")
                    echo "  ⬆️  Current mode : $mode"
                    echo
                    cat "$ROUTING_DIR/${mode}.rules" 2>/dev/null || echo "  ${GRAY}No detailed rules file.${RESET}"
                    if [ -f "$RT_NFT_FILE" ]; then
                        echo
                        echo "  ${GRAY}nftables : $RT_NFT_FILE${RESET}"
                    fi
                else
                    echo "  💅🏻 No routing mode configured yet!"
                fi
                ;;
            5)
                proxy_engine_menu
                continue
                ;;
            q|Q) daypass_quit ;;
            h|H)
                if command -v show_help >/dev/null 2>&1; then
                    show_help "$HELP_MODULE_ID"
                else
                    log_warn "Help module not loaded!"
                    sleep 1
                fi
                continue
                ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
        read -r _ </dev/tty || daypass_quit
    done
}


# 📄 Source : node_balancer.sh
# ============================================================
# DayPass - Node Load Balancing
# Probes the active transport engine's nodes and switches to the
# best one per mode (Passwall nodes, WireGuard peers, OpenVPN
# instances, sing-box / Xray outbounds)
# ============================================================

# ------------------------------------------------------------
# Paths
# nodes.list : engine|node_id per line
# ------------------------------------------------------------
PROXY_DIR="/etc/daypass/proxy"
CONFIG_DIR="$PROXY_DIR/configs"
BALANCER_DIR="$PROXY_DIR/balancer"
mkdir -p "$BALANCER_DIR"

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

# Prints the list_nodes line (id|name|proto|host|port|l4) for a node id
_nb_node_line() {
    transport_call "$1" list_nodes 2>/dev/null | awk -F'|' -v id="$2" '$1 == id { print; exit }'
}

_nb_node_name() {
    local line
    line=$(_nb_node_line "$1" "$2")
    if [ -n "$line" ]; then
        echo "$line" | cut -d'|' -f2
    else
        echo "$2"
    fi
}

# Selected node ids for an engine, in saved order
_nb_selected_ids() {
    [ -f "$BALANCER_DIR/nodes.list" ] || return 0
    awk -F'|' -v e="$1" 'NF >= 2 && $1 == e { print $2 }' "$BALANCER_DIR/nodes.list"
}

_nb_legacy_entries() {
    [ -f "$BALANCER_DIR/nodes.list" ] || { echo 0; return; }
    grep -vc '|' "$BALANCER_DIR/nodes.list" 2>/dev/null || true
}

_nb_random() {
    awk -v seed="$(( $(date +%s) + $$ ))" -v n="$1" 'BEGIN { srand(seed); print int(rand() * n) + 1 }'
}

# ------------------------------------------------------------
# Show current balancer status
# ------------------------------------------------------------
show_balancer_status() {
    local mode engine count names id current legacy

    echo "  ⚖️  Current Node Balancer Status"
    echo "  ───────────────────────────────────────────────────────────"

    if [ -f "$BALANCER_DIR/mode" ]; then
        mode=$(cat "$BALANCER_DIR/mode")
        echo "  🫀 Active Mode  : ${GREEN}$mode${RESET}"
    else
        echo "  🫀 Active Mode  : ${GRAY}Disabled${RESET}"
    fi

    engine=$(get_active_engine)

    count=0
    names=""
    if [ "$engine" != "none" ]; then
        while IFS= read -r id <&3; do
            [ -n "$id" ] || continue
            count=$((count + 1))
            names="$names $(_nb_node_name "$engine" "$id")"
        done 3<< EOF
$(_nb_selected_ids "$engine")
EOF
    fi
    echo "  🧠 Active Nodes : $count"
    [ "$count" -gt 0 ] && echo "  📋 Nodes        : ${GRAY}${names# }${RESET}"

    legacy=$(_nb_legacy_entries)
    [ "${legacy:-0}" -gt 0 ] && echo "  ⚠️  ${YELLOW}$legacy old-format entr(ies) ignored - reselect nodes.${RESET}"

    if [ "$engine" = "none" ]; then
        echo "  🛡️  Engine       : ${GRAY}none${RESET}"
    else
        echo "  🛡️  Engine       : ${CYAN}$(transport_engine_label "$engine")${RESET}"
        current=$(transport_call "$engine" active_node 2>/dev/null)
        [ -n "$current" ] && echo "  🎯 Current Node : ${GREEN}$(_nb_node_name "$engine" "$current")${RESET}"
    fi
    echo "  ───────────────────────────────────────────────────────────"
}

# ------------------------------------------------------------
# Select nodes for balancing (from the active engine)
# ------------------------------------------------------------
select_nodes() {
    local engine nodes rc i idx selected num added id name proto host port

    engine=$(_transport_target_engine "") || return 1
    nodes=$(transport_call "$engine" list_nodes 2>/dev/null)
    rc=$?
    if [ "$rc" -eq 3 ]; then
        log_error "Engine [$engine] does not expose switchable nodes."
        return 1
    fi

    if [ -z "$nodes" ]; then
        log_warn "No nodes found in [$(transport_engine_label "$engine")]. Add some nodes first!"
        return 1
    fi

    echo
    echo "  📋 Available Nodes ($(transport_engine_label "$engine")) :"
    echo "  ───────────────────────────────────────────────────────────"

    i=1
    while IFS='|' read -r id name proto host port _; do
        [ -n "$id" ] || continue
        echo "  $i) $name  ${GRAY}($proto $host${port:+:$port})${RESET}"
        i=$((i + 1))
    done << EOF
$nodes
EOF

    echo "  ───────────────────────────────────────────────────────────"
    printf "  🧶 Enter node numbers to include (e.g. 1 3 4) : "
    read -r selected </dev/tty

    if [ -z "$selected" ]; then
        log_warn "No selection entered!"
        return 1
    fi

    : > "$BALANCER_DIR/nodes.list"
    rm -f "$BALANCER_DIR/last_index"

    added=0
    for num in $selected; do
        idx=1
        while IFS='|' read -r id name _; do
            [ -n "$id" ] || continue
            if [ "$num" = "$idx" ]; then
                if ! grep -qxF "$engine|$id" "$BALANCER_DIR/nodes.list"; then
                    echo "$engine|$id" >> "$BALANCER_DIR/nodes.list"
                    log_success "Added : [$name]"
                    added=$((added + 1))
                fi
            fi
            idx=$((idx + 1))
        done << EOF
$nodes
EOF
    done

    if [ "$added" -eq 0 ]; then
        log_warn "No valid nodes selected!"
    else
        log_success "[$added] node(s) selected for balancing!"
    fi
}

# ------------------------------------------------------------
# Set balancing mode
# ------------------------------------------------------------
set_balancer_mode() {
    local mode_choice mode

    while true; do
        echo
        echo "  ⚖️  Select Load Balancing Mode :"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  ⏳ 1) Round-Robin      (distribute equally)"
        echo "  🏓 2) Least Ping       (prefer lowest latency)"
        echo "  👨‍👩‍👧‍👦 3) Failover         (use next only if previous fails)"
        echo "  🤹 4) Random"
        if command -v ui_nav_footer >/dev/null 2>&1; then
            ui_nav_footer
        fi
        printf "  ⁉️ Select mode [1-4] : "
        read -r mode_choice </dev/tty

        case "$mode_choice" in
            0) return 0 ;;
            q|Q)
                command -v daypass_quit >/dev/null 2>&1 && daypass_quit
                return 0
                ;;
            h|H)
                if command -v show_help >/dev/null 2>&1; then
                    show_help "proxy_balancer_modes"
                else
                    log_warn "Help module not loaded!"
                    sleep 1
                fi
                continue
                ;;
            1) mode="round-robin" ;;
            2) mode="least-ping" ;;
            3) mode="failover" ;;
            4) mode="random" ;;
            *) log_warn "Invalid mode!"; return 1 ;;
        esac
        break
    done

    echo "$mode" > "$BALANCER_DIR/mode"
    log_success "Balancer mode set to : [$mode]"
}

# ------------------------------------------------------------
# Probe selected nodes
# Writes $BALANCER_DIR/probe.last : id|state|ms|method (selection order)
# ------------------------------------------------------------
probe_nodes() {
    local engine="$1"
    local quiet="${2:-0}"
    local id line name host port l4 total=0 up=0

    : > "$BALANCER_DIR/probe.last"

    while IFS= read -r id <&3; do
        [ -n "$id" ] || continue
        line=$(_nb_node_line "$engine" "$id")
        total=$((total + 1))

        if [ -z "$line" ]; then
            echo "$id|missing||" >> "$BALANCER_DIR/probe.last"
            [ "$quiet" = "1" ] || echo "  ❌ $id  ${GRAY}(no longer in engine config)${RESET}"
            continue
        fi

        name=$(echo "$line" | cut -d'|' -f2)
        host=$(echo "$line" | cut -d'|' -f4)
        port=$(echo "$line" | cut -d'|' -f5)
        l4=$(echo "$line" | cut -d'|' -f6)

        transport_probe "$host" "$port" "$l4"
        echo "$id|$PROBE_STATE|$PROBE_MS|$PROBE_METHOD" >> "$BALANCER_DIR/probe.last"

        [ "$PROBE_STATE" = "down" ] || up=$((up + 1))
        if [ "$quiet" != "1" ]; then
            case "$PROBE_STATE" in
                up)      echo "  ✅ $name  ${GRAY}($host:$port)${RESET}  ${GREEN}${PROBE_MS:-?} ms${RESET} ${GRAY}[$PROBE_METHOD]${RESET}" ;;
                unknown) echo "  ❔ $name  ${GRAY}($host:$port)${RESET}  ${YELLOW}no ICMP reply (UDP not verifiable)${RESET}" ;;
                *)       echo "  ❌ $name  ${GRAY}($host:$port)${RESET}  ${RED}unreachable${RESET} ${GRAY}[$PROBE_METHOD]${RESET}" ;;
            esac
        fi
    done 3<< EOF
$(_nb_selected_ids "$engine")
EOF

    [ "$quiet" = "1" ] || log_info "$up / $total node(s) reachable."
    [ "$total" -gt 0 ]
}

probe_selected_nodes() {
    local engine
    engine=$(_transport_target_engine "") || return 1

    if [ -z "$(_nb_selected_ids "$engine")" ]; then
        log_warn "No nodes selected for balancing."
        return 1
    fi

    log_info "Probing nodes of [$(transport_engine_label "$engine")] ..."
    probe_nodes "$engine"
}

# Picks a node id from probe.last for the mode. up nodes are preferred, unknown
# (UDP without ICMP) nodes are used only when no node is confirmed up.
_nb_pick() {
    local mode="$1"
    local usable n pick last

    usable=$(awk -F'|' '$2 == "up" { print $1 }' "$BALANCER_DIR/probe.last")
    [ -z "$usable" ] && usable=$(awk -F'|' '$2 == "unknown" { print $1 }' "$BALANCER_DIR/probe.last")
    [ -n "$usable" ] || return 1

    n=$(echo "$usable" | wc -l)

    case "$mode" in
        failover)
            echo "$usable" | head -n 1
            ;;
        least-ping)
            pick=$(awk -F'|' '$2 == "up" && $3 != "" { if (best == "" || $3 + 0 < best) { best = $3 + 0; id = $1 } } END { print id }' "$BALANCER_DIR/probe.last")
            [ -z "$pick" ] && pick=$(echo "$usable" | head -n 1)
            echo "$pick"
            ;;
        round-robin)
            last=$(cat "$BALANCER_DIR/last_index" 2>/dev/null)
            case "$last" in ''|*[!0-9]*) last=0 ;; esac
            pick=$(( last % n + 1 ))
            echo "$pick" > "$BALANCER_DIR/last_index"
            echo "$usable" | sed -n "${pick}p"
            ;;
        random)
            echo "$usable" | sed -n "$(_nb_random "$n")p"
            ;;
        *)
            return 1
            ;;
    esac
}

# ------------------------------------------------------------
# Apply balancer: probe selected nodes and switch the active engine
# ------------------------------------------------------------
apply_balancer() {
    local engine mode chosen current name

    engine=$(_transport_target_engine "") || return 1

    if [ ! -f "$BALANCER_DIR/mode" ]; then
        log_warn "No balancer mode selected yet."
        return 1
    fi

    if [ -z "$(_nb_selected_ids "$engine")" ]; then
        if [ -s "$BALANCER_DIR/nodes.list" ]; then
            log_warn "Selected nodes do not belong to [$engine] (or use the old format). Select nodes again."
        else
            log_warn "No nodes selected for balancing."
        fi
        return 1
    fi

    if ! transport_has_hook "$engine" select_node; then
        log_error "Engine [$engine] does not support node switching."
        return 1
    fi

    transport_call "$engine" cleanup >/dev/null 2>&1

    mode=$(cat "$BALANCER_DIR/mode")
    log_info "Applying balancer [$mode] to $engine ..."

    probe_nodes "$engine" || return 1

    if ! chosen=$(_nb_pick "$mode") || [ -z "$chosen" ]; then
        log_error "No reachable node among the selected nodes. Active node unchanged."
        return 1
    fi

    name=$(_nb_node_name "$engine" "$chosen")
    current=$(transport_call "$engine" active_node 2>/dev/null)

    if [ "$chosen" = "$current" ]; then
        echo "$chosen" > "$BALANCER_DIR/current"
        log_success "Node [$name] is already active on $engine."
        return 0
    fi

    if ! transport_call "$engine" select_node "$chosen"; then
        log_error "Failed to switch $engine to node [$name]!"
        return 1
    fi

    echo "$chosen" > "$BALANCER_DIR/current"
    log_success "Switched $engine to node [$name] ($mode)."
}

# ------------------------------------------------------------
# Disable balancer
# ------------------------------------------------------------
disable_balancer() {
    local engine

    rm -f "$BALANCER_DIR/mode" "$BALANCER_DIR/nodes.list" "$BALANCER_DIR/last_index" \
        "$BALANCER_DIR/probe.last" "$BALANCER_DIR/current"

    engine=$(get_active_engine)
    [ "$engine" != "none" ] && transport_call "$engine" cleanup >/dev/null 2>&1

    log_success "Node Balancer disabled!"
}

# ------------------------------------------------------------
# Main Menu
# ------------------------------------------------------------
node_balancer_menu() {
    local HELP_MODULE_ID="proxy_balancer"

    while true; do
        render_persistent_header

        echo "  🧶 Node Load Balancing"
        echo "  ───────────────────────────────────────────────────────────"
        show_balancer_status
        echo
        echo "  💆‍♀️ 1) Select Nodes for Balancing"
        echo "  ⚖️  2) Set Balancing Mode"
        echo "  🔥 3) Apply Balancer (probe & switch node)"
        echo "  🚫 4) Disable Balancer"
        echo "  🏓 5) Probe Selected Nodes"
        ui_nav_footer

        ui_prompt 5
        choice="$UI_CHOICE"

        case "$choice" in
            1) select_nodes ;;
            2) set_balancer_mode ;;
            3) apply_balancer ;;
            4) disable_balancer ;;
            5) probe_selected_nodes ;;
            q|Q) daypass_quit ;;
            h|H)
                if command -v show_help >/dev/null 2>&1; then
                    show_help "$HELP_MODULE_ID"
                else
                    log_warn "Help module not loaded!"
                    sleep 1
                fi
                continue
                ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
        read -r _ </dev/tty || daypass_quit
    done
}


# 📄 Source : health_checker.sh

# Tests reachability + approximate latency of proxy nodes
# ============================================================


# Paths

PROXY_DIR="/etc/daypass/proxy"
CONFIG_DIR="$PROXY_DIR/configs"
HEALTH_DIR="$PROXY_DIR/health"
mkdir -p "$HEALTH_DIR"


# True unless the config is explicitly disabled.
# jq's "//" treats false as absent, so '.enabled // true' reads a disabled
# config as enabled; test the value itself instead.

_hc_enabled() {
    [ "$(jq -r 'if .enabled == false then "false" else "true" end' "$1" 2>/dev/null)" != "false" ]
}


# Extract host, port and L4 protocol from share link

extract_host_port() {
    local link="$1"
    HOST=""
    PORT=""
    L4="tcp"

    # The transport bridge's parser understands every scheme DayPass supports
    if command -v parse_share_link >/dev/null 2>&1 && parse_share_link "$link"; then
        HOST="$PARSED_ADDRESS"
        PORT="$PARSED_PORT"
        L4="${PARSED_L4:-tcp}"
        [ -n "$HOST" ] && [ -n "$PORT" ] && return 0
    fi

    # VLESS / Trojan style: protocol://uuid@host:port
    HOST=$(echo "$link" | sed -n 's/.*@\([^:/]*\).*/\1/p' | head -1)
    PORT=$(echo "$link" | sed -n 's/.*@[^:]*:\([0-9]*\).*/\1/p' | head -1)

    # Fallback: protocol://host:port
    if [ -z "$HOST" ]; then
        HOST=$(echo "$link" | sed -n 's/.*\/\/\([^:/]*\).*/\1/p' | head -1)
        PORT=$(echo "$link" | sed -n 's/.*\/\/[^:]*:\([0-9]*\).*/\1/p' | head -1)
    fi

    # Last fallback for some formats
    if [ -z "$PORT" ]; then
        PORT=$(echo "$link" | grep -oE ':[0-9]{2,5}' | head -1 | tr -d ':')
    fi
}


# Test a single node (TCP + latency)

test_node() {
    local name="$1"
    local file="$CONFIG_DIR/${name}.json"

    if [ ! -f "$file" ]; then
        log_error "$name → file not found"
        return 1
    fi

    # Skip disabled configs
    if ! _hc_enabled "$file"; then
        log_warn "$name → disabled (skipped)"
        return 1
    fi

    local share_link
    share_link=$(jq -r '.share_link // empty' "$file" 2>/dev/null)

    if [ -z "$share_link" ]; then
        log_error "[$name] → no share link"
        return 1
    fi

    extract_host_port "$share_link"

    if [ -z "$HOST" ] || [ -z "$PORT" ]; then
        log_warn "[$name] → could not parse address"
        return 1
    fi

    local state="down"
    local latency=""
    local start_time end_time

    if command -v transport_probe >/dev/null 2>&1; then
        # Shared probe: knows whether this busybox nc supports -z and reports
        # UDP endpoints as unknown instead of unreachable.
        transport_probe "$HOST" "$PORT" "${L4:-tcp}"
        state="$PROBE_STATE"
        latency="$PROBE_MS"
    else
        start_time=$(date +%s%N 2>/dev/null || date +%s)

        if command -v nc >/dev/null 2>&1; then
            # busybox nc has no -z: connect with stdin closed instead
            if nc -w 3 "$HOST" "$PORT" </dev/null >/dev/null 2>&1; then
                state="up"
            fi
        elif timeout 3 sh -c "echo > /dev/tcp/$HOST/$PORT" 2>/dev/null; then
            state="up"
        fi

        end_time=$(date +%s%N 2>/dev/null || date +%s)
        if [ "$state" = "up" ] && [ "${#start_time}" -ge 13 ] 2>/dev/null; then
            latency=$(( (end_time - start_time) / 1000000 ))
        fi
    fi

    case "$state" in
        up)
            if [ -n "$latency" ]; then
                log_success "$name → ${HOST}:${PORT}  |  ${latency} ms"
            else
                log_success "$name → ${HOST}:${PORT}  |  Reachable"
            fi
            return 0
            ;;
        unknown)
            log_warn "$name → ${HOST}:${PORT}  |  UDP endpoint, no ICMP reply (unknown)"
            return 1
            ;;
    esac

    log_error "$name → ${HOST}:${PORT}  |  Unreachable"
    return 1
}


# Test all nodes

test_all_nodes() {
    echo
    echo "  🩺 Checking all nodes ..."
    echo "  ───────────────────────────────────────────────────────────"

    local total=0
    local ok=0
    local skipped=0

    for file in "$CONFIG_DIR"/*.json; do
        [ -f "$file" ] || continue
        name=$(basename "$file" .json)
        total=$((total + 1))

        if test_node "$name"; then
            ok=$((ok + 1))
        else
            # Count disabled separately if needed
            _hc_enabled "$file" || skipped=$((skipped + 1))
        fi
    done

    echo "  ───────────────────────────────────────────────────────────"
    if [ "$skipped" -gt 0 ]; then
        echo "  Result : ${GREEN}$ok${RESET} / $total reachable  ${GRAY}($skipped disabled)${RESET}"
    else
        echo "  Result : ${GREEN}$ok${RESET} / $total nodes are reachable"
    fi
    echo
}


# Test selected nodes only

test_selected_nodes() {
    echo
    echo "  📋 Available Configs :"
    echo "  ───────────────────────────────────────────────────────────"

    local configs=""
    local i=1

    for file in "$CONFIG_DIR"/*.json; do
        [ -f "$file" ] || continue
        name=$(basename "$file" .json)
        protocol=$(jq -r '.protocol // "unknown"' "$file" 2>/dev/null)

        if _hc_enabled "$file"; then
            echo "  $i) $name  ${GRAY}($protocol)${RESET}"
        else
            echo "  $i) $name  ${GRAY}($protocol) [DISABLED]${RESET}"
        fi

        configs="$configs $name"
        i=$((i + 1))
    done

    if [ "$i" -eq 1 ]; then
        log_warn "No configs found!"
        return 1
    fi

    echo "  ───────────────────────────────────────────────────────────"
    printf "  💊 Enter node numbers to check (e.g. 1 2 4) : "
    read -r selected </dev/tty

    if [ -z "$selected" ]; then
        log_warn "No selection entered!"
        return 1
    fi

    echo
    echo "  🩺 Checking selected nodes ..."
    echo "  ───────────────────────────────────────────────────────────"

    local idx=1
    for name in $configs; do
        for num in $selected; do
            if [ "$num" = "$idx" ]; then
                test_node "$name"
            fi
        done
        idx=$((idx + 1))
    done

    echo "  ───────────────────────────────────────────────────────────"
}


# Main Menu

health_checker_menu() {
    local HELP_MODULE_ID="proxy_health_checker"

    while true; do
        render_persistent_header

        echo "  🩺 Node Health Checker"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  🔭 1) Check All Nodes"
        echo "  🔬 2) Check Selected Nodes"
        ui_nav_footer

        ui_prompt 2
        choice="$UI_CHOICE"

        case "$choice" in
            1) test_all_nodes ;;
            2) test_selected_nodes ;;
            q|Q) daypass_quit ;;
            h|H)
                if command -v show_help >/dev/null 2>&1; then
                    show_help "$HELP_MODULE_ID"
                else
                    log_warn "Help module not loaded!"
                    sleep 1
                fi
                continue
                ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
        read -r _ </dev/tty || daypass_quit
    done
}

# 📄 Source : profile_manager.sh

# Applies ready-to-use profiles by calling real routing modes
# ============================================================


# Paths

PROXY_DIR="/etc/daypass/proxy"
PROFILE_DIR="$PROXY_DIR/profiles"
ROUTING_DIR="$PROXY_DIR/routing"
mkdir -p "$PROFILE_DIR"
mkdir -p "$ROUTING_DIR"


# Show current active profile

show_active_profile() {
    echo "  🎭 Current Active Profile"
    echo "  ───────────────────────────────────────────────────────────"

    if [ -f "$PROFILE_DIR/active" ]; then
        active=$(cat "$PROFILE_DIR/active")
        echo "  🫀 Active Profile : ${GREEN}$active${RESET}"
    else
        echo "  🫀 Active Profile : ${GRAY}None${RESET}"
    fi

    if [ -f "$ROUTING_DIR/current_mode" ]; then
        mode=$(cat "$ROUTING_DIR/current_mode")
        echo "  🚦 Routing Mode   : ${CYAN}$mode${RESET}"
    else
        echo "  🚦 Routing Mode   : ${GRAY}Not set${RESET}"
    fi

    echo "  ───────────────────────────────────────────────────────────"
}


# List available profiles

list_profiles() {
    echo "  🎭 Available Routing Profiles"
    echo "  ───────────────────────────────────────────────────────────"
    echo "  ⚖️  1) Balanced       (Iran Direct + Foreign Proxy)"
    echo "  🕹️  2) Gaming         (Low latency focus)"
    echo "  📺  3) Streaming      (Better for video services)"
    echo "  🌎  4) Global Proxy   (All traffic through proxy)"
    echo "  🎯  5) Direct Only    (Disable proxy completely)"
    echo "  ───────────────────────────────────────────────────────────"
}


# Apply a profile (calls real routing functions when possible)

apply_profile() {
    local profile="$1"

    case "$profile" in
        balanced)
            echo "balanced" > "$PROFILE_DIR/active"

            if command -v apply_iran_direct >/dev/null 2>&1; then
                apply_iran_direct
            else
                echo "iran_direct" > "$ROUTING_DIR/current_mode"
                log_warn "Routing module not fully loaded. Mode saved locally."
            fi

            log_success "Profile [⚖️ Balanced] applied!"
            log_info "Iranian sites → Direct | Foreign sites → Proxy"
            ;;

        gaming)
            echo "gaming" > "$PROFILE_DIR/active"

            # Gaming currently uses Iran Direct as base
            if command -v apply_iran_direct >/dev/null 2>&1; then
                apply_iran_direct
            else
                echo "iran_direct" > "$ROUTING_DIR/current_mode"
                log_warn "Routing module not fully loaded. Mode saved locally."
            fi

            log_success "Profile [🕹️ Gaming] applied!"
            log_info "Optimized for lower latency and stability."
            ;;

        streaming)
            echo "streaming" > "$PROFILE_DIR/active"

            if command -v apply_iran_direct >/dev/null 2>&1; then
                apply_iran_direct
            else
                echo "iran_direct" > "$ROUTING_DIR/current_mode"
                log_warn "Routing module not fully loaded. Mode saved locally."
            fi

            log_success "Profile [📺 Streaming] applied!"
            log_info "Optimized for YouTube / Netflix style traffic."
            ;;

        global)
            echo "global" > "$PROFILE_DIR/active"

            if command -v apply_global_proxy >/dev/null 2>&1; then
                apply_global_proxy
            else
                echo "global_proxy" > "$ROUTING_DIR/current_mode"
                log_warn "Routing module not fully loaded. Mode saved locally."
            fi

            log_success "Profile [🌎 Global Proxy] applied!"
            log_info "All traffic will go through proxy."
            ;;

        direct)
            echo "direct" > "$PROFILE_DIR/active"

            if command -v apply_direct_only >/dev/null 2>&1; then
                apply_direct_only
            else
                echo "direct_only" > "$ROUTING_DIR/current_mode"
                log_warn "Routing module not fully loaded. Mode saved locally."
            fi

            log_success "Profile [🎯 Direct Only] applied!"
            log_info "Proxy disabled. All traffic is direct."
            ;;

        *)
            log_error "Unknown profile!"
            return 1
            ;;
    esac
}


# Main Menu

profile_manager_menu() {
    local HELP_MODULE_ID="proxy_profiles"

    while true; do
        render_persistent_header

        echo "  🎭 Routing Profiles"
        echo "  ───────────────────────────────────────────────────────────"
        show_active_profile
        echo
        list_profiles
        echo
        ui_nav_footer

        ui_prompt 5
        choice="$UI_CHOICE"

        case "$choice" in
            1) apply_profile "balanced" ;;
            2) apply_profile "gaming" ;;
            3) apply_profile "streaming" ;;
            4) apply_profile "global" ;;
            5) apply_profile "direct" ;;
            q|Q) daypass_quit ;;
            h|H)
                if command -v show_help >/dev/null 2>&1; then
                    show_help "$HELP_MODULE_ID"
                else
                    log_warn "Help module not loaded!"
                    sleep 1
                fi
                continue
                ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
        read -r _ </dev/tty || daypass_quit
    done
}

# 📄 Source : core.sh
# ============================================================
# Shared paths and proxy core detection
# ============================================================

PROXY_DIR="/etc/daypass/proxy"
CONFIG_DIR="$PROXY_DIR/configs"
CLEAN_IP_DIR="$PROXY_DIR/clean_ip"
CANDIDATE_FILE="$CLEAN_IP_DIR/candidates.txt"
RESULT_FILE="$CLEAN_IP_DIR/last_results.txt"

mkdir -p "$CLEAN_IP_DIR"
mkdir -p "$CONFIG_DIR"

# ------------------------------------------------------------
# Detect installed proxy core
# Returns: xray | sing-box | none
# ------------------------------------------------------------
detect_proxy_core() {
    if command -v xray >/dev/null 2>&1; then
        echo "xray"
        return
    fi

    if command -v sing-box >/dev/null 2>&1; then
        echo "sing-box"
        return
    fi

    echo "none"
}

# 📄 Source : link_utils.sh
# ============================================================
# DayPass - Share link helpers for the Cloudflare Clean IP flow
# ============================================================

# Transports Cloudflare can front; anything else cannot survive an address swap
_cf_cdn_transport() {
    case "$1" in
        ws|websocket|httpupgrade|h2|h2c|http|grpc|xhttp|splithttp) return 0 ;;
    esac
    return 1
}

# A name we can pin as SNI / Host; bare IP literals are not
_cf_is_domain() {
    case "$1" in
        ''|*:*)        return 1 ;;   # empty or IPv6 literal
        *[A-Za-z]*)    return 0 ;;   # has letters, so not an IPv4 literal
        *)             return 1 ;;
    esac
}

# Sets CF_HOST / CF_PORT from host:port or [v6]:port
_cf_split_hostport() {
    local hp="${1%%/*}"

    CF_HOST=""
    CF_PORT=""

    case "$hp" in
        '['*)
            CF_HOST=${hp#\[}
            CF_HOST=${CF_HOST%%\]*}
            CF_PORT=${hp##*\]}
            CF_PORT=${CF_PORT#:}
            ;;
        *:*:*)
            CF_HOST="$hp"
            ;;
        *:*)
            CF_HOST=${hp%:*}
            CF_PORT=${hp##*:}
            ;;
        *)
            CF_HOST="$hp"
            ;;
    esac

    CF_PORT=${CF_PORT%%,*}
    case "$CF_PORT" in
        ''|*[!0-9]*) CF_PORT="" ;;
    esac
}

# base64 decode / encode tolerating the url-safe alphabet and missing padding
_cf_b64d() {
    local data pad

    data=$(printf '%s' "$1" | tr -d '\r\n' | tr '_-' '/+')
    [ -n "$data" ] || return 1

    pad=$(( ${#data} % 4 ))
    case "$pad" in
        2) data="${data}==" ;;
        3) data="${data}=" ;;
        1) return 1 ;;
    esac

    printf '%s' "$data" | base64 -d 2>/dev/null
}

_cf_b64e() {
    printf '%s' "$1" | base64 2>/dev/null | tr -d '\n'
}

_cf_json_get() {
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$1" | jq -r --arg k "$2" '.[$k] // empty | tostring' 2>/dev/null
        return 0
    fi

    printf '%s' "$1" | tr ',{' '\n\n' | \
        sed -n "s/^[[:space:]]*\"$2\"[[:space:]]*:[[:space:]]*//p" | head -n 1 | \
        sed 's/^"//;s/"[[:space:]]*}*[[:space:]]*$//;s/[[:space:]]*}*[[:space:]]*$//'
}

# Decoded JSON document of a vmess:// link
_cf_vmess_json() {
    local body="${1#vmess://}"
    _cf_b64d "${body%%#*}"
}

_cf_query_get() {
    printf '%s\n' "$1" | tr '&' '\n' | sed -n "s/^$2=//p" | head -n 1
}

# Appends key=value to a query string
_cf_query_add() {
    if [ -z "$1" ]; then
        printf '%s=%s' "$2" "$3"
    else
        printf '%s&%s=%s' "$1" "$2" "$3"
    fi
}

# ------------------------------------------------------------
# Extract address from share link
# ------------------------------------------------------------
extract_address_from_link() {
    local link="$1"
    local body json

    case "$link" in
        vmess://*)
            json=$(_cf_vmess_json "$link")
            [ -n "$json" ] && _cf_json_get "$json" add
            return 0
            ;;
        *://*) body=${link#*://} ;;
        *)     body="$link" ;;
    esac

    body=${body%%#*}
    body=${body%%\?*}
    case "$body" in *@*) body=${body##*@} ;; esac

    _cf_split_hostport "$body"
    echo "$CF_HOST"
}

# ------------------------------------------------------------
# Extract port from share link
# ------------------------------------------------------------
extract_port_from_link() {
    local link="$1"
    local body json port=""

    case "$link" in
        vmess://*)
            json=$(_cf_vmess_json "$link")
            [ -n "$json" ] && port=$(_cf_json_get "$json" port)
            ;;
        *)
            case "$link" in
                *://*) body=${link#*://} ;;
                *)     body="$link" ;;
            esac
            body=${body%%#*}
            body=${body%%\?*}
            case "$body" in *@*) body=${body##*@} ;; esac
            _cf_split_hostport "$body"
            port="$CF_PORT"
            ;;
    esac

    [ -z "$port" ] && port="443"
    echo "$port"
}

# ------------------------------------------------------------
# Replace only the connect address of a share link with a clean IP
#
# A clean IP only works when the link is fronted by Cloudflare: the TLS
# handshake and the CDN's own routing still have to target the original
# domain, so that domain is pinned into sni= / host= when the link has
# neither. Links where an address swap cannot work are refused (rc 1,
# nothing printed): Reality, QUIC transports and shadowsocks.
#
# Sets CF_REPLACE_NOTE describing what was pinned.
# ------------------------------------------------------------
replace_address_in_link() {
    local link="$1"
    local new_ip="$2"
    local scheme body frag userinfo query hostport
    local old_host port network security sni host_header json

    CF_REPLACE_NOTE=""

    if [ -z "$link" ] || [ -z "$new_ip" ]; then
        log_error "replace_address_in_link needs a share link and a clean IP!"
        return 1
    fi

    case "$link" in
        *://*)
            scheme=${link%%://*}
            body=${link#*://}
            ;;
        *)
            log_warn "Not a share link; cannot replace its address."
            return 1
            ;;
    esac

    case "$scheme" in
        vless|trojan|vmess) ;;
        ss|ssr)
            log_warn "Shadowsocks has no SNI to fall back on, so a clean IP cannot replace its address. Config left unchanged."
            return 1
            ;;
        hysteria|hysteria2|hy2|tuic|naive+quic)
            log_warn "[$scheme] runs over QUIC/UDP, which Cloudflare's proxy does not carry. Config left unchanged."
            return 1
            ;;
        *)
            log_warn "Unsupported share link type [$scheme] for Clean IP. Config left unchanged."
            return 1
            ;;
    esac

    # ---------------- vmess: edit the JSON document, never the base64 ----------------
    if [ "$scheme" = "vmess" ]; then
        frag=""
        case "$body" in *'#'*) frag="#${body#*#}" ;; esac

        json=$(_cf_vmess_json "$link")
        case "$json" in
            '{'*) ;;
            *)
                log_warn "Could not decode this vmess link. Config left unchanged."
                return 1
                ;;
        esac

        if ! command -v jq >/dev/null 2>&1; then
            log_error "jq is required to rewrite a vmess link safely!"
            return 1
        fi

        network=$(_cf_json_get "$json" net)
        [ -n "$network" ] || network="tcp"
        old_host=$(_cf_json_get "$json" add)

        if ! _cf_cdn_transport "$network"; then
            log_warn "vmess over [$network] is not fronted by Cloudflare, so a clean IP would break it. Config left unchanged."
            return 1
        fi
        if [ -z "$old_host" ]; then
            log_warn "This vmess link carries no address. Config left unchanged."
            return 1
        fi

        sni=$(_cf_json_get "$json" sni)
        host_header=$(_cf_json_get "$json" host)
        if [ -z "$sni" ] && [ -z "$host_header" ]; then
            if ! _cf_is_domain "$old_host"; then
                log_warn "This vmess link connects to the bare address [$old_host] with no host/sni, so there is no domain to keep targeting. Config left unchanged."
                return 1
            fi
            CF_REPLACE_NOTE="Host header pinned to [$old_host] so the CDN still routes to it."
        fi

        json=$(printf '%s' "$json" | jq -c --arg ip "$new_ip" --arg dom "$old_host" '
            .add = $ip
            | if ((.sni // "") == "") and ((.host // "") == "") then .host = $dom else . end
        ' 2>/dev/null)
        if [ -z "$json" ]; then
            log_error "Failed to rewrite the vmess link!"
            return 1
        fi

        printf 'vmess://%s%s\n' "$(_cf_b64e "$json")" "$frag"
        return 0
    fi

    # ---------------- vless / trojan ----------------
    frag=""
    userinfo=""
    query=""
    case "$body" in *'#'*) frag="#${body#*#}"; body=${body%%#*} ;; esac
    case "$body" in *'?'*) query=${body#*\?};  body=${body%%\?*} ;; esac
    case "$body" in *@*)   userinfo="${body%@*}@"; body=${body##*@} ;; esac

    _cf_split_hostport "$body"
    old_host="$CF_HOST"
    port="$CF_PORT"

    if [ -z "$old_host" ]; then
        log_warn "Could not read the address of this link. Config left unchanged."
        return 1
    fi

    network=$(_cf_query_get "$query" type)
    [ -n "$network" ] || network="tcp"
    security=$(_cf_query_get "$query" security)
    if [ -z "$security" ] && [ "$scheme" = "trojan" ]; then
        security="tls"
    fi
    sni=$(_cf_query_get "$query" sni)
    [ -n "$sni" ] || sni=$(_cf_query_get "$query" peer)
    host_header=$(_cf_query_get "$query" host)

    if [ "$security" = "reality" ]; then
        log_warn "Reality pins the server's public key to its real address, so a clean IP cannot be used. Config left unchanged."
        return 1
    fi
    if ! _cf_cdn_transport "$network"; then
        log_warn "[$scheme] over [$network] is not fronted by Cloudflare, so a clean IP would break it. Config left unchanged."
        return 1
    fi

    case "$security" in
        tls|xtls)
            # host already defines the SNI; only pin it when neither is set
            if [ -z "$sni" ] && [ -z "$host_header" ]; then
                if ! _cf_is_domain "$old_host"; then
                    log_warn "This link connects to the bare address [$old_host] with no sni/host, so there is no domain for the TLS handshake to keep targeting. Config left unchanged."
                    return 1
                fi
                query=$(_cf_query_add "$query" "sni" "$old_host")
                CF_REPLACE_NOTE="TLS SNI pinned to [$old_host] so the handshake still targets it."
            fi
            ;;
        *)
            # plaintext over the CDN: the Host header is what routes the request
            if [ -z "$host_header" ]; then
                if ! _cf_is_domain "$old_host"; then
                    log_warn "This link connects to the bare address [$old_host] with no host header, so the CDN would have nothing to route on. Config left unchanged."
                    return 1
                fi
                query=$(_cf_query_add "$query" "host" "$old_host")
                CF_REPLACE_NOTE="Host header pinned to [$old_host] so the CDN still routes to it."
            fi
            ;;
    esac

    case "$new_ip" in
        *:*) hostport="[$new_ip]" ;;
        *)   hostport="$new_ip" ;;
    esac
    [ -n "$port" ] && hostport="$hostport:$port"

    printf '%s://%s%s%s%s\n' "$scheme" "$userinfo" "$hostport" "${query:+?$query}" "$frag"
    return 0
}


# 📄 Source : scanner.sh

# ------------------------------------------------------------
# Basic TCP connectivity test on specific port
# ------------------------------------------------------------
test_ip_basic() {
    local ip="$1"
    local port="$2"
    local timeout_sec="${3:-3}"

    if command -v curl >/dev/null 2>&1; then
        if curl -s -o /dev/null --connect-timeout "$timeout_sec" "telnet://$ip:$port"; then
            return 0
        fi
        return 1
    fi

    if command -v nc >/dev/null 2>&1; then
        if nc -w "$timeout_sec" "$ip" "$port" </dev/null >/dev/null 2>&1; then
            return 0
        fi
        return 1
    fi

    return 1
}

# ------------------------------------------------------------
# Measure rough latency (ms)
# ------------------------------------------------------------
measure_latency() {
    local ip="$1"
    local port="$2"
    local start end

    start=$(date +%s%N 2>/dev/null || date +%s)

    if test_ip_basic "$ip" "$port" 2; then
        end=$(date +%s%N 2>/dev/null || date +%s)
        if [ "${#start}" -ge 13 ] 2>/dev/null; then
            echo $(( (end - start) / 1000000 ))
        else
            echo "0"
        fi
        return 0
    fi

    echo ""
    return 1
}

# ------------------------------------------------------------
# Advanced validation placeholder (xray / sing-box)
# ------------------------------------------------------------
test_ip_advanced() {
    local ip="$1"
    local port="$2"
    local share_link="$3"
    local core

    core=$(detect_proxy_core)

    case "$core" in
        xray)
            log_info "Advanced Xray validation not fully implemented yet. Using basic test!"
            test_ip_basic "$ip" "$port"
            ;;
        sing-box)
            log_info "Advanced Sing-box validation not fully implemented yet. Using basic test!"
            test_ip_basic "$ip" "$port"
            ;;
        *)
            test_ip_basic "$ip" "$port"
            ;;
    esac
}

# ------------------------------------------------------------
# Ensure candidate IP list exists
# ------------------------------------------------------------
ensure_candidate_file() {
    if [ -f "$CANDIDATE_FILE" ] && [ -s "$CANDIDATE_FILE" ]; then
        return 0
    fi

    cat > "$CANDIDATE_FILE" << EOF
# DayPass Clean IP candidates (Cloudflare-focused)
# One IP per line. Lines starting with # are ignored!
1.1.1.1
1.0.0.1
104.16.0.1
104.17.0.1
104.18.0.1
104.19.0.1
104.20.0.1
104.21.0.1
104.22.0.1
104.24.0.1
EOF

    log_info "Default candidate list created at : [$CANDIDATE_FILE]"
}

# ------------------------------------------------------------
# Scan candidate IPs using the config port
# ------------------------------------------------------------
scan_candidate_ips() {
    local port="$1"
    local share_link="$2"
    local mode="${3:-basic}"

    ensure_candidate_file
    > "$RESULT_FILE"

    echo
    echo "  🔍 Scanning candidate IPs on port [$port] ..."
    echo "  ───────────────────────────────────────────────────────────"

    local total=0
    local ok=0
    local ip latency

    while IFS= read -r line; do
        line=$(echo "$line" | xargs)
        [ -z "$line" ] && continue
        case "$line" in
            \#*) continue ;;
        esac

        ip="$line"
        total=$((total + 1))

        if [ "$mode" = "advanced" ]; then
            if test_ip_advanced "$ip" "$port" "$share_link"; then
                latency=$(measure_latency "$ip" "$port")
                [ -z "$latency" ] && latency="?"
                log_success "$ip:$port  |  ${latency} ms"
                echo "$latency $ip" >> "$RESULT_FILE"
                ok=$((ok + 1))
            else
                log_error "$ip:$port  |  Unreachable"
            fi
        else
            if test_ip_basic "$ip" "$port"; then
                latency=$(measure_latency "$ip" "$port")
                [ -z "$latency" ] && latency="?"
                log_success "$ip:$port  |  ${latency} ms"
                echo "$latency $ip" >> "$RESULT_FILE"
                ok=$((ok + 1))
            else
                log_error "$ip:$port  |  Unreachable"
            fi
        fi
    done < "$CANDIDATE_FILE"

    echo "  ───────────────────────────────────────────────────────────"
    echo "  Result : ${GREEN}$ok${RESET} / $total IP(s) reachable ;)"
    echo

    if [ "$ok" -gt 0 ]; then
        sort -n "$RESULT_FILE" -o "$RESULT_FILE" 2>/dev/null || true
        echo "  🏆 Best candidates :"
        awk '{printf "   - %s  (%s ms)\n", $2, $1}' "$RESULT_FILE" | head -n 10
        echo
    fi
}

# ------------------------------------------------------------
# Show / hint edit candidate list
# ------------------------------------------------------------
edit_candidates() {
    ensure_candidate_file
    echo
    log_info "Candidate file : [$CANDIDATE_FILE]"
    echo "  Current list :"
    echo "  ───────────────────────────────────────────────────────────"
    cat "$CANDIDATE_FILE"
    echo "  ───────────────────────────────────────────────────────────"
    echo
    log_info "Edit this file manually, then rerun scan!"
}

# 📄 Source : applier.sh

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
    if [ -n "${CF_REPLACE_NOTE:-}" ]; then
        log_info "$CF_REPLACE_NOTE"
    else
        log_info "SNI / Host / Path left unchanged!"
    fi
}

# 📄 Source : cf.sh

# ------------------------------------------------------------
# Interactive flow: select config -> scan -> apply
# ------------------------------------------------------------
clean_ip_for_config() {
    echo
    echo "  📋 Available Configs :"
    echo "  ───────────────────────────────────────────────────────────"

    local configs=""
    local i=1
    for file in "$CONFIG_DIR"/*.json; do
        [ -f "$file" ] || continue
        name=$(basename "$file" .json)
        protocol=$(jq -r '.protocol // "unknown"' "$file" 2>/dev/null)
        echo "  $i) $name  ${GRAY}($protocol)${RESET}"
        configs="$configs $name"
        i=$((i + 1))
    done

    if [ "$i" -eq 1 ]; then
        log_warn "No configs found!"
        return 1
    fi

    echo "  ───────────────────────────────────────────────────────────"
    printf "  🎯 Select config number : "
    read -r choice </dev/tty

    local idx=1
    local conf_name=""
    for name in $configs; do
        if [ "$choice" = "$idx" ]; then
            conf_name="$name"
            break
        fi
        idx=$((idx + 1))
    done

    if [ -z "$conf_name" ]; then
        log_warn "Invalid selection!"
        return 1
    fi

    local file="$CONFIG_DIR/${conf_name}.json"
    local share_link port old_addr core
    share_link=$(jq -r '.share_link // empty' "$file" 2>/dev/null)
    port=$(extract_port_from_link "$share_link")
    old_addr=$(extract_address_from_link "$share_link")
    core=$(detect_proxy_core)

    echo
    log_info "Config   : $conf_name"
    log_info "Address  : ${old_addr:-unknown}"
    log_info "Port     : $port"
    log_info "Core     : $core"
    echo

    echo "  🧪 Test mode :"
    echo "  👼🏻 1) Basic TCP only"
    echo "  👩🏻‍🔬 2) Advanced (Xray/Sing-box aware - placeholder)"
    if command -v ui_nav_footer >/dev/null 2>&1; then
        ui_nav_footer
    fi
    printf "  ⁉️ Select mode [1-2] : "
    read -r mode_choice </dev/tty

    while [ "$mode_choice" = "h" ] || [ "$mode_choice" = "H" ]; do
        if command -v show_help >/dev/null 2>&1; then
            show_help "proxy_clean_ip_scan"
        else
            log_warn "Help module not loaded!"
            sleep 1
        fi
        echo
        echo "  🧪 Test mode :"
        echo "  👼🏻 1) Basic TCP only"
        echo "  👩🏻‍🔬 2) Advanced (Xray/Sing-box aware - placeholder)"
        if command -v ui_nav_footer >/dev/null 2>&1; then
            ui_nav_footer
        fi
        printf "  ⁉️ Select mode [1-2] : "
        read -r mode_choice </dev/tty
    done

    case "$mode_choice" in
        0) log_info "Cancelled."; return 0 ;;
        q|Q)
            command -v daypass_quit >/dev/null 2>&1 && daypass_quit
            return 0
            ;;
    esac

    local mode="basic"
    [ "$mode_choice" = "2" ] && mode="advanced"

    scan_candidate_ips "$port" "$share_link" "$mode"

    if [ ! -s "$RESULT_FILE" ]; then
        log_warn "No reachable clean IPs found!"
        return 1
    fi

    printf "  🧼 Enter Clean IP to apply (or empty to cancel) : "
    read -r clean_ip </dev/tty
    [ -z "$clean_ip" ] && { log_info "Cancelled."; return 0; }

    apply_clean_ip_to_config "$conf_name" "$clean_ip"

    printf "  🫸🏻 Push updated config to the active engine now? [y/N] : "
    read -r push_now </dev/tty
    case "$push_now" in
        y|Y)
            if command -v transport_push_config >/dev/null 2>&1; then
                transport_push_config "$conf_name"
            else
                log_warn "transport_push_config() not found!"
            fi
            ;;
    esac
}

# ------------------------------------------------------------
# Main Cloudflare Clean IP Menu
# ------------------------------------------------------------
clean_ip_menu() {
    local HELP_MODULE_ID="proxy_clean_ip"

    while true; do
        render_persistent_header

        local core
        core=$(detect_proxy_core)

        echo "  🧼 Clean IP Manager (Cloudflare)"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  🛡️ Proxy Core : ${CYAN}$core${RESET}"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  🕵🏻‍♀️ 1) Find Clean IP for a Config"
        echo "  👫🏻 2) Show / Edit Candidate IP List"
        echo "  📺 3) Show Last Scan Results"
        ui_nav_footer

        ui_prompt 3
        choice="$UI_CHOICE"

        case "$choice" in
            1) clean_ip_for_config ;;
            2) edit_candidates ;;
            3)
                if [ -f "$RESULT_FILE" ] && [ -s "$RESULT_FILE" ]; then
                    echo
                    echo "  🏆 Last Results :"
                    echo "  ───────────────────────────────────────────────────────────"
                    awk '{printf "   - %s  (%s ms)\n", $2, $1}' "$RESULT_FILE"
                    echo "  ───────────────────────────────────────────────────────────"
                else
                    log_warn "No scan results yet!"
                fi
                ;;
            q|Q) daypass_quit ;;
            h|H)
                if command -v show_help >/dev/null 2>&1; then
                    show_help "$HELP_MODULE_ID"
                else
                    log_warn "Help module not loaded!"
                    sleep 1
                fi
                continue
                ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
        read -r _ </dev/tty || daypass_quit
    done
}


# 📄 Source : backup_restore.sh

# Config Backup and Restore Module for DayPass Deployment Stack
# Preserves critical UCI configurations during updates and system migration

BACKUP_DIR="/tmp/daypass/backups"
CONFIG_PATHS="/etc/config/passwall /etc/config/passwall2 /etc/config/xray /etc/config/sing-box /etc/config/niki"

# Creates a compressed timestamped archive of target configuration files
backup_configs()
{
    log_info "Initiating UCI configuration backup ..." 2>/dev/null || echo "ℹ️ Initiating UCI configuration backup ..."

    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    ARCHIVE_FILE="$BACKUP_DIR/daypass_config_backup_$TIMESTAMP.tar.gz"

    EXISTING_TARGETS=""
    for path in $CONFIG_PATHS; do
        if [ -e "$path" ]; then
            EXISTING_TARGETS="$EXISTING_TARGETS $path"
        fi
    done

    if [ -z "$EXISTING_TARGETS" ]; then
        log_warn "No existing target configuration files found to backup!" 2>/dev/null || echo "❌♻️ No existing configs to backup!"
        return 0
    fi

    if tar -czf "$ARCHIVE_FILE" $EXISTING_TARGETS 2>/dev/null; then
        # Create a symlink to latest backup
        ln -sf "$ARCHIVE_FILE" "$BACKUP_DIR/latest_backup.tar.gz"
        log_success "Backup created successfully : [$ARCHIVE_FILE]" 2>/dev/null || echo "✅♻️ Backup created :)"
        return 0
    else
        log_error "Failed to create configuration backup archive!" 2>/dev/null || echo "❌♻️ Backup failed :("
        return 1
    fi
}

# Restores configurations from the latest backup archive
restore_configs()
{
    TARGET_ARCHIVE="${1:-$BACKUP_DIR/latest_backup.tar.gz}"

    if [ ! -f "$TARGET_ARCHIVE" ]; then
        log_error "Backup archive not found at path : [$TARGET_ARCHIVE]" 2>/dev/null || echo "❌♻️ Backup archive missing."
        return 1
    fi

    log_info "Restoring UCI configuration from : [$TARGET_ARCHIVE] ..." 2>/dev/null || echo "ℹ️ Restoring configs ..."

    if tar -xzf "$TARGET_ARCHIVE" -C / 2>/dev/null; then
        log_success "Configurations restored successfully from backup!" 2>/dev/null || echo "✅♻️ Configs restored!"
        
        # Reload UCI subsystem to commit restored configs
        uci commit 2>/dev/null
        return 0
    else
        log_error "Failed to unpack backup archive during restore!" 2>/dev/null || echo "❌♻️ Restore failed."
        return 1
    fi
}

# Standalone execution handler
case "$0" in
    *backup_restore.sh)
        case "${1:-backup}" in
            backup)  backup_configs ;;
            restore) restore_configs "$2" ;;
        esac
        ;;
esac

# 📄 Source : banner.sh

# Single source of truth for the version shown in the UI, the system
# login banner (/etc/banner) and the help metadata.
DAYPASS_VERSION="v2.1.2"

_banner_row()
{
    printf '%s%s%s%s%s%s%s\n' "$RED" "$1" "$RESET" "$WHITE" "$2" "$RESET" "$3"
}

show_banner()
{
    VERSION="${DAYPASS_VERSION}"

    printf '\n'

    _banner_row '   ____              ' ' ____               '
    _banner_row '  |  _ \  __ _ _   _ ' '|  _ \  __ _ ___ ___'
    _banner_row '  | | | |/ _` | | | |' '| |_) / _` / __/ __|'
    _banner_row '  | |_| | (_| | |_| |' '|  __/ (_| \__ \__ \'
    _banner_row '  |____/ \__,_|\__, |' '|_|   \__,_|___/___/' "${GRAY} ${VERSION}${RESET}"
    _banner_row '               |___/ ' ''

    printf '%s%s%s\n' "$GRAY" \
        '  ───────────────────── 🕊️ Remembering the IRAN Massacre on Jan 8-9, 2026 ─────────────────────' \
        "$RESET"
}


# 📄 Source : banner.sh

# ============================================================
# DayPass - System Login Banner (/etc/banner)
# Keeps one copy of the stock OpenWrt banner, then writes the
# DayPass banner printed on every SSH / console login.
# ============================================================

SYS_BANNER_FILE="/etc/banner"
SYS_BANNER_BACKUP="/etc/banner.daypass-orig"

# Marker used to tell our own banner apart from the stock one
SYS_BANNER_TAG="DayPass Deployment Toolkit"

# ------------------------------------------------------------
# DayPass version (single source of truth is ui/banner.sh)
# ------------------------------------------------------------
_sys_banner_version() {
    if [ -n "${DAYPASS_VERSION:-}" ]; then
        echo "$DAYPASS_VERSION"
    else
        echo "v2.1.1"
    fi
}

# ------------------------------------------------------------
# Firmware release, e.g. "OpenWrt 24.10.0 r28427-6df0e3d02a"
# ------------------------------------------------------------
_sys_banner_release() {
    if [ -f /etc/openwrt_release ]; then
        (
            . /etc/openwrt_release 2>/dev/null
            printf '%s %s %s' "${DISTRIB_ID:-OpenWrt}" "${DISTRIB_RELEASE:-unknown}" "${DISTRIB_REVISION:-}"
        ) | sed -e 's/  */ /g' -e 's/ *$//'
        return 0
    fi

    if [ -f /etc/os-release ]; then
        (
            . /etc/os-release 2>/dev/null
            printf '%s %s' "${NAME:-OpenWrt}" "${VERSION:-${BUILD_ID:-unknown}}"
        ) | sed -e 's/  */ /g' -e 's/ *$//'
        return 0
    fi

    echo "OpenWrt (release unknown)"
}

# ------------------------------------------------------------
# Build target and CPU arch, e.g. "ath79/generic (mips_24kc)"
# ------------------------------------------------------------
_sys_banner_target() {
    SYS_BANNER_T=""
    SYS_BANNER_A=""

    if [ -f /etc/openwrt_release ]; then
        SYS_BANNER_T=$(
            . /etc/openwrt_release 2>/dev/null
            echo "${DISTRIB_TARGET:-}"
        )
        SYS_BANNER_A=$(
            . /etc/openwrt_release 2>/dev/null
            echo "${DISTRIB_ARCH:-}"
        )
    fi

    [ -z "$SYS_BANNER_A" ] && SYS_BANNER_A="$(uname -m 2>/dev/null)"

    if [ -n "$SYS_BANNER_T" ] && [ -n "$SYS_BANNER_A" ]; then
        echo "$SYS_BANNER_T ($SYS_BANNER_A)"
    elif [ -n "$SYS_BANNER_T" ]; then
        echo "$SYS_BANNER_T"
    elif [ -n "$SYS_BANNER_A" ]; then
        echo "$SYS_BANNER_A"
    else
        echo "unknown target"
    fi
}

# ------------------------------------------------------------
# Banner template. Quoted heredoc: backslashes and backticks of
# the ASCII art stay literal and the @...@ fields are filled in
# by system_banner_render.
# ------------------------------------------------------------
_sys_banner_template() {
    cat <<'DAYPASS_BANNER_EOF'
 ---------------------------------------------------------------------
  ____               ____
 |  _ \  __ _ _   _ |  _ \  __ _ ___ ___
 | | | |/ _` | | | || |_) / _` / __/ __|
 | |_| | (_| | |_| ||  __/ (_| \__ \__ \
 |____/ \__,_|\__, ||_|   \__,_|___/___/  @VERSION@
              |___/
 ---------------------------------------------------------------------

DAYPASS_BANNER_EOF
}

# ------------------------------------------------------------
# Print the banner with the current system values filled in
# ------------------------------------------------------------
system_banner_render() {
    SYS_BANNER_VER=$(_sys_banner_version | tr -d '|')
    SYS_BANNER_REL=$(_sys_banner_release | tr -d '|')
    SYS_BANNER_TGT=$(_sys_banner_target | tr -d '|')
    SYS_BANNER_DATE=$(date '+%Y-%m-%d' 2>/dev/null)
    [ -n "$SYS_BANNER_DATE" ] || SYS_BANNER_DATE="unknown date"

    _sys_banner_template | sed \
        -e "s|@VERSION@|$SYS_BANNER_VER|g" \
        -e "s|@RELEASE@|$SYS_BANNER_REL|g" \
        -e "s|@TARGET@|$SYS_BANNER_TGT|g" \
        -e "s|@DATE@|$SYS_BANNER_DATE|g"
}

# ------------------------------------------------------------
# True when /etc/banner is the DayPass one
# ------------------------------------------------------------
system_banner_is_daypass() {
    [ -f "$SYS_BANNER_FILE" ] || return 1
    grep -qF "$SYS_BANNER_TAG" "$SYS_BANNER_FILE" 2>/dev/null
}

# ------------------------------------------------------------
# One-line state for menus and logs
# ------------------------------------------------------------
system_banner_status() {
    if system_banner_is_daypass; then
        if [ -f "$SYS_BANNER_BACKUP" ]; then
            echo "DayPass banner installed (original kept at $SYS_BANNER_BACKUP)"
        else
            echo "DayPass banner installed (no backup of the original)"
        fi
    elif [ -f "$SYS_BANNER_FILE" ]; then
        echo "stock OpenWrt banner"
    else
        echo "no $SYS_BANNER_FILE on this system"
    fi
}

# ------------------------------------------------------------
# Install (or refresh) the DayPass banner
# ------------------------------------------------------------
install_system_banner() {
    SYS_BANNER_TMP="$SYS_BANNER_FILE.daypass-new"

    if ! system_banner_render > "$SYS_BANNER_TMP" 2>/dev/null; then
        rm -f "$SYS_BANNER_TMP" 2>/dev/null
        log_error "Failed to build the DayPass login banner!"
        return 1
    fi

    if [ ! -s "$SYS_BANNER_TMP" ]; then
        rm -f "$SYS_BANNER_TMP" 2>/dev/null
        log_error "Generated login banner is empty, keeping the current one!"
        return 1
    fi

    # Nothing to do when the installed banner already matches
    if [ -f "$SYS_BANNER_FILE" ] && cmp -s "$SYS_BANNER_TMP" "$SYS_BANNER_FILE"; then
        rm -f "$SYS_BANNER_TMP" 2>/dev/null
        log_info "DayPass login banner is already up to date."
        return 0
    fi

    # Keep the stock banner the first time only, so repeated installs
    # never overwrite the backup with our own banner.
    if [ ! -f "$SYS_BANNER_BACKUP" ] && [ -f "$SYS_BANNER_FILE" ] && ! system_banner_is_daypass; then
        if cp "$SYS_BANNER_FILE" "$SYS_BANNER_BACKUP" 2>/dev/null; then
            log_info "Original banner backed up to : [$SYS_BANNER_BACKUP]"
        else
            rm -f "$SYS_BANNER_TMP" 2>/dev/null
            log_error "Could not back up [$SYS_BANNER_FILE], banner left unchanged!"
            return 1
        fi
    fi

    if ! mv "$SYS_BANNER_TMP" "$SYS_BANNER_FILE" 2>/dev/null; then
        rm -f "$SYS_BANNER_TMP" 2>/dev/null
        log_error "Failed to write [$SYS_BANNER_FILE]!"
        return 1
    fi

    chmod 644 "$SYS_BANNER_FILE" 2>/dev/null
    log_success "DayPass login banner installed to [$SYS_BANNER_FILE]!"
    log_info "It shows on the next SSH or console login."
    return 0
}

# ------------------------------------------------------------
# Put the stock OpenWrt banner back
# ------------------------------------------------------------
restore_system_banner() {
    if [ ! -f "$SYS_BANNER_BACKUP" ]; then
        log_warn "No banner backup found at [$SYS_BANNER_BACKUP]."
        log_info "The original banner is restored by a firmware upgrade or factory reset."
        return 1
    fi

    if ! cp "$SYS_BANNER_BACKUP" "$SYS_BANNER_FILE" 2>/dev/null; then
        log_error "Failed to restore [$SYS_BANNER_FILE] from the backup!"
        return 1
    fi

    rm -f "$SYS_BANNER_BACKUP" 2>/dev/null
    chmod 644 "$SYS_BANNER_FILE" 2>/dev/null
    log_success "Original OpenWrt login banner restored!"
    return 0
}

# ------------------------------------------------------------
# Called after a deployment: install the banner unless the user
# opted out with DAYPASS_SKIP_BANNER=1
# ------------------------------------------------------------
system_banner_post_install() {
    [ "${DAYPASS_SKIP_BANNER:-0}" = "1" ] && return 0
    install_system_banner
}

# ------------------------------------------------------------
# Interactive entry used by the maintenance menu
# ------------------------------------------------------------
system_banner_manage() {
    echo
    printf "  🪧 ${BOLD}SSH / Console Login Banner${RESET}\n"
    echo "  ───────────────────────────────────────────────────────────"
    printf "  📄 Banner file : ${CYAN}%s${RESET}\n" "$SYS_BANNER_FILE"
    printf "  🫀 Current     : ${GRAY}%s${RESET}\n" "$(system_banner_status)"
    echo "  ───────────────────────────────────────────────────────────"
    printf "  ${GRAY}[i] Install / refresh the DayPass banner${RESET}\n"
    printf "  ${GRAY}[p] Preview it without writing anything${RESET}\n"
    printf "  ${GRAY}[r] Restore the original OpenWrt banner${RESET}\n"
    echo
    printf "  ⁉️ ${YELLOW}Action${RESET} ${GRAY}(i/p/r, [Enter] cancel) :${RESET} "
    read -r SYS_BANNER_CMD </dev/tty || daypass_quit

    case "$SYS_BANNER_CMD" in
        i|I) install_system_banner ;;
        p|P)
            echo
            system_banner_render
            ;;
        r|R) restore_system_banner ;;
        q|Q) daypass_quit ;;
        *)   log_info "Login banner left unchanged." ;;
    esac
}

# Standalone execution handler
case "$0" in
    *banner.sh)
        case "${1:-install}" in
            install) install_system_banner ;;
            restore) restore_system_banner ;;
            render)  system_banner_render ;;
            status)  system_banner_status ;;
        esac
        ;;
esac


# 📄 Source : maintenance.sh

# 1. Purge Packages Installed by DayPass (selective engine in installer/pkg/purge.sh)
purge_daypass_packages()
{
    if command -v purge_menu >/dev/null 2>&1; then
        purge_menu
        return $?
    fi
    log_error "Purge engine is not loaded."
    return 1
}

# 2. OpenWrt Factory Reset
factory_reset_system()
{
    echo
    printf "  ${RED}🚨 WARNING : FACTORY RESET SYSTEM${RESET}\n"
    printf "  This will erase ALL user configurations and restore system defaults!\n\n"
    
    printf "  Type '${BOLD}RESET${RESET}' to confirm factory reset : "
    read -r confirm </dev/tty

    if [ "$confirm" = "RESET" ]; then
        log_warn "Initiating Firstboot / Factory Reset procedure ..."
        sleep 2
        if command -v firstboot >/dev/null 2>&1; then
            firstboot -y && reboot
        else
            log_error "Command 'firstboot' not found on this system!"
        fi
    else
        log_info "Factory reset aborted!"
    fi
}

# 3. Clean DayPass Temporary Cache
clean_daypass_cache()
{
    log_info "Cleaning DayPass temporary files and package caches ..."
    rm -rf "${DAYPASS_DIR:?}"/*.apk "${DAYPASS_DIR:?}"/*.ipk "${DAYPASS_DIR:?}"/*.part 2>/dev/null
    log_success "Cache cleaned successfully!"
}

# 4. Backup System Configuration
backup_system_config()
{
    BACKUP_FILE="/tmp/backup-$(date +%Y%m%d_%H%M%S).tar.gz"
    log_info "Generating OpenWrt system configuration backup ..."
    if sysupgrade -b "$BACKUP_FILE" >/dev/null 2>&1; then
        log_success "Backup saved to : [$BACKUP_FILE]"
    else
        log_error "Failed to generate system backup!"
    fi
}

# Maintenance Sub-Menu
maintenance_menu()
{
    local HELP_MODULE_ID="system"

    while true; do
        render_persistent_header
        
        printf "  🛠️ ${BOLD}DayPass Maintenance & Recovery${RESET}\n"
        printf "  ─────────────────────────────────────────────────────────── \n"
        printf "  🧹 1) Purge DayPass Installed Packages\n"
        printf "  🗑️ 2) Clean Temporary Cache & Downloads\n"
        printf "  💾 3) Backup System Configuration\n"
        printf "  🚨 4) Factory Reset OpenWrt (Firstboot)\n"
        printf "  🪧 5) SSH Login Banner (install / restore)\n"
        ui_nav_footer
        ui_prompt 5
        choice="$UI_CHOICE"

        case "$choice" in
            1) purge_daypass_packages ;;
            2) clean_daypass_cache ;;
            3) backup_system_config ;;
            4) factory_reset_system ;;
            5)
                if command -v system_banner_manage >/dev/null 2>&1; then
                    system_banner_manage
                else
                    log_warn "Login banner module not loaded!"
                fi
                ;;
            q|Q) daypass_quit ;;
            h|H)
                if command -v show_help >/dev/null 2>&1; then
                    show_help "$HELP_MODULE_ID"
                else
                    log_warn "Help module not loaded!"
                    sleep 1
                fi
                continue
                ;;
            0) break ;;
            *)
                log_warn "Invalid choice!"
                sleep 2
                ;;
        esac
        
        printf "\n  ${GRAY:-}Press [Enter] to continue ... ${RESET:-}"
        read -r _ </dev/tty || daypass_quit
    done
}

# 📄 Source : service_manager.sh

# Service Manager module for managing init.d / procd services in OpenWrt
# Compatible with both OpenWrt 24 (opkg) and OpenWrt 25 (apk) setups

# Checks if a given service init script exists in /etc/init.d/
service_exists()
{
    service_name="$1"
    [ -n "$service_name" ] && [ -x "/etc/init.d/$service_name" ]
}

# Enables a service to automatically start on boot
service_enable()
{
    service_name="$1"
    if service_exists "$service_name"; then
        log_info "Enabling service to start on boot : [$service_name]"
        /etc/init.d/"$service_name" enable >/dev/null 2>&1
        return $?
    else
        log_warn "Cannot enable service [$service_name] : init script not found!"
        return 1
    fi
}

# Starts or restarts a target service via init.d
service_start()
{
    service_name="$1"
    if service_exists "$service_name"; then
        log_info "Starting service : [$service_name] ..."
        /etc/init.d/"$service_name" restart >/dev/null 2>&1 || /etc/init.d/"$service_name" start >/dev/null 2>&1
        
        # Brief pause for procd process spawning
        sleep 1
        
        if service_is_running "$service_name"; then
            log_success "Service [$service_name] is running smoothly!"
            return 0
        else
            log_warn "Service [$service_name] was triggered but is not reporting as active."
            return 1
        fi
    else
        log_error "Failed to start service [$service_name] : Service script missing!"
        return 1
    fi
}

# Stops an active service
service_stop()
{
    service_name="$1"
    if service_exists "$service_name"; then
        log_info "Stopping service : [$service_name] ..."
        /etc/init.d/"$service_name" stop >/dev/null 2>&1
        return 0
    fi
    return 1
}

# Checks if a target service process is currently active/running
service_is_running()
{
    service_name="$1"
    [ -z "$service_name" ] && return 1

    # Check via init.d status if supported by script
    if service_exists "$service_name"; then
        if /etc/init.d/"$service_name" status >/dev/null 2>&1; then
            return 0
        fi
    fi

    # Fallback process detection via pgrep or ps
    if command -v pgrep >/dev/null 2>&1; then
        pgrep -f "$service_name" >/dev/null 2>&1
        return $?
    else
        ps | grep -v grep | grep -q "$service_name"
        return $?
    fi
}

# Post-deployment orchestration for core network services
post_install_services_init()
{
    echo
    log_info "─────────────────────────────────────────────────────────── "
    log_info "Initiating Post-Install Service Operations"
    log_info "─────────────────────────────────────────────────────────── "
    echo

    # 1. Start core proxy profiles if selected
    case "${SELECTED_PROFILE:-passwall2}" in
        passwall2)
            service_enable "passwall2"
            service_start "passwall2"
            ;;
        passwall)
            service_enable "passwall"
            service_start "passwall"
            ;;
    esac

    # 2. Reload DNS resolution stack (dnsmasq) to apply new rules
    if service_exists "dnsmasq"; then
        log_info "Reloading dnsmasq configuration ..."
        /etc/init.d/dnsmasq reload >/dev/null 2>&1 || /etc/init.d/dnsmasq restart >/dev/null 2>&1
        log_success "DNS subsystem reloaded!"
    fi

    # 3. Reload firewall rules
    if service_exists "firewall"; then
        log_info "Reloading system firewall rules ..."
        /etc/init.d/firewall reload >/dev/null 2>&1
        log_success "Firewall rules updated!"
    fi

    echo
    log_success "All post-install service configurations applied!"
}

# Standalone test runner
case "$0" in
    *service_manager.sh)
        post_install_services_init
        ;;
esac

# 📄 Source : install_core.sh

cleanup_and_exit() {
    printf "\r\033[K"
    echo ""
    
    if command -v log_warn >/dev/null 2>&1; then
        log_warn "Installation cancelled by user. Exiting DayPass ..."
    else
        echo "  ⚠️ Installation cancelled by user. Exiting ..."
    fi

    stty echo 2>/dev/null
    rm -rf /tmp/daypass/*.part 2>/dev/null
    
    echo ""
    exit 130
}

stty -echoctl 2>/dev/null || true

trap cleanup_and_exit INT TERM

initialize_installer()
{
    # Clear lock files for both opkg (OpenWrt <=24) and apk (OpenWrt >=25)
    rm -f /var/lock/opkg.lock /lib/apk/db/lock /var/run/apk.lock /run/apk/db.lock 2>/dev/null
    
    # 1. Detect package manager (opkg or apk)
    if command -v detect_package_manager >/dev/null 2>&1; then
        detect_package_manager
    fi

    log_info "Updating package database ..."
    if command -v pkg_update >/dev/null 2>&1; then
        pkg_update >/dev/null 2>&1 || log_warn "Package index update finished with warnings!"
    fi

    # 2. Setup temporary workspace
    TMP_DIR="/tmp/daypass"
    mkdir -p "$TMP_DIR"
    MANIFEST_FILE="$TMP_DIR/manifest.json"

    # 3. Validate base repository URL
    if [ -z "${REPO_URL:-}" ]; then
        log_error "[REPO_URL] environment variable is not defined!"
        exit 1
    fi

    # 🛠️ Dynamic Manifest Selection based on PKG_MANAGER (opkg vs apk)
    MANIFEST_PATH="manifest.json"
    if [ "${PKG_MANAGER:-opkg}" = "apk" ]; then
        MANIFEST_PATH="v25/manifest.json"
    else
        MANIFEST_PATH="v24/manifest.json"
    fi

    MANIFEST_TARGET_URL="${REPO_URL}/${MANIFEST_PATH}"

    log_info "Downloading architecture manifest from : [$MANIFEST_TARGET_URL]"
    
    # 4. Download manifest using resilient fallback mechanisms (curl -> wget -> uclient-fetch)
    DOWNLOAD_SUCCESS=0

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$MANIFEST_TARGET_URL" -o "$MANIFEST_FILE" && DOWNLOAD_SUCCESS=1
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$MANIFEST_FILE" "$MANIFEST_TARGET_URL" && DOWNLOAD_SUCCESS=1
    elif command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -q -O "$MANIFEST_FILE" "$MANIFEST_TARGET_URL" && DOWNLOAD_SUCCESS=1
    else
        log_error "No network download utility found (curl, wget, or uclient-fetch)!"
        exit 1
    fi

    # 5. Verify downloaded file presence and size
    if [ "$DOWNLOAD_SUCCESS" -ne 1 ] || [ ! -s "$MANIFEST_FILE" ]; then
        log_error "Failed to download or received empty manifest from : [$MANIFEST_TARGET_URL]"
        exit 1
    fi

    # Log downloaded file size for telemetry
    MANIFEST_SIZE=$(wc -c < "$MANIFEST_FILE" | awk '{print $1}')
    log_info "Manifest downloaded successfully ($MANIFEST_SIZE bytes)."

    # 6. Detect host system target architecture
    if [ -z "${ARCH:-}" ]; then
        if command -v detect_arch >/dev/null 2>&1; then
            detect_arch
        elif [ -f /etc/openwrt_release ]; then
            . /etc/openwrt_release
            ARCH="${DISTRIB_ARCH:-}"
        fi
        
        [ -z "$ARCH" ] && ARCH="$(uname -m)"
    fi

    if [ -z "$ARCH" ]; then
        log_error "Unable to detect host system architecture!"
        exit 1
    fi

    log_info "Target System Architecture detected : [$ARCH]"

    # 7. Validate JSON syntax integrity
    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq parser utility is not available on host system!"
        exit 1
    fi

    if ! jq empty "$MANIFEST_FILE" >/dev/null 2>&1; then
        log_error "Manifest file is corrupted or invalid JSON!"
        log_warn "JSON Parser Output Error:"
        jq empty "$MANIFEST_FILE" 2>&1 | head -n 3 | sed 's/^/   └─ /'
        exit 1
    fi

    # 8. Extract release metadata for diagnostic logs
    MANIFEST_REL=$(jq -r '.release // "unknown"' "$MANIFEST_FILE" 2>/dev/null)
    MANIFEST_GEN=$(jq -r '.generated_at // "unknown"' "$MANIFEST_FILE" 2>/dev/null)
    log_info "Manifest Metadata -> Release : [$MANIFEST_REL] | Generated At : [$MANIFEST_GEN]"

    # 9. Query architecture support in manifest
    FOUND_ARCH=$(jq -r --arg arch "$ARCH" '.architectures[]? | select(.name == $arch) | .name' "$MANIFEST_FILE" 2>/dev/null | head -n1)

    if [ -z "$FOUND_ARCH" ] || [ "$FOUND_ARCH" = "null" ]; then
        log_error "Architecture [$ARCH] is NOT supported in this build manifest!"
        log_warn "Available architectures in current manifest : "
        
        jq -r '.architectures[].name' "$MANIFEST_FILE" 2>/dev/null | sed 's/^/   • /'
        
        exit 1
    fi

    # 10. Success confirmation & environment export
    log_success "Manifest loaded & verified for architecture : [$ARCH]"

    export ARCH
    export TMP_DIR
    export MANIFEST_FILE
}

# 📄 Source : resource_checker.sh

# Shared global state for resource checks
BEFORE_FREE_RAM=0
BEFORE_FREE_FLASH=0
TOTAL_REQUIRED_BYTES=0
TOTAL_SAVED_BYTES=0

human_readable_bytes()
{
    bytes="${1:-0}"
    if [ "$bytes" -ge 1048576 ]; then
        awk -v b="$bytes" 'BEGIN {printf "%.2f MB", b/1048576}' 2>/dev/null
    elif [ "$bytes" -ge 1024 ]; then
        awk -v b="$bytes" 'BEGIN {printf "%.1f KB", b/1024}' 2>/dev/null
    else
        echo "${bytes} Bytes"
    fi
}

get_free_ram_bytes()
{
    if [ -f /proc/meminfo ]; then
        mem_avail=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null)
        if [ -n "$mem_avail" ] && [ "$mem_avail" -gt 0 ]; then
            echo $((mem_avail * 1024))
        else
            mem_free=$(awk '/MemFree:/ {print $2}' /proc/meminfo 2>/dev/null)
            buffers=$(awk '/Buffers:/ {print $2}' /proc/meminfo 2>/dev/null)
            cached=$(awk '/^Cached:/ {print $2}' /proc/meminfo 2>/dev/null)
            echo $(( (${mem_free:-0} + ${buffers:-0} + ${cached:-0}) * 1024 ))
        fi
    else
        echo 0
    fi
}

get_free_flash_bytes()
{
    target_path="${1:-/overlay}"
    if ! df "$target_path" >/dev/null 2>&1; then
        target_path="/"
    fi
    free_blocks=$(df -k "$target_path" 2>/dev/null | awk 'NR==2 {print $4}')
    echo $(( ${free_blocks:-0} * 1024 ))
}

resource_snapshot()
{
    BEFORE_FREE_RAM=$(get_free_ram_bytes)
    BEFORE_FREE_FLASH=$(get_free_flash_bytes "/overlay")

    log_info "System Memory Snapshot :"
    log_info "  ├─ Available RAM          : [$(human_readable_bytes "$BEFORE_FREE_RAM")]"
    log_info "  └─ Free Flash Space       : [$(human_readable_bytes "$BEFORE_FREE_FLASH")]"
}

# Smart estimation: Calculates REAL net storage expansion
estimate_install_size()
{
    _est_list="${PACKAGES_TO_PROCESS:-${FINAL_PACKAGES:-}}"
    [ -z "$_est_list" ] && return 0
    [ -z "${MANIFEST_FILE:-}" ] || [ ! -f "$MANIFEST_FILE" ] && return 0

    TOTAL_REQUIRED_BYTES=0
    TOTAL_SAVED_BYTES=0
    RECLAIMABLE_BYTES=0

    for pkg in $_est_list; do
        pkg_bytes=$(manifest_lookup "size" "$pkg")
        [ -z "$pkg_bytes" ] || [ "$pkg_bytes" = "null" ] && pkg_bytes=0

        # Payload size counts only packages that are missing or outdated.
        if command -v pkg_payload_required >/dev/null 2>&1 && ! pkg_payload_required "$pkg"; then
            TOTAL_SAVED_BYTES=$((TOTAL_SAVED_BYTES + pkg_bytes))
        else
            TOTAL_REQUIRED_BYTES=$((TOTAL_REQUIRED_BYTES + pkg_bytes))

            inst_ver=$(pkg_get_installed_version "$pkg" 2>/dev/null | awk 'NR==1 { print $1 }')
            if [ -n "$inst_ver" ]; then
                RECLAIMABLE_BYTES=$((RECLAIMABLE_BYTES + pkg_bytes))
            fi
        fi
    done

    # Buffer: Only 10% safety margin for extract/temp operational overhead
    TEMP_OVERHEAD=$((TOTAL_REQUIRED_BYTES / 10))
    PEAK_STORAGE_REQ=$((TOTAL_REQUIRED_BYTES + TEMP_OVERHEAD))

    log_info "Smart Resource Allocation Requirements :"
    log_info "  ├─ Payload Download Req   : [$(human_readable_bytes "$TOTAL_REQUIRED_BYTES")]"
    log_info "  ├─ Reclaimable Storage    : [$(human_readable_bytes "$RECLAIMABLE_BYTES")]"
    log_info "  ├─ Saved Traffic (Skip)   : [$(human_readable_bytes "$TOTAL_SAVED_BYTES")]"
    log_info "  └─ Peak Temp Storage Req  : [$(human_readable_bytes "$PEAK_STORAGE_REQ")]"

    CURRENT_RAM=$(get_free_ram_bytes)
    RAM_MARGIN=$((2 * 1024 * 1024)) # 2MB margin
    MIN_RAM_NEEDED=$((TOTAL_REQUIRED_BYTES + RAM_MARGIN))

    if [ "$CURRENT_RAM" -lt "$MIN_RAM_NEEDED" ]; then
        log_error "Insufficient RAM workspace for package downloads :( "
        log_warn "Available RAM : $(human_readable_bytes "$CURRENT_RAM") | Required : $(human_readable_bytes "$MIN_RAM_NEEDED")"
        return 1
    fi

    CURRENT_FLASH=$(get_free_flash_bytes "/overlay")

    # Soft check: If space is tight, warn but DON'T abort if old packages can be purged first
    if [ "$CURRENT_FLASH" -lt "$PEAK_STORAGE_REQ" ]; then
        if [ "$((CURRENT_FLASH + RECLAIMABLE_BYTES))" -ge "$PEAK_STORAGE_REQ" ]; then
            log_warn "Flash storage is tight, but replacing old packages will yield enough space :("
        else
            log_error "Insufficient Flash storage space on system!"
            log_warn "Available Storage : $(human_readable_bytes "$CURRENT_FLASH") | Peak Required : $(human_readable_bytes "$PEAK_STORAGE_REQ")"
            return 1
        fi
    fi

    log_success "System resource check PASSED!"
    return 0
}

resource_compare()
{
    AFTER_FREE_RAM=$(get_free_ram_bytes)
    AFTER_FREE_FLASH=$(get_free_flash_bytes "/overlay")

    [ "$BEFORE_FREE_RAM" -gt "$AFTER_FREE_RAM" ] && USED_RAM=$((BEFORE_FREE_RAM - AFTER_FREE_RAM)) || USED_RAM=0
    [ "$BEFORE_FREE_FLASH" -gt "$AFTER_FREE_FLASH" ] && USED_FLASH=$((BEFORE_FREE_FLASH - AFTER_FREE_FLASH)) || USED_FLASH=0

    echo
    echo "  🤌🏻 DayPass Deployment Efficiency Summary"
    echo "  ────────────────────────────────────────────────────────── "
    echo "    ├─ Total Downloaded Payload     : $(human_readable_bytes "$TOTAL_REQUIRED_BYTES")"
    echo "    ├─ Total Network Traffic Saved  : $(human_readable_bytes "$TOTAL_SAVED_BYTES") "
    echo "    ├─ Net Storage Consumed         : $(human_readable_bytes "$USED_FLASH")"
    echo "    └─ Free Storage Remaining       : $(human_readable_bytes "$AFTER_FREE_FLASH")"
    echo "  ────────────────────────────────────────────────────────── "
    echo
}

get_total_ram_bytes()
{
    if [ -f /proc/meminfo ]; then
        mem_total=$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null)
        echo $(( ${mem_total:-0} * 1024 ))
    else
        echo 0
    fi
}

get_total_flash_bytes()
{
    target_path="${1:-/overlay}"
    if ! df "$target_path" >/dev/null 2>&1; then
        target_path="/"
    fi
    total_blocks=$(df -k "$target_path" 2>/dev/null | awk 'NR==2 {print $2}')
    echo $(( ${total_blocks:-0} * 1024 ))
}

show_system_resources_menu()
{
    render_persistent_header

    # Fetch Architecture
    [ -z "$ARCH" ] && command -v detect_arch >/dev/null 2>&1 && detect_arch

    # Fetch OpenWrt Release & Date Details
    OW_VER="Unknown"
    OW_DATE=""
    if [ -f /etc/openwrt_release ]; then
        . /etc/openwrt_release
        OW_VER="${DISTRIB_RELEASE:-Unknown}"
        
        if [ -n "$DISTRIB_REVISION" ]; then
            OW_DATE=" ($DISTRIB_REVISION)"
        fi
    fi

    # Fetch Memory Data
    tot_ram_b=$(get_total_ram_bytes)
    free_ram_b=$(get_free_ram_bytes)
    used_ram_b=$((tot_ram_b - free_ram_b))

    # Fetch Storage Data
    tot_flash_b=$(get_total_flash_bytes "/overlay")
    free_flash_b=$(get_free_flash_bytes "/overlay")
    used_flash_b=$((tot_flash_b - free_flash_b))

    echo "  🖥️ System Hardware & Resource Status"
    echo "  ──────────────────────────────────────────────────────────"
    printf "  🩻 Architecture      : ${CYAN}%s${RESET}\n" "${ARCH:-N/A}"
    printf "  💡 OpenWrt System    : ${CYAN}%s [%s]${RESET}\n" "$OW_VER" "${PKG_MANAGER:-opkg}"
    echo "  ──────────────────────────────────────────────────────────"
    printf "  🧠 Total RAM         : %s\n" "$(human_readable_bytes "$tot_ram_b")"
    printf "     🟠 Used RAM       : ${YELLOW}%s${RESET}\n" "$(human_readable_bytes "$used_ram_b")"
    printf "     🟢 Free RAM       : ${GREEN}%s${RESET}\n" "$(human_readable_bytes "$free_ram_b")"
    echo "  ──────────────────────────────────────────────────────────"
    printf "  💾 Total Storage     : %s\n" "$(human_readable_bytes "$tot_flash_b")"
    printf "     🟠 Used Storage   : ${YELLOW}%s${RESET}\n" "$(human_readable_bytes "$used_flash_b")"
    printf "     🟢 Free Storage   : ${GREEN}%s${RESET}\n" "$(human_readable_bytes "$free_flash_b")"
    echo "  ──────────────────────────────────────────────────────────"
    echo

    if command -v ui_nav_footer >/dev/null 2>&1; then
        ui_nav_footer
    fi
    printf "  ⁉️ Select option : "
    read -r res_choice </dev/tty || daypass_quit
    case "$res_choice" in
        q|Q) daypass_quit ;;
        h|H)
            if command -v show_help >/dev/null 2>&1; then
                show_help "system"
                show_system_resources_menu
            else
                log_warn "Help module not loaded!"
                sleep 1
            fi
            ;;
    esac
}

# 📄 Source : resolver.sh

# Profile-based package resolver and installer for opkg (OpenWrt 24.x) and apk (OpenWrt 25.x).
# Profile definitions: config/package_profiles.json
#
# Public functions (all return 0 on success, 1 on failure):
#   list_package_profiles      Compact CLI list of profile ids (menu uses profile_status_dashboard)
#   resolve_profile <name>     Build PROFILE_PLAN / PROFILE_PACKAGES without installing
#   install_profile <name>     Resolve and install a profile (DAYPASS_DRY_RUN=1 only prints the plan)
#   resolve_packages           Resolve the default profile into FINAL_PACKAGES (installer UI flow)

PROFILES_FILE="${PROFILES_FILE:-}"
PROFILE_PLAN=""
PROFILE_PACKAGES=""

_pr_log()
{
    _pr_level="$1"
    shift
    _pr_msg="$*"
    _pr_logfile="${DAYPASS_RESOLVE_LOG:-/tmp/daypass_resolve.log}"

    if [ "${DAYPASS_RESOLVE_QUIET:-0}" = "1" ]; then
        printf '[%s] %s\n' "$_pr_level" "$_pr_msg" >> "$_pr_logfile" 2>/dev/null
        case "$_pr_level" in
            ERROR) printf '  [%s] %s\n' "$_pr_level" "$_pr_msg" >&2 ;;
        esac
        return 0
    fi

    case "$_pr_level" in
        WARN|ERROR) printf '  [%s] %s\n' "$_pr_level" "$_pr_msg" >&2 ;;
        *)          printf '  [%s] %s\n' "$_pr_level" "$_pr_msg" ;;
    esac
}

_pr_fetch()
{
    _pr_url="$1"
    _pr_out="$2"

    rm -f "$_pr_out"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 15 --max-time 120 --retry 3 --retry-delay 2 "$_pr_url" -o "$_pr_out" 2>/dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=20 --tries=3 -O "$_pr_out" "$_pr_url" 2>/dev/null
    elif command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -q --timeout=20 -O "$_pr_out" "$_pr_url" 2>/dev/null
    else
        _pr_log ERROR "No download utility found (curl, wget or uclient-fetch)!"
        return 1
    fi

    [ $? -eq 0 ] && [ -s "$_pr_out" ] && return 0
    rm -f "$_pr_out"
    return 1
}

_pr_valid_profiles_file()
{
    [ -n "$1" ] && [ -s "$1" ] && jq -e '.profiles | type == "object"' "$1" >/dev/null 2>&1
}

# Locate profile definitions: explicit file, embedded copy (install.sh), CDN, local checkout
load_package_profiles()
{
    if ! command -v jq >/dev/null 2>&1; then
        _pr_log ERROR "jq is required to read package profiles!"
        return 1
    fi

    if _pr_valid_profiles_file "${DAYPASS_PROFILES_FILE:-}"; then
        PROFILES_FILE="$DAYPASS_PROFILES_FILE"
        export PROFILES_FILE
        return 0
    fi

    _pr_valid_profiles_file "$PROFILES_FILE" && return 0

    _pr_cache_dir="${TMP_DIR:-/tmp/daypass}"
    _pr_cache="$_pr_cache_dir/package_profiles.json"
    mkdir -p "$_pr_cache_dir" 2>/dev/null

    if command -v daypass_embedded_profiles >/dev/null 2>&1; then
        daypass_embedded_profiles > "$_pr_cache.part" 2>/dev/null
        if _pr_valid_profiles_file "$_pr_cache.part"; then
            mv "$_pr_cache.part" "$_pr_cache"
            PROFILES_FILE="$_pr_cache"
            export PROFILES_FILE
            return 0
        fi
        rm -f "$_pr_cache.part"
    fi

    if [ -n "${REPO_URL:-}" ] && _pr_fetch "${REPO_URL}/config/package_profiles.json" "$_pr_cache.part"; then
        if _pr_valid_profiles_file "$_pr_cache.part"; then
            mv "$_pr_cache.part" "$_pr_cache"
            PROFILES_FILE="$_pr_cache"
            export PROFILES_FILE
            return 0
        fi
        rm -f "$_pr_cache.part"
    fi

    for _pr_candidate in "config/package_profiles.json" "${DAYPASS_DIR:-/etc/daypass}/config/package_profiles.json"; do
        if _pr_valid_profiles_file "$_pr_candidate"; then
            PROFILES_FILE="$_pr_candidate"
            export PROFILES_FILE
            return 0
        fi
    done

    _pr_log ERROR "Package profile definitions (package_profiles.json) could not be loaded!"
    return 1
}

# Sets PKG_MANAGER, OPENWRT_MAJOR, PROFILE_RELEASE and _PR_ARCH
_pr_detect_environment()
{
    if [ -z "${PKG_MANAGER:-}" ]; then
        if command -v apk >/dev/null 2>&1; then
            PKG_MANAGER="apk"
        elif command -v opkg >/dev/null 2>&1; then
            PKG_MANAGER="opkg"
        fi
    fi

    if [ -z "${OPENWRT_MAJOR:-}" ] && [ -f /etc/openwrt_release ]; then
        OPENWRT_MAJOR="$(
            . /etc/openwrt_release 2>/dev/null
            echo "$DISTRIB_RELEASE" | cut -d'.' -f1
        )"
    fi

    case "${OPENWRT_MAJOR:-}" in
        ''|*[!0-9]*)
            case "${PKG_MANAGER:-}" in
                apk)  OPENWRT_MAJOR="25" ;;
                opkg) OPENWRT_MAJOR="24" ;;
                *)
                    _pr_log ERROR "Unable to detect the OpenWrt release or package manager (opkg/apk)!"
                    return 1
                    ;;
            esac
            ;;
    esac

    PROFILE_RELEASE="$OPENWRT_MAJOR"
    if ! jq -e --arg r "$PROFILE_RELEASE" '.releases[$r]' "$PROFILES_FILE" >/dev/null 2>&1; then
        case "${PKG_MANAGER:-}" in
            apk)  PROFILE_RELEASE="25" ;;
            opkg) PROFILE_RELEASE="24" ;;
        esac
        if ! jq -e --arg r "$PROFILE_RELEASE" '.releases[$r]' "$PROFILES_FILE" >/dev/null 2>&1; then
            _pr_log ERROR "OpenWrt release [$OPENWRT_MAJOR] has no package profile definition!"
            return 1
        fi
        _pr_log WARN "OpenWrt [$OPENWRT_MAJOR] is not listed; using the [$PROFILE_RELEASE.x] package set for [$PKG_MANAGER]."
    fi

    _pr_expected_pm="$(jq -r --arg r "$PROFILE_RELEASE" '.releases[$r].package_manager // empty' "$PROFILES_FILE" 2>/dev/null)"
    if [ -z "${PKG_MANAGER:-}" ]; then
        PKG_MANAGER="$_pr_expected_pm"
    elif [ -n "$_pr_expected_pm" ] && [ "$_pr_expected_pm" != "$PKG_MANAGER" ]; then
        _pr_log WARN "OpenWrt [$PROFILE_RELEASE.x] normally uses [$_pr_expected_pm], but [$PKG_MANAGER] was detected."
    fi

    _PR_ARCH="${ARCH:-}"
    if [ -z "$_PR_ARCH" ] && [ -f /etc/openwrt_release ]; then
        _PR_ARCH="$(
            . /etc/openwrt_release 2>/dev/null
            echo "$DISTRIB_ARCH"
        )"
    fi

    export PKG_MANAGER OPENWRT_MAJOR PROFILE_RELEASE
    return 0
}

# Sets _PR_MANIFEST to a readable manifest; with "download" it may fetch one from REPO_URL
_pr_locate_manifest()
{
    _PR_MANIFEST=""
    for _pr_candidate in "${MANIFEST_FILE:-}" "${TMP_DIR:-/tmp/daypass}/manifest.json" "/tmp/manifest.json" "manifest.json"; do
        if [ -n "$_pr_candidate" ] && [ -s "$_pr_candidate" ] && jq -e '.architectures' "$_pr_candidate" >/dev/null 2>&1; then
            _PR_MANIFEST="$_pr_candidate"
            return 0
        fi
    done

    [ "${1:-}" = "download" ] || return 1
    [ -n "${REPO_URL:-}" ] || return 1

    _pr_manifest_path="$(jq -r --arg r "$PROFILE_RELEASE" '.releases[$r].manifest_path // empty' "$PROFILES_FILE" 2>/dev/null)"
    [ -n "$_pr_manifest_path" ] || return 1

    mkdir -p "${TMP_DIR:-/tmp/daypass}" 2>/dev/null
    _pr_target="${TMP_DIR:-/tmp/daypass}/manifest.json"
    _pr_log INFO "Downloading package manifest : [${REPO_URL}/${_pr_manifest_path}]"
    if _pr_fetch "${REPO_URL}/${_pr_manifest_path}" "$_pr_target" && jq -e '.architectures' "$_pr_target" >/dev/null 2>&1; then
        _PR_MANIFEST="$_pr_target"
        return 0
    fi

    rm -f "$_pr_target"
    _pr_log WARN "Package manifest is unavailable; manifest-only packages cannot be installed."
    return 1
}

# Prints "file|sha256" for an exact manifest package match on the current architecture
_pr_manifest_entry()
{
    [ -n "${_PR_MANIFEST:-}" ] && [ -n "${_PR_ARCH:-}" ] || return 1

    _pr_entry="$(jq -r --arg arch "$_PR_ARCH" --arg pkg "$1" '
        first(.architectures[]? | select(.name == $arch) | .feeds[]?[]? | select(.package == $pkg)
              | "\(.file // "")|\(.sha256 // .SHA256 // "")") // empty
    ' "$_PR_MANIFEST" 2>/dev/null)"

    case "$_pr_entry" in
        ''|'|'*) return 1 ;;
    esac
    echo "$_pr_entry"
}

# JSON object with the current values of every variable referenced by the profiles
_pr_vars_json()
{
    _pr_names="$(jq -r '
        [ .profiles[]?.steps[]?
          | (.var // empty),
            ((.vars // {}) | keys[]),
            ((.skip_values // {}) | keys[]),
            ((.without_manifest // {}) | keys[]) ]
        | unique[]
    ' "$PROFILES_FILE" 2>/dev/null)"

    _pr_json='{}'
    for _pr_name in $_pr_names; do
        case "$_pr_name" in
            ''|[0-9]*|*[!A-Za-z0-9_]*) continue ;;
        esac
        eval "_pr_value=\${$_pr_name:-}"
        _pr_value="$(printf '%s' "$_pr_value" | tr ',\t\n' '   ')"
        _pr_json="$(printf '%s' "$_pr_json" | jq -c --arg k "$_pr_name" --arg v "$_pr_value" '. + {($k): $v}')"
    done
    printf '%s' "$_pr_json"
}

# Output records (one per line):
#   E|message
#   W|message
#   P|name|source|optional|alternatives|profile|step|check|without_manifest_ok|note
_PR_PLAN_JQ='
def uniq: reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);
def words: (. // "") | tostring | split(" ") | map(select(length > 0));
def val($v): ($vars[$v] // "") | words | join(" ");
def clean: tostring | split("|") | join("/");
def norm($src):
    (if type == "string" then {name: .} else . end)
    | .source = (.source // $src)
    | .optional = (.optional // false)
    | .kind = "pkg";
def in_release: (.releases // null) as $r | ($r == null) or any($r[]; tostring == $rel);
def excluded($pats):
    . as $n | any($pats[]; . as $p | if ($p | endswith("*")) then ($n | startswith($p[:-1])) else $p == $n end);

def order($p; $seen):
    if any($seen[]; . == $p) then []
    else [ (.profiles[$p].requires // [])[] as $r | order($r; $seen + [$p])[] ] + [$p]
    end;

def step_entries($src):
    if .type == "packages" then
        (.packages // [])[] | norm($src)
    elif .type == "choice" then
        val(.var) as $v
        | (if $v == "" then (.default // "") else $v end) as $c
        | ((.choices // {})[$c]
           // (if .fallback then (.choices // {})[.fallback] else null end)
           // [])[]
        | norm($src)
    elif .type == "components" then
        (.components // {}) as $comp
        | (val(.var) | words) as $sel
        | (if ($sel | length) == 0 then (.default // ($comp | keys_unsorted))
           elif any($sel[]; . == "all") then ($comp | keys_unsorted)
           else $sel end) as $want
        | .var as $var
        | ( ($want[] | select(. as $w | $comp | has($w) | not)
             | {kind: "warn", msg: "Unknown component [\(.)] in \($var); skipped."}),
            (($comp | keys_unsorted)[] as $k
             | select(any($want[]; . == $k))
             | $comp[$k][] | norm($src)) )
    elif .type == "list_var" then
        (.exclude // []) as $ex
        | val(.var) | words[]
        | select(excluded($ex) | not)
        | norm($src)
    elif .type == "template" then
        . as $st
        | ((.vars // {}) | with_entries(.value = (val(.key) as $x | if $x == "" then .value else $x end))) as $tv
        | if any(($st.skip_values // {}) | to_entries[]; .key as $k | any(.value[]; . == $tv[$k])) then empty
          else
            (reduce ($tv | to_entries[]) as $e ($st.pattern; split("{" + $e.key + "}") | join($e.value))) as $name
            | {kind: "pkg", name: $name, source: ($st.source // $src), optional: false,
               check: (if $st.require_in_manifest then "manifest" else "" end),
               without_manifest_ok: (($st.without_manifest // {}) | to_entries
                                     | all(.[]; .key as $k | any(.value[]; . == $tv[$k])))}
          end
    else
        {kind: "warn", msg: "Unknown step type [\(.type)] in step [\(.id // "?")]; skipped."}
    end;

def visit($all; $e):
    if any(.out[]; .name == $e.name) or any(.stack[]; . == $e.name) then .
    else
        .stack += [$e.name]
        | reduce (($e.depends // [])[]) as $d (.;
            visit($all; (first($all[] | select(.name == $d))
                         // ($e | {kind, source, optional, profile, step, name: $d}))))
        | .stack -= [$e.name]
        | .out += [$e]
    end;

. as $root
| (order($profile; []) | uniq) as $plist
| ($plist | map(select($root.profiles[.] == null))) as $missing
| if ($missing | length) > 0 then
    $missing[] | "E|Unknown package profile [\(.)]"
  else
    [ $plist[] as $p
      | $root.profiles[$p] as $prof
      | ($prof.default_source // "auto") as $src
      | ($prof.steps // [])[] as $st
      | $st | step_entries($st.source // $src)
      | if .kind == "pkg" then select(in_release) | .profile = $p | .step = ($st.id // "") else . end
    ] as $records
    | ($records | map(select(.kind == "warn"))[] | "W|\(.msg | clean)"),
      ( ($records | map(select(.kind == "pkg"))) as $pkgs
        | (reduce $pkgs[] as $e ({out: [], stack: []}; visit($pkgs; $e))).out[]
        | "P|\(.name | clean)|\(.source)|\(if .optional then 1 else 0 end)|\((.alternatives // []) | join(" ") | clean)|\(.profile)|\(.step)|\(.check // "")|\(if .without_manifest_ok then 1 else 0 end)|\((.note // "") | clean)" )
  end
'

list_package_profiles()
{
    load_package_profiles || return 1
    jq -r '(.default_profile // "") as $d | .profiles | to_entries[]
           | "  \(.key)\t\(.value.title // "")\(if .key == $d then " (default)" else "" end)"' "$PROFILES_FILE"
}

_pr_default_profile()
{
    jq -r '.default_profile // empty' "$PROFILES_FILE" 2>/dev/null
}

resolve_profile()
{
    _rp_profile="${1:-}"
    PROFILE_PLAN=""
    PROFILE_PACKAGES=""

    load_package_profiles || return 1
    [ -z "$_rp_profile" ] && _rp_profile="$(_pr_default_profile)"

    case "$_rp_profile" in
        ''|*[!A-Za-z0-9_-]*)
            _pr_log ERROR "Invalid package profile name : [$_rp_profile]"
            return 1
            ;;
    esac

    _pr_detect_environment || return 1
    _pr_locate_manifest

    _pr_log INFO "Resolving package profile [$_rp_profile] for OpenWrt [$PROFILE_RELEASE.x] (${PKG_MANAGER:-unknown}, ${_PR_ARCH:-unknown arch}) ..."

    _rp_vars="$(_pr_vars_json)"
    [ -z "$_rp_vars" ] && _rp_vars='{}'
    _rp_records="$(jq -r --arg profile "$_rp_profile" --arg rel "$PROFILE_RELEASE" --argjson vars "$_rp_vars" \
        "$_PR_PLAN_JQ" "$PROFILES_FILE" 2>&1)"
    if [ $? -ne 0 ]; then
        _pr_log ERROR "Failed to evaluate package profile [$_rp_profile] : $_rp_records"
        return 1
    fi

    while IFS='|' read -r _rp_kind _rp_name _rp_source _rp_optional _rp_alts _rp_prof _rp_step _rp_check _rp_nomanifest _rp_note; do
        case "$_rp_kind" in
            E)
                _pr_log ERROR "$_rp_name"
                PROFILE_PLAN=""
                PROFILE_PACKAGES=""
                return 1
                ;;
            W)
                _pr_log WARN "$_rp_name"
                continue
                ;;
            P) ;;
            *) continue ;;
        esac

        if [ "$_rp_check" = "manifest" ]; then
            if [ -n "$_PR_MANIFEST" ]; then
                if ! _pr_manifest_entry "$_rp_name" >/dev/null; then
                    _pr_log WARN "Package [$_rp_name] is not available in the manifest. Skipped."
                    continue
                fi
            elif [ "$_rp_nomanifest" != "1" ]; then
                _pr_log WARN "Package [$_rp_name] needs the manifest to confirm availability. Skipped."
                continue
            fi
        fi

        PROFILE_PLAN="${PROFILE_PLAN}${_rp_name}|${_rp_source}|${_rp_optional}|${_rp_alts}|${_rp_prof}|${_rp_step}|${_rp_note}
"
        PROFILE_PACKAGES="${PROFILE_PACKAGES:+$PROFILE_PACKAGES }$_rp_name"

        _rp_flags="$_rp_source"
        [ "$_rp_optional" = "1" ] && _rp_flags="$_rp_flags, optional"
        [ -n "$_rp_alts" ] && _rp_flags="$_rp_flags, alt: $_rp_alts"
        _pr_log INFO "  ├─ Resolved target : [$_rp_name] ($_rp_flags)"
    done <<EOF
$_rp_records
EOF

    if [ -z "$PROFILE_PACKAGES" ]; then
        _pr_log ERROR "Package profile [$_rp_profile] resolved to an empty package list!"
        return 1
    fi

    _pr_log SUCCESS "Profile [$_rp_profile] resolved : [$PROFILE_PACKAGES]"
    export PROFILE_PLAN PROFILE_PACKAGES
    return 0
}

_pr_is_installed()
{
    case "$PKG_MANAGER" in
        apk)  apk info -e "$1" >/dev/null 2>&1 ;;
        opkg) opkg status "$1" 2>/dev/null | grep -q "Status: .* installed" ;;
        *)    return 1 ;;
    esac
}

_pr_refresh_index()
{
    [ "${_PR_INDEX_REFRESHED:-0}" = "1" ] && return 1
    _PR_INDEX_REFRESHED=1

    _pr_log INFO "Refreshing package indexes with [$PKG_MANAGER] ..."
    case "$PKG_MANAGER" in
        apk)  apk update >/dev/null 2>&1 </dev/null ;;
        opkg) opkg update >/dev/null 2>&1 </dev/null ;;
    esac
    return 0
}

# $1 = package name or local file, $2 = "file" for verified local packages
_pr_pm_install()
{
    _pr_pm_log="${TMP_DIR:-/tmp/daypass}/pkg_install.log"

    case "$PKG_MANAGER" in
        apk)
            if [ "${2:-}" = "file" ]; then
                apk add --no-progress --allow-untrusted "$1" >"$_pr_pm_log" 2>&1 </dev/null
            else
                apk add --no-progress "$1" >"$_pr_pm_log" 2>&1 </dev/null
            fi
            ;;
        opkg)
            if [ "${2:-}" = "file" ]; then
                opkg install --force-checksum "$1" >"$_pr_pm_log" 2>&1 </dev/null
            else
                opkg install "$1" >"$_pr_pm_log" 2>&1 </dev/null
            fi
            ;;
        *)
            _pr_log ERROR "No supported package manager (opkg/apk) found!"
            return 1
            ;;
    esac
}

_pr_show_pm_log()
{
    [ -s "${TMP_DIR:-/tmp/daypass}/pkg_install.log" ] || return 0
    tail -n 5 "${TMP_DIR:-/tmp/daypass}/pkg_install.log" | sed 's/^/        /' >&2
}

_pr_install_from_feed()
{
    if _pr_pm_install "$1"; then
        return 0
    fi

    if _pr_refresh_index && _pr_pm_install "$1"; then
        return 0
    fi

    _pr_show_pm_log
    return 1
}

_pr_install_from_manifest()
{
    _pm_entry="$(_pr_manifest_entry "$1")" || return 1
    _pm_file="${_pm_entry%%|*}"
    _pm_sha="${_pm_entry#*|}"

    _pm_base="$(jq -r '.download_base // empty' "$_PR_MANIFEST" 2>/dev/null)"
    [ -z "$_pm_base" ] && _pm_base="${REPO_URL:-}"
    if [ -z "$_pm_base" ]; then
        _pr_log ERROR "No download base URL for manifest package [$1]!"
        return 1
    fi

    mkdir -p "${TMP_DIR:-/tmp/daypass}" 2>/dev/null
    _pm_target="${TMP_DIR:-/tmp/daypass}/$(basename "$_pm_file")"

    if [ -s "$_pm_target" ] && [ -n "$_pm_sha" ] && echo "$_pm_sha  $_pm_target" | sha256sum -c - >/dev/null 2>&1; then
        :
    elif ! _pr_fetch "${_pm_base}/${_pm_file}" "$_pm_target.part"; then
        _pr_log ERROR "Download failed : [${_pm_base}/${_pm_file}]"
        return 1
    elif [ -n "$_pm_sha" ] && ! echo "$_pm_sha  $_pm_target.part" | sha256sum -c - >/dev/null 2>&1; then
        rm -f "$_pm_target.part"
        _pr_log ERROR "Checksum mismatch for [$1]!"
        return 1
    else
        mv "$_pm_target.part" "$_pm_target"
    fi

    if _pr_pm_install "$_pm_target" file; then
        rm -f "$_pm_target"
        return 0
    fi

    if _pr_refresh_index && _pr_pm_install "$_pm_target" file; then
        rm -f "$_pm_target"
        return 0
    fi

    _pr_show_pm_log
    rm -f "$_pm_target"
    return 1
}

_pr_install_candidate()
{
    case "$2" in
        manifest)
            if ! _pr_manifest_entry "$1" >/dev/null; then
                _pr_log WARN "Package [$1] is not listed in the manifest for [${_PR_ARCH:-unknown}]."
                return 1
            fi
            _pr_install_from_manifest "$1"
            ;;
        feed)
            _pr_install_from_feed "$1"
            ;;
        *)
            if _pr_manifest_entry "$1" >/dev/null; then
                _pr_install_from_manifest "$1" && return 0
                _pr_log WARN "Manifest install failed for [$1]; falling back to OpenWrt feeds ..."
            fi
            _pr_install_from_feed "$1"
                    ;;
            esac
}

_pr_rollback()
{
    [ -n "$1" ] || return 0

    _rb_reversed=""
    for _rb_pkg in $1; do
        _rb_reversed="$_rb_pkg${_rb_reversed:+ $_rb_reversed}"
    done

    _pr_log WARN "Rolling back packages installed in this session : [$_rb_reversed]"
    for _rb_pkg in $_rb_reversed; do
        case "$PKG_MANAGER" in
            apk)  apk del "$_rb_pkg" >/dev/null 2>&1 </dev/null ;;
            opkg) opkg remove "$_rb_pkg" >/dev/null 2>&1 </dev/null ;;
        esac
        if [ $? -eq 0 ]; then
            _pr_log INFO "Rollback : removed [$_rb_pkg]"
        else
            _pr_log WARN "Rollback : could not remove [$_rb_pkg]"
        fi
    done
}

install_profile()
{
    _ip_profile="${1:-}"

    resolve_profile "$_ip_profile" || return 1
    [ -z "$_ip_profile" ] && _ip_profile="$(_pr_default_profile)"

    if [ "${DAYPASS_DRY_RUN:-0}" = "1" ]; then
        _pr_log INFO "Dry run : no packages were installed."
        return 0
    fi

    case "${PKG_MANAGER:-}" in
        apk|opkg) ;;
        *)
            _pr_log ERROR "No supported package manager (opkg/apk) found!"
            return 1
            ;;
    esac

    if [ -z "$_PR_MANIFEST" ] && printf '%s' "$PROFILE_PLAN" | grep -qE '^[^|]*\|(manifest|auto)\|'; then
        _pr_locate_manifest download
    fi

    mkdir -p "${TMP_DIR:-/tmp/daypass}" 2>/dev/null
    _PR_INDEX_REFRESHED=0
    _ip_session=""
    _ip_done=0
    _ip_skipped=0
    _ip_failed_optional=0
    _ip_ui="${DAYPASS_INSTALL_UI:-0}"
    _ip_total=0
    _ip_idx=0
    for _ip_row in $PROFILE_PACKAGES; do
        _ip_total=$((_ip_total + 1))
    done

    while IFS='|' read -r _ip_name _ip_source _ip_optional _ip_alts _ip_prof _ip_step _ip_note; do
        [ -z "$_ip_name" ] && continue
        _ip_idx=$((_ip_idx + 1))
        _ip_label="$_ip_name"
        command -v pkg_display_title >/dev/null 2>&1 && _ip_label="$(pkg_display_title "$_ip_name")"

        if [ "$_ip_ui" = "1" ] && command -v show_ascii_progress >/dev/null 2>&1 && [ "$_ip_total" -gt 0 ]; then
            show_ascii_progress "Installing" "$_ip_idx" "$_ip_total"
            printf '\n'
        fi

        _ip_present=""
        for _ip_candidate in $_ip_name $_ip_alts; do
            if _pr_is_installed "$_ip_candidate"; then
                _ip_present="$_ip_candidate"
                break
            fi
        done

        if [ -n "$_ip_present" ]; then
            if [ "$_ip_ui" = "1" ]; then
                log_info "[$_ip_idx/$_ip_total] $_ip_label — already on this router."
            else
                _pr_log INFO "[$_ip_present] is already installed. Skipped."
            fi
            _ip_skipped=$((_ip_skipped + 1))
            continue
        fi

        [ -n "$_ip_note" ] && [ "$_ip_ui" != "1" ] && _pr_log INFO "Note for [$_ip_name] : $_ip_note"
        if [ "$_ip_ui" = "1" ]; then
            log_info "[$_ip_idx/$_ip_total] Installing $_ip_label ..."
        else
            _pr_log INFO "Installing [$_ip_name] ($_ip_source) ..."
        fi

        _ip_installed=""
        for _ip_candidate in $_ip_name $_ip_alts; do
            [ "$_ip_candidate" != "$_ip_name" ] && [ "$_ip_ui" != "1" ] && \
                _pr_log INFO "Trying alternative [$_ip_candidate] ..."
            if _pr_install_candidate "$_ip_candidate" "$_ip_source"; then
                _ip_installed="$_ip_candidate"
                break
            fi
        done

        if [ -n "$_ip_installed" ]; then
            _ip_session="${_ip_session:+$_ip_session }$_ip_installed"
            _ip_done=$((_ip_done + 1))
            if [ "$_ip_ui" = "1" ]; then
                log_success "Installed $_ip_label"
            else
                _pr_log SUCCESS "Installed [$_ip_installed]"
            fi
            continue
        fi

        if [ "$_ip_optional" = "1" ]; then
            _ip_failed_optional=$((_ip_failed_optional + 1))
            if [ "$_ip_ui" = "1" ]; then
                log_warn "Optional: $_ip_label could not be installed — continuing."
            else
                _pr_log WARN "Optional package [$_ip_name] could not be installed. Continuing ..."
            fi
            continue
        fi

        _pr_log ERROR "Required package [$_ip_name] (profile [$_ip_prof], step [$_ip_step]) could not be installed!"
        _pr_rollback "$_ip_session"
        _pr_log ERROR "Profile [$_ip_profile] installation failed."
        return 1
    done <<EOF
$PROFILE_PLAN
EOF

    if [ -n "$_ip_session" ] && [ -n "${INSTALL_LOG:-}" ]; then
        mkdir -p "$(dirname "$INSTALL_LOG")" 2>/dev/null
        for _ip_pkg in $_ip_session; do
            echo "$_ip_pkg" >> "$INSTALL_LOG"
        done
        sort -u "$INSTALL_LOG" -o "$INSTALL_LOG" 2>/dev/null
    fi

    # Record the whole resolved suite (including already-present packages)
    # so purge can remove the module as a unit.
    if command -v mf_record_install >/dev/null 2>&1; then
        _ip_tracked=""
        for _ip_name in $PROFILE_PACKAGES; do
            if command -v _pr_is_installed >/dev/null 2>&1 && _pr_is_installed "$_ip_name"; then
                _ip_tracked="${_ip_tracked:+$_ip_tracked }$_ip_name"
            fi
        done
        [ -z "$_ip_tracked" ] && _ip_tracked="$_ip_session"
        [ -n "$_ip_tracked" ] && mf_record_install "$_ip_profile" "$_ip_tracked"
    fi

    if [ "$_ip_ui" = "1" ]; then
        echo
        log_success "Profile finished : $_ip_done installed, $_ip_skipped already present, $_ip_failed_optional optional skipped."
    else
        _pr_log SUCCESS "Profile [$_ip_profile] finished : $_ip_done installed, $_ip_skipped already present, $_ip_failed_optional optional skipped."
    fi
    return 0
}

# Installer UI flow: resolves the default profile from the SELECTED_* state into FINAL_PACKAGES
resolve_packages()
{
    FINAL_PACKAGES=""

    if ! resolve_profile ""; then
        _pr_log ERROR "Package resolution finished with an empty target package list :("
        export FINAL_PACKAGES
        return 1
    fi

    FINAL_PACKAGES="$PROFILE_PACKAGES"
    _pr_log INFO "Final deployment target list : [$FINAL_PACKAGES]"
    export FINAL_PACKAGES
    return 0
}

# Standalone execution handler
case "$0" in
    *package_resolver.sh|*/resolver.sh|resolver.sh)
        if [ -z "${DAYPASS_PROFILES_FILE:-}" ]; then
            _pr_self_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
            [ -n "$_pr_self_dir" ] && [ -f "$_pr_self_dir/../../config/package_profiles.json" ] && \
                DAYPASS_PROFILES_FILE="$_pr_self_dir/../../config/package_profiles.json"
        fi

        case "${1:-resolve}" in
            list)    list_package_profiles ;;
            install) install_profile "${2:-}" ;;
            resolve)
                if [ -n "${2:-}" ]; then
                    resolve_profile "$2"
                else
                    resolve_packages
                fi
                ;;
            *)
                echo "Usage : $0 [list | resolve [profile] | install <profile>]" >&2
                exit 1
                ;;
        esac
        exit $?
        ;;
esac


# 📄 Source : package_catalog.sh
# ============================================================
# DayPass - Friendly package titles for the Profile Install UI
# Data: config/package_catalog.json (embedded as daypass_embedded_catalog)
# ============================================================

PACKAGE_CATALOG_FILE="${PACKAGE_CATALOG_FILE:-}"
DAYPASS_RESOLVE_LOG="${DAYPASS_RESOLVE_LOG:-/tmp/daypass_resolve.log}"

load_package_catalog() {
    if [ -n "$PACKAGE_CATALOG_FILE" ] && [ -s "$PACKAGE_CATALOG_FILE" ]; then
        return 0
    fi

    _pc_dir="${TMP_DIR:-/tmp/daypass}"
    _pc_cache="$_pc_dir/package_catalog.json"
    mkdir -p "$_pc_dir" 2>/dev/null

    if [ -s "${DAYPASS_DIR:-/etc/daypass}/package_catalog.json" ]; then
        PACKAGE_CATALOG_FILE="${DAYPASS_DIR}/package_catalog.json"
        export PACKAGE_CATALOG_FILE
        return 0
    fi

    if command -v daypass_embedded_catalog >/dev/null 2>&1; then
        daypass_embedded_catalog > "$_pc_cache" 2>/dev/null
        if [ -s "$_pc_cache" ]; then
            PACKAGE_CATALOG_FILE="$_pc_cache"
            export PACKAGE_CATALOG_FILE
            return 0
        fi
    fi

    if [ -s "config/package_catalog.json" ]; then
        PACKAGE_CATALOG_FILE="config/package_catalog.json"
        export PACKAGE_CATALOG_FILE
        return 0
    fi

    return 1
}

_pc_field() {
    _pc_pkg="$1"
    _pc_key="$2"
    command -v jq >/dev/null 2>&1 || return 1
    [ -n "$PACKAGE_CATALOG_FILE" ] || load_package_catalog || return 1
    jq -r --arg p "$_pc_pkg" --arg k "$_pc_key" \
        '.packages[$p][$k] // empty' "$PACKAGE_CATALOG_FILE" 2>/dev/null
}

pkg_display_title() {
    _pc_t="$(_pc_field "$1" title)"
    if [ -n "$_pc_t" ]; then
        printf '%s' "$_pc_t"
        return 0
    fi
    case "$1" in
        luci-app-*)
            printf 'Web Interface for %s' "$(printf '%s' "${1#luci-app-}" | tr '-' ' ')"
            ;;
        luci-i18n-*)
            printf 'Translation pack (%s)' "${1#luci-i18n-}"
            ;;
        luci-proto-*)
            printf 'Web protocol helper (%s)' "${1#luci-proto-}"
            ;;
        *)
            printf '%s' "$1"
            ;;
    esac
}

pkg_display_desc() {
    _pc_d="$(_pc_field "$1" description)"
    [ -n "$_pc_d" ] && printf '%s' "$_pc_d"
}

pkg_display_role() {
    _pc_pkg="$1"
    _pc_optional="$2"
    _pc_r="$(_pc_field "$_pc_pkg" role)"
    if [ -z "$_pc_r" ]; then
        case "$_pc_pkg" in
            luci-app-*|luci-proto-*) _pc_r="web" ;;
            luci-i18n-*)             _pc_r="enhancement" ;;
            *)
                if [ "$_pc_optional" = "1" ]; then
                    _pc_r="enhancement"
                else
                    _pc_r="core"
                fi
                ;;
        esac
    fi
    case "$_pc_r" in
        web)         printf '%s' "Web Interface" ;;
        enhancement) printf '%s' "Enhancement" ;;
        *)           printf '%s' "Core" ;;
    esac
}

profile_display_title() {
    _pc_id="$1"
    if command -v load_package_profiles >/dev/null 2>&1 && load_package_profiles \
        && command -v jq >/dev/null 2>&1; then
        _pc_t=$(jq -r --arg id "$_pc_id" '.profiles[$id].title // empty' "$PROFILES_FILE" 2>/dev/null)
        [ -n "$_pc_t" ] && printf '%s' "$_pc_t" && return 0
    fi
    command -v _mf_pretty >/dev/null 2>&1 && _mf_pretty "$_pc_id" && return 0
    printf '%s' "$_pc_id"
}

# Renders PROFILE_PLAN as a framed, non-technical list.
render_profile_plan() {
    _pc_profile="$1"
    _pc_title="$(profile_display_title "$_pc_profile")"
    _pc_count=$(echo $PROFILE_PACKAGES | wc -w | tr -d ' ')

    load_package_catalog >/dev/null 2>&1 || true

    echo
    printf "  📦 ${BOLD}Profile Installation: %s${RESET}\n" "$_pc_title"
    echo "  ───────────────────────────────────────────────────────────"
    printf "  ${GRAY}OpenWrt %s  ·  %s  ·  %s component(s)${RESET}\n" \
        "${PROFILE_RELEASE:-?}.x" "${PKG_MANAGER:-opkg}" "${_pc_count:-0}"
    echo "  ───────────────────────────────────────────────────────────"
    echo

    printf '%s\n' "$PROFILE_PLAN" | while IFS='|' read -r _pc_name _pc_src _pc_opt _pc_alts _; do
        [ -n "$_pc_name" ] || continue
        _pc_role="$(pkg_display_role "$_pc_name" "$_pc_opt")"
        _pc_pt="$(pkg_display_title "$_pc_name")"
        _pc_pd="$(pkg_display_desc "$_pc_name")"
        case "$_pc_role" in
            Core)            _pc_tag="${GREEN}[Core]${RESET}" ;;
            "Web Interface") _pc_tag="${CYAN}[Web Interface]${RESET}" ;;
            *)               _pc_tag="${YELLOW}[Enhancement]${RESET}" ;;
        esac
        printf "  %b  ${BOLD}%s${RESET}\n" "$_pc_tag" "$_pc_pt"
        if [ -n "$_pc_pd" ]; then
            printf "         ${GRAY}%s${RESET}\n" "$_pc_pd"
        fi
        if [ -n "$_pc_alts" ]; then
            printf "         ${GRAY}If unavailable, a compatible fallback is tried.${RESET}\n"
        fi
        echo
    done

    echo "  ───────────────────────────────────────────────────────────"
}

profile_install_prompt() {
    _pc_title="$1"
    _pc_count="$2"
    printf "  ⁉️ ${YELLOW}Install profile [%s] (%s packages)?${RESET} ${GRAY}[Y/n] :${RESET} " \
        "$_pc_title" "$_pc_count"
    if ! read -r UI_CHOICE </dev/tty; then
        UI_CHOICE=""
        daypass_quit
    fi
}

profile_display_icon() {
    _pc_id="$1"
    _pc_icon=""
    if command -v jq >/dev/null 2>&1 && load_package_catalog >/dev/null 2>&1; then
        _pc_icon=$(jq -r --arg id "$_pc_id" '.profiles[$id].icon // empty' "$PACKAGE_CATALOG_FILE" 2>/dev/null)
    fi
    if [ -n "$_pc_icon" ]; then
        printf '%s' "$_pc_icon"
        return 0
    fi
    case "$_pc_id" in
        proxy)          printf '⚡' ;;
        vpn)            printf '🔐' ;;
        usb)            printf '🔌' ;;
        network_tools)  printf '📈' ;;
        *)              printf '📦' ;;
    esac
}

# Manifest ids that belong to a package profile (proxy wizard records passwall / passwall2).
_pd_related_ids() {
    case "$1" in
        proxy) printf '%s' "proxy passwall passwall2" ;;
        *)     printf '%s' "$1" ;;
    esac
}

_pd_tool_label() {
    case "$1" in
        luci-app-passwall2) printf 'passwall2' ;;
        luci-app-passwall)  printf 'passwall' ;;
        luci-app-*)         printf '%s' "${1#luci-app-}" ;;
        *)                  printf '%s' "$1" ;;
    esac
}

_pd_in_words() {
    _pd_n="$1"
    _pd_h="$2"
    for _pd_w in $_pd_h; do
        [ "$_pd_w" = "$_pd_n" ] && return 0
    done
    return 1
}

_pd_pkg_present() {
    _pd_name="$1"
    _pd_alts="$2"
    _pd_ids="$3"

    if command -v _pr_is_installed >/dev/null 2>&1; then
        _pr_is_installed "$_pd_name" && return 0
        for _pd_alt in $_pd_alts; do
            [ -n "$_pd_alt" ] || continue
            _pr_is_installed "$_pd_alt" && return 0
        done
    fi

    if command -v mf_module_packages >/dev/null 2>&1; then
        for _pd_mid in $_pd_ids; do
            _pd_mpkgs="$(mf_module_packages "$_pd_mid" 2>/dev/null)"
            [ -n "$_pd_mpkgs" ] || continue
            _pd_in_words "$_pd_name" "$_pd_mpkgs" && return 0
            for _pd_alt in $_pd_alts; do
                [ -n "$_pd_alt" ] || continue
                _pd_in_words "$_pd_alt" "$_pd_mpkgs" && return 0
            done
        done
    fi
    return 1
}

_pd_highlights() {
    _pd_id="$1"
    _pd_pkgs="$2"
    _pd_list=""

    if command -v jq >/dev/null 2>&1 && load_package_catalog >/dev/null 2>&1; then
        _pd_list=$(jq -r --arg id "$_pd_id" '(.profiles[$id].highlights // []) | join(" ")' \
            "$PACKAGE_CATALOG_FILE" 2>/dev/null)
    fi

    _pd_out=""
    _pd_n=0
    for _pd_h in $_pd_list; do
        [ "$_pd_n" -ge 4 ] && break
        if [ -n "$_pd_pkgs" ] && ! _pd_in_words "$_pd_h" "$_pd_pkgs"; then
            case "$_pd_id" in
                proxy) ;;
                *) continue ;;
            esac
        fi
        _pd_lab="$(_pd_tool_label "$_pd_h")"
        _pd_in_words "$_pd_lab" "$_pd_out" && continue
        _pd_out="${_pd_out:+$_pd_out, }$_pd_lab"
        _pd_n=$((_pd_n + 1))
    done

    if [ "$_pd_n" -lt 3 ]; then
        for _pd_h in $_pd_pkgs; do
            [ "$_pd_n" -ge 4 ] && break
            case "$_pd_h" in
                luci-i18n-*) continue ;;
            esac
            _pd_lab="$(_pd_tool_label "$_pd_h")"
            _pd_in_words "$_pd_lab" "$_pd_out" && continue
            _pd_out="${_pd_out:+$_pd_out, }$_pd_lab"
            _pd_n=$((_pd_n + 1))
        done
    fi

    [ -n "$_pd_out" ] && printf '%s' "$_pd_out"
}

_pd_profile_ids() {
    _pd_all=""
    if command -v load_package_profiles >/dev/null 2>&1 && load_package_profiles \
        && command -v jq >/dev/null 2>&1; then
        _pd_all=$(jq -r '.profiles | keys[]' "$PROFILES_FILE" 2>/dev/null)
    fi
    [ -n "$_pd_all" ] || _pd_all="proxy vpn usb network_tools"
    for _pd_pref in proxy vpn usb network_tools; do
        _pd_in_words "$_pd_pref" "$_pd_all" && printf '%s\n' "$_pd_pref"
    done
    for _pd_x in $_pd_all; do
        case "$_pd_x" in
            proxy|vpn|usb|network_tools) continue ;;
        esac
        printf '%s\n' "$_pd_x"
    done
}

# Interactive Option 6: framed dashboard with live install status.
profile_status_dashboard() {
    local _pd_id _pd_title _pd_icon _pd_count _pd_hit _pd_miss
    local _pd_tools _pd_badge _pd_name _pd_src _pd_opt _pd_alts
    local _pd_ids _pd_saved_plan _pd_saved_pkgs _pd_quiet

    render_persistent_header
    ui_title "📋 Profile Overview & Status Dashboard"
    printf "  ${GRAY}Live status from this router and the DayPass install record.${RESET}\n"
    echo "  ───────────────────────────────────────────────────────────"
    echo

    _pd_saved_plan="${PROFILE_PLAN:-}"
    _pd_saved_pkgs="${PROFILE_PACKAGES:-}"
    _pd_quiet="${DAYPASS_RESOLVE_QUIET:-0}"

    load_package_catalog >/dev/null 2>&1 || true

    for _pd_id in $(_pd_profile_ids); do
        [ -n "$_pd_id" ] || continue
        _pd_title="$(profile_display_title "$_pd_id")"
        _pd_icon="$(profile_display_icon "$_pd_id")"
        _pd_ids="$(_pd_related_ids "$_pd_id")"
        _pd_count=0
        _pd_hit=0
        _pd_miss=0

        DAYPASS_RESOLVE_QUIET=1
        export DAYPASS_RESOLVE_QUIET
        if command -v resolve_profile >/dev/null 2>&1 && resolve_profile "$_pd_id"; then
            _pd_count=$(echo $PROFILE_PACKAGES | wc -w | tr -d ' ')
            while IFS='|' read -r _pd_name _pd_src _pd_opt _pd_alts _; do
                [ -n "$_pd_name" ] || continue
                if _pd_pkg_present "$_pd_name" "$_pd_alts" "$_pd_ids"; then
                    _pd_hit=$((_pd_hit + 1))
                else
                    _pd_miss=$((_pd_miss + 1))
                fi
            done <<EOF
$PROFILE_PLAN
EOF
            _pd_tools="$(_pd_highlights "$_pd_id" "$PROFILE_PACKAGES")"
        else
            _pd_tools="$(_pd_highlights "$_pd_id" "")"
        fi

        if [ "$_pd_hit" -eq 0 ]; then
            _pd_badge="${GRAY}[✖ Not Installed]${RESET}"
        elif [ "$_pd_miss" -eq 0 ]; then
            _pd_badge="${GREEN}[✔ Installed]${RESET}"
        else
            _pd_badge="${YELLOW}[⚠ Partial]${RESET}"
        fi

        printf "  %s  ${BOLD}%s${RESET}\n" "$_pd_icon" "$_pd_title"
        printf "      Status   %b\n" "$_pd_badge"
        printf "      Tools    ${GRAY}%s${RESET}\n" "${_pd_tools:-—}"
        printf "      Count    %s package(s)\n" "${_pd_count:-0}"
        echo
    done

    DAYPASS_RESOLVE_QUIET="$_pd_quiet"
    export DAYPASS_RESOLVE_QUIET
    PROFILE_PLAN="$_pd_saved_plan"
    PROFILE_PACKAGES="$_pd_saved_pkgs"
    export PROFILE_PLAN PROFILE_PACKAGES

    echo "  ───────────────────────────────────────────────────────────"
    printf "  ${GRAY}Press [Enter] to return to menu ...${RESET}"
    read -r _ </dev/tty || daypass_quit
}


# 📄 Source : manifest_manager.sh
# ============================================================
# POSIX backing store: $DAYPASS_DIR/manifest.d/<id>
# Public JSON    : $DAYPASS_DIR/installed_manifest.json
# ============================================================

mf_path() {
    echo "${DAYPASS_MANIFEST:-${DAYPASS_DIR:-/etc/daypass}/installed_manifest.json}"
}

mf_dir() {
    echo "${DAYPASS_DIR:-/etc/daypass}/manifest.d"
}

_mf_init() {
    mkdir -p "$(dirname "$(mf_path)")" "$(mf_dir)" 2>/dev/null || true
}

_mf_safe_id() {
    case "$1" in
        ''|*[!A-Za-z0-9_-]*) return 1 ;;
    esac
    return 0
}

_mf_json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

_mf_json_str_array() {
    _mf_first=1
    printf '['
    for _mf_w in $1; do
        [ "$_mf_first" -eq 1 ] || printf ','
        printf '"%s"' "$(_mf_json_escape "$_mf_w")"
        _mf_first=0
    done
    printf ']'
}

# passwall2 -> Passwall 2 ; network_tools -> Network Tools
_mf_pretty() {
    printf '%s' "$1" | sed 's/_/ /g; s/-/ /g; s/\([A-Za-z]\)\([0-9]\)/\1 \2/g' | awk '{
        for (i = 1; i <= NF; i++)
            $i = toupper(substr($i, 1, 1)) substr($i, 2)
        print
    }'
}

_mf_kv_get() {
    _mf_file="$1"
    _mf_key="$2"
    [ -f "$_mf_file" ] || return 1
    sed -n "s/^${_mf_key}=//p" "$_mf_file" 2>/dev/null | head -n 1
}

_mf_kv_set() {
    _mf_file="$1"
    _mf_key="$2"
    _mf_val="$3"
    _mf_tmp="${_mf_file}.tmp"
    mkdir -p "$(dirname "$_mf_file")" 2>/dev/null
    if [ -f "$_mf_file" ]; then
        grep -v "^${_mf_key}=" "$_mf_file" > "$_mf_tmp" 2>/dev/null || true
    else
        : > "$_mf_tmp"
    fi
    printf '%s=%s\n' "$_mf_key" "$_mf_val" >> "$_mf_tmp"
    mv "$_mf_tmp" "$_mf_file"
}

# Rebuild installed_manifest.json from manifest.d
mf_export_json() {
    _mf_init
    _mf_out="$(mf_path)"
    _mf_tmp="${_mf_out}.tmp"
    _mf_first=1

    printf '{\n  "modules": {\n' > "$_mf_tmp"
    for _mf_file in "$(mf_dir)"/*; do
        [ -f "$_mf_file" ] || continue
        _mf_id="${_mf_file##*/}"
        _mf_safe_id "$_mf_id" || continue
        [ "$_mf_first" -eq 1 ] || printf ',\n' >> "$_mf_tmp"
        _mf_first=0
        printf '    "%s": {\n' "$(_mf_json_escape "$_mf_id")" >> "$_mf_tmp"
        printf '      "title": "%s",\n' "$(_mf_json_escape "$(_mf_kv_get "$_mf_file" title)")" >> "$_mf_tmp"
        printf '      "category": "%s",\n' "$(_mf_json_escape "$(_mf_kv_get "$_mf_file" category)")" >> "$_mf_tmp"
        printf '      "installed_at": "%s",\n' "$(_mf_json_escape "$(_mf_kv_get "$_mf_file" installed_at)")" >> "$_mf_tmp"
        printf '      "packages": %s,\n' "$(_mf_json_str_array "$(_mf_kv_get "$_mf_file" packages)")" >> "$_mf_tmp"
        printf '      "configs": %s,\n' "$(_mf_json_str_array "$(_mf_kv_get "$_mf_file" configs)")" >> "$_mf_tmp"
        printf '      "services": %s\n' "$(_mf_json_str_array "$(_mf_kv_get "$_mf_file" services)")" >> "$_mf_tmp"
        printf '    }' >> "$_mf_tmp"
    done
    printf '\n  }\n}\n' >> "$_mf_tmp"
    mv "$_mf_tmp" "$_mf_out"
}

mf_module_ids() {
    _mf_init
    for _mf_file in "$(mf_dir)"/*; do
        [ -f "$_mf_file" ] || continue
        _mf_id="${_mf_file##*/}"
        _mf_safe_id "$_mf_id" && printf '%s\n' "$_mf_id"
    done
}

mf_has_modules() {
    [ -n "$(mf_module_ids)" ]
}

mf_module_title()    { _mf_kv_get "$(mf_dir)/$1" title; }
mf_module_category() { _mf_kv_get "$(mf_dir)/$1" category; }
mf_module_packages() { _mf_kv_get "$(mf_dir)/$1" packages; }
mf_module_configs()  { _mf_kv_get "$(mf_dir)/$1" configs; }
mf_module_services() { _mf_kv_get "$(mf_dir)/$1" services; }

_mf_in_words() {
    _mf_n="$1"
    _mf_h="$2"
    for _mf_w in $_mf_h; do
        [ "$_mf_w" = "$_mf_n" ] && return 0
    done
    return 1
}

_mf_union() {
    _mf_out="$1"
    shift
    for _mf_w in $*; do
        [ -n "$_mf_w" ] || continue
        _mf_in_words "$_mf_w" "$_mf_out" || _mf_out="${_mf_out:+$_mf_out }$_mf_w"
    done
    printf '%s' "$_mf_out"
}

_mf_profile_title() {
    _mf_id="$1"
    if command -v load_package_profiles >/dev/null 2>&1 && load_package_profiles \
        && command -v jq >/dev/null 2>&1; then
        jq -r --arg id "$_mf_id" '.profiles[$id].title // empty' "$PROFILES_FILE" 2>/dev/null
    fi
}

# Category for a module: profile title when the id is a profile, else proxy title.
mf_category_for() {
    _mf_id="$1"
    _mf_t="$(_mf_profile_title "$_mf_id")"
    if [ -n "$_mf_t" ]; then
        printf '%s' "$_mf_t"
        return 0
    fi
    _mf_t="$(_mf_profile_title "proxy")"
    [ -n "$_mf_t" ] && printf '%s' "$_mf_t" && return 0
    printf '%s' "DayPass"
}

mf_title_for() {
    _mf_id="$1"
    _mf_t="$(_mf_profile_title "$_mf_id")"
    if [ -n "$_mf_t" ]; then
        printf '%s' "$_mf_t"
        return 0
    fi
    printf '%s Suite' "$(_mf_pretty "$_mf_id")"
}

_mf_pkg_files() {
    case "${PKG_MANAGER:-opkg}" in
        apk) apk info -L "$1" 2>/dev/null ;;
        *)   opkg files "$1" 2>/dev/null ;;
    esac
}

mf_discover_services() {
    _mf_seen=""
    for _mf_pkg in $1; do
        [ -n "$_mf_pkg" ] || continue
        for _mf_svc in $(_mf_pkg_files "$_mf_pkg" | sed -n 's|^/etc/init.d/\([^/]*\)$|\1|p'); do
            _mf_in_words "$_mf_svc" "$_mf_seen" && continue
            _mf_seen="${_mf_seen:+$_mf_seen }$_mf_svc"
        done
        case "$_mf_pkg" in
            luci-app-*|luci-proto-*)
                _mf_svc="${_mf_pkg#luci-app-}"
                _mf_svc="${_mf_svc#luci-proto-}"
                if [ -x "/etc/init.d/$_mf_svc" ] && ! _mf_in_words "$_mf_svc" "$_mf_seen"; then
                    _mf_seen="${_mf_seen:+$_mf_seen }$_mf_svc"
                fi
                ;;
            luci-i18n-*|kmod-*) ;;
            *)
                if [ -x "/etc/init.d/$_mf_pkg" ] && ! _mf_in_words "$_mf_pkg" "$_mf_seen"; then
                    _mf_seen="${_mf_seen:+$_mf_seen }$_mf_pkg"
                fi
                ;;
        esac
    done
    printf '%s' "$_mf_seen"
}

mf_discover_configs() {
    _mf_seen=""
    for _mf_pkg in $1; do
        [ -n "$_mf_pkg" ] || continue
        for _mf_cfg in $(_mf_pkg_files "$_mf_pkg" | sed -n 's|^/etc/config/\([^/]*\)$|/etc/config/\1|p'); do
            _mf_in_words "$_mf_cfg" "$_mf_seen" && continue
            _mf_seen="${_mf_seen:+$_mf_seen }$_mf_cfg"
        done
        case "$_mf_pkg" in
            luci-app-*|luci-proto-*)
                _mf_stem="${_mf_pkg#luci-app-}"
                _mf_stem="${_mf_stem#luci-proto-}"
                _mf_cfg="/etc/config/$_mf_stem"
                _mf_in_words "$_mf_cfg" "$_mf_seen" || _mf_seen="${_mf_seen:+$_mf_seen }$_mf_cfg"
                ;;
        esac
    done
    printf '%s' "$_mf_seen"
}

# $1 id, $2 title, $3 category, $4 packages (space-separated)
# Optional: $5 configs, $6 services (discovered when omitted)
mf_register_module() {
    _mf_id="$1"
    _mf_title="$2"
    _mf_cat="$3"
    _mf_pkgs="$4"
    _mf_cfgs="$5"
    _mf_svcs="$6"

    _mf_safe_id "$_mf_id" || return 1
    _mf_init

    _mf_file="$(mf_dir)/$_mf_id"
    if [ -f "$_mf_file" ]; then
        _mf_pkgs="$(_mf_union "$(_mf_kv_get "$_mf_file" packages)" $_mf_pkgs)"
        [ -z "$_mf_title" ] && _mf_title="$(_mf_kv_get "$_mf_file" title)"
        [ -z "$_mf_cat" ] && _mf_cat="$(_mf_kv_get "$_mf_file" category)"
        _mf_cfgs="$(_mf_union "$(_mf_kv_get "$_mf_file" configs)" $_mf_cfgs)"
        _mf_svcs="$(_mf_union "$(_mf_kv_get "$_mf_file" services)" $_mf_svcs)"
    fi

    [ -n "$_mf_title" ] || _mf_title="$(mf_title_for "$_mf_id")"
    [ -n "$_mf_cat" ] || _mf_cat="$(mf_category_for "$_mf_id")"
    [ -n "$_mf_cfgs" ] || _mf_cfgs="$(mf_discover_configs "$_mf_pkgs")"
    [ -n "$_mf_svcs" ] || _mf_svcs="$(mf_discover_services "$_mf_pkgs")"

    {
        printf 'title=%s\n' "$_mf_title"
        printf 'category=%s\n' "$_mf_cat"
        printf 'installed_at=%s\n' "$(date +%Y-%m-%d 2>/dev/null || echo unknown)"
        printf 'packages=%s\n' "$_mf_pkgs"
        printf 'configs=%s\n' "$_mf_cfgs"
        printf 'services=%s\n' "$_mf_svcs"
    } > "$_mf_file"

    mf_export_json
}

mf_unregister_module() {
    _mf_safe_id "$1" || return 1
    rm -f "$(mf_dir)/$1"
    mf_export_json
}

# Drop package names from a module; unregister when none remain.
mf_drop_packages() {
    _mf_id="$1"
    _mf_drop="$2"
    _mf_file="$(mf_dir)/$_mf_id"
    [ -f "$_mf_file" ] || return 0

    _mf_keep=""
    for _mf_pkg in $(_mf_kv_get "$_mf_file" packages); do
        _mf_in_words "$_mf_pkg" "$_mf_drop" && continue
        _mf_keep="${_mf_keep:+$_mf_keep }$_mf_pkg"
    done

    if [ -z "$_mf_keep" ]; then
        mf_unregister_module "$_mf_id"
        return 0
    fi

    _mf_kv_set "$_mf_file" packages "$_mf_keep"
    _mf_kv_set "$_mf_file" configs "$(mf_discover_configs "$_mf_keep")"
    _mf_kv_set "$_mf_file" services "$(mf_discover_services "$_mf_keep")"
    mf_export_json
}

mf_drop_packages_from_all() {
    for _mf_id in $(mf_module_ids); do
        mf_drop_packages "$_mf_id" "$1"
    done
    mf_sync_install_log
}

# Rebuild INSTALL_LOG from every module's package list.
mf_sync_install_log() {
    _mf_log="${INSTALL_LOG:-${DAYPASS_DIR:-/etc/daypass}/install.log}"
    mkdir -p "$(dirname "$_mf_log")" 2>/dev/null
    : > "$_mf_log"
    for _mf_id in $(mf_module_ids); do
        for _mf_pkg in $(mf_module_packages "$_mf_id"); do
            printf '%s\n' "$_mf_pkg"
        done
    done | sort -u > "$_mf_log"
    [ -s "$_mf_log" ] || rm -f "$_mf_log"
}

# Seed the registry from a legacy install.log grouped by package profiles.
mf_migrate_from_log() {
    mf_has_modules && return 0
    _mf_log="${INSTALL_LOG:-${DAYPASS_DIR:-/etc/daypass}/install.log}"
    [ -s "$_mf_log" ] || return 1

    _mf_pkgs=$(sort -u "$_mf_log" | tr '\n' ' ')
    [ -n "$_mf_pkgs" ] || return 1

    if command -v load_package_profiles >/dev/null 2>&1 && load_package_profiles \
        && command -v jq >/dev/null 2>&1; then
        jq -r '
            def names:
                [.. | objects |
                    (.name // empty),
                    ((.alternatives // [])[]?),
                    ((.depends // [])[]?),
                    ((.packages // [])[]? | if type == "string" then . else empty end)
                ]
                | map(select(type == "string" and test("^[A-Za-z0-9._+-]+$")))
                | unique;
            .profiles | to_entries[] |
            [.key, (.value.title // .key), ((.value | names) | join(" "))] | @tsv
        ' "$PROFILES_FILE" 2>/dev/null | while IFS="$(printf '\t')" read -r _mf_id _mf_title _mf_names; do
            _mf_hit=""
            for _mf_pkg in $_mf_pkgs; do
                _mf_in_words "$_mf_pkg" "$_mf_names" && _mf_hit="${_mf_hit:+$_mf_hit }$_mf_pkg"
            done
            [ -n "$_mf_hit" ] && mf_register_module "$_mf_id" "$_mf_title" "$_mf_title" "$_mf_hit"
        done
    fi

    if ! mf_has_modules; then
        mf_register_module "daypass" "DayPass" "DayPass" "$_mf_pkgs"
    fi
}

# Heading used by the inspection table.
mf_inspection_title() {
    if [ -n "${INSPECT_MODULE_TITLE:-}" ]; then
        printf '%s' "$INSPECT_MODULE_TITLE"
        return 0
    fi
    if [ -n "${INSPECT_MODULE_ID:-}" ]; then
        _mf_t="$(mf_module_title "$INSPECT_MODULE_ID")"
        [ -n "$_mf_t" ] && printf '%s' "$_mf_t" && return 0
        mf_title_for "$INSPECT_MODULE_ID"
        return 0
    fi
    if [ -n "${SELECTED_PROFILE:-}" ]; then
        mf_title_for "$SELECTED_PROFILE"
        return 0
    fi
    _mf_ids=$(mf_module_ids)
    _mf_n=0
    _mf_one=""
    for _mf_id in $_mf_ids; do
        _mf_n=$((_mf_n + 1))
        _mf_one="$_mf_id"
    done
    if [ "$_mf_n" -eq 1 ]; then
        mf_module_title "$_mf_one"
        return 0
    fi
    printf '%s' "DayPass"
}

mf_inspection_category() {
    if [ -n "${INSPECT_MODULE_CATEGORY:-}" ]; then
        printf '%s' "$INSPECT_MODULE_CATEGORY"
        return 0
    fi
    if [ -n "${INSPECT_MODULE_ID:-}" ]; then
        mf_module_category "$INSPECT_MODULE_ID"
        return 0
    fi
    if [ -n "${SELECTED_PROFILE:-}" ]; then
        mf_category_for "$SELECTED_PROFILE"
        return 0
    fi
    printf '%s' ""
}

# Record the current install session as a named module.
# $1 module id, $2 packages
mf_record_install() {
    _mf_id="$1"
    _mf_pkgs="$2"
    [ -n "$_mf_id" ] && [ -n "$_mf_pkgs" ] || return 1
    mf_register_module "$_mf_id" "$(mf_title_for "$_mf_id")" "$(mf_category_for "$_mf_id")" "$_mf_pkgs"
    mf_sync_install_log
}


# 📄 Source : installer.sh

manifest_lookup()
{
    field="$1"
    package="$2"

    val=$(jq -r \
        --arg pkg "$package" \
        --arg arch "$ARCH" \
        --arg field "$field" \
'
.architectures[]?
| select(.name == $arch)
| .feeds[]?[]?
| select(
    (.package == $pkg)
    or
    (.package | startswith($pkg + "-"))
)
| .[$field] // empty
' \
"$MANIFEST_FILE" 2>/dev/null | head -n1)

    if [ -z "$val" ] || [ "$val" = "null" ]; then
        alt_field=""
        case "$field" in
            size) alt_field="Size" ;;
            Size) alt_field="size" ;;
            version) alt_field="Version" ;;
            Version) alt_field="version" ;;
            sha256) alt_field="SHA256" ;;
        esac

        if [ -n "$alt_field" ]; then
            val=$(jq -r \
                --arg pkg "$package" \
                --arg arch "$ARCH" \
                --arg field "$alt_field" \
'
.architectures[]?
| select(.name == $arch)
| .feeds[]?[]?
| select(
    (.package == $pkg)
    or
    (.package | startswith($pkg + "-"))
)
| .[$field] // empty
' \
"$MANIFEST_FILE" 2>/dev/null | head -n1)
        fi
    fi

    echo "$val"
}

format_size()
{
    bytes="${1:-0}"
    if [ "$bytes" -ge 1048576 ]; then
        awk "BEGIN {printf \"%.2f MB\", $bytes/1048576}" 2>/dev/null
    elif [ "$bytes" -ge 1024 ]; then
        awk "BEGIN {printf \"%.1f KB\", $bytes/1024}" 2>/dev/null
    else
        echo "${bytes} Bytes"
    fi
}

download_package()
{
    package="$1"

    file=$(manifest_lookup "file" "$package")
    sha256=$(manifest_lookup "sha256" "$package")

    if [ -z "$file" ] || [ "$file" = "null" ]; then
        log_error "Package [$package] not found in manifest for target [$ARCH]!"
        return 1
    fi

    base_url=$(jq -r '.download_base // empty' "$MANIFEST_FILE" 2>/dev/null)
    [ -z "$base_url" ] && base_url="$REPO_URL"
    target_url="${base_url}/${file}"

    file_basename=$(basename "$file")
    target="$TMP_DIR/$file_basename"
    tmp="$target.part"

    if [ -f "$target" ]; then
        if echo "$sha256  $target" | sha256sum -c - >/dev/null 2>&1; then
            return 0
        fi
        rm -f "$target"
    fi

    DOWNLOAD_SUCCESS=0
    trap 'rm -f "$tmp" 2>/dev/null' INT TERM

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 15 --max-time 120 --retry 3 --retry-delay 2 "$target_url" -o "$tmp" 2>/dev/null && DOWNLOAD_SUCCESS=1
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=20 --tries=3 -O "$tmp" "$target_url" 2>/dev/null && DOWNLOAD_SUCCESS=1
    elif command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -q --timeout=20 -O "$tmp" "$target_url" 2>/dev/null && DOWNLOAD_SUCCESS=1
    fi

    if [ "$DOWNLOAD_SUCCESS" -ne 1 ] || [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        trap - INT TERM
        return 1
    fi

    if [ -n "$sha256" ] && [ "$sha256" != "null" ]; then
        if ! echo "$sha256  $tmp" | sha256sum -c - >/dev/null 2>&1; then
            rm -f "$tmp"
            trap - INT TERM
            return 1
        fi
    fi

    mv "$tmp" "$target"
    trap - INT TERM
    return 0
}

deploy_targeted_packages()
{
    rm -f /var/lock/opkg.lock /lib/apk/db/lock /var/run/apk.lock /run/apk/db.lock 2>/dev/null

    mkdir -p "$(dirname "$INSTALL_LOG")"
    touch "$INSTALL_LOG"
    rm -f "$TRANSACTION_LOG"
    touch "$TRANSACTION_LOG"

    if [ -z "$PACKAGES_TO_PROCESS" ]; then
        PACKAGES_TO_PROCESS="$FINAL_PACKAGES"
    fi
    PACKAGES_PLANNED="$PACKAGES_TO_PROCESS"

    echo "  🔍 Executing Pre-Flight System Resource Validation ..."
    resource_snapshot

    APPLY_LIST="${TMP_DIR:-/tmp}/daypass_applied.list"
    : > "$APPLY_LIST"
    PACKAGES_NEEDED=""

    echo
    log_info "Checking packages already on this router ..."
    for pkg in $PACKAGES_PLANNED; do
        if command -v pkg_payload_required >/dev/null 2>&1 && ! pkg_payload_required "$pkg"; then
            printf "  ${GRAY}[SKIP]${RESET} Package %s is already installed and up-to-date.\n" "$pkg"
            printf '%s\t%s\n' "$pkg" "(Already Installed)" >> "$APPLY_LIST"
        else
            PACKAGES_NEEDED="$PACKAGES_NEEDED $pkg"
            printf '%s\t%s\n' "$pkg" "pending" >> "$APPLY_LIST"
        fi
    done
    echo

    if ! estimate_install_size; then
        log_error "Installation aborted due to system resource limits!"
        return 1
    fi

    INSTALL_FILES=""
    total_pkgs=0
    for p in $PACKAGES_NEEDED; do
        total_pkgs=$((total_pkgs + 1))
    done

    if [ "$total_pkgs" -gt 0 ]; then
        current_idx=0
        log_info "Downloading required packages ..."

        for pkg in $PACKAGES_NEEDED; do
            current_idx=$((current_idx + 1))

            curr_ram_bytes=$(get_free_ram_bytes 2>/dev/null)
            curr_ram_fmt=$(human_readable_bytes "$curr_ram_bytes" 2>/dev/null)

            if command -v show_ascii_progress >/dev/null 2>&1; then
                show_ascii_progress "Downloading ($pkg) [Free RAM: ${curr_ram_fmt:-N/A}]" "$current_idx" "$total_pkgs"
            else
                echo "  📦 [$current_idx/$total_pkgs] Downloading $pkg ... (Free RAM: ${curr_ram_fmt:-N/A})"
            fi

            if ! download_package "$pkg"; then
                echo
                log_error "Failed downloading dependency : [$pkg]"
                rollback_failed_install
                return 1
            fi

            file=$(manifest_lookup "file" "$pkg")
            file_basename=$(basename "$file")
            INSTALL_FILES="$INSTALL_FILES $TMP_DIR/$file_basename"
            echo "$pkg" >> "$TRANSACTION_LOG"
        done
        echo
    else
        log_info "Nothing to download — every selected package is already current."
        echo
    fi

    INSTALL_SUCCESS=1
    CURRENT_PKG_MGR="${PKG_MANAGER:-opkg}"
    DAYPASS_OPKG_LOG="${DAYPASS_OPKG_LOG:-/tmp/daypass_opkg.log}"
    DAYPASS_APK_LOG="${DAYPASS_APK_LOG:-/tmp/daypass_apk.log}"

    if [ -n "$INSTALL_FILES" ]; then
        INSTALL_SUCCESS=0
        case "$CURRENT_PKG_MGR" in
            apk)
                : > "$DAYPASS_APK_LOG"
                (apk add --allow-untrusted --no-progress $INSTALL_FILES >"$DAYPASS_APK_LOG" 2>&1) &
                BG_PID=$!
                if command -v show_timer_progress >/dev/null 2>&1; then
                    show_timer_progress "$BG_PID" "applying APK package bundle"
                fi
                wait "$BG_PID"
                [ $? -eq 0 ] && INSTALL_SUCCESS=1
                ;;
            opkg|*)
                : > "$DAYPASS_OPKG_LOG"
                (opkg install --force-checksum $INSTALL_FILES >"$DAYPASS_OPKG_LOG" 2>&1) &
                BG_PID=$!
                if command -v show_timer_progress >/dev/null 2>&1; then
                    show_timer_progress "$BG_PID" "applying OPKG package bundle"
                fi
                wait "$BG_PID"
                [ $? -eq 0 ] && INSTALL_SUCCESS=1
                ;;
        esac
    fi

    if [ "$INSTALL_SUCCESS" -eq 1 ]; then
        _apply_tmp="${APPLY_LIST}.tmp"
        : > "$_apply_tmp"
        while IFS='	' read -r _ap_name _ap_note; do
            [ -n "$_ap_name" ] || continue
            if [ "$_ap_note" = "pending" ]; then
                _ap_ver=$(pkg_get_installed_version "$_ap_name" 2>/dev/null | awk 'NR==1 { print $1 }')
                [ -z "$_ap_ver" ] && _ap_ver=$(manifest_lookup "version" "$_ap_name" 2>/dev/null)
                case "$_ap_ver" in
                    ""|null|Latest|N/A) _ap_note="(Installed)" ;;
                    *) _ap_note="(Installed v${_ap_ver})" ;;
                esac
            fi
            printf '%s\t%s\n' "$_ap_name" "$_ap_note" >> "$_apply_tmp"
            echo "$_ap_name" >> "$INSTALL_LOG"
        done < "$APPLY_LIST"
        mv "$_apply_tmp" "$APPLY_LIST"

        if [ -f "$INSTALL_LOG" ]; then
            sort -u "$INSTALL_LOG" -o "$INSTALL_LOG"
        fi

        render_applied_components "$APPLY_LIST"
        resource_compare

        rm -f $INSTALL_FILES 2>/dev/null
        rm -f "$TRANSACTION_LOG"

        log_success "All targeted packages deployed successfully!"

        if command -v mf_record_install >/dev/null 2>&1; then
            mf_record_install "${INSPECT_MODULE_ID:-${SELECTED_PROFILE:-proxy}}" "$PACKAGES_PLANNED"
        fi

        return 0
    fi

    echo
    log_error "Package manager batch execution failed!"
    case "$CURRENT_PKG_MGR" in
        apk)  log_info "Details : ${DAYPASS_APK_LOG}" ;;
        *)    log_info "Details : ${DAYPASS_OPKG_LOG}" ;;
    esac
    rollback_failed_install
    return 1
}

# $1 tab-separated file: package<TAB>note
render_applied_components()
{
    [ -s "$1" ] || return 0

    echo
    printf '  ┌─ Applied Package Components ────────────────────────┐\n'
    while IFS='	' read -r _rc_name _rc_note; do
        [ -n "$_rc_name" ] || continue
        printf "  │  ${GREEN}✔${RESET} %-26.26s %-22.22s│\n" "$_rc_name" "$_rc_note"
    done < "$1"
    printf '  └─────────────────────────────────────────────────────┘\n'
    echo
}

rollback_failed_install()
{
    echo
    log_warn "Initiating Selective Atomic Rollback Procedures ..."
    echo

    rm -f "$TMP_DIR"/*.part "$TMP_DIR"/*.apk "$TMP_DIR"/*.ipk 2>/dev/null

    if [ -s "$TRANSACTION_LOG" ]; then
        log_info "Rolling back modified packages from current session ..."
        while read -r pkg; do
            [ -z "$pkg" ] && continue
            log_info "Rollback : Removing package [$pkg] ..."
            
            case "${PKG_MANAGER:-opkg}" in
                apk)  apk del "$pkg" >/dev/null 2>&1 || true ;;
                opkg|*) opkg remove "$pkg" >/dev/null 2>&1 || true ;;
            esac
        done < "$TRANSACTION_LOG"
    else
        log_info "No system packages were installed in this session. Skipping removal!"
    fi

    rm -f "$TRANSACTION_LOG"
    log_success "Rollback procedure completed safely!"
}

# 📄 Source : updater.sh

inspect_and_confirm_updates()
{
    _in_title="DayPass"
    _in_category=""
    if command -v mf_inspection_title >/dev/null 2>&1; then
        _in_title="$(mf_inspection_title)"
        _in_category="$(mf_inspection_category)"
    elif [ -n "${SELECTED_PROFILE:-}" ]; then
        _in_title="${SELECTED_PROFILE}"
    fi

    echo "  📦 ${_in_title} Package Inspection Table"
    echo "  ─────────────────────────────────────────────────────────── "
    [ -n "$_in_category" ] && printf "  ${GRAY}Category : %s${RESET}\n" "$_in_category"
    printf "  ${GRAY}Manifest : %s${RESET}\n" "${MANIFEST_REL:-unknown} / ${ARCH:-unknown}"
    echo "  ─────────────────────────────────────────────────────────── "
    printf "   %-28s %-16s %-16s %-12s\n" "Package" "Installed" "Manifest Ver" "Action"
    echo "  ─────────────────────────────────────────────────────────── "

    PACKAGES_TO_PROCESS=""
    UPGRADE_COUNT=0
    INSTALL_COUNT=0
    SKIP_COUNT=0

    for pkg in $FINAL_PACKAGES; do
        raw_inst_ver=$(pkg_get_installed_version "$pkg" 2>/dev/null | head -n1)
        inst_ver=$(echo "$raw_inst_ver" | awk '{print $1}' | tr -d ':')
        
        if [ "$inst_ver" = "$pkg" ] || [ -z "$inst_ver" ]; then
            inst_ver="None"
        fi
        
        manif_ver=$(manifest_lookup "version" "$pkg")
        manif_hash=$(manifest_lookup "sha256" "$pkg")
        
        [ -z "$manif_ver" ] || [ "$manif_ver" = "null" ] && manif_ver="N/A"

        ACTION_STR=""
        
        if [ "$inst_ver" = "None" ]; then
            ACTION_STR="${GREEN}[➕ Install]${RESET}"
            INSTALL_COUNT=$((INSTALL_COUNT + 1))
            PACKAGES_TO_PROCESS="$PACKAGES_TO_PROCESS $pkg"
        elif [ "$manif_ver" != "N/A" ] && [ "$manif_ver" != "Latest" ] && [ "$inst_ver" != "$manif_ver" ]; then
            ACTION_STR="${YELLOW}[🔄 Upgrade]${RESET}"
            UPGRADE_COUNT=$((UPGRADE_COUNT + 1))
            PACKAGES_TO_PROCESS="$PACKAGES_TO_PROCESS $pkg"
        elif [ "$manif_ver" = "Latest" ] || [ "$inst_ver" = "$manif_ver" ]; then
            inst_hash=$(pkg_get_installed_hash "$pkg" 2>/dev/null)
            if [ -n "$manif_hash" ] && [ "$manif_hash" != "null" ] && [ -n "$inst_hash" ] && [ "$inst_hash" != "$manif_hash" ]; then
                ACTION_STR="${ORANGE}[🩹 Patch]${RESET}"
                UPGRADE_COUNT=$((UPGRADE_COUNT + 1))
                PACKAGES_TO_PROCESS="$PACKAGES_TO_PROCESS $pkg"
            else
                ACTION_STR="${GREEN}[✅ Up-to-date]${RESET}"
                SKIP_COUNT=$((SKIP_COUNT + 1))
            fi
        fi

        inst_ver_fmt=$(printf "%.14s" "$inst_ver")
        manif_ver_fmt=$(printf "%.14s" "$manif_ver")

        printf "   🔹 ${CYAN}%-24s${RESET} ${YELLOW}%-14s${RESET} %-14s %b\n" \
            "$pkg" "$inst_ver_fmt" "$manif_ver_fmt" "$ACTION_STR"
    done

    echo "  ─────────────────────────────────────────────────────────── "
    printf "   Summary : %d to install, %d to upgrade, %d skipped!\n" "$INSTALL_COUNT" "$UPGRADE_COUNT" "$SKIP_COUNT"
    echo "  ─────────────────────────────────────────────────────────── "
    echo

    if [ -z "$PACKAGES_TO_PROCESS" ]; then
        log_success "All packages are up-to-date! No changes required!"
        return 2
    fi

    printf "  ⁉️ Do you want to proceed with deployment? [Y/n] : "
    read -r user_confirm </dev/tty
    echo

    case "$user_confirm" in
        [nN][oO]|[nN])
            log_warn "Update cancelled by user!"
            return 3
            ;;
        *)
            log_info "User confirmed. Proceeding with updates ..."
            echo
            ;;
    esac

    export PACKAGES_TO_PROCESS
    return 0
}


update_packages_menu()
{
    render_persistent_header

    if command -v mf_migrate_from_log >/dev/null 2>&1; then
        mf_migrate_from_log >/dev/null 2>&1 || true
    fi

    if command -v mf_has_modules >/dev/null 2>&1 && mf_has_modules; then
        echo "  📦 ${BOLD}Select a module to inspect${RESET}"
        echo "  ───────────────────────────────────────────────────────────"
        _up_i=0
        _up_ids=""
        for _up_id in $(mf_module_ids); do
            _up_i=$((_up_i + 1))
            _up_ids="${_up_ids:+$_up_ids }$_up_id"
            printf "  ${CYAN}%s${RESET}) %s ${GRAY}(%s)${RESET}\n" \
                "$_up_i" "$(mf_module_title "$_up_id")" "$(mf_module_category "$_up_id")"
        done
        _up_all=$((_up_i + 1))
        printf "  ${CYAN}%s${RESET}) All DayPass packages\n" "$_up_all"
        ui_nav_footer
        ui_prompt "$_up_all"

        case "$UI_CHOICE" in
            0) return 0 ;;
            q|Q) daypass_quit ;;
            h|H) ui_show_help "packages"; return 0 ;;
        esac

        INSPECT_MODULE_ID=""
        INSPECT_MODULE_TITLE=""
        INSPECT_MODULE_CATEGORY=""
        FINAL_PACKAGES=""

        if [ "$UI_CHOICE" = "$_up_all" ]; then
            FINAL_PACKAGES=$(cat "${INSTALL_LOG:-/dev/null}" 2>/dev/null | tr '\n' ' ')
            INSPECT_MODULE_TITLE="DayPass"
        elif [ "$UI_CHOICE" -ge 1 ] 2>/dev/null && [ "$UI_CHOICE" -le "$_up_i" ]; then
            _up_n=0
            for _up_id in $_up_ids; do
                _up_n=$((_up_n + 1))
                if [ "$_up_n" -eq "$UI_CHOICE" ]; then
                    INSPECT_MODULE_ID="$_up_id"
                    INSPECT_MODULE_TITLE="$(mf_module_title "$_up_id")"
                    INSPECT_MODULE_CATEGORY="$(mf_module_category "$_up_id")"
                    FINAL_PACKAGES="$(mf_module_packages "$_up_id")"
                    break
                fi
            done
        else
            log_warn "Invalid option!"
            ui_pause
            return 1
        fi
        export FINAL_PACKAGES INSPECT_MODULE_ID INSPECT_MODULE_TITLE INSPECT_MODULE_CATEGORY
        echo
    elif [ -f "$INSTALL_LOG" ] && [ -s "$INSTALL_LOG" ]; then
        FINAL_PACKAGES=$(cat "$INSTALL_LOG" | tr '\n' ' ')
        export FINAL_PACKAGES
    else
        log_warn "No installed packages log found. Please install DayPass packages first!"
        echo
        printf "  ${GRAY}Press [ENTER] to go back ...${RESET}"
        read -r _ </dev/tty || daypass_quit
        return 1
    fi

    inspect_and_confirm_updates
    INSPECT_STATUS=$?

    if [ "$INSPECT_STATUS" -eq 2 ] || [ "$INSPECT_STATUS" -eq 3 ]; then
        printf "  ${GRAY}Press [ENTER] to go back ...${RESET}"
        read -r _ </dev/tty || daypass_quit
        return 0
    fi

    if deploy_targeted_packages; then
        echo
        log_success "All packages updated successfully!"
    else
        echo
        log_error "Update process failed!"
    fi

    echo
    printf "  ${GRAY}Press [ENTER] to go back ...${RESET}"
    read -r _ </dev/tty || daypass_quit
}

# 📄 Source : purge.sh
# ============================================================
# Groups tracked packages by config/package_profiles.json, then
# stops services, removes packages, drops leftover UCI files and
# flushes the LuCI index cache.
# ============================================================

PURGE_CORE_CONFIGS="network firewall dhcp system wireless luci rpcd uhttpd dropbear fstab ubootenv"

# ------------------------------------------------------------
_pu_tracked_file() {
    echo "${INSTALL_LOG:-${DAYPASS_DIR:-/etc/daypass}/install.log}"
}

_pu_tracked_pkgs() {
    _pu_log="$(_pu_tracked_file)"
    [ -s "$_pu_log" ] || return 1
    sort -u "$_pu_log" | sed '/^[[:space:]]*$/d'
}

_pu_in_words() {
    _pu_needle="$1"
    _pu_hay="$2"
    for _pu_w in $_pu_hay; do
        [ "$_pu_w" = "$_pu_needle" ] && return 0
    done
    return 1
}

_pu_union() {
    _pu_out="$1"
    shift
    for _pu_w in $*; do
        [ -n "$_pu_w" ] || continue
        _pu_in_words "$_pu_w" "$_pu_out" || _pu_out="${_pu_out:+$_pu_out }$_pu_w"
    done
    printf '%s' "$_pu_out"
}

_pu_is_core_config() {
    _pu_base="${1##*/}"
    _pu_in_words "$_pu_base" "$PURGE_CORE_CONFIGS"
}

# Files owned by a package (needed before the package is deleted).
_pu_pkg_files() {
    case "${PKG_MANAGER:-opkg}" in
        apk)
            apk info -L "$1" 2>/dev/null
            ;;
        *)
            opkg files "$1" 2>/dev/null
            ;;
    esac
}

# Init scripts shipped by the package, plus a luci-app-* / luci-proto-* name map.
_pu_discover_services() {
    _pu_pkg="$1"
    _pu_pkg_files "$_pu_pkg" | sed -n 's|^/etc/init.d/\([^/]*\)$|\1|p'
    case "$_pu_pkg" in
        luci-app-*|luci-proto-*)
            _pu_svc="${_pu_pkg#luci-app-}"
            _pu_svc="${_pu_svc#luci-proto-}"
            [ -x "/etc/init.d/$_pu_svc" ] && echo "$_pu_svc"
            ;;
        luci-i18n-*)
            ;;
        *)
            [ -x "/etc/init.d/$_pu_pkg" ] && echo "$_pu_pkg"
            ;;
    esac
}

# UCI files shipped by the package, plus leftover names derived from the pkg.
_pu_discover_configs() {
    _pu_pkg="$1"
    _pu_pkg_files "$_pu_pkg" | sed -n 's|^/etc/config/\([^/]*\)$|/etc/config/\1|p'
    case "$_pu_pkg" in
        luci-app-*|luci-proto-*)
            _pu_cfg="${_pu_pkg#luci-app-}"
            _pu_cfg="${_pu_cfg#luci-proto-}"
            echo "/etc/config/$_pu_cfg"
            ;;
        luci-i18n-*|kmod-*)
            ;;
        *)
            echo "/etc/config/$_pu_pkg"
            ;;
    esac
}

_pu_profiles_json() {
    if command -v load_package_profiles >/dev/null 2>&1 && load_package_profiles; then
        echo "$PROFILES_FILE"
        return 0
    fi
    return 1
}

# id<TAB>title<TAB>space-separated names declared by the profile
_pu_profile_catalog() {
    _pu_json="$(_pu_profiles_json)" || return 1
    command -v jq >/dev/null 2>&1 || return 1
    jq -r '
        def names:
            [.. | objects |
                (.name // empty),
                ((.alternatives // [])[]?),
                ((.depends // [])[]?),
                ((.packages // [])[]? | if type == "string" then . else empty end)
            ]
            | map(select(type == "string" and test("^[A-Za-z0-9._+-]+$")))
            | unique;
        .profiles | to_entries[] |
        [.key, (.value.title // .key), ((.value | names) | join(" "))] | @tsv
    ' "$_pu_json" 2>/dev/null
}

# Assign each tracked package to the first matching profile, else "other".
# Writes: id|title|pkg pkg ...
_pu_build_groups() {
    _pu_out="$1"
    : > "$_pu_out"

    _pu_tracked="$(_pu_tracked_pkgs)" || return 1
    _pu_assigned=""
    _pu_catalog="$(_pu_profile_catalog)" || _pu_catalog=""

    if [ -n "$_pu_catalog" ]; then
        printf '%s\n' "$_pu_catalog" | while IFS="$(printf '\t')" read -r _pu_id _pu_title _pu_names; do
            [ -n "$_pu_id" ] || continue
            _pu_hit=""
            for _pu_pkg in $_pu_tracked; do
                _pu_in_words "$_pu_pkg" "$_pu_assigned" && continue
                if _pu_in_words "$_pu_pkg" "$_pu_names"; then
                    _pu_hit="${_pu_hit:+$_pu_hit }$_pu_pkg"
                    _pu_assigned="${_pu_assigned:+$_pu_assigned }$_pu_pkg"
                fi
            done
            [ -n "$_pu_hit" ] && printf '%s|%s|%s\n' "$_pu_id" "$_pu_title" "$_pu_hit"
        done > "$_pu_out"

        # The pipeline subshell cannot update _pu_assigned in the parent, so
        # recompute leftovers from the groups file.
        _pu_assigned=""
        while IFS='|' read -r _pu_id _pu_title _pu_hit; do
            _pu_assigned="${_pu_assigned:+$_pu_assigned }$_pu_hit"
        done < "$_pu_out"
    fi

    _pu_other=""
    for _pu_pkg in $_pu_tracked; do
        _pu_in_words "$_pu_pkg" "$_pu_assigned" && continue
        _pu_other="${_pu_other:+$_pu_other }$_pu_pkg"
    done
    [ -n "$_pu_other" ] && printf '%s|%s|%s\n' "other" "Other DayPass packages" "$_pu_other" >> "$_pu_out"

    [ -s "$_pu_out" ]
}

_pu_count_words() {
    _pu_n=0
    for _pu_w in $1; do
        _pu_n=$((_pu_n + 1))
    done
    echo "$_pu_n"
}

_pu_collect_preview() {
    PURGE_SERVICES=""
    PURGE_CONFIGS=""
    for _pu_pkg in $1; do
        [ -n "$_pu_pkg" ] || continue
        for _pu_svc in $(_pu_discover_services "$_pu_pkg"); do
            [ -x "/etc/init.d/$_pu_svc" ] || continue
            _pu_in_words "$_pu_svc" "$PURGE_SERVICES" || \
                PURGE_SERVICES="${PURGE_SERVICES:+$PURGE_SERVICES }$_pu_svc"
        done
        for _pu_cfg in $(_pu_discover_configs "$_pu_pkg"); do
            [ -e "$_pu_cfg" ] || continue
            _pu_is_core_config "$_pu_cfg" && continue
            _pu_in_words "$_pu_cfg" "$PURGE_CONFIGS" || \
                PURGE_CONFIGS="${PURGE_CONFIGS:+$PURGE_CONFIGS }$_pu_cfg"
        done
    done
}

_pu_print_list() {
    _pu_label="$1"
    _pu_items="$2"
    printf "  ${BOLD}%s${RESET}\n" "$_pu_label"
    if [ -z "$_pu_items" ]; then
        printf "    ${GRAY}(none)${RESET}\n"
        return 0
    fi
    for _pu_item in $_pu_items; do
        printf "    • ${CYAN}%s${RESET}\n" "$_pu_item"
    done
}

# ------------------------------------------------------------
# Deep-clean pipeline for a space-separated package list
# ------------------------------------------------------------
purge_packages() {
    _pu_targets="$1"
    [ -n "$_pu_targets" ] || return 1

    PKG_MGR="${PKG_MANAGER:-opkg}"
    [ -n "${PKG_MANAGER:-}" ] || {
        command -v apk >/dev/null 2>&1 && PKG_MGR="apk"
    }

    _pu_collect_preview "$_pu_targets"
    if [ -n "${PURGE_MODULE_ID:-}" ] && command -v mf_module_services >/dev/null 2>&1; then
        PURGE_SERVICES="$(_pu_union "$PURGE_SERVICES" $(mf_module_services "$PURGE_MODULE_ID"))"
        PURGE_CONFIGS="$(_pu_union "$PURGE_CONFIGS" $(mf_module_configs "$PURGE_MODULE_ID"))"
    fi

    echo
    printf "  ${YELLOW}⚠️ The following will be removed${RESET}\n"
    echo "  ───────────────────────────────────────────────────────────"
    _pu_print_list "Packages" "$_pu_targets"
    _pu_print_list "Services" "$PURGE_SERVICES"
    _pu_print_list "UCI configs" "$PURGE_CONFIGS"
    echo "  ───────────────────────────────────────────────────────────"
    printf "  ${GRAY}LuCI index cache will be flushed and rpcd restarted.${RESET}\n"
    echo

    printf "  ⁉️ Proceed with this purge? [y/N]: "
    read -r _pu_confirm </dev/tty || return 1
    case "$_pu_confirm" in
        [yY]|[yY][eE][sS]) ;;
        *)
            log_info "Purge cancelled."
            return 1
            ;;
    esac

    echo
    log_info "── 1/4  Service termination"
    for _pu_svc in $PURGE_SERVICES; do
        log_info "Stopping and disabling [$_pu_svc] ..."
        if [ -x "/etc/init.d/$_pu_svc" ]; then
            /etc/init.d/"$_pu_svc" stop >/dev/null 2>&1 || true
            /etc/init.d/"$_pu_svc" disable >/dev/null 2>&1 || true
        fi
    done
    log_success "Service termination finished."

    echo
    log_info "── 2/4  Package removal ($PKG_MGR)"
    for _pu_pkg in $_pu_targets; do
        [ -n "$_pu_pkg" ] || continue
        log_info "Removing [$_pu_pkg] ..."
        case "$PKG_MGR" in
            apk)
                apk del "$_pu_pkg" >/dev/null 2>&1 || true
                ;;
            *)
                opkg remove --autoremove "$_pu_pkg" >/dev/null 2>&1 \
                    || opkg remove "$_pu_pkg" >/dev/null 2>&1 \
                    || true
                ;;
        esac
    done
    if [ "$PKG_MGR" = "apk" ] && command -v apk >/dev/null 2>&1; then
        apk autoremove >/dev/null 2>&1 || true
    fi
    log_success "Package removal finished."

    echo
    log_info "── 3/4  Config cleanup"
    for _pu_cfg in $PURGE_CONFIGS; do
        _pu_is_core_config "$_pu_cfg" && continue
        if [ -e "$_pu_cfg" ]; then
            log_info "Deleting [$_pu_cfg] ..."
            rm -f "$_pu_cfg" 2>/dev/null || true
        fi
    done
    log_success "Config cleanup finished."

    echo
    log_info "── 4/4  LuCI cache flush"
    rm -f /tmp/luci-indexcache* 2>/dev/null || true
    rm -rf /tmp/luci-modulecache 2>/dev/null || true
    if [ -x /etc/init.d/rpcd ]; then
        log_info "Restarting rpcd ..."
        /etc/init.d/rpcd restart >/dev/null 2>&1 || true
    fi
    if [ -x /etc/init.d/uhttpd ]; then
        /etc/init.d/uhttpd reload >/dev/null 2>&1 || true
    fi
    log_success "LuCI menus will refresh on the next page load."

    echo
    log_success "Purge completed."

    if [ -n "${PURGE_MODULE_ID:-}" ] && command -v mf_unregister_module >/dev/null 2>&1; then
        _pu_left="$(mf_module_packages "$PURGE_MODULE_ID")"
        _pu_still=""
        for _pu_pkg in $_pu_left; do
            _pu_in_words "$_pu_pkg" "$_pu_targets" && continue
            _pu_still="${_pu_still:+$_pu_still }$_pu_pkg"
        done
        if [ -z "$_pu_still" ]; then
            mf_unregister_module "$PURGE_MODULE_ID"
        else
            mf_drop_packages "$PURGE_MODULE_ID" "$_pu_targets"
        fi
        mf_sync_install_log
        PURGE_MODULE_ID=""
    elif command -v mf_drop_packages_from_all >/dev/null 2>&1; then
        mf_drop_packages_from_all "$_pu_targets"
    else
        _pu_logf="$(_pu_tracked_file)"
        if [ -f "$_pu_logf" ]; then
            _pu_keep=""
            while IFS= read -r _pu_line || [ -n "$_pu_line" ]; do
                [ -n "$_pu_line" ] || continue
                _pu_in_words "$_pu_line" "$_pu_targets" && continue
                _pu_keep="${_pu_keep:+$_pu_keep
}$_pu_line"
            done < "$_pu_logf"
            if [ -n "$_pu_keep" ]; then
                printf '%s\n' "$_pu_keep" | sort -u > "$_pu_logf"
            else
                rm -f "$_pu_logf"
            fi
        fi
    fi

    return 0
}

# ------------------------------------------------------------
# Multi-select a subset of a package list
# ------------------------------------------------------------
_pu_pick_packages() {
    _pu_pool="$1"
    _pu_n="$(_pu_count_words "$_pu_pool")"
    [ "$_pu_n" -gt 0 ] || return 1

    echo
    printf "  ${BOLD}Select packages to remove${RESET}\n"
    echo "  ───────────────────────────────────────────────────────────"
    _pu_i=0
    for _pu_pkg in $_pu_pool; do
        _pu_i=$((_pu_i + 1))
        printf "  ${CYAN}%s${RESET}) %s\n" "$_pu_i" "$_pu_pkg"
    done
    echo "  ───────────────────────────────────────────────────────────"
    printf "  ${GRAY}Numbers separated by spaces, [a] all, [0] cancel${RESET}\n"
    printf "  ⁉️ Selection : "
    read -r _pu_sel </dev/tty || return 1

    case "$_pu_sel" in
        ''|0) return 1 ;;
        a|A)
            PURGE_SELECTION="$_pu_pool"
            return 0
            ;;
    esac

    PURGE_SELECTION=""
    for _pu_tok in $_pu_sel; do
        case "$_pu_tok" in
            *[!0-9]*) continue ;;
        esac
        [ "$_pu_tok" -ge 1 ] && [ "$_pu_tok" -le "$_pu_n" ] || continue
        _pu_i=0
        for _pu_pkg in $_pu_pool; do
            _pu_i=$((_pu_i + 1))
            if [ "$_pu_i" -eq "$_pu_tok" ]; then
                _pu_in_words "$_pu_pkg" "$PURGE_SELECTION" || \
                    PURGE_SELECTION="${PURGE_SELECTION:+$PURGE_SELECTION }$_pu_pkg"
                break
            fi
        done
    done

    [ -n "$PURGE_SELECTION" ]
}

_pu_category_menu() {
    _pu_id="$1"
    _pu_title="$2"
    _pu_pkgs="$3"

    while true; do
        render_persistent_header
        printf "  🧹 ${BOLD}%s${RESET}\n" "$_pu_title"
        echo "  ───────────────────────────────────────────────────────────"
        [ -n "$_pu_id" ] && command -v mf_module_category >/dev/null 2>&1 && \
            printf "  ${GRAY}Category : %s${RESET}\n" "$(mf_module_category "$_pu_id")"
        for _pu_pkg in $_pu_pkgs; do
            printf "    • %s\n" "$_pu_pkg"
        done
        echo "  ───────────────────────────────────────────────────────────"
        printf "  ${CYAN}1${RESET}) Purge this entire module\n"
        printf "  ${CYAN}2${RESET}) Choose individual packages\n"
        ui_nav_footer
        ui_prompt 2

        case "$UI_CHOICE" in
            1)
                PURGE_MODULE_ID="$_pu_id"
                purge_packages "$_pu_pkgs"
                PURGE_MODULE_ID=""
                return 0
                ;;
            2)
                if _pu_pick_packages "$_pu_pkgs"; then
                    PURGE_MODULE_ID="$_pu_id"
                    purge_packages "$PURGE_SELECTION"
                    PURGE_MODULE_ID=""
                    return 0
                fi
                ;;
            0) return 0 ;;
            *)
                ui_nav_common "$UI_CHOICE" "system" && continue
                log_warn "Invalid option!"
                sleep 1
                ;;
        esac
    done
}

# ------------------------------------------------------------
# Interactive purge (maintenance menu option 1)
# ------------------------------------------------------------
purge_menu() {
    command -v mf_migrate_from_log >/dev/null 2>&1 && mf_migrate_from_log >/dev/null 2>&1 || true

    while true; do
        render_persistent_header
        printf "  🧹 ${BOLD}Purge DayPass Installed Modules${RESET}\n"
        echo "  ───────────────────────────────────────────────────────────"

        _pu_ids=""
        if command -v mf_has_modules >/dev/null 2>&1 && mf_has_modules; then
            _pu_ids=$(mf_module_ids)
        fi

        if [ -z "$_pu_ids" ]; then
            if ! _pu_tracked_pkgs >/dev/null; then
                log_warn "No installed modules recorded in [$(mf_path 2>/dev/null || echo /etc/daypass/installed_manifest.json)]"
                return 0
            fi
            _pu_groups="/tmp/daypass_purge_groups.$$"
            if ! _pu_build_groups "$_pu_groups"; then
                log_warn "No tracked packages to purge!"
                rm -f "$_pu_groups"
                return 0
            fi
            _pu_all=""
            _pu_idx=0
            while IFS='|' read -r _pu_id _pu_title _pu_pkgs; do
                _pu_idx=$((_pu_idx + 1))
                printf "  ${CYAN}%s${RESET}) %s ${GRAY}(%s)${RESET}\n" \
                    "$_pu_idx" "$_pu_title" "$(_pu_count_words "$_pu_pkgs")"
                _pu_all="${_pu_all:+$_pu_all }$_pu_pkgs"
            done < "$_pu_groups"
            _pu_cats="$_pu_idx"
            _pu_all_n=$((_pu_cats + 1))
            printf "  ${CYAN}%s${RESET}) Purge ALL DayPass-installed packages\n" "$_pu_all_n"
            ui_nav_footer
            ui_prompt "$_pu_all_n"
            case "$UI_CHOICE" in
                0) rm -f "$_pu_groups"; return 0 ;;
                q|Q) rm -f "$_pu_groups"; daypass_quit ;;
                h|H) ui_show_help "system"; continue ;;
            esac
            if [ "$UI_CHOICE" = "$_pu_all_n" ]; then
                PURGE_MODULE_ID=""
                purge_packages "$_pu_all"
            elif [ "$UI_CHOICE" -ge 1 ] 2>/dev/null && [ "$UI_CHOICE" -le "$_pu_cats" ]; then
                _pu_line="$(sed -n "${UI_CHOICE}p" "$_pu_groups")"
                _pu_id="${_pu_line%%|*}"
                _pu_rest="${_pu_line#*|}"
                _pu_title="${_pu_rest%%|*}"
                _pu_pkgs="${_pu_rest#*|}"
                _pu_category_menu "$_pu_id" "$_pu_title" "$_pu_pkgs"
            else
                log_warn "Invalid option!"
                sleep 1
            fi
            rm -f "$_pu_groups"
            continue
        fi

        _pu_idx=0
        _pu_all=""
        for _pu_id in $_pu_ids; do
            _pu_idx=$((_pu_idx + 1))
            _pu_pkgs="$(mf_module_packages "$_pu_id")"
            _pu_n="$(_pu_count_words "$_pu_pkgs")"
            printf "  ${CYAN}%s${RESET}) %s ${GRAY}[%s] — %s package(s)${RESET}\n" \
                "$_pu_idx" "$(mf_module_title "$_pu_id")" "$(mf_module_category "$_pu_id")" "$_pu_n"
            _pu_all="${_pu_all:+$_pu_all }$_pu_pkgs"
        done

        _pu_cats="$_pu_idx"
        _pu_all_n=$((_pu_cats + 1))
        _pu_pick_n=$((_pu_cats + 2))
        printf "  ${CYAN}%s${RESET}) Purge ALL recorded modules\n" "$_pu_all_n"
        printf "  ${CYAN}%s${RESET}) Choose individual packages\n" "$_pu_pick_n"
        ui_nav_footer
        ui_prompt "$_pu_pick_n"

        case "$UI_CHOICE" in
            0) return 0 ;;
            q|Q) daypass_quit ;;
            h|H) ui_show_help "system"; continue ;;
        esac

        case "$UI_CHOICE" in
            *[!0-9]*|'') log_warn "Invalid option!"; sleep 1; continue ;;
        esac

        if [ "$UI_CHOICE" -eq "$_pu_all_n" ]; then
            for _pu_id in $_pu_ids; do
                PURGE_MODULE_ID="$_pu_id"
                purge_packages "$(mf_module_packages "$_pu_id")" || true
            done
            PURGE_MODULE_ID=""
            continue
        fi

        if [ "$UI_CHOICE" -eq "$_pu_pick_n" ]; then
            if _pu_pick_packages "$_pu_all"; then
                PURGE_MODULE_ID=""
                purge_packages "$PURGE_SELECTION"
            fi
            continue
        fi

        if [ "$UI_CHOICE" -ge 1 ] && [ "$UI_CHOICE" -le "$_pu_cats" ]; then
            _pu_n=0
            for _pu_id in $_pu_ids; do
                _pu_n=$((_pu_n + 1))
                if [ "$_pu_n" -eq "$UI_CHOICE" ]; then
                    _pu_category_menu "$_pu_id" "$(mf_module_title "$_pu_id")" "$(mf_module_packages "$_pu_id")"
                    break
                fi
            done
            continue
        fi

        log_warn "Invalid option!"
        sleep 1
    done
}

# Backwards-compatible name used by the maintenance menu
purge_daypass_packages() {
    purge_menu
}


# 📄 Source : state.sh

SELECTED_PROFILE=""
SELECTED_ENGINE="auto"
SELECTED_LANGUAGE="none"
SELECTED_GEO="none"
SELECTED_PACKAGES=""
GEOIP_URL=""
GEOSITE_URL=""

add_selected_package()
{
    pkg="$1"
    [ -z "$pkg" ] && return

    case " $SELECTED_PACKAGES " in
        *" $pkg "*) ;;
        *) SELECTED_PACKAGES="$SELECTED_PACKAGES $pkg" ;;
    esac
}

reset_state()
{
    SELECTED_PROFILE=""
    SELECTED_ENGINE="auto"
    SELECTED_LANGUAGE="none"
    SELECTED_GEO="none"
    SELECTED_PACKAGES=""
    GEOIP_URL=""
    GEOSITE_URL=""
}

# 📄 Source : custom.sh

show_custom_help()
{
    render_persistent_header
    echo "  📖 ${BOLD}Custom Selection Guide & Keyboard Shortcuts${RESET}"
    echo "  ──────────────────────────────────────────────────────────"
    echo "  🔹 ${YELLOW}Toggle Item (1-6):${RESET} Enter item number to Select [✔] or Deselect [ ]."
    echo "  🔹 ${YELLOW}Language Notice:${RESET} Selecting a new language (e.g. -fa) automatically"
    echo "     replaces previously selected translations for clean config."
    echo "  🔹 ${YELLOW}[n] / [p]:${RESET} Navigate to Next or Previous page."
    echo "  🔹 ${YELLOW}[d]:${RESET} Save your current selection and proceed to Review."
    _nav_muted="${COLOR_MUTED:-$GRAY}"
    printf "  ${_nav_muted}0) Back / Skip${RESET}\n"
    printf "  ${_nav_muted}q) Quit DayPass${RESET}\n"
    echo "  ──────────────────────────────────────────────────────────"
    echo "  💡 ${CYAN}Pro-Tip:${RESET} Combining Sing-box and Xray together is supported,"
    echo "     but recommended mainly for powerful hardware (ARM64 / x86)."
    echo "  ──────────────────────────────────────────────────────────"
    echo
    printf "  ${GRAY}Press [ENTER] to return to selection menu ...${RESET}"
    read -r _ </dev/tty || daypass_quit
}

toggle_custom_package()
{
    pkg_to_toggle="$1"

    case "$pkg_to_toggle" in
        luci-i18n-passwall*-*)
            base_prefix=$(echo "$pkg_to_toggle" | sed -E 's/-(fa|ru|zh-cn|zh-tw|en)$//')
            NEW_SEL=""
            for p in $SELECTED_PACKAGES; do
                case "$p" in
                    ${base_prefix}-*) ;;
                    *) NEW_SEL="$NEW_SEL $p" ;;
                esac
            done
            SELECTED_PACKAGES="$NEW_SEL"
            ;;
    esac

    if echo " $SELECTED_PACKAGES " | grep -q " $pkg_to_toggle "; then
        NEW_SEL=""
        for p in $SELECTED_PACKAGES; do
            [ "$p" != "$pkg_to_toggle" ] && NEW_SEL="$NEW_SEL $p"
        done
        SELECTED_PACKAGES="$NEW_SEL"
        log_info "Removed package : [$pkg_to_toggle]"
    else
        SELECTED_PACKAGES="$SELECTED_PACKAGES $pkg_to_toggle"
        log_success "Selected package: [$pkg_to_toggle]"

        if [ "$pkg_to_toggle" = "sing-box" ] || [ "$pkg_to_toggle" = "xray-core" ]; then
            case "${ARCH:-}" in
                *mips*|*ramips*|*aarch64_cortex-a53*)
                    echo
                    log_warn "⚠️ PERFORMANCE NOTICE : Engine [$pkg_to_toggle] on architecture [$ARCH]"
                    log_warn "Running heavy proxy engines alongside Passwall on low-resource hardware may cause high CPU/RAM usage!"
                    sleep 1
                    ;;
            esac
        fi
    fi

    SELECTED_PACKAGES=$(echo "$SELECTED_PACKAGES" | xargs)
    export SELECTED_PACKAGES
}

handle_custom_profile()
{
    if [ -z "$MANIFEST_FILE" ] || [ ! -f "$MANIFEST_FILE" ]; then
        if [ -f "/tmp/manifest.json" ]; then
            MANIFEST_FILE="/tmp/manifest.json"
        elif [ -f "manifest.json" ]; then
            MANIFEST_FILE="manifest.json"
        else
            OW_VER="25"
            [ "${PKG_MANAGER:-opkg}" = "opkg" ] && OW_VER="24"
            MANIFEST_FILE="build-artifacts/v${OW_VER}/manifest.json"
        fi
    fi

    TARGET_PROFILE="${SELECTED_PROFILE:-passwall2}"

    if [ "$TARGET_PROFILE" = "passwall" ]; then
        ALL_AVAILABLE_PKGS="$(jq -r --arg arch "$ARCH" \
            '.architectures[] | select(.name==$arch) | (.feeds["passwall_luci"][]?.package, .feeds["passwall_packages"][]?.package)' \
            "$MANIFEST_FILE" 2>/dev/null | sort -u)"
    else
        ALL_AVAILABLE_PKGS="$(jq -r --arg arch "$ARCH" \
            '.architectures[] | select(.name==$arch) | (.feeds["passwall2"][]?.package, .feeds["passwall_packages"][]?.package)' \
            "$MANIFEST_FILE" 2>/dev/null | sort -u)"
    fi

    if [ -z "$ALL_AVAILABLE_PKGS" ]; then
        log_error "No packages found in manifest [$MANIFEST_FILE] for architecture : [$ARCH]"
        return 1
    fi

    PAGE_SIZE=6
    CURRENT_PAGE=1
    
    set -- $ALL_AVAILABLE_PKGS
    TOTAL_PKGS=$#
    TOTAL_PAGES=$(( (TOTAL_PKGS + PAGE_SIZE - 1) / PAGE_SIZE ))
    
    FIRST_RENDER=1

    while true; do
        render_persistent_header

        SEL_COUNT=0
        for _p in $SELECTED_PACKAGES; do
            SEL_COUNT=$((SEL_COUNT + 1))
        done

        echo "  🛠️ ${BOLD}Custom Package Selection${RESET} ${GRAY}(Page ${YELLOW}$CURRENT_PAGE${RESET}${GRAY}/$TOTAL_PAGES | Selected : ${GREEN}$SEL_COUNT${RESET}${GRAY})${RESET}"
        echo "  ${GRAY}──────────────────────────────────────────────────────────${RESET}"

        START_IDX=$(( (CURRENT_PAGE - 1) * PAGE_SIZE + 1 ))
        END_IDX=$(( CURRENT_PAGE * PAGE_SIZE ))

        item_no=1
        curr_idx=1
        
        for pkg in "$@"; do
            if [ "$curr_idx" -ge "$START_IDX" ] && [ "$curr_idx" -le "$END_IDX" ]; then
                
                is_selected="${GRAY}[ ]${RESET}"
                case " $SELECTED_PACKAGES " in
                    *" $pkg "*) is_selected="${GREEN}[✔]${RESET}" ;;
                esac
                
                printf "   ${CYAN}%d${RESET}) %b %s\n" "$item_no" "$is_selected" "$pkg"
                
                if [ "$FIRST_RENDER" -eq 1 ]; then
                    command -v usleep >/dev/null 2>&1 && usleep 12000
                fi

                item_no=$((item_no + 1))
            fi
            curr_idx=$((curr_idx + 1))
        done

        FIRST_RENDER=0

        _nav_muted="${COLOR_MUTED:-$GRAY}"
        printf "  ${_nav_muted}n) Next page${RESET}\n"
        printf "  ${_nav_muted}p) Previous page${RESET}\n"
        printf "  ${_nav_muted}d) Save and continue${RESET}\n"
        if command -v ui_nav_footer >/dev/null 2>&1; then
            ui_nav_footer
        fi

        printf "  ⁉️ Toggle item [1-%s] : " "$((item_no - 1))"
        read -r cmd </dev/tty || daypass_quit

        case "$cmd" in
            n|N)
                [ "$CURRENT_PAGE" -lt "$TOTAL_PAGES" ] && CURRENT_PAGE=$((CURRENT_PAGE + 1))
                ;;
            p|P)
                [ "$CURRENT_PAGE" -gt 1 ] && CURRENT_PAGE=$((CURRENT_PAGE - 1))
                ;;
            h|H)
                show_custom_help
                ;;
            q|Q)
                daypass_quit
                ;;
            0)
                log_warn "Custom selection cancelled."
                SELECTED_PACKAGES=""
                return 1
                ;;
            d|D)
                if [ -z "$SELECTED_PACKAGES" ]; then
                    log_warn "No packages selected! Please select at least one package!"
                    sleep 1
                else
                    log_info "Custom package selection saved!"
                    break
                fi
                ;;
            [1-9])
                if [ "$cmd" -ge 1 ] && [ "$cmd" -lt "$item_no" ]; then
                    TARGET_INDEX=$(( START_IDX + cmd - 1 ))
                    idx=1
                    for pkg in "$@"; do
                        if [ "$idx" -eq "$TARGET_INDEX" ]; then
                            toggle_custom_package "$pkg"
                            break
                        fi
                        idx=$((idx + 1))
                    done
                else
                    log_warn "Invalid selection range!"
                    sleep 1
                fi
                ;;
            *)
                log_warn "Invalid command!"
                sleep 1
                ;;
        esac
    done
}

# 📄 Source : mode.sh

handle_recommended_profile()
{
    SELECTED_PACKAGES=""
    export SELECTED_PACKAGES
}

menu_mode()
{
    render_persistent_header

    echo "  🕵️‍♀️ Select Installation Mode                                "
    echo "  ───────────────────────────────────────────────────────────"
    echo "  1) ⚡ Recommended (Quick & Pre-configured for users)       "
    echo "  2) 🛠️ Custom      (Advanced package selection)             "
    echo "  ───────────────────────────────────────────────────────────"
    ui_nav_footer

    ui_prompt 2
    choice="$UI_CHOICE"

    case "$choice" in
        0)
            return 1
            ;;
        q|Q)
            daypass_quit
            ;;
        h|H)
            ui_show_help "packages"
            menu_mode
            return
            ;;
        1|"")
            SELECTED_MODE="recommended"  
            export SELECTED_MODE
            handle_recommended_profile
            ;;
        2)
            SELECTED_MODE="custom"       
            export SELECTED_MODE
            handle_custom_profile || return 1
            ;;
        *)
            log_warn "Invalid choice! Defaulting to Recommended mode!"
            SELECTED_MODE="recommended"   
            export SELECTED_MODE
            handle_recommended_profile
            ;;
    esac
}

# 📄 Source : engine.sh

engine_menu()
{
    render_persistent_header

    echo "  🕵️‍♀️ Select Proxy Engine                                    "
    echo "  ───────────────────────────────────────────────────────── "
    echo "  1) ⚡ Auto      (Recommended)                             "
    echo "  2) ✖️ Xray      (Xray-core proxy engine)                  "
    echo "  3) 📦 Sing-box  (Sing-box proxy engine)                   "
    echo "  ───────────────────────────────────────────────────────── "
    echo

    if command -v ui_nav_footer >/dev/null 2>&1; then
        ui_nav_footer
    fi
    printf "  ⁉️ Select option [1-3] : "
    read -r choice </dev/tty

    case "$choice" in
        0) return 0 ;;
        q|Q) command -v daypass_quit >/dev/null 2>&1 && daypass_quit; return 0 ;;
        h|H) command -v ui_show_help >/dev/null 2>&1 && ui_show_help "packages"; engine_menu; return ;;
        1|"")
            SELECTED_ENGINE="auto"
            ;;
        2)
            SELECTED_ENGINE="xray"
            add_selected_package "xray-core"
            ;;
        3)
            SELECTED_ENGINE="sing-box"
            echo
            log_warn "Sing-box may consume higher RAM on low-end hardware!"
            echo
            printf "  ⁉️  Are you sure you want to proceed with Sing-box? [y/N] : "
            read -r confirm </dev/tty

            case "$confirm" in
                y|Y)
                    add_selected_package "sing-box"
                    ;;
                *)
                    log_info "Reverting Proxy Engine selection to Auto!"
                    SELECTED_ENGINE="auto"
                    ;;
            esac
            ;;
        *)
            log_warn "Invalid choice! Defaulting to Auto engine!"
            SELECTED_ENGINE="auto"
            ;;
    esac

    export SELECTED_ENGINE
}

# 📄 Source : language.sh

language_menu()
{
    if [ "$SELECTED_PROFILE" != "passwall2" ]; then
        SELECTED_LANGUAGE="en"
        export SELECTED_LANGUAGE
        return 0
    fi

    render_persistent_header

    echo "  🕵️‍♀️ Select Language (Passwall 2)                             "
    echo "  ─────────────────────────────────────────────────────────── "
    echo "  1) 🦁☀️ Persian  (fa)                                       "
    echo "  2) 🇬🇧   English  (en)                                       "
    echo "  3) 🇨🇳   Chinese  (zh)                                       "
    echo "  4) 🇷🇺   Russian  (ru)                                       "
    echo "  ─────────────────────────────────────────────────────────── "
    echo

    if command -v ui_nav_footer >/dev/null 2>&1; then
        ui_nav_footer
    fi
    printf "  ⁉️ Select option [1-4] : "
    read -r choice </dev/tty

    case "$choice" in
        0) return 0 ;;
        q|Q) command -v daypass_quit >/dev/null 2>&1 && daypass_quit; return 0 ;;
        h|H) command -v ui_show_help >/dev/null 2>&1 && ui_show_help "packages"; language_menu; return ;;
        1|"")
            SELECTED_LANGUAGE="fa"
            add_selected_package "luci-i18n-passwall2-fa"
            ;;
        2)
            SELECTED_LANGUAGE="en"
            ;;
        3)
            SELECTED_LANGUAGE="zh-cn"
            add_selected_package "luci-i18n-passwall2-zh-cn"
            ;;
        4)
            SELECTED_LANGUAGE="ru"
            add_selected_package "luci-i18n-passwall2-ru"
            ;;
        *)
            log_warn "Invalid choice! Defaulting to English."
            SELECTED_LANGUAGE="en"
            ;;
    esac

    export SELECTED_LANGUAGE
}

# 📄 Source : geo.sh

geo_menu()
{
    render_persistent_header

    echo "  🕵️‍♀️ Select Geo Database                                      "
    echo "  ─────────────────────────────────────────────────────────── "
    echo "  🫸🏻 1) Skip       (Do not install Geo databases)             "
    echo "  👔 2) Official   (Standard official release packages)       "
    echo "  🍺 3) Iran Full  (Custom ruleset - Full database)           "
    echo "  🍷 4) Iran Lite  (Custom ruleset - Compact database)        "
    echo "  ─────────────────────────────────────────────────────────── "
    echo

    if command -v ui_nav_footer >/dev/null 2>&1; then
        ui_nav_footer
    fi
    printf "  ⁉️ Select option [1-4] : "
    read -r choice </dev/tty

    GEOIP_URL=""
    GEOSITE_URL=""

    case "$choice" in
        0) return 0 ;;
        q|Q) command -v daypass_quit >/dev/null 2>&1 && daypass_quit; return 0 ;;
        h|H) command -v ui_show_help >/dev/null 2>&1 && ui_show_help "packages"; geo_menu; return ;;
        1|"")
            SELECTED_GEO="none"
            ;;
        2)
            SELECTED_GEO="official"
            if [ "${PKG_MANAGER:-opkg}" = "apk" ]; then
                add_selected_package "geosite" 2>/dev/null || add_selected_package "v2ray-geosite"
                add_selected_package "geoip" 2>/dev/null || add_selected_package "v2ray-geoip"
            else
                add_selected_package "v2ray-geoip"
                add_selected_package "v2ray-geosite"
            fi
            ;;
        3)
            SELECTED_GEO="iran-full"
            GEOIP_URL="https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geoip.dat"
            GEOSITE_URL="https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geosite.dat"
            ;;
        4)
            SELECTED_GEO="iran-lite"
            GEOIP_URL="https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geoip-lite.dat"
            GEOSITE_URL="https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geosite-lite.dat"
            ;;
        *)
            log_warn "Invalid choice! Defaulting to Skip!"
            SELECTED_GEO="none"
            ;;
    esac

    export SELECTED_GEO
    export GEOIP_URL
    export GEOSITE_URL
}

# 📄 Source : review.sh

review_install()
{
    if ! resolve_packages; then
        log_error "Failed to resolve final package list!"
        sleep 2
        return 1
    fi

    render_persistent_header

    _rv_title="${SELECTED_PROFILE:-DayPass}"
    command -v mf_title_for >/dev/null 2>&1 && _rv_title="$(mf_title_for "${SELECTED_PROFILE:-proxy}")"

    echo "  📊 ${_rv_title} — Installation Plan"
    echo "  ─────────────────────────────────────────────────────────────"
    printf "  👤 %-18s : %s\n" "Module" "${SELECTED_PROFILE:-N/A}"
    command -v mf_category_for >/dev/null 2>&1 && \
        printf "  📂 %-18s : %s\n" "Category" "$(mf_category_for "${SELECTED_PROFILE:-proxy}")"
    printf "  🛠️ %-18s : %s\n" "Installation Mode" "${SELECTED_MODE:-recommended}"
    printf "  ⚙️ %-18s : %s\n" "Proxy Engine"    "${SELECTED_ENGINE:-xray}"
    
    if [ "${SELECTED_MODE:-}" = "recommended" ]; then
        printf "  🗣️ %-18s : %s\n" "Language"        "${SELECTED_LANGUAGE:-fa}"
        printf "  🌐 %-18s : %s\n" "Geo Database"     "${SELECTED_GEO:-official}"
    fi
    echo "  ─────────────────────────────────────────────────────────────"

    PKG_COUNT=$(echo $FINAL_PACKAGES | wc -w | tr -d ' ')
    echo "  📦 Targeted Packages (${PKG_COUNT:-0}) :"

    i=0
    for pkg in $FINAL_PACKAGES; do
        i=$((i + 1))
        if [ "$i" -eq "$PKG_COUNT" ]; then
            echo "     └─ 🔹 ${CYAN}$pkg${RESET}"
        else
            echo "     ├─ 🔹 ${CYAN}$pkg${RESET}"
        fi
    done
    echo "  ─────────────────────────────────────────────────────────────"
    echo

    while true; do
        if command -v ui_nav_footer >/dev/null 2>&1; then
            ui_nav_footer
        fi
        ui_read "Proceed with deployment? [Y/n]"
        confirm="$UI_CHOICE"

        case "$confirm" in
            y|Y|"")
                return 0
                ;;
            q|Q)
                daypass_quit
                ;;
            n|N|0)
                log_warn "Installation cancelled by user!"
                FINAL_PACKAGES=""
                export FINAL_PACKAGES
                sleep 1
                clear
                return 1
                ;;
            *)
                log_error "Invalid input! Please enter Y, N or 0."
                ;;
        esac
    done
}

# 📄 Source : packages.sh
# ============================================================
# DayPass - Package Profiles & Dependencies
# ============================================================

# Proxy stack wizard: Passwall app -> mode -> review -> deploy
proxy_install_wizard()
{
    render_persistent_header

    ui_title "🕵️‍♀️ Select Package Type"
    echo "  🔒 1) Passwall-1  (Legacy Stable Release)"
    echo "  🔒 2) Passwall-2  (Modern Release - Recommended)"
    echo "  ───────────────────────────────────────────────────────────"
    ui_nav_footer

    ui_prompt 2

    SELECTED_PACKAGES=""

    case "$UI_CHOICE" in
        1)
            SELECTED_PROFILE="passwall"
            ;;
        2)
            SELECTED_PROFILE="passwall2"
            ;;
        0)
            return 0
            ;;
        *)
            ui_nav_common "$UI_CHOICE" "packages" && return 0
            log_error "Invalid choice! Returning to menu ..."
            sleep 1
            return 1
            ;;
    esac

    export SELECTED_PROFILE

    # 1. Select Mode (Recommended or Custom)
    menu_mode || return 0

    # 2. Set environment vars based on Mode
    if [ "${SELECTED_MODE:-}" = "recommended" ]; then
        SELECTED_ENGINE="xray"
        SELECTED_LANGUAGE="fa"
        SELECTED_GEO="official"
        export SELECTED_ENGINE SELECTED_LANGUAGE SELECTED_GEO
    else
        SELECTED_ENGINE="custom"
        SELECTED_LANGUAGE="auto-detected"
        SELECTED_GEO="auto-detected"
        export SELECTED_ENGINE SELECTED_LANGUAGE SELECTED_GEO
    fi

    # 3. Review Summary Screen
    review_install || return 0

    # 4. Deployment Pipeline
    render_persistent_header
    if deploy_targeted_packages; then
        echo
        log_success "All targeted components deployed successfully!"

        if command -v system_banner_post_install >/dev/null 2>&1; then
            system_banner_post_install
        fi

        ui_pause
    else
        echo
        log_error "Installation process failed!"
        ui_pause
        return 1
    fi

    return 0
}

# Resolves a profile, shows a friendly plan and installs it after confirmation.
# $1 profile id from config/package_profiles.json
install_profile_interactive()
{
    local profile="$1"
    local count title rel_label

    render_persistent_header

    if ! command -v resolve_profile >/dev/null 2>&1; then
        log_error "Package resolver not loaded!"
        ui_pause
        return 1
    fi

    title="$(profile_display_title "$profile" 2>/dev/null || echo "$profile")"
    printf "  📦 ${BOLD}Profile Installation: %s${RESET}\n" "$title"
    echo "  ───────────────────────────────────────────────────────────"

    rel_label="${OPENWRT_MAJOR:-${PROFILE_RELEASE:-?}}"
    log_info "Resolving package dependencies for OpenWrt [${rel_label}.x]..."

    : > "${DAYPASS_RESOLVE_LOG:-/tmp/daypass_resolve.log}"
    DAYPASS_RESOLVE_QUIET=1
    export DAYPASS_RESOLVE_QUIET
    if ! resolve_profile "$profile"; then
        DAYPASS_RESOLVE_QUIET=0
        log_error "Could not build the package list for this profile."
        log_info "Details : ${DAYPASS_RESOLVE_LOG:-/tmp/daypass_resolve.log}"
        ui_pause
        return 1
    fi
    DAYPASS_RESOLVE_QUIET=0

    count=$(echo $PROFILE_PACKAGES | wc -w | tr -d ' ')
    log_success "Ready — ${count:-0} component(s) selected."

    render_persistent_header
    render_profile_plan "$profile"

    profile_install_prompt "$title" "${count:-0}"
    case "$UI_CHOICE" in
        ''|y|Y)
            ;;
        0|n|N)
            log_info "Installation cancelled."
            ui_pause
            return 0
            ;;
        q|Q)
            daypass_quit
            ;;
        *)
            log_warn "Please answer Y or n."
            ui_pause
            return 0
            ;;
    esac

    echo
    DAYPASS_RESOLVE_QUIET=1
    DAYPASS_INSTALL_UI=1
    export DAYPASS_RESOLVE_QUIET DAYPASS_INSTALL_UI
    install_profile "$profile"
    _ip_rc=$?
    DAYPASS_RESOLVE_QUIET=0
    DAYPASS_INSTALL_UI=0
    export DAYPASS_RESOLVE_QUIET DAYPASS_INSTALL_UI
    echo
    ui_pause
    return "$_ip_rc"
}

packages_menu()
{
    local HELP_MODULE_ID="packages"

    while true; do
        render_persistent_header

        ui_title "📦 Package Profiles & Dependencies"
        echo "  🛡️ 1) Proxy & Evasion Cores"
        echo "  🔐 2) VPN & Tunnels"
        echo "  🔌 3) USB & Hardware Drivers"
        echo "  📈 4) Network Tools & Traffic"
        echo "  🔄 5) Check & Update Installed Packages"
        echo "  📋 6) Profile Status Dashboard"
        ui_nav_footer main

        ui_prompt 6

        case "$UI_CHOICE" in
            1) ui_run proxy_install_wizard "Proxy installer" ;;
            2) install_profile_interactive vpn ;;
            3) install_profile_interactive usb ;;
            4) install_profile_interactive network_tools ;;
            5) ui_run update_packages_menu "Update" ;;
            6) ui_run profile_status_dashboard "Profile dashboard" ;;
            0) return 0 ;;
            *)
                ui_nav_common "$UI_CHOICE" "$HELP_MODULE_ID" && continue
                log_warn "Invalid option!"
                sleep 1
                ;;
        esac
    done
}


# 📄 Source : hardware.sh
# ============================================================
# DayPass - Hardware & USB Tethering Manager
# USB phones (RNDIS / CDC-Ether / NCM / iPhone), USB modems,
# ModeSwitch and WAN failover metrics.
# ============================================================

_hw_metric() {
    local m
    m=$(uci -q get network.$1.metric)
    echo "${m:-default}"
}

show_hardware_status() {
    local devices line dev driver kind state carrier ports iface

    ui_title "🔌 USB Devices"
    devices=$(usb_device_list 2>/dev/null)
    if [ -n "$devices" ]; then
        printf '%s\n' "$devices" | while IFS= read -r line; do
            printf "  • %s\n" "$line"
        done
    else
        echo "  ${GRAY}No USB devices detected.${RESET}"
    fi
    command -v lsusb >/dev/null 2>&1 || echo "  ${GRAY}(lsusb missing, read from sysfs; install the USB profile for usbutils)${RESET}"

    echo
    ui_title "📱 USB Network Interfaces"
    line=$(usb_net_interfaces 2>/dev/null)
    if [ -n "$line" ]; then
        printf '%s\n' "$line" | while IFS='|' read -r dev driver kind; do
            carrier=$(cat "/sys/class/net/$dev/operstate" 2>/dev/null)
            printf "  • %-8s %-14s ${GRAY}%-7s${RESET} link %s\n" "$dev" "$driver" "$kind" "${carrier:-unknown}"
        done
    else
        echo "  ${GRAY}None. Connect the phone and enable USB Tethering on it.${RESET}"
    fi

    ports=$(usb_modem_ports)
    [ -n "$ports" ] && printf "  📟 Modem ports : %s\n" "$ports"

    echo
    ui_title "🧭 WAN Failover (lower metric = preferred)"
    for iface in wan wan_usb wwan; do
        [ "$(uci -q get network.$iface)" = "interface" ] || continue
        if [ "$iface" = "wan_usb" ]; then
            state=$(usb_wan_state)
        elif [ "$(uci -q get network.$iface.disabled)" = "1" ]; then
            state="disabled"
        else
            state="enabled"
        fi
        printf "  • %-8s metric %-8s %s\n" "$iface" "$(_hw_metric "$iface")" "$state"
    done
    usb_wan_exists || echo "  ${GRAY}wan_usb not configured.${RESET}"
    if [ -f /etc/config/mwan3 ]; then
        echo "  ${GRAY}mwan3 is configured; its member metrics decide failover while it runs.${RESET}"
    fi
    echo "  ───────────────────────────────────────────────────────────"
}

# Sets HW_DEVICE to a tethering device picked by the user (empty = cancel)
_hw_pick_tether_device() {
    local list count i dev

    HW_DEVICE=""
    list=$(usb_tether_interfaces)
    count=$(printf '%s\n' "$list" | grep -c .)

    if [ "$count" -eq 0 ]; then
        log_warn "No tethering interface detected."
        ui_read "Device name [usb0]"
        case "$UI_CHOICE" in
            0) return 1 ;;
            q|Q) daypass_quit ;;
        esac
        HW_DEVICE="${UI_CHOICE:-usb0}"
        return 0
    fi

    if [ "$count" -eq 1 ]; then
        HW_DEVICE="$list"
        return 0
    fi

    i=1
    for dev in $list; do
        printf "  %s) %s (%s)\n" "$i" "$dev" "$(usb_net_driver "$dev")"
        i=$((i + 1))
    done
    ui_read "Select device [1-$count]"
    case "$UI_CHOICE" in
        0|'') return 1 ;;
        q|Q) daypass_quit ;;
    esac

    i=1
    for dev in $list; do
        [ "$UI_CHOICE" = "$i" ] && HW_DEVICE="$dev"
        i=$((i + 1))
    done
    [ -n "$HW_DEVICE" ] || { log_warn "Invalid option!"; return 1; }
}

hardware_setup_tethering() {
    if command -v usb_mtp_waiting >/dev/null 2>&1 && usb_mtp_waiting; then
        log_warn "Phone is in MTP mode. Enable USB Tethering on the phone first."
        ui_read "Create the WAN interface anyway? [y/N]"
        case "$UI_CHOICE" in
            y|Y) ;;
            q|Q) daypass_quit ;;
            *) return 0 ;;
        esac
    fi

    _hw_pick_tether_device || return 0

    ui_read "Route metric [${USB_WAN_DEFAULT_METRIC}]"
    case "$UI_CHOICE" in
        q|Q) daypass_quit ;;
        '') UI_CHOICE="$USB_WAN_DEFAULT_METRIC" ;;
        *[!0-9]*) log_warn "Invalid metric!"; return 0 ;;
    esac

    setup_usb_wan "$HW_DEVICE" "$UI_CHOICE"
}

hardware_toggle_tethering() {
    case "$(usb_wan_state)" in
        enabled)  usb_wan_set_enabled 0 ;;
        disabled) usb_wan_set_enabled 1 ;;
        *)        log_warn "USB WAN is not configured. Use option 1 first." ;;
    esac
}

hardware_failover_menu() {
    if command -v usb_metric_menu >/dev/null 2>&1; then
        usb_metric_menu
        return 0
    fi
    log_error "USB metric module not found!"
    return 1
}

hardware_modeswitch() {
    local list

    if ! command -v usbmode >/dev/null 2>&1; then
        log_warn "usbmode not found. Install the USB profile (option 7) for usb-modeswitch."
        return 0
    fi

    list=$(usbmode -l 2>/dev/null)
    if [ -z "$list" ]; then
        log_info "No USB device needs mode switching (modems in storage mode appear here)."
        return 0
    fi

    printf '%s\n' "$list" | sed 's/^/  • /'
    ui_read "Switch these devices to modem mode? [y/N]"
    case "$UI_CHOICE" in
        y|Y)
            if usbmode -s >/dev/null 2>&1; then
                log_success "ModeSwitch sent. Re-check status in a few seconds."
            else
                log_error "usbmode -s failed!"
            fi
            ;;
        q|Q) daypass_quit ;;
    esac
}

hardware_remove_tethering() {
    ui_read "Remove wan_usb? [y/N]"
    case "$UI_CHOICE" in
        y|Y) remove_usb_wan ;;
        q|Q) daypass_quit ;;
    esac
}

hardware_menu() {
    local HELP_MODULE_ID="hardware"

    if ! command -v usb_net_interfaces >/dev/null 2>&1; then
        log_error "USB WAN module not found!"
        sleep 2
        return 1
    fi

    while true; do
        render_persistent_header
        if command -v usb_render_dashboard >/dev/null 2>&1; then
            usb_render_dashboard
        else
            show_hardware_status
        fi
        ui_nav_footer main
        ui_read "Select option"

        case "$UI_CHOICE" in
            1) hardware_setup_tethering ;;
            2) hardware_toggle_tethering ;;
            3) hardware_failover_menu; continue ;;
            4) ui_run usb_driver_menu "USB Drivers"; continue ;;
            5)
                if command -v usb_restore_settings >/dev/null 2>&1; then
                    usb_restore_settings || true
                else
                    hardware_remove_tethering
                fi
                ;;
            6) hardware_modeswitch ;;
            7) continue ;;
            8) ui_run show_system_resources_menu "System Resources"; continue ;;
            0) return 0 ;;
            *)
                ui_nav_common "$UI_CHOICE" "$HELP_MODULE_ID" && continue
                log_warn "Invalid option!"
                sleep 1
                continue
                ;;
        esac

        ui_pause
    done
}


# 📄 Source : guest_network.sh

# Guest Sub-Menu (Network + QoS)

guest_menu() {
    local HELP_MODULE_ID="network_guest"

    while true; do
        render_persistent_header

        ui_title "👥 Guest Network Management"
        echo "  🍚 1) Setup Guest Network (Interface + Firewall)"
        echo "  🛜 2) Setup Guest WiFi"
        echo "  🛣️ 3) Bandwidth Control (QoS / SQM)"
        echo "  ❌ 4) Remove Guest Network"
        ui_nav_footer

        ui_prompt 4

        case "$UI_CHOICE" in
            1) ui_run setup_guest_network "Guest Network" ;;
            2) ui_run setup_guest_wifi "Guest WiFi" ;;
            3) ui_run guest_qos_menu "Guest QoS"; continue ;;
            4) ui_run remove_guest_network "Guest Network" ;;
            0) return 0 ;;
            *)
                ui_nav_common "$UI_CHOICE" "$HELP_MODULE_ID" && continue
                log_warn "Invalid option!"
                sleep 1
                continue
                ;;
        esac

        ui_pause
    done
}

# Main Network Menu

network_menu() {
    local HELP_MODULE_ID="network"

    while true; do
        render_persistent_header

        ui_title "🌐 Network & Routing Configuration"
        echo "  📡 1) Wi-Fi Access Point (Home WiFi)"
        echo "  👥 2) Guest Network & Bandwidth Control (QoS / SQM)"
        echo "  🏠 3) Change Local Router LAN IP"
        echo "  ⚖️ 4) Multi-WAN Load Balancer (mwan3)"
        echo "  📊 5) Network Info & Speed Monitor"
        echo "  🧭 6) DNS Manager (DNS modes)"
        ui_nav_footer main

        ui_prompt 6

        case "$UI_CHOICE" in
            1) ui_run wifi_ap_menu "WiFi Access Point (AP)" ;;
            2) guest_menu ;;
            3) ui_run change_lan_ip_menu "LAN IP" ;;
            4) ui_run load_balancer_menu "Load Balancer" ;;
            5) ui_run network_info_menu "Network Info" ;;
            6) ui_run dns_menu "DNS" ;;
            0) return 0 ;;
            *)
                ui_nav_common "$UI_CHOICE" "$HELP_MODULE_ID" && continue
                log_warn "Invalid option!"
                sleep 1
                ;;
        esac
    done
}


# 📄 Source : proxy_engine.sh
# ============================================================
# DayPass - Proxy & Tunnel Engine Manager
# Lists every transport engine known to the transport bridge
# (Passwall, Passwall2, sing-box, Xray, WireGuard, OpenVPN)
# and controls the installed ones.
# ============================================================

# Package profile that provides an engine (Package Profiles menu entry)
_pe_install_hint() {
    case "$1" in
        wireguard|openvpn) echo "Package Profiles -> 2 (VPN & Tunnels)" ;;
        *)                 echo "Package Profiles -> 1 (Proxy & Evasion Cores)" ;;
    esac
}

# Prints the engine table; numbers follow TRANSPORT_ENGINES order
show_transport_status() {
    local active engine i state intercept

    active=$(get_active_engine)
    ui_title "🚀 Transport Engines"

    i=1
    for engine in $TRANSPORT_ENGINES; do
        if ! transport_call "$engine" detect >/dev/null 2>&1; then
            printf "  ${GRAY}%s) %-24s not installed${RESET}\n" "$i" "$(transport_engine_label "$engine")"
            i=$((i + 1))
            continue
        fi

        intercept=$(transport_call "$engine" interception)
        if status_engine "$engine" >/dev/null 2>&1; then
            state="${GREEN}running${RESET}"
        else
            state="${YELLOW}stopped${RESET}"
        fi

        if [ "$engine" = "$active" ]; then
            printf "  %s) ${BOLD}%-24s${RESET} %b  ${GRAY}[%s]${RESET} ${GREEN}◀ active${RESET}\n" \
                "$i" "$(transport_engine_label "$engine")" "$state" "$intercept"
        else
            printf "  %s) %-24s %b  ${GRAY}[%s]${RESET}\n" \
                "$i" "$(transport_engine_label "$engine")" "$state" "$intercept"
        fi
        i=$((i + 1))
    done

    [ "$active" = "none" ] && echo "  ${GRAY}No supported engine detected.${RESET}"
    echo "  ───────────────────────────────────────────────────────────"
}

# Makes $1 the active engine, offers to stop the previous one and
# re-applies the saved routing mode to the new engine.
proxy_engine_activate() {
    local engine="$1"
    local previous

    previous=$(get_active_engine)
    set_active_engine "$engine" || return 1
    [ "$previous" = "$engine" ] && return 0

    if [ "$previous" != "none" ] && status_engine "$previous" >/dev/null 2>&1; then
        ui_read "Stop previous engine [$previous] to avoid double interception? [Y/n]"
        case "$UI_CHOICE" in
            n|N) log_warn "Both engines may intercept traffic until one is stopped." ;;
            q|Q) daypass_quit ;;
            *)   stop_engine "$previous" ;;
        esac
    fi

    if command -v routing_reapply >/dev/null 2>&1; then
        routing_reapply "$engine"
    fi
}

proxy_engine_show_nodes() {
    local engine="$1"
    local nodes current id name proto host port

    nodes=$(transport_call "$engine" list_nodes 2>/dev/null)
    if [ -z "$nodes" ]; then
        log_warn "No nodes / endpoints found in [$(transport_engine_label "$engine")]."
        return 0
    fi

    current=$(transport_call "$engine" active_node 2>/dev/null)
    echo
    ui_title "🧶 Nodes of $(transport_engine_label "$engine")"
    while IFS='|' read -r id name proto host port _; do
        [ -n "$id" ] || continue
        if [ "$id" = "$current" ]; then
            printf "  ${GREEN}◀${RESET} %s  ${GRAY}(%s %s%s)${RESET} ${GREEN}active${RESET}\n" "$name" "$proto" "$host" "${port:+:$port}"
        else
            printf "    %s  ${GRAY}(%s %s%s)${RESET}\n" "$name" "$proto" "$host" "${port:+:$port}"
        fi
    done << EOF
$nodes
EOF
    echo "  ───────────────────────────────────────────────────────────"
}

# Actions for one installed engine
proxy_engine_actions_menu() {
    local engine="$1"
    local HELP_MODULE_ID="proxy_transport"
    local label active status detail

    label=$(transport_engine_label "$engine")

    while true; do
        render_persistent_header

        active=$(get_active_engine)
        status=$(status_engine "$engine" 2>/dev/null)
        detail=$(transport_call "$engine" describe 2>/dev/null)

        ui_title "🛡️ $label"
        printf "  ⚙️ Status       : %s\n" "${status#*: }"
        printf "  🧭 Interception : %s\n" "$(transport_call "$engine" interception)"
        [ -n "$detail" ] && printf "  📄 Details      : ${GRAY}%s${RESET}\n" "$detail"
        if [ "$engine" = "$active" ]; then
            printf "  🎯 Active       : ${GREEN}yes${RESET}\n"
        else
            printf "  🎯 Active       : ${GRAY}no (active: %s)${RESET}\n" "$active"
        fi
        echo "  ───────────────────────────────────────────────────────────"
        echo "  🎯 1) Set as Active Engine"
        echo "  ▶️  2) Start"
        echo "  ⏹️  3) Stop"
        echo "  🔁 4) Restart"
        echo "  🔄 5) Reload Rules"
        echo "  🧶 6) Show Nodes / Endpoints"
        echo "  ───────────────────────────────────────────────────────────"
        ui_nav_footer

        ui_prompt 6

        case "$UI_CHOICE" in
            1) proxy_engine_activate "$engine" ;;
            2) start_engine "$engine" ;;
            3) stop_engine "$engine" ;;
            4) stop_engine "$engine"; start_engine "$engine" ;;
            5) reload_rules "$engine" ;;
            6) proxy_engine_show_nodes "$engine" ;;
            0) return 0 ;;
            *)
                ui_nav_common "$UI_CHOICE" "$HELP_MODULE_ID" && continue
                log_warn "Invalid option!"
                sleep 1
                continue
                ;;
        esac

        ui_pause
    done
}

proxy_engine_menu() {
    local HELP_MODULE_ID="proxy_transport"
    local count engine i picked

    if ! command -v get_active_engine >/dev/null 2>&1; then
        log_error "Transport bridge module not found!"
        sleep 2
        return 1
    fi

    set -- $TRANSPORT_ENGINES
    count=$#

    while true; do
        render_persistent_header
        show_transport_status
        echo "  ${GRAY}Pick an engine number to manage it.${RESET}"
        ui_nav_footer

        ui_prompt "$count"

        case "$UI_CHOICE" in
            0) return 0 ;;
            ''|*[!0-9]*)
                ui_nav_common "$UI_CHOICE" "$HELP_MODULE_ID" && continue
                log_warn "Invalid option!"
                sleep 1
                continue
                ;;
        esac

        picked=""
        i=1
        for engine in $TRANSPORT_ENGINES; do
            [ "$UI_CHOICE" = "$i" ] && picked="$engine"
            i=$((i + 1))
        done

        if [ -z "$picked" ]; then
            log_warn "Invalid option!"
            sleep 1
        elif ! transport_call "$picked" detect >/dev/null 2>&1; then
            log_warn "$(transport_engine_label "$picked") is not installed. Install it from : $(_pe_install_hint "$picked")"
            ui_pause
        else
            proxy_engine_actions_menu "$picked"
        fi
    done
}


# 📄 Source : proxy.sh

proxy_menu() {
    local HELP_MODULE_ID="proxy"
    local active

    while true; do
        render_persistent_header

        ui_title "🛡️ Proxy & Tunnel Engine Manager"
        if command -v get_active_engine >/dev/null 2>&1; then
            active=$(get_active_engine)
            if [ "$active" = "none" ]; then
                echo "  🎯 Active Engine : ${GRAY}none${RESET}"
            else
                echo "  🎯 Active Engine : ${GREEN}$(transport_engine_label "$active")${RESET}"
            fi
            echo "  ───────────────────────────────────────────────────────────"
        fi
        echo "  🚀 1) Transport Engines (Passwall, sing-box, Xray, WireGuard, OpenVPN)"
        echo "  🧶 2) Config Manager (Nodes & Subscriptions)"
        echo "  🚦 3) Traffic Routing / Shunt Rules"
        echo "  🎭 4) Routing Profiles"
        echo "  🧼 5) Clean IP Manager"
        ui_nav_footer main

        ui_prompt 5

        case "$UI_CHOICE" in
            1) ui_run proxy_engine_menu "Transport Engine" ;;
            2) ui_run config_manager_menu "Config Manager" ;;
            3) ui_run routing_menu "Routing" ;;
            4) ui_run profile_manager_menu "Profile Manager" ;;
            5) ui_run clean_ip_menu "Clean IP" ;;
            0) return 0 ;;
            *)
                ui_nav_common "$UI_CHOICE" "$HELP_MODULE_ID" && continue
                log_warn "Invalid option!"
                sleep 1
                ;;
        esac
    done
}


# 📄 Source : diagnostics.sh
# ============================================================
# DayPass - Node Balancer & Health Diagnostics
# ============================================================

diagnostics_menu() {
    local HELP_MODULE_ID="diagnostics"

    while true; do
        render_persistent_header

        ui_title "⚖️ Node Balancer & Health Diagnostics"
        if command -v show_balancer_status >/dev/null 2>&1; then
            show_balancer_status
        fi
        echo
        echo "  🧶 1) Node Balancer (select nodes, Active/Standby mode)"
        echo "  🏓 2) Probe Selected Nodes"
        echo "  🔥 3) Probe & Auto-Switch Now"
        echo "  🩺 4) Node Health Checker"
        echo "  🌍 5) Internet Connectivity Check"
        ui_nav_footer main

        ui_prompt 5

        case "$UI_CHOICE" in
            1) ui_run node_balancer_menu "Node Balancer"; continue ;;
            2) ui_run probe_selected_nodes "Node Balancer" ;;
            3) ui_run apply_balancer "Node Balancer" ;;
            4) ui_run health_checker_menu "Health Checker"; continue ;;
            5) ui_run network_check "Connectivity Check"; continue ;;
            0) return 0 ;;
            *)
                ui_nav_common "$UI_CHOICE" "$HELP_MODULE_ID" && continue
                log_warn "Invalid option!"
                sleep 1
                continue
                ;;
        esac

        ui_pause
    done
}


# 📄 Source : system.sh
# ============================================================
# DayPass - System Maintenance & Backup
# ============================================================

# $1 grep -iE filter (empty = all of logread)
_system_log_fetch() {
    local filter="$1"
    local lines="$2"
    local dest="$3"

    : > "$dest"
    if [ -n "$filter" ]; then
        logread 2>/dev/null | grep -iE "$filter" | tail -n "$lines" > "$dest" 2>/dev/null || true
    else
        logread 2>/dev/null | tail -n "$lines" > "$dest" 2>/dev/null || true
    fi
}

_system_log_render() {
    local filter="$1"
    local label="$2"
    local lines dest shown

    render_persistent_header
    ui_title "📜 Log Viewer — $label"
    printf "  ${GRAY}Source : logread${RESET}\n"
    echo "  ───────────────────────────────────────────────────────────"
    printf "  ⁉️ ${YELLOW}Number of lines${RESET} ${GRAY}[50] :${RESET} "

    if ! read -r UI_CHOICE </dev/tty; then
        UI_CHOICE=""
        daypass_quit
    fi

    case "$UI_CHOICE" in
        0) return 0 ;;
        q|Q) daypass_quit ;;
        ''|*[!0-9]*) lines=50 ;;
        *) lines="$UI_CHOICE" ;;
    esac
    [ "$lines" -gt 0 ] 2>/dev/null || lines=50

    dest="/tmp/daypass_logview.$$"
    _system_log_fetch "$filter" "$lines" "$dest"

    echo
    if [ ! -s "$dest" ]; then
        echo "  ───────────────────────────────────────────────────────────"
        if [ -n "$filter" ]; then
            log_warn "No log entries found for the selected module."
        else
            log_info "Log buffer is empty."
        fi
        echo "  ───────────────────────────────────────────────────────────"
    else
        shown=$(wc -l < "$dest" | tr -d ' ')
        printf "  ────── Log Output (Last %s lines) ──────\n" "$shown"
        sed 's/^/  /' "$dest"
        echo "  ───────────────────────────────────────────────────────────"
    fi

    rm -f "$dest" 2>/dev/null
}

system_log_viewer() {
    local HELP_MODULE_ID="system_menu"

    while true; do
        render_persistent_header

        if ! command -v logread >/dev/null 2>&1; then
            ui_title "📜 Log Viewer"
            log_warn "logread is not available on this system."
            echo "  ───────────────────────────────────────────────────────────"
            return 0
        fi

        ui_title "📜 Log Viewer"
        echo "  🛡️ 1) DayPass & proxy engines"
        echo "  🌐 2) Network (netifd, dnsmasq, mwan3)"
        echo "  🔌 3) Kernel (USB / modem events)"
        echo "  📚 4) Everything"
        ui_nav_footer
        ui_prompt 4

        case "$UI_CHOICE" in
            1) _system_log_render "daypass|passwall|xray|sing-box|openvpn|wireguard|wg[0-9]" "DayPass & engines" ;;
            2) _system_log_render "netifd|dnsmasq|mwan3|odhcpd|udhcpc" "Network" ;;
            3) _system_log_render "kernel" "Kernel" ;;
            4) _system_log_render "" "Everything" ;;
            0) return 0 ;;
            *)
                ui_nav_common "$UI_CHOICE" "$HELP_MODULE_ID" && continue
                log_warn "Invalid option!"
                sleep 1
                continue
                ;;
        esac

        ui_pause
    done
}

system_restore_configs() {
    local archive="$BACKUP_DIR/latest_backup.tar.gz"

    render_persistent_header
    ui_title "💾 Restore DayPass Engine Configs"

    if [ -d "$BACKUP_DIR" ]; then
        ls -1t "$BACKUP_DIR"/daypass_config_backup_*.tar.gz 2>/dev/null | sed 's/^/  • /'
        echo "  ───────────────────────────────────────────────────────────"
    else
        log_info "No backup directory yet."
        echo "  ───────────────────────────────────────────────────────────"
    fi

    ui_read "Archive path [latest], [0] Cancel"
    case "$UI_CHOICE" in
        0) return 0 ;;
        q|Q) daypass_quit ;;
        '') ;;
        *) archive="$UI_CHOICE" ;;
    esac

    ui_read "Overwrite current engine configs from [$archive]? [y/N]"
    case "$UI_CHOICE" in
        y|Y) restore_configs "$archive" ;;
        q|Q) daypass_quit ;;
    esac
}

system_menu() {
    local HELP_MODULE_ID="system_menu"

    while true; do
        render_persistent_header

        ui_title "🛠️ System Maintenance & Backup"
        echo "  🧰 1) Maintenance & Recovery (purge, cache, factory reset)"
        echo "  💾 2) Backup DayPass Engine Configs"
        echo "  ♻️ 3) Restore DayPass Engine Configs"
        echo "  📜 4) Log Viewer"
        echo "  🔄 5) System Updates (check & update packages)"
        ui_nav_footer main

        ui_prompt 5

        case "$UI_CHOICE" in
            1) ui_run maintenance_menu "Maintenance"; continue ;;
            2) ui_run backup_configs "Backup" ;;
            3) system_restore_configs ;;
            4) system_log_viewer; continue ;;
            5) ui_run update_packages_menu "Update"; continue ;;
            0) return 0 ;;
            *)
                ui_nav_common "$UI_CHOICE" "$HELP_MODULE_ID" && continue
                log_warn "Invalid option!"
                sleep 1
                continue
                ;;
        esac

        ui_pause
    done
}


# 📄 Source : help.sh
# ============================================================
# DayPass - In-App Help Viewer & Manual Index
# Renders the JSON manuals cached by ui/lib/help.sh.
# Pages use the same DayPass banner as every other screen.
# ============================================================

HELP_ITEM_INDENT="       "
HELP_LIST_FILE=""
HELP_TAB="$(printf '\t')"

# ------------------------------------------------------------
# Detected terminal height (falls back to 24 rows)
# ------------------------------------------------------------
help_rows() {
    HELP_ROWS=$(stty size 2>/dev/null | awk 'NR==1 {print $1+0}')
    [ -z "$HELP_ROWS" ] && HELP_ROWS=0
    [ "$HELP_ROWS" -le 0 ] && HELP_ROWS=24
    echo "$HELP_ROWS"
}

# ------------------------------------------------------------
# How many help items fit on one contextual-help page.
# Floor is 2 so typical OpenWrt terminals (24 rows) no longer show
# a single entry per page; taller screens get 3.
# ------------------------------------------------------------
help_item_page_size() {
    HELP_ROWS="$(help_rows)"
    if [ "$HELP_ROWS" -ge 36 ]; then
        echo 3
    else
        echo 2
    fi
}

# ------------------------------------------------------------
# How many manuals fit in the global help index
# ------------------------------------------------------------
help_list_page_size() {
    HELP_ROWS="$(help_rows)"
    if [ "$HELP_ROWS" -ge 46 ]; then
        echo 8
    elif [ "$HELP_ROWS" -ge 36 ]; then
        echo 6
    elif [ "$HELP_ROWS" -ge 28 ]; then
        echo 4
    else
        echo 2
    fi
}

# ------------------------------------------------------------
# Wrap text to terminal-friendly lines
# ------------------------------------------------------------
help_wrap() {
    HELP_TEXT="$1"
    HELP_PREFIX="$2"
    HELP_WIDTH="${3:-66}"

    printf '%s\n' "$HELP_TEXT" | awk -v pre="$HELP_PREFIX" -v w="$HELP_WIDTH" '
    {
        n = split($0, word, " ")
        line = pre
        for (i = 1; i <= n; i++) {
            if (word[i] == "") continue
            if (length(line) > length(pre) && length(line) + length(word[i]) + 1 > w) {
                print line
                line = pre word[i]
            } else if (length(line) > length(pre)) {
                line = line " " word[i]
            } else {
                line = line word[i]
            }
        }
        if (length(line) > length(pre)) print line
    }'
}

# ------------------------------------------------------------
# Friendly message when a manual cannot be loaded at all
# ------------------------------------------------------------
help_unavailable() {
    HELP_LABEL="${1:-Manual}"

    render_persistent_header
    log_warn "Manual unavailable"
    echo "  ${GRAY}[${HELP_LABEL}] has no cached copy, and jq or the download failed.${RESET}"
    echo "  ${GRAY}Cache directory : [$(help_cache_dir)]${RESET}"
    echo
    printf "  ${GRAY}Press [Enter] to continue ...${RESET}"
    read -r _ </dev/tty || daypass_quit
    return 0
}

# ------------------------------------------------------------
# Contextual help screen for one module manual
# ------------------------------------------------------------
show_help() {
    HELP_ID="$1"

    if [ -z "$HELP_ID" ] || ! command -v jq >/dev/null 2>&1; then
        help_unavailable "${HELP_ID:-Help}"
        return 0
    fi

    if ! help_ensure_manual "$HELP_ID"; then
        help_unavailable "$HELP_ID"
        return 0
    fi

    HELP_FILE="$(help_manual_path "$HELP_ID")"

    HELP_TOTAL=$(jq '.items | length' "$HELP_FILE" 2>/dev/null)
    case "$HELP_TOTAL" in
        ''|*[!0-9]*) HELP_TOTAL=0 ;;
    esac

    HELP_PAGE_SIZE="$(help_item_page_size)"
    HELP_PAGES=$(( (HELP_TOTAL + HELP_PAGE_SIZE - 1) / HELP_PAGE_SIZE ))
    [ "$HELP_PAGES" -lt 1 ] && HELP_PAGES=1
    HELP_PAGE=1

    while true; do
        render_persistent_header

        HELP_TITLE=$(jq -r '.title // "Help"' "$HELP_FILE" 2>/dev/null)
        HELP_SUMMARY=$(jq -r '.summary // ""' "$HELP_FILE" 2>/dev/null)

        echo "  📖 ${BOLD}${HELP_TITLE}${RESET}"
        echo "  ───────────────────────────────────────────────────────────"
        if [ -n "$HELP_SUMMARY" ]; then
            help_wrap "$HELP_SUMMARY" "  " 66
        fi
        echo "  ───────────────────────────────────────────────────────────"

        jq -r \
            --argjson s "$(( (HELP_PAGE - 1) * HELP_PAGE_SIZE ))" \
            --argjson e "$(( HELP_PAGE * HELP_PAGE_SIZE ))" '
            .items[$s:$e] as $page |
            $page | to_entries[] |
            "K\u0009\(.value.key)\u0009\(.value.title)",
            "D\u0009\(.value.description // "")",
            "T\u0009\(.value.usage_tip // "")",
            (if .key + 1 < ($page | length) then "S\u0009" else empty end)
        ' "$HELP_FILE" 2>/dev/null | while IFS="$HELP_TAB" read -r HELP_TAG HELP_F1 HELP_F2; do
            case "$HELP_TAG" in
                K)
                    printf "\n  ${CYAN}${BOLD}%s)${RESET} ${BOLD}%s${RESET}\n" "$HELP_F1" "$HELP_F2"
                    ;;
                D)
                    if [ -n "$HELP_F1" ]; then
                        help_wrap "$HELP_F1" "$HELP_ITEM_INDENT" 66
                    fi
                    ;;
                T)
                    if [ -n "$HELP_F1" ]; then
                        help_wrap "$HELP_F1" "${HELP_ITEM_INDENT}💡 " 66
                    fi
                    ;;
                S)
                    printf "  %s\n" "───────────────────────────────────────────────────────────"
                    ;;
            esac
        done

        echo "  ───────────────────────────────────────────────────────────"
        _nav_muted="${COLOR_MUTED:-$GRAY}"
        printf "  ${_nav_muted}Page %s/%s${RESET}\n" "$HELP_PAGE" "$HELP_PAGES"
        printf "  ${_nav_muted}n) Next${RESET}\n"
        printf "  ${_nav_muted}p) Previous${RESET}\n"
        printf "  ${_nav_muted}0) Back / Skip${RESET}\n"
        printf "  ${_nav_muted}q) Quit DayPass${RESET}\n"
        printf "  ⁉️ Option : "
        read -r HELP_CMD </dev/tty || daypass_quit

        case "$HELP_CMD" in
            n|N)
                [ "$HELP_PAGE" -lt "$HELP_PAGES" ] && HELP_PAGE=$((HELP_PAGE + 1))
                ;;
            p|P)
                [ "$HELP_PAGE" -gt 1 ] && HELP_PAGE=$((HELP_PAGE - 1))
                ;;
            ''|0)
                return 0
                ;;
            q|Q)
                daypass_quit
                ;;
            *)
                log_warn "Use a page key or a manual number."
                sleep 1
                ;;
        esac
    done
}

# ------------------------------------------------------------
# Global help index (driven by help/index.json)
# ------------------------------------------------------------
help_menu() {
    HELP_LIST_FILE="/tmp/.daypass_help_index.$$"
    HELP_PAGE=1

    while true; do
        render_persistent_header

        echo "  📖 ${BOLD}Help & Manuals${RESET}"
        echo "  ───────────────────────────────────────────────────────────"

        if ! command -v jq >/dev/null 2>&1; then
            rm -f "$HELP_LIST_FILE" 2>/dev/null
            help_unavailable "index"
            return 0
        fi

        if ! help_ensure_manual "index"; then
            rm -f "$HELP_LIST_FILE" 2>/dev/null
            help_unavailable "index"
            return 0
        fi

        jq -r '
            .manuals[]? |
            "\(.module_id)\u0009\(.title)\u0009\(.item_count // 0)\u0009\(.reachable_from // "")"
        ' "$(help_manual_path index)" > "$HELP_LIST_FILE" 2>/dev/null

        HELP_TOTAL=$(wc -l < "$HELP_LIST_FILE" 2>/dev/null | tr -d ' ')
        case "$HELP_TOTAL" in
            ''|*[!0-9]*) HELP_TOTAL=0 ;;
        esac

        if [ "$HELP_TOTAL" -eq 0 ]; then
            log_warn "No manuals available!"
            rm -f "$HELP_LIST_FILE" 2>/dev/null
            sleep 1
            return 1
        fi

        HELP_LIST_SIZE="$(help_list_page_size)"
        HELP_PAGES=$(( (HELP_TOTAL + HELP_LIST_SIZE - 1) / HELP_LIST_SIZE ))
        HELP_PAGE_START=$(( (HELP_PAGE - 1) * HELP_LIST_SIZE + 1 ))
        HELP_PAGE_END=$(( HELP_PAGE * HELP_LIST_SIZE ))
        [ "$HELP_PAGE_END" -gt "$HELP_TOTAL" ] && HELP_PAGE_END=$HELP_TOTAL

        HELP_IDX=$(( HELP_PAGE_START - 1 ))
        sed -n "${HELP_PAGE_START},${HELP_PAGE_END}p" "$HELP_LIST_FILE" | \
        while IFS="$HELP_TAB" read -r HELP_MID HELP_MTITLE HELP_MCOUNT HELP_MFROM; do
            HELP_IDX=$((HELP_IDX + 1))
            HELP_NO=$(( HELP_IDX - HELP_PAGE_START + 1 ))
            printf "  ${CYAN}%s${RESET}) %s ${GRAY}(%s entries)${RESET}\n" \
                "$HELP_NO" "$HELP_MTITLE" "$HELP_MCOUNT"
            if [ -n "$HELP_MFROM" ]; then
                printf "      ${GRAY}↳ %s${RESET}\n" "$HELP_MFROM"
            fi
        done

        echo "  ───────────────────────────────────────────────────────────"
        _nav_muted="${COLOR_MUTED:-$GRAY}"
        printf "  ${_nav_muted}Page %s/%s${RESET}\n" "$HELP_PAGE" "$HELP_PAGES"
        printf "  ${_nav_muted}n) Next${RESET}\n"
        printf "  ${_nav_muted}p) Previous${RESET}\n"
        printf "  ${_nav_muted}r) Refresh${RESET}\n"
        printf "  ${_nav_muted}0) Back / Skip${RESET}\n"
        printf "  ${_nav_muted}q) Quit DayPass${RESET}\n"
        printf "  ⁉️ Manual number : "
        read -r HELP_CMD </dev/tty || daypass_quit

        case "$HELP_CMD" in
            n|N)
                [ "$HELP_PAGE" -lt "$HELP_PAGES" ] && HELP_PAGE=$((HELP_PAGE + 1))
                continue
                ;;
            p|P)
                [ "$HELP_PAGE" -gt 1 ] && HELP_PAGE=$((HELP_PAGE - 1))
                continue
                ;;
            r|R)
                help_cache_reset
                log_info "Manual cache cleared, re-downloading ..."
                sleep 1
                continue
                ;;
            ''|0)
                rm -f "$HELP_LIST_FILE" 2>/dev/null
                return 0
                ;;
            q|Q)
                rm -f "$HELP_LIST_FILE" 2>/dev/null
                daypass_quit
                ;;
            *[!0-9]*)
                log_warn "Invalid choice!"
                sleep 1
                continue
                ;;
        esac

        if [ "$HELP_CMD" -ge 1 ] && [ "$HELP_CMD" -le $(( HELP_PAGE_END - HELP_PAGE_START + 1 )) ]; then
            HELP_LINE=$(( HELP_PAGE_START + HELP_CMD - 1 ))
            HELP_MID=$(sed -n "${HELP_LINE}p" "$HELP_LIST_FILE" | cut -f1)
            if [ -n "$HELP_MID" ]; then
                HELP_SAVED_PAGE=$HELP_PAGE
                show_help "$HELP_MID"
                HELP_PAGE=$HELP_SAVED_PAGE
            fi
        else
            log_warn "Invalid manual number!"
            sleep 1
        fi
    done
}




# 📄 Source : main.sh

main_menu()
{
    local HELP_MODULE_ID="main"

    trap daypass_interrupt INT TERM

    while true; do
        render_persistent_header

        ui_title "🏠 Main Menu"
        echo "  📦 1) Package Profiles & Dependencies"
        echo "  🔌 2) Hardware & USB Tethering Manager"
        echo "  🌐 3) Network & Routing Configuration"
        echo "  🛡️ 4) Proxy & Tunnel Engine Manager"
        echo "  ⚖️ 5) Node Balancer & Health Diagnostics"
        echo "  🛠️ 6) System Maintenance & Backup"
        echo "  📖 7) Help & Manuals"
        echo "  🌐 8) Network Bootstrap Wizard"
        ui_nav_footer root

        ui_prompt 8

        case "$UI_CHOICE" in
            1) ui_run packages_menu "Package Profiles" ;;
            2) ui_run hardware_menu "Hardware & USB Tethering" ;;
            3) ui_run network_menu "Network" ;;
            4) ui_run proxy_menu "Proxy & Tunnel Engine" ;;
            5) ui_run diagnostics_menu "Node Balancer & Diagnostics" ;;
            6) ui_run system_menu "System Maintenance" ;;
            7) ui_run help_menu "Help" ;;
            8) ui_run network_bootstrap_from_menu "Network Bootstrap" ;;
            0) daypass_quit ;;
            *)
                ui_nav_common "$UI_CHOICE" "$HELP_MODULE_ID" && continue
                log_warn "Invalid choice!"
                sleep 1
                ;;
        esac
    done
}


# 📄 Source : installer_ui.sh

start_ui()
{
    reset_state
    main_menu
}

# 📄 Source : package_profiles.json (embedded)
daypass_embedded_profiles()
{
    cat <<'DAYPASS_PROFILES_JSON'
{
  "schema_version": "1.0.0",
  "description": "Selectable DayPass package profiles resolved by installer/pkg/resolver.sh (install_profile / resolve_profile).",
  "default_profile": "proxy",
  "releases": {
    "24": {
      "release": "24.10",
      "package_manager": "opkg",
      "package_format": "ipk",
      "manifest_path": "v24/manifest.json"
    },
    "25": {
      "release": "25.12",
      "package_manager": "apk",
      "package_format": "apk",
      "manifest_path": "v25/manifest.json"
    }
  },
  "sources": {
    "manifest": "DayPass CDN mirror listed in manifest.json for the router architecture; downloaded and sha256-verified before install.",
    "feed": "OpenWrt feeds configured on the router, installed with opkg (24.x) or apk (25.x).",
    "auto": "Manifest first when the package is listed there, otherwise the OpenWrt feeds."
  },
  "entry_fields": {
    "name": "Package name; a plain string is shorthand for {\"name\": ...}.",
    "source": "manifest | feed | auto; defaults to the profile default_source.",
    "optional": "true = a failed install only warns; false = aborts and rolls back the profile.",
    "alternatives": "Packages that satisfy the same need; tried in order when name fails and counted as installed.",
    "depends": "Package names resolved before this entry.",
    "releases": "Limit the entry to OpenWrt major releases, e.g. [\"25\"].",
    "note": "Free text shown in plans."
  },
  "step_types": {
    "packages": "Fixed list of entries.",
    "choice": "One value from var (default when empty, fallback when unknown) selects an entry list.",
    "components": "Space- or comma-separated values from var select entry lists; all selects every component.",
    "list_var": "Every word in var is a package; exclude entries are exact names or prefix* patterns.",
    "template": "pattern with {VAR} placeholders builds one name; optional manifest presence check."
  },
  "profiles": {
    "proxy": {
      "title": "Proxy & Evasion Cores",
      "description": "Passwall or Passwall2 LuCI app with Xray-core, sing-box or V2Ray-core engines, geo data and translations.",
      "default_source": "auto",
      "requires": [],
      "steps": [
        {
          "id": "utilities",
          "type": "packages",
          "packages": [
            "tcping",
            "geoview"
          ]
        },
        {
          "id": "geo_data",
          "type": "choice",
          "var": "SELECTED_GEO",
          "default": "official",
          "choices": {
            "official": [
              "v2ray-geoip",
              "v2ray-geosite"
            ]
          }
        },
        {
          "id": "engine",
          "type": "choice",
          "var": "SELECTED_ENGINE",
          "default": "xray",
          "fallback": "xray",
          "choices": {
            "xray": [
              "xray-core"
            ],
            "sing-box": [
              "sing-box"
            ],
            "singbox": [
              "sing-box"
            ],
            "v2ray": [
              "v2ray-core"
            ],
            "both": [
              "xray-core",
              "sing-box"
            ],
            "all": [
              "xray-core",
              "sing-box",
              "v2ray-core"
            ]
          }
        },
        {
          "id": "custom",
          "type": "list_var",
          "var": "SELECTED_PACKAGES",
          "exclude": [
            "luci-app-passwall",
            "luci-app-passwall2",
            "luci-i18n-*"
          ]
        },
        {
          "id": "app",
          "type": "choice",
          "var": "SELECTED_PROFILE",
          "default": "passwall2",
          "choices": {
            "passwall2": [
              {
                "name": "luci-app-passwall2",
                "source": "manifest"
              }
            ],
            "passwall": [
              {
                "name": "luci-app-passwall",
                "source": "manifest"
              }
            ]
          }
        },
        {
          "id": "translation",
          "type": "template",
          "pattern": "luci-i18n-{SELECTED_PROFILE}-{SELECTED_LANGUAGE}",
          "source": "manifest",
          "vars": {
            "SELECTED_PROFILE": "passwall2",
            "SELECTED_LANGUAGE": "fa"
          },
          "skip_values": {
            "SELECTED_LANGUAGE": [
              "en"
            ]
          },
          "require_in_manifest": true,
          "without_manifest": {
            "SELECTED_PROFILE": [
              "passwall2"
            ]
          }
        }
      ]
    },
    "vpn": {
      "title": "VPN & Tunnels",
      "description": "WireGuard, AmneziaWG, OpenVPN and SoftEther VPN clients/servers.",
      "default_source": "feed",
      "requires": [],
      "steps": [
        {
          "id": "tunnels",
          "type": "components",
          "var": "DAYPASS_VPN_COMPONENTS",
          "default": [
            "wireguard",
            "amneziawg",
            "openvpn",
            "softether"
          ],
          "components": {
            "wireguard": [
              "kmod-wireguard",
              {
                "name": "wireguard-tools",
                "depends": [
                  "kmod-wireguard"
                ]
              },
              {
                "name": "luci-proto-wireguard",
                "optional": true,
                "depends": [
                  "wireguard-tools"
                ]
              }
            ],
            "amneziawg": [
              {
                "name": "kmod-amneziawg",
                "optional": true,
                "note": "Third-party feed (github.com/amnezia-vpn/amneziawg-openwrt); not in the official OpenWrt feeds."
              },
              {
                "name": "amneziawg-tools",
                "optional": true,
                "depends": [
                  "kmod-amneziawg"
                ]
              },
              {
                "name": "luci-proto-amneziawg",
                "optional": true,
                "depends": [
                  "amneziawg-tools"
                ]
              }
            ],
            "openvpn": [
              {
                "name": "openvpn-openssl",
                "alternatives": [
                  "openvpn-mbedtls",
                  "openvpn-wolfssl"
                ]
              },
              {
                "name": "luci-app-openvpn",
                "optional": true,
                "depends": [
                  "openvpn-openssl"
                ]
              }
            ],
            "softether": [
              "softethervpn5-client",
              {
                "name": "softethervpn5-server",
                "optional": true
              }
            ]
          }
        }
      ]
    },
    "usb": {
      "title": "USB & Hardware Drivers",
      "description": "Kernel drivers and tools for USB tethering (Android RNDIS, CDC Ethernet/NCM, iPhone) and USB modem mode switching.",
      "default_source": "feed",
      "requires": [],
      "steps": [
        {
          "id": "tethering",
          "type": "packages",
          "packages": [
            "kmod-usb-net-rndis",
            "kmod-usb-net-cdc-ether",
            {
              "name": "kmod-usb-net-cdc-ncm",
              "optional": true,
              "note": "Newer phones that tether over CDC-NCM."
            },
            "usbutils",
            "usb-modeswitch",
            {
              "name": "kmod-usb-net-ipheth",
              "optional": true,
              "note": "iPhone USB tethering (also needs usbmuxd)."
            },
            {
              "name": "usbmuxd",
              "optional": true,
              "depends": [
                "kmod-usb-net-ipheth"
              ]
            }
          ]
        }
      ]
    },
    "network_tools": {
      "title": "Network Tools & Traffic Management",
      "description": "mwan3 multi-WAN, SQM with Cake, nftables, iperf3, tcpdump and TPROXY support for direct cores.",
      "default_source": "feed",
      "requires": [],
      "steps": [
        {
          "id": "multiwan",
          "type": "packages",
          "packages": [
            "mwan3",
            {
              "name": "luci-app-mwan3",
              "optional": true,
              "depends": [
                "mwan3"
              ]
            }
          ]
        },
        {
          "id": "sqm",
          "type": "packages",
          "packages": [
            "kmod-sched-cake",
            {
              "name": "sqm-scripts",
              "depends": [
                "kmod-sched-cake"
              ]
            },
            {
              "name": "luci-app-sqm",
              "optional": true,
              "depends": [
                "sqm-scripts"
              ]
            }
          ]
        },
        {
          "id": "diagnostics",
          "type": "packages",
          "packages": [
            {
              "name": "nftables-json",
              "alternatives": [
                "nftables-nojson"
              ]
            },
            {
              "name": "iperf3",
              "alternatives": [
                "iperf3-ssl"
              ]
            },
            {
              "name": "tcpdump",
              "alternatives": [
                "tcpdump-mini"
              ]
            }
          ]
        },
        {
          "id": "interception",
          "type": "packages",
          "packages": [
            {
              "name": "kmod-nft-tproxy",
              "optional": true
            }
          ]
        }
      ]
    }
  }
}
DAYPASS_PROFILES_JSON
}

# 📄 Source : package_catalog.json (embedded)
daypass_embedded_catalog()
{
    cat <<'DAYPASS_CATALOG_JSON'
{
  "schema_version": "1.0.0",
  "description": "User-facing titles, one-line descriptions and UI roles for DayPass profile packages. Used by the Profile Installation screen.",
  "roles": {
    "core": "Core",
    "web": "Web Interface",
    "enhancement": "Enhancement"
  },
  "profiles": {
    "proxy": {
      "icon": "⚡",
      "highlights": ["xray-core", "luci-app-passwall2", "geoview"]
    },
    "vpn": {
      "icon": "🔐",
      "highlights": ["wireguard-tools", "openvpn-openssl", "softethervpn5-client"]
    },
    "usb": {
      "icon": "🔌",
      "highlights": ["kmod-usb-net-rndis", "usbutils", "usb-modeswitch"]
    },
    "network_tools": {
      "icon": "📈",
      "highlights": ["mwan3", "sqm-scripts", "iperf3"]
    }
  },
  "packages": {
    "tcping": {
      "title": "TCP Ping Probe",
      "description": "Checks whether a remote host and port actually accept connections.",
      "role": "enhancement"
    },
    "geoview": {
      "title": "Geo Database Viewer",
      "description": "Looks up country and site categories used by routing rules.",
      "role": "enhancement"
    },
    "v2ray-geoip": {
      "title": "IP Country Database",
      "description": "Maps IP addresses to countries so Iranian and foreign traffic can be split.",
      "role": "core"
    },
    "v2ray-geosite": {
      "title": "Site Category Database",
      "description": "Domain lists (video, ads, Iran, and so on) used by the proxy engine.",
      "role": "core"
    },
    "xray-core": {
      "title": "Xray Proxy Engine",
      "description": "The Xray core that carries VLESS, VMess, Trojan and Reality traffic.",
      "role": "core"
    },
    "sing-box": {
      "title": "sing-box Proxy Engine",
      "description": "A modern all-in-one proxy core (VLESS, Hysteria2, TUIC, and more).",
      "role": "core"
    },
    "v2ray-core": {
      "title": "V2Ray Proxy Engine",
      "description": "The classic V2Ray core for VMess and VLESS links.",
      "role": "core"
    },
    "luci-app-passwall": {
      "title": "Passwall 1 Control Panel",
      "description": "LuCI web app that configures Passwall 1 on this router.",
      "role": "web"
    },
    "luci-app-passwall2": {
      "title": "Passwall 2 Control Panel",
      "description": "LuCI web app that configures Passwall 2 on this router.",
      "role": "web"
    },
    "kmod-wireguard": {
      "title": "WireGuard Kernel Module",
      "description": "In-kernel WireGuard so the tunnel runs with little CPU cost.",
      "role": "core"
    },
    "wireguard-tools": {
      "title": "WireGuard Tools",
      "description": "Creates and manages WireGuard interfaces from the command line.",
      "role": "core"
    },
    "luci-proto-wireguard": {
      "title": "Web Interface for WireGuard",
      "description": "Lets you add WireGuard tunnels from LuCI Network → Interfaces.",
      "role": "web"
    },
    "kmod-amneziawg": {
      "title": "AmneziaWG Kernel Module",
      "description": "Censorship-resistant WireGuard variant (needs a third-party feed).",
      "role": "enhancement"
    },
    "amneziawg-tools": {
      "title": "AmneziaWG Tools",
      "description": "User-space tools to bring AmneziaWG interfaces up.",
      "role": "enhancement"
    },
    "luci-proto-amneziawg": {
      "title": "Web Interface for AmneziaWG",
      "description": "LuCI protocol helper for AmneziaWG tunnels.",
      "role": "web"
    },
    "openvpn-openssl": {
      "title": "OpenVPN",
      "description": "OpenVPN client/server using OpenSSL for TLS.",
      "role": "core"
    },
    "openvpn-mbedtls": {
      "title": "OpenVPN (mbedTLS)",
      "description": "OpenVPN built against mbedTLS — used if the OpenSSL build is missing.",
      "role": "core"
    },
    "openvpn-wolfssl": {
      "title": "OpenVPN (WolfSSL)",
      "description": "OpenVPN built against WolfSSL — another fallback build.",
      "role": "core"
    },
    "luci-app-openvpn": {
      "title": "Web Interface for OpenVPN",
      "description": "Manage OpenVPN instances from the LuCI web UI.",
      "role": "web"
    },
    "softethervpn5-client": {
      "title": "SoftEther VPN Client",
      "description": "Connects this router to a SoftEther VPN server.",
      "role": "core"
    },
    "softethervpn5-server": {
      "title": "SoftEther VPN Server",
      "description": "Turns the router into a SoftEther VPN server (optional).",
      "role": "enhancement"
    },
    "kmod-usb-net-rndis": {
      "title": "Android USB Tethering Driver",
      "description": "Lets most Android phones share their mobile data over USB.",
      "role": "core"
    },
    "kmod-usb-net-cdc-ether": {
      "title": "USB Ethernet Interface Drivers",
      "description": "CDC Ethernet support for phones and USB tethering gadgets.",
      "role": "core"
    },
    "kmod-usb-net-cdc-ncm": {
      "title": "USB Ethernet Interface Drivers",
      "description": "CDC-NCM support used by newer phones instead of classic CDC Ethernet.",
      "role": "enhancement"
    },
    "usbutils": {
      "title": "USB Device Diagnostics Tool (lsusb)",
      "description": "Lists connected USB devices so tethering and modems can be diagnosed.",
      "role": "enhancement"
    },
    "usb-modeswitch": {
      "title": "Modem Mode Switching Tool (3G/4G/5G)",
      "description": "Switches USB modems from storage mode into a real network/modem mode.",
      "role": "core"
    },
    "kmod-usb-net-ipheth": {
      "title": "iPhone USB Tethering Support",
      "description": "Kernel driver for iPhone Personal Hotspot over USB.",
      "role": "enhancement"
    },
    "usbmuxd": {
      "title": "iPhone USB Tethering Support",
      "description": "Pairs the iPhone over USB so Personal Hotspot can actually pass data.",
      "role": "enhancement"
    },
    "mwan3": {
      "title": "Multi-WAN Load Balancing & Failover",
      "description": "Keeps several internet links online and fails over when one drops.",
      "role": "core"
    },
    "luci-app-mwan3": {
      "title": "Web Interface for Multi-WAN",
      "description": "Configure WAN members, policies and rules from LuCI.",
      "role": "web"
    },
    "kmod-sched-cake": {
      "title": "Smart Queue Management (Bufferbloat Reduction)",
      "description": "Cake kernel scheduler that keeps latency low when the line is busy.",
      "role": "core"
    },
    "sqm-scripts": {
      "title": "Smart Queue Management (Bufferbloat Reduction)",
      "description": "Applies Cake/SQM so browsing stays snappy during heavy downloads.",
      "role": "core"
    },
    "luci-app-sqm": {
      "title": "Web Interface for SQM",
      "description": "Set SQM speeds and the Cake/fq_codel queue from LuCI.",
      "role": "web"
    },
    "nftables-json": {
      "title": "nftables Firewall Engine",
      "description": "Modern packet filter used by DayPass TPROXY rules and OpenWrt 24+.",
      "role": "core"
    },
    "nftables-nojson": {
      "title": "nftables (compact build)",
      "description": "Fallback nftables package when the JSON build is not in the feeds.",
      "role": "core"
    },
    "iperf3": {
      "title": "Network Bandwidth Performance Tester",
      "description": "Measures how fast a link really is between two points.",
      "role": "enhancement"
    },
    "iperf3-ssl": {
      "title": "iperf3 with TLS",
      "description": "Same bandwidth tester, built with TLS support.",
      "role": "enhancement"
    },
    "tcpdump": {
      "title": "Network Packet Analyzer",
      "description": "Captures live packets so you can see what the router is sending.",
      "role": "enhancement"
    },
    "tcpdump-mini": {
      "title": "Packet Analyzer (mini)",
      "description": "Smaller tcpdump build for routers with little flash.",
      "role": "enhancement"
    },
    "kmod-nft-tproxy": {
      "title": "Transparent Proxy Support (TPROXY)",
      "description": "Lets DayPass send LAN traffic into sing-box or Xray without a local proxy setting.",
      "role": "enhancement"
    }
  }
}
DAYPASS_CATALOG_JSON
}

# 📄 Source : worker.js (embedded)
daypass_embedded_worker_js()
{
    cat <<'DAYPASS_WORKER_JS'
/**
 * DayPass - OpenWrt package mirror (Cloudflare Worker)
 *
 * Reverse-proxies downloads.openwrt.org so opkg / apk on the router can
 * fetch packages through the Cloudflare edge.
 *
 * Deployed by modules/network/relays/cloudflare/worker.sh as the script
 * "daypass-mirror"; worker.sh recognises a genuine deployment through
 * GET /daypass-health.
 */

const MIRROR_ID = 'daypass-openwrt';
const MIRROR_VERSION = '2.0.0';
const UPSTREAM_HOST = 'downloads.openwrt.org';
const HEALTH_PATH = '/daypass-health';
const MODULE_NAME = 'worker.js';

// Package payloads never change once published, so they can sit in the
// edge cache for a long time.
const IMMUTABLE_RE = /\.(ipk|apk)$/i;
const IMMUTABLE_TTL = 2592000; // 30 days

// Indexes, signatures and checksums must stay fresh: a stale index and a
// fresh package feed make opkg/apk fail with a hash mismatch.
const VOLATILE_RE = /(^|\/)(Packages(\.gz|\.sig)?|APKINDEX\.tar\.gz|index\.json|sha256sums(\.asc|\.sig)?|.*\.(sig|pub|asc|manifest))$/i;
const VOLATILE_TTL = 300; // 5 minutes

// Request headers worth forwarding upstream. Everything else (cookies,
// authorization, CF internals) is dropped so the cache key stays stable
// and nothing client-specific leaks to the origin.
const FORWARD_HEADERS = [
    'range',
    'if-range',
    'if-none-match',
    'if-modified-since',
    'accept',
    'accept-encoding',
    'user-agent',
];

const CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
    'Access-Control-Allow-Headers':
        'Range, If-Range, If-None-Match, If-Modified-Since, Accept, Accept-Encoding, User-Agent',
    'Access-Control-Expose-Headers':
        'Accept-Ranges, Content-Range, Content-Length, Content-Encoding, ETag, Last-Modified, X-DayPass-Cache',
    'Access-Control-Max-Age': '86400',
};

// Statuses that must be sent without a body.
const BODYLESS_STATUS = new Set([204, 205, 304]);

function withCors(headers) {
    for (const [name, value] of Object.entries(CORS_HEADERS)) {
        headers.set(name, value);
    }
    return headers;
}

function jsonResponse(payload, status, extra) {
    const headers = withCors(
        new Headers({
            'Content-Type': 'application/json; charset=utf-8',
            'Cache-Control': 'no-store',
            'X-DayPass-Mirror': MIRROR_ID,
            ...extra,
        }),
    );
    return new Response(`${JSON.stringify(payload)}\n`, { status, headers });
}

/**
 * Identity endpoint. worker.sh probes this to tell a real DayPass mirror
 * apart from any other host the user may have typed in.
 */
function healthResponse(request) {
    return jsonResponse(
        {
            status: 'ok',
            mirror: MIRROR_ID,
            version: MIRROR_VERSION,
            upstream: UPSTREAM_HOST,
            colo: (request.cf && request.cf.colo) || null,
            time: new Date().toISOString(),
        },
        200,
    );
}

/** How long the edge may keep this path, and whether it is immutable. */
function cachePolicy(pathname) {
    if (IMMUTABLE_RE.test(pathname)) {
        return { ttl: IMMUTABLE_TTL, immutable: true, storable: true };
    }
    if (VOLATILE_RE.test(pathname)) {
        return { ttl: VOLATILE_TTL, immutable: false, storable: false };
    }
    return { ttl: VOLATILE_TTL, immutable: false, storable: false };
}

function upstreamUrl(request) {
    const url = new URL(request.url);
    url.protocol = 'https:';
    url.hostname = UPSTREAM_HOST;
    url.port = '';
    return url;
}

function buildUpstreamRequest(request, url) {
    const headers = new Headers();
    for (const name of FORWARD_HEADERS) {
        const value = request.headers.get(name);
        if (value) headers.set(name, value);
    }

    // GET upstream even for HEAD: Cloudflare answers the client's HEAD
    // from it and the response stays cacheable.
    return new Request(url.toString(), {
        method: 'GET',
        headers,
        redirect: 'follow',
    });
}

/**
 * Copies the upstream response and streams its body straight through, so
 * a 300 MB package never lands in the Worker's memory.
 */
function proxyResponse(request, upstream, policy, cacheState) {
    const headers = withCors(new Headers(upstream.headers));

    headers.set('X-DayPass-Mirror', MIRROR_ID);
    headers.set('X-DayPass-Cache', cacheState);
    headers.delete('Set-Cookie');

    if (upstream.status === 200 || upstream.status === 206) {
        headers.set('Accept-Ranges', 'bytes');
    }

    if (policy.immutable && upstream.status === 200) {
        headers.set('Cache-Control', `public, max-age=${policy.ttl}, immutable`);
    } else if (upstream.status === 200 || upstream.status === 206) {
        headers.set('Cache-Control', `public, max-age=${policy.ttl}, must-revalidate`);
    }

    // 304 and friends must not carry a body, and a HEAD answer has none.
    const body =
        BODYLESS_STATUS.has(upstream.status) || request.method === 'HEAD'
            ? null
            : upstream.body;

    return new Response(body, {
        status: upstream.status,
        statusText: upstream.statusText,
        headers,
    });
}

/** One retry, so a single upstream hiccup does not fail a long install. */
async function fetchUpstream(upstreamRequest, ttl) {
    const options = { cf: { cacheEverything: true, cacheTtl: ttl } };

    try {
        return await fetch(upstreamRequest.clone(), options);
    } catch (err) {
        return await fetch(upstreamRequest, options);
    }
}

export default {
    async fetch(request, env, ctx) {
        const url = new URL(request.url);

        if (request.method === 'OPTIONS') {
            return new Response(null, {
                status: 204,
                headers: withCors(new Headers({ 'Cache-Control': 'no-store' })),
            });
        }

        if (url.pathname === HEALTH_PATH || url.pathname === `${HEALTH_PATH}/`) {
            return healthResponse(request);
        }

        if (request.method !== 'GET' && request.method !== 'HEAD') {
            return jsonResponse(
                { status: 'error', mirror: MIRROR_ID, error: 'method not allowed' },
                405,
                { Allow: 'GET, HEAD, OPTIONS' },
            );
        }

        const target = upstreamUrl(request);
        const policy = cachePolicy(target.pathname);
        const isRange = request.headers.has('Range');
        const cache = caches.default;

        // The Cache API cannot slice a stored body, so it is used only for
        // whole-file GETs of package payloads. Range requests (opkg/curl
        // resuming a download) go to fetch() with cacheEverything, which is
        // Cloudflare's HTTP cache and does serve 206 from a cached object.
        const useCacheApi =
            policy.storable && policy.immutable && request.method === 'GET' && !isRange;
        const cacheKey = new Request(target.toString(), { method: 'GET' });

        if (useCacheApi) {
            const hit = await cache.match(cacheKey);
            if (hit) {
                const headers = withCors(new Headers(hit.headers));
                headers.set('X-DayPass-Mirror', MIRROR_ID);
                headers.set('X-DayPass-Cache', 'HIT');
                headers.set('Accept-Ranges', 'bytes');
                return new Response(hit.body, {
                    status: hit.status,
                    statusText: hit.statusText,
                    headers,
                });
            }
        }

        let upstream;
        try {
            upstream = await fetchUpstream(buildUpstreamRequest(request, target), policy.ttl);
        } catch (err) {
            return jsonResponse(
                {
                    status: 'error',
                    mirror: MIRROR_ID,
                    error: 'upstream unreachable',
                    detail: String((err && err.message) || err),
                },
                502,
            );
        }

        const response = proxyResponse(request, upstream, policy, useCacheApi ? 'MISS' : 'EDGE');

        if (useCacheApi && upstream.status === 200) {
            // clone() tees the stream: one copy goes to the client while
            // the other is written to the cache in the background.
            ctx.waitUntil(cache.put(cacheKey, response.clone()));
        }

        return response;
    },
};

export { MIRROR_ID, MIRROR_VERSION, MODULE_NAME, UPSTREAM_HOST, HEALTH_PATH };
DAYPASS_WORKER_JS
}


###############################################################################
# Runtime Execution Pipeline
###############################################################################
DEPLOYMENT_FAILED=0

# 1. Pre-flight network bootstrap (skipped when a mirror or proxy is already set)
network_bootstrap_startup

# 2. Pre-flight connectivity check
network_check || exit 1

# 3. System environment discovery & version validation
check_version || exit 1
detect_system_architecture

# 4. Core dependency initialization => with delay (2 secs) to ensure system stability after installing the dnsmasq-full tool!
deploy_system_dependencies
initialize_installer

# 5. Optional Automatic UCI Config Backup
if command -v backup_configs >/dev/null 2>&1; then
    backup_configs
fi

# 6. Replace the OpenWrt SSH/console banner (/etc/banner)
if command -v system_banner_post_install >/dev/null 2>&1; then
    system_banner_post_install
fi

# 7. Interactive UI Launch
clear
reset_state
main_menu

# 8. Clean Exit
echo
log_success "👋 DayPass session finished!"
exit 0

