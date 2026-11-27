#!/bin/sh

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
    
    case "$OPENWRT_MAJOR/$PKG_MANAGER" in
        24/opkg|25/apk) ;;
        *) log_error "Unsupported OpenWrt release [$OPENWRT_VERSION] with [$PKG_MANAGER]."; return 1 ;;
    esac
    export OPENWRT_MAJOR
    log_info "OpenWrt Version : $OPENWRT_VERSION ($PKG_MANAGER)"
}
