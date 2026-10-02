#!/bin/sh

# Purpose:
#   Point OpenWrt package feeds (opkg / apk) at a Cloudflare Worker
#   reverse-proxy so downloads.openwrt.org can be reached through the
#   Cloudflare edge.
#
#   Three ways in:
#     1. import a Worker hostname the user already has,
#     2. deploy config/worker.js to the user's own Cloudflare account
#        through the REST API and use the resulting workers.dev URL,
#     3. roll the feed files back to the OpenWrt defaults.
#
#   Feed files are never touched before the target host is confirmed, so a
#   cancelled prompt or a failed API call always leaves the router working.

# ---------- defaults ----------
WORKER_DEFAULT_HOST="openwrt.daypass.workers.dev"
WORKER_UPSTREAM_HOST="downloads.openwrt.org"
WORKER_OPKG_FEEDS="/etc/opkg/distfeeds.conf"
WORKER_APK_REPOS="/etc/apk/repositories"

# ---------- Worker identity (must match config/worker.js) ----------
WORKER_SCRIPT_NAME="daypass-mirror"
WORKER_MODULE_NAME="worker.js"
WORKER_COMPAT_DATE="2025-01-01"
WORKER_HEALTH_PATH="/daypass-health"
WORKER_HEALTH_ID="daypass-openwrt"
WORKER_CF_API="https://api.cloudflare.com/client/v4"
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

# $1 prompt — reads without echoing; result in WB_SECRET
_wb_read_secret() {
    WB_SECRET=""

    printf '  %s%s :%s ' "$CYAN" "$1" "$RESET"

    if command -v stty >/dev/null 2>&1 && stty -echo </dev/tty 2>/dev/null; then
        if read -r WB_SECRET </dev/tty; then
            stty echo </dev/tty 2>/dev/null
            printf '\n'
            return 0
        fi
        stty echo </dev/tty 2>/dev/null
        printf '\n'
        return 1
    fi

    _wb_warn "Terminal echo cannot be disabled — the token will be visible."
    read -r WB_SECRET </dev/tty || return 1
    return 0
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
            _wb_hint "Deploy option 2 to get a verified Worker, or continue if you"
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

# Health probe with retries: a fresh deployment needs a few seconds.
_wb_wait_for_worker() {
    local _host="$1"
    local _tries="${2:-6}"
    local _n=1

    while [ "$_n" -le "$_tries" ]; do
        if _wb_health_probe "$_host"; then
            return 0
        fi
        _wb_info "Worker not answering yet (${_n}/${_tries}) ..."
        [ "$_n" -lt "$_tries" ] && sleep 3
        _n=$((_n + 1))
    done

    return 1
}

# ------------------------------------------------------------
# Worker source (embedded by the build, on disk, or downloaded)
# ------------------------------------------------------------
_wb_mirror_branch() {
    if command -v help_branch >/dev/null 2>&1; then
        help_branch
    else
        echo "main"
    fi
}

# $1 destination — leaves a validated worker.js behind
_wb_mirror_source() {
    local _out="$1"
    local _candidate
    local _url

    if command -v daypass_embedded_worker_js >/dev/null 2>&1; then
        if daypass_embedded_worker_js > "$_out" 2>/dev/null && _wb_mirror_valid "$_out"; then
            _wb_ok "Worker source : embedded in this installer."
            return 0
        fi
    fi

    for _candidate in "${DAYPASS_DIR:-/etc/daypass}/worker.js" "config/worker.js" "./worker.js"; do
        [ -f "$_candidate" ] || continue
        if cp "$_candidate" "$_out" 2>/dev/null && _wb_mirror_valid "$_out"; then
            _wb_ok "Worker source : ${_candidate}"
            return 0
        fi
    done

    for _url in \
        "${REPO_URL:+${REPO_URL%/}/worker.js}" \
        "https://cdn.jsdelivr.net/gh/${WORKER_REPO_SLUG}@$(_wb_mirror_branch)/config/worker.js" \
        "https://raw.githubusercontent.com/${WORKER_REPO_SLUG}/$(_wb_mirror_branch)/config/worker.js"
    do
        [ -n "$_url" ] || continue
        if _wb_http_fetch "$_url" "$_out" && _wb_mirror_valid "$_out"; then
            _wb_ok "Worker source : downloaded."
            return 0
        fi
    done

    rm -f "$_out" 2>/dev/null
    _wb_err "Could not obtain the Worker script (config/worker.js)."
    return 1
}

_wb_mirror_valid() {
    [ -s "$1" ] || return 1
    grep -q 'export default' "$1" 2>/dev/null || return 1
    grep -qF "$WORKER_HEALTH_ID" "$1" 2>/dev/null || return 1
    return 0
}

# ------------------------------------------------------------
# Cloudflare REST API
# ------------------------------------------------------------
WB_API_OUT=""
WB_API_CODE=""
WB_API_TOKEN=""

_wb_api_reset() {
    WB_API_TOKEN=""
    WB_SECRET=""
    rm -f "${WORKER_TMP}".* 2>/dev/null
    return 0
}

# $1 method, $2 api path, $3 body file (optional), $4 content type (optional)
# Uses daypass_http_request (curl, then uclient-fetch, then wget).
_wb_api_call() {
    local _method="$1"
    local _path="$2"
    local _body="$3"
    local _ctype="$4"
    local _hdr="${WORKER_TMP}.hdr"
    local _code
    local _umask

    WB_API_OUT="${WORKER_TMP}.api"
    rm -f "$WB_API_OUT" "$_hdr" 2>/dev/null

    _umask="$(umask)"
    umask 077
    {
        printf 'Authorization: Bearer %s\n' "$WB_API_TOKEN"
        [ -n "$_ctype" ] && printf 'Content-Type: %s\n' "$_ctype"
    } > "$_hdr" 2>/dev/null
    umask "$_umask"

    if ! command -v daypass_http_request >/dev/null 2>&1; then
        WB_API_CODE="000"
        printf '%s\n' "HTTP helper is not loaded." > "${DAYPASS_HTTP_ERR:-/tmp/daypass_http.err}"
        return 1
    fi

    _code="$(daypass_http_request "$_method" "${WORKER_CF_API}${_path}" "$WB_API_OUT" "$_body" "$_hdr")"
    rm -f "$_hdr" 2>/dev/null
    WB_API_CODE="$(printf '%s\n' "$_code" | tail -n 1)"
    [ -n "$WB_API_CODE" ] || WB_API_CODE="000"

    case "$WB_API_CODE" in
        2[0-9][0-9]) return 0 ;;
    esac
    return 1
}

