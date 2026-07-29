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
        ver=$(apk list --installed "$pkg" 2>/dev/null | awk '{print $1}' | sed "s/^$pkg-//")
        [ -z "$ver" ] && ver=$(apk info -v "$pkg" 2>/dev/null | sed "s/^$pkg-//")
        echo "$ver"
    elif [ "$PKG_MANAGER" = "opkg" ]; then
        opkg status "$pkg" 2>/dev/null | awk '/^Version:/ {print $2}'
    fi
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
        log_warn "Standard APK installation failed for [$PACKAGE_NAME]. Trying IPv4 fallback..." 2>/dev/null
        if apk add --force-ipv4 --no-cache --allow-untrusted "$PACKAGE_NAME" >/dev/null 2>&1; then
            log_success "Package [$PACKAGE_NAME] installed successfully via APK (IPv4 fallback)." 2>/dev/null
            return 0
        fi

        log_error "APK failed to install package : [$PACKAGE_NAME]" 2>/dev/null
        return 1

    elif [ "$PKG_MANAGER" = "opkg" ]; then
        # Install with opkg bypassing unverified signature warnings
        if opkg install --force-checksum "$PACKAGE_NAME" >/dev/null 2>&1; then
            log_success "Package [$PACKAGE_NAME] installed successfully via OPKG." 2>/dev/null
            return 0
        fi

        log_error "OPKG failed to install package : [$PACKAGE_NAME]" 2>/dev/null
        return 1
    fi
}