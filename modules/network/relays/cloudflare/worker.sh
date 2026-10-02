#!/bin/sh

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
        printf '  %s🔄 3)%s Restore Default OpenWrt Feeds %s(fail-safe)%s\n' "$WHITE" "$RESET" "$GRAY" "$RESET"
        printf '  %s⬅️ 0)%s Back\n' "$WHITE" "$RESET"
        printf '  %s─────────────────────────────────────────────────────────%s\n' "$GRAY" "$RESET"
        printf '\n'
        printf '  %s⁉️ Select option%s %s[0-3]%s : ' "$YELLOW" "$RESET" "$GRAY" "$RESET"

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