_wb_api_success() {
    [ -s "$WB_API_OUT" ] || return 1

    if command -v jq >/dev/null 2>&1; then
        [ "$(jq -r '.success // false' "$WB_API_OUT" 2>/dev/null)" = "true" ] && return 0
        return 1
    fi

    tr -d ' \t\n\r' < "$WB_API_OUT" 2>/dev/null | grep -qF '"success":true'
}

# $1 jq path (e.g. .result.subdomain), $2 fallback JSON key name
_wb_api_field() {
    [ -s "$WB_API_OUT" ] || return 1

    if command -v jq >/dev/null 2>&1; then
        jq -r "$1 // empty" "$WB_API_OUT" 2>/dev/null
        return 0
    fi

    sed -n "s|.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*|\1|p" "$WB_API_OUT" 2>/dev/null \
        | head -n 1
}

_wb_put_unsupported() {
    [ "${WB_API_CODE:-000}" = "000" ] || return 1
    [ -s "${DAYPASS_HTTP_ERR:-/tmp/daypass_http.err}" ] || return 1
    grep -q '^PUT_UNSUPPORTED$' "${DAYPASS_HTTP_ERR:-/tmp/daypass_http.err}"
}

# Stock wget cannot PUT. Point the user at a manual deploy, then option 1.
# $1 path to the prepared worker.js
_wb_manual_worker_guide() {
    local _js="$1"
    local _paste="/tmp/daypass_worker.js"
    local _link="https://deploy.workers.cloudflare.com/?url=https://github.com/${WORKER_REPO_SLUG}"

    if [ -s "$_js" ]; then
        cp "$_js" "$_paste" 2>/dev/null || _paste="$_js"
    fi

    echo
    _wb_warn "CLI PUT upload not supported by stock wget."
    _wb_hint "Feeds are unchanged. Deploy the script once, then import its hostname"
    _wb_hint "with option 1."
    echo
    _wb_info "1-click Cloudflare deploy (open on a computer):"
    printf '      %s%s%s\n' "$CYAN" "$_link" "$RESET"
    echo
    if [ -s "$_paste" ]; then
        _wb_info "Worker script saved for pasting:"
        printf '      %s%s%s\n' "$CYAN" "$_paste" "$RESET"
        _wb_hint "Dashboard → Workers & Pages → Create → paste that file → Deploy."
    fi
    echo
    _wb_hint "When the Worker answers, choose option 1 and enter its workers.dev URL."
}

