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