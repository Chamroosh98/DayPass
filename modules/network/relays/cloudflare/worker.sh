#!/bin/sh

# Purpose:
#   Point OpenWrt package feeds (opkg / apk) at a Cloudflare Worker
#   reverse-proxy so downloads.openwrt.org can be reached via a custom
#   workers.dev (or custom-domain) hostname.

# ---------- defaults ----------
WORKER_DEFAULT_HOST="openwrt.daypass.workers.dev"
WORKER_UPSTREAM_HOST="downloads.openwrt.org"
WORKER_OPKG_FEEDS="/etc/opkg/distfeeds.conf"
WORKER_APK_REPOS="/etc/apk/repositories"

# ---------- banner ----------
_wb_banner() {
    echo
    echo "  ${CYAN}${RESET}${BOLD}☁️ Cloudflare Worker Mirror${RESET}"
    echo "  ${CYAN}─────────────────────────────────────────────────────────${RESET}"
    echo "  ${CYAN}${RESET}Package feeds are rewritten from downloads.openwrt.org"
    echo "  ${CYAN}${RESET}to your Worker so opkg / apk can fetch through CF.  "
    echo "  ${CYAN}─────────────────────────────────────────────────────────${RESET}"
    echo
}

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
        echo "${GREEN}  [+] Backup saved → ${_bak}${RESET}"
        return 0
    fi

    echo "${RED}  [x] Failed to backup : [${_src}]${RESET}"
    return 1
}

# Rewrite from the original backup (when present) so re-runs stay idempotent.
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
    if ! sed "s|${WORKER_UPSTREAM_HOST}|${_host}|g" "$_base" >"$_tmp" 2>/dev/null; then
        rm -f "$_tmp" 2>/dev/null
        echo "${RED}  [x] Failed to rewrite : [${_src}]${RESET}"
        return 1
    fi

    if ! mv "$_tmp" "$_src" 2>/dev/null; then
        rm -f "$_tmp" 2>/dev/null
        echo "${RED}  [x] Failed to install rewritten : [${_src}]${RESET}"
        return 1
    fi

    echo "${GREEN}  [+] Feeds updated → [${_src}]${RESET}"
    return 0
}

_wb_restore_file() {
    local _src="$1"
    local _bak="${_src}.bak"

    if [ ! -f "$_bak" ]; then
        return 1
    fi

    if cp "$_bak" "$_src" 2>/dev/null; then
        echo "${GREEN}  [+] Restored default feeds → [${_src}]${RESET}"
        return 0
    fi

    echo "${RED}  [x] Failed to restore : [${_src}]${RESET}"
    return 1
}

# Probe Worker over HTTPS; 2xx–4xx counts as reachable (root may 404).
_wb_http_probe() {
    local _url="$1"
    local _code=""
    local _tmp

    _tmp="/tmp/daypass_wb_probe.$$"
    rm -f "$_tmp" 2>/dev/null

    if command -v curl >/dev/null 2>&1; then
        _code="$(curl -sS -o /dev/null -w '%{http_code}' \
            --connect-timeout 8 --max-time 15 "$_url" 2>/dev/null || true)"
        case "$_code" in
            [234][0-9][0-9]) return 0 ;;
        esac
    fi

    if command -v wget >/dev/null 2>&1; then
        if wget -q -T 15 -O "$_tmp" "$_url" 2>/dev/null; then
            rm -f "$_tmp" 2>/dev/null
            return 0
        fi
        # HTTP 4xx still proves the Worker answered.
        if [ -s "$_tmp" ]; then
            rm -f "$_tmp" 2>/dev/null
            return 0
        fi
    fi

    if command -v uclient-fetch >/dev/null 2>&1; then
        if uclient-fetch -q -T 15 -O "$_tmp" "$_url" 2>/dev/null; then
            rm -f "$_tmp" 2>/dev/null
            return 0
        fi
        if [ -s "$_tmp" ]; then
            rm -f "$_tmp" 2>/dev/null
            return 0
        fi
    fi

    rm -f "$_tmp" 2>/dev/null
    return 1
}

_wb_check_connectivity() {
    local _host="$1"
    local _url="https://${_host}/"

    echo "${CYAN}  [i] Checking Worker mirror : [${_url}]${RESET}"

    if ! command -v curl >/dev/null 2>&1 \
        && ! command -v wget >/dev/null 2>&1 \
        && ! command -v uclient-fetch >/dev/null 2>&1; then
        echo "${YELLOW}  [!] No curl / wget / uclient-fetch — skipped connectivity check.${RESET}"
        return 0
    fi

    if _wb_http_probe "$_url"; then
        echo "${GREEN}  [+] Worker mirror is reachable.${RESET}"
        return 0
    fi

    echo "${RED}  [x] Cannot reach Worker mirror (network, TLS, or DNS).${RESET}"
    echo "${YELLOW}  [!] Feeds were still rewritten; restore if downloads fail.${RESET}"
    return 1
}

# Public — roll feeds back to the backed-up OpenWrt endpoints
worker_bootstrap_restore() {
    local _restored=0

    if [ -f "${WORKER_OPKG_FEEDS}.bak" ]; then
        _wb_restore_file "$WORKER_OPKG_FEEDS" && _restored=1
    fi

    if [ -f "${WORKER_APK_REPOS}.bak" ]; then
        _wb_restore_file "$WORKER_APK_REPOS" && _restored=1
    fi

    if [ "$_restored" -eq 1 ]; then
        echo "${GREEN}  [+] OpenWrt default endpoints restored.${RESET}"
        return 0
    fi

    echo "${YELLOW}  [!] No feed backups found — nothing to restore.${RESET}"
    return 1
}

# Public — apply hostname to whichever feed files exist
worker_bootstrap_apply() {
    local _host="$1"
    local _changed=0
    local _failed=0

    _host="$(_wb_normalize_host "$_host")"

    if ! _wb_valid_host "$_host"; then
        echo "${RED}  [x] Invalid Worker domain : [${_host}]${RESET}"
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
        echo "${YELLOW}  [!] No feed files found (${WORKER_OPKG_FEEDS} / ${WORKER_APK_REPOS}).${RESET}"
        return 1
    fi

    if [ "$_failed" -eq 1 ]; then
        echo "${YELLOW}  [!] Some feed files could not be updated.${RESET}"
        return 1
    fi

    echo "${GREEN}  [+] Mirror host set → ${BOLD}https://${_host}/${RESET}"
    _wb_check_connectivity "$_host"
    return 0
}

# Public — interactive Worker mirror offer (never aborts the installer)
worker_bootstrap_offer() {
    local _default
    local _input
    local _host

    _default="$(_wb_default_host)"

    render_persistent_header
    _wb_banner

    echo "  ${DIM}Type ${WHITE}restore${DIM} to roll feeds back to downloads.openwrt.org.${RESET}"
    echo
    printf "  Worker domain ${DIM}[default ${_default}]${RESET} : "
    read -r _input </dev/tty

    case "$_input" in
        [rR]|[rR][eE][sS][tT][oO][rR][eE])
            worker_bootstrap_restore || true
            return 0
            ;;
    esac

    if [ -z "$_input" ]; then
        _host="$_default"
        echo "${CYAN}  [i] Using default Worker domain : [${_host}]${RESET}"
    else
        _host="$(_wb_normalize_host "$_input")"
    fi

    if worker_bootstrap_apply "$_host"; then
        echo "${GREEN}  [i] Subsequent package updates will use this mirror.${RESET}"
    else
        echo "${YELLOW}  [!] Worker mirror setup did not complete — continuing.${RESET}"
    fi

    return 0
}

# Public — helpers (optional use elsewhere)
worker_bootstrap_status() {
    local _file=""
    local _hit=""

    if [ -f "$WORKER_OPKG_FEEDS" ]; then
        _file="$WORKER_OPKG_FEEDS"
    elif [ -f "$WORKER_APK_REPOS" ]; then
        _file="$WORKER_APK_REPOS"
    fi

    if [ -z "$_file" ]; then
        echo "${YELLOW}  [!] No package feed files present.${RESET}"
        return 0
    fi

    _hit="$(sed -n "s|.*https\{0,1\}://\([^/]*\)/.*|\1|p" "$_file" 2>/dev/null | head -n 1)"

    if [ -n "$_hit" ] && [ "$_hit" != "$WORKER_UPSTREAM_HOST" ]; then
        echo "${GREEN}  [+] Worker mirror active : [${_hit}]${RESET}"
    else
        echo "${YELLOW}  [!] Feeds still point at ${WORKER_UPSTREAM_HOST}.${RESET}"
    fi
}
