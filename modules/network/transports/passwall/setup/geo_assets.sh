#!/bin/sh

# Publish only complete pairs. Readers must ignore directories without READY.
# The hashes pin the exact, audited bytes even if the moving release URL changes.
pw_stage_iran_assets() (
    umask 077
    local variant="$1" mode="$2" ip_url="$3" site_url="$4"
    local ip_hash site_hash minimum_kib available_kib
    local base="${DAYPASS_DIR:-/etc/daypass}" generation owner

    case "$variant" in passwall|passwall2) ;; *) return 1 ;; esac
    case "$mode:$ip_url:$site_url" in
        "iran-full:https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geoip.dat:https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geosite.dat")
            ip_hash=2c8b3f92780e6d7409bd5b5ec9fd049cf3965c5c474ee8caed50715050b17bd4
            site_hash=1ea5255b0b110aca3da839367b19d14a1c6c9ef257d4e26606e492e3062b67a5
            minimum_kib=$(( (16497331 + 8226561 + 1023) / 1024 ))
            ;;
        "iran-lite:https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geoip-lite.dat:https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geosite-lite.dat")
            ip_hash=595156a2d13a0a0ddafa15172a2b407169b6acb1bc43485cc68fb04954fb5dd0
            site_hash=528bb8055d40b566d437eec216e8754420100dc3fc5e68a2cd0ee412e898e8a4
            minimum_kib=$(( (37252 + 1948383 + 1023) / 1024 ))
            ;;
        *) log_error "Unrecognized Passwall dataset source."; return 1 ;;
    esac

    if [ ! -e "$base" ] && [ ! -L "$base" ]; then
        mkdir "$base" || return 1
    fi
    owner=$(id -u) || return 1
    if [ ! -d "$base" ] || [ -L "$base" ]; then
        log_error "The DayPass data path is not a regular directory."
        return 1
    fi
    case "$(stat -c '%u:%a' "$base")" in
        "$owner:700"|"$owner:750"|"$owner:755") ;;
        *) log_error "The DayPass data directory has unexpected ownership or permissions."; return 1 ;;
    esac

    available_kib=$(df -Pk "$base" | awk 'NR == 2 { print $4 }')
    case "$available_kib" in ''|*[!0-9]*) return 1 ;; esac
    if [ "$available_kib" -lt "$minimum_kib" ]; then
        log_error "Insufficient storage to stage the $mode dataset pair."
        return 1
    fi

    generation=$(mktemp -d "$base/$variant-$mode.XXXXXX") || return 1
    trap '[ -f "$generation/READY" ] || rm -rf -- "$generation"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    if ! _pr_stage_payload "$ip_url" "$generation/geoip.dat" "$ip_hash" ||
       ! _pr_stage_payload "$site_url" "$generation/geosite.dat" "$site_hash"; then
        log_error "Could not stage the complete verified $mode dataset pair."
        return 1
    fi

    printf 'variant=%s\nmode=%s\ngeoip_sha256=%s\ngeosite_sha256=%s\n' \
        "$variant" "$mode" "$ip_hash" "$site_hash" > "$generation/READY.tmp" || return 1
    sync || return 1
    mv "$generation/READY.tmp" "$generation/READY" || return 1
    sync || return 1

    log_info "Verified dataset pair staged at [$generation]. The running engine was left unchanged."
)