_wb_api_report_errors() {
    if [ "${WB_API_CODE:-000}" = "000" ] && [ -s "${DAYPASS_HTTP_ERR:-/tmp/daypass_http.err}" ]; then
        _wb_err "$(sed -n '1p' "${DAYPASS_HTTP_ERR:-/tmp/daypass_http.err}")"
        return 0
    fi

    _wb_err "Cloudflare API returned HTTP ${WB_API_CODE}."

    [ -s "$WB_API_OUT" ] || return 0

    if command -v jq >/dev/null 2>&1; then
        jq -r '.errors[]? | "      - [\(.code // "?")] \(.message // "unknown error")"' \
            "$WB_API_OUT" 2>/dev/null | head -n 5
    else
        sed -n 's|.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*|      - \1|p' \
            "$WB_API_OUT" 2>/dev/null | head -n 5
    fi

    return 0
}

# Builds the multipart/form-data body the Workers script API expects for an
# ES-module Worker. Boundary ends up in WB_MP_BOUNDARY.
# $1 worker.js, $2 output body file
_wb_build_multipart() {
    local _js="$1"
    local _out="$2"

    WB_MP_BOUNDARY="DayPassMirror$$$(date +%s 2>/dev/null)"

    {
        printf -- '--%s\r\n' "$WB_MP_BOUNDARY"
        printf 'Content-Disposition: form-data; name="metadata"; filename="metadata.json"\r\n'
        printf 'Content-Type: application/json\r\n\r\n'
        printf '{"main_module":"%s","compatibility_date":"%s","bindings":[]}\r\n' \
            "$WORKER_MODULE_NAME" "$WORKER_COMPAT_DATE"
        printf -- '--%s\r\n' "$WB_MP_BOUNDARY"
        printf 'Content-Disposition: form-data; name="%s"; filename="%s"\r\n' \
            "$WORKER_MODULE_NAME" "$WORKER_MODULE_NAME"
        printf 'Content-Type: application/javascript+module\r\n\r\n'
        cat "$_js"
        printf '\r\n--%s--\r\n' "$WB_MP_BOUNDARY"
    } > "$_out" 2>/dev/null

    [ -s "$_out" ]
}

_wb_valid_account_id() {
    case "$1" in
        *[!0-9a-fA-F]*) return 1 ;;
        ????????????????????????????????) return 0 ;;
    esac
    return 1
}

_wb_valid_token() {
    case "$1" in
        '')                 return 1 ;;
        *[!A-Za-z0-9_.-]*)  return 1 ;;
    esac

    # Cloudflare tokens are 40 characters; stay lenient but reject typos.
    [ "${#1}" -ge 20 ] || return 1
    return 0
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
# Menu 2 — deploy / update the Worker through the Cloudflare API
# ------------------------------------------------------------
worker_api_deploy() {
    local _account=""
    local _js="${WORKER_TMP}.worker.js"
    local _body="${WORKER_TMP}.multipart"
    local _json="${WORKER_TMP}.json"
    local _subdomain=""
    local _host=""
    local _action="Creating"
    local _rc=1

    printf '  %s⚡ Deploy the DayPass mirror to your Cloudflare account%s\n' "$BOLD" "$RESET"
    printf '  %s─────────────────────────────────────────────────────────%s\n' "$GRAY" "$RESET"
    _wb_hint "Needs an API token with : Account → Cloudflare Workers → Edit"
    _wb_hint "Create one at dash.cloudflare.com → My Profile → API Tokens."
    _wb_hint "The Account ID is on the right side of any domain overview."
    printf '\n'

    if ! daypass_http_available; then
        _wb_err "No HTTP client found (curl, uclient-fetch or wget)."
        _wb_hint "Use option 1 with a Worker you deployed by hand."
        return 1
    fi

    printf '  %sCloudflare Account ID%s : ' "$CYAN" "$RESET"
    read -r _account </dev/tty || return 1
    _account="$(printf '%s' "$_account" | tr -d ' \t\r')"

    if [ -z "$_account" ]; then
        _wb_warn "Cancelled — nothing was deployed and feeds are unchanged."
        return 1
    fi

    if ! _wb_valid_account_id "$_account"; then
        _wb_err "That does not look like an Account ID (32 hex characters)."
        return 1
    fi

    if ! _wb_read_secret "Cloudflare API Token (hidden)"; then
        _wb_warn "Cancelled — nothing was deployed and feeds are unchanged."
        _wb_api_reset
        return 1
    fi

    WB_API_TOKEN="$WB_SECRET"
    WB_SECRET=""

    if ! _wb_valid_token "$WB_API_TOKEN"; then
        _wb_err "Empty or malformed API token."
        _wb_api_reset
        return 1
    fi

    # 1. token
    _wb_info "Verifying the API token ..."
    if ! _wb_api_call GET "/user/tokens/verify" || ! _wb_api_success; then
        _wb_api_report_errors
        _wb_hint "Feeds are unchanged."
        _wb_api_reset
        return 1
    fi
    _wb_ok "Token accepted by Cloudflare."

    # 2. worker source
    if ! _wb_mirror_source "$_js"; then
        _wb_api_reset
        return 1
    fi

    # 3. create or update?
    if _wb_api_call GET "/accounts/${_account}/workers/scripts/${WORKER_SCRIPT_NAME}"; then
        _action="Updating"
        _wb_info "Script [${WORKER_SCRIPT_NAME}] exists — it will be overwritten."
    else
        _wb_info "Script [${WORKER_SCRIPT_NAME}] not found — it will be created."
    fi

    # 4. upload
    if ! _wb_build_multipart "$_js" "$_body"; then
        _wb_err "Failed to build the upload body."
        _wb_api_reset
        return 1
    fi

    _wb_info "${_action} Worker [${WORKER_SCRIPT_NAME}] ..."
    if ! _wb_api_call PUT "/accounts/${_account}/workers/scripts/${WORKER_SCRIPT_NAME}" \
        "$_body" "multipart/form-data; boundary=${WB_MP_BOUNDARY}" || ! _wb_api_success; then
        if _wb_put_unsupported; then
            _wb_manual_worker_guide "$_js"
            _wb_api_reset
            return 1
        fi
        _wb_api_report_errors
        _wb_hint "Check that the token has Account → Cloudflare Workers → Edit."
        _wb_hint "Feeds are unchanged."
        _wb_api_reset
        return 1
    fi
    _wb_ok "Worker script uploaded."

    # 5. account workers.dev subdomain
    if ! _wb_api_call GET "/accounts/${_account}/workers/subdomain" || ! _wb_api_success; then
        _wb_api_report_errors
        _wb_hint "Register a workers.dev subdomain once in the Cloudflare dashboard."
        _wb_api_reset
        return 1
    fi

    _subdomain="$(_wb_api_field '.result.subdomain' 'subdomain')"
    _subdomain="$(printf '%s' "$_subdomain" | tr -d ' \t\r\n')"

    if [ -z "$_subdomain" ]; then
        _wb_err "This account has no workers.dev subdomain yet."
        _wb_hint "Create it in the dashboard (Workers & Pages → subdomain), then retry."
        _wb_api_reset
        return 1
    fi

    # 6. route it on *.workers.dev
    printf '{"enabled":true,"previews_enabled":false}\n' > "$_json" 2>/dev/null
    _wb_info "Enabling the workers.dev route ..."
    if ! _wb_api_call POST \
        "/accounts/${_account}/workers/scripts/${WORKER_SCRIPT_NAME}/subdomain" \
        "$_json" "application/json" || ! _wb_api_success; then
        _wb_api_report_errors
        _wb_hint "Enable the workers.dev route for [${WORKER_SCRIPT_NAME}] by hand,"
        _wb_hint "then import the URL with option 1."
        _wb_api_reset
        return 1
    fi
    _wb_ok "Route enabled on *.workers.dev."

    _host="${WORKER_SCRIPT_NAME}.${_subdomain}.workers.dev"
    _wb_api_reset

    _wb_ok "Deployed → ${BOLD}https://${_host}/${RESET}"

    # 7. prove it answers before any feed file is touched
    _wb_info "Waiting for the Worker to answer its health check ..."
    if ! _wb_wait_for_worker "$_host" 6; then
        _wb_err "The Worker did not pass the health check yet."
        _wb_hint "Propagation can take a minute. Feeds are unchanged — import"
        _wb_hint "[${_host}] with option 1 once https://${_host}${WORKER_HEALTH_PATH} answers."
        return 1
    fi
    _wb_ok "Health check passed — verified DayPass mirror."

    # 8. apply (probe already done)
    if worker_bootstrap_apply "$_host" "verified"; then
        _wb_info "Package updates will now go through your own Worker."
        _rc=0
    fi

    return "$_rc"
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
        printf '  %s🔗 1)%s Import Custom Worker Domain / URL\n' "$WHITE" "$RESET"
        printf '  %s⚡ 2)%s Auto-Deploy / Update Worker via Cloudflare API\n' "$WHITE" "$RESET"
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
            1) worker_import_domain || true ;;
            2) worker_api_deploy    || true ;;
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
