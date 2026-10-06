#!/bin/sh

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

# $1 apk|opkg. Prints the IPv4-only flag that binary accepts, or nothing.
# opkg accepts --force-ipv4. OpenWrt 25 apk does not; only --ipv4 or -4
# are passed when `apk --help` actually lists them.
pkg_ipv4_flag()
{
    _pf_help=""

    case "$1" in
        opkg)
            printf '%s\n' "--force-ipv4"
            return 0
            ;;
        apk)
            _pf_help=$(apk --help 2>&1 || true)
            case "$_pf_help" in
                *--ipv4*)
                    printf '%s\n' "--ipv4"
                    return 0
                    ;;
            esac
            case "$_pf_help" in
                *" -4 "*|*" -4,"*|*"[-4"*|*"( -4)"*)
                    printf '%s\n' "-4"
                    return 0
                    ;;
            esac
            ;;
    esac
    return 1
}

# Update package index with fallback logic for network/mirror failures
pkg_update()
{
    [ -z "${PKG_MANAGER:-}" ] && detect_package_manager

    log_info "Updating package indexes using [$PKG_MANAGER] ..." 2>/dev/null || echo "[INFO] Updating package indexes..."

    if [ "$PKG_MANAGER" = "apk" ]; then
        # Standard update first; if IPv6/DNS issues occur, fall back to IPv4
        (apk update --network-timeout 5 >/dev/null 2>&1) &
        if command -v ui_spinner >/dev/null 2>&1; then
            ui_spinner $! "Updating package database ..."
        else
            wait $!
        fi
        if [ $? -ne 0 ]; then
            _pf_flag=$(pkg_ipv4_flag apk) || _pf_flag=""
            if [ -z "$_pf_flag" ]; then
                log_warn "apk has no IPv4-only option on this build. Proceeding with the local cache ..." 2>/dev/null
            else
                log_warn "Standard APK update failed/timed out! Retrying with [$_pf_flag] ..." 2>/dev/null
                (apk update "$_pf_flag" --network-timeout 5 >/dev/null 2>&1) &
                if command -v ui_spinner >/dev/null 2>&1; then
                    ui_spinner $! "Updating package database ..."
                else
                    wait $!
                fi
                if [ $? -ne 0 ]; then
                    log_warn "APK update encountered repository warnings. Proceeding with local cache ..." 2>/dev/null
                else
                    log_success "APK indexes updated successfully using IPv4 fallback." 2>/dev/null
                fi
            fi
        else
            log_success "APK package indexes updated successfully." 2>/dev/null
        fi

    elif [ "$PKG_MANAGER" = "opkg" ]; then
        (opkg update >/dev/null 2>&1) &
        if command -v ui_spinner >/dev/null 2>&1; then
            ui_spinner $! "Updating package database ..."
        else
            wait $!
        fi
        if [ $? -ne 0 ]; then
            log_warn "OPKG update failed. Retrying with [--force-ipv4] ..." 2>/dev/null
            (opkg update --force-ipv4 >/dev/null 2>&1) &
            if command -v ui_spinner >/dev/null 2>&1; then
                ui_spinner $! "Updating package database ..."
            else
                wait $!
            fi
            if [ $? -ne 0 ]; then
                log_warn "OPKG update encountered minor mirror warnings. Proceeding anyway ..." 2>/dev/null
            else
                log_success "OPKG package indexes updated using IPv4." 2>/dev/null
            fi
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

        # 2. IPv4 retry only when this apk build documents an address-family flag
        _pf_flag=$(pkg_ipv4_flag apk) || _pf_flag=""
        if [ -n "$_pf_flag" ]; then
            log_warn "Standard APK installation failed for [$PACKAGE_NAME]. Retrying with [$_pf_flag] ..." 2>/dev/null
            if apk add "$_pf_flag" --no-cache --allow-untrusted "$PACKAGE_NAME" >/dev/null 2>&1; then
                log_success "Package [$PACKAGE_NAME] installed successfully via APK (IPv4 fallback)." 2>/dev/null
                return 0
            fi
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