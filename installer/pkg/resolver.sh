#!/bin/sh

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
