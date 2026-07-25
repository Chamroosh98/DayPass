#!/bin/sh

detect_package_manager()
{
    rm -f /var/lock/opkg.lock /lib/apk/db/lock /var/run/apk.lock 2>/dev/null
    
    # 1. Identify standard package manager binary
    if command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
        log_info "Package manager identified : [apk] (Alpine/OpenWrt NextGen)"
    elif command -v opkg >/dev/null 2>&1; then
        PKG_MANAGER="opkg"
        log_info "Package manager identified : [opkg] (Legacy OpenWrt)"
    else
        log_error "Critical Error : Neither 'apk' nor 'opkg' package manager was found!"
        exit 1
    fi

    export PKG_MANAGER
}

pkg_update()
{
    log_info "Updating package indexes using [$PKG_MANAGER] ..."

    if [ "$PKG_MANAGER" = "apk" ]; then
        # Standard update first; if IPv6/DNS issues occur, fall back to IPv4
        if ! apk update --network-timeout 5 >/dev/null 2>&1; then
            log_warn "Standard APK update failed/timed out! Attempting fallback via IPv4 ..."
            if ! apk update --force-ipv4 --network-timeout 5 >/dev/null 2>&1; then
                log_warn "APK update encountered repository warnings. Proceeding with local cache ..."
            else
                log_success "APK indexes updated successfully using IPv4 fallback."
            fi
        else
            log_success "APK package indexes updated successfully."
        fi

    elif [ "$PKG_MANAGER" = "opkg" ]; then
        if ! opkg update >/dev/null 2>&1; then
            log_warn "OPKG update encountered minor mirror warnings. Proceeding anyway ..."
        else
            log_success "OPKG package indexes updated successfully."
        fi
    fi
}

pkg_installed()
{
    PACKAGE_NAME="$1"

    # Check if target package is registered as installed in the local DB
    if [ "$PKG_MANAGER" = "apk" ]; then
        apk info -e "$PACKAGE_NAME" >/dev/null 2>&1
    elif [ "$PKG_MANAGER" = "opkg" ]; then
        opkg list-installed | grep -q "^$PACKAGE_NAME - "
    fi
}

pkg_install()
{
    PACKAGE_NAME="$1"

    log_info "Executing package installation : [$PACKAGE_NAME]"

    if [ "$PKG_MANAGER" = "apk" ]; then
        # 1. Try standard installation with untrusted keyring bypass (for local/custom builds)
        if apk add --no-cache --allow-untrusted "$PACKAGE_NAME" >/dev/null 2>&1; then
            log_success "Package [$PACKAGE_NAME] installed successfully via APK."
            return 0
        fi

        # 2. Fallback attempt using IPv4 explicit routing if network fails
        log_warn "Standard APK installation failed for [$PACKAGE_NAME]. Trying IPv4 fallback..."
        if apk add --force-ipv4 --no-cache --allow-untrusted "$PACKAGE_NAME" >/dev/null 2>&1; then
            log_success "Package [$PACKAGE_NAME] installed successfully via APK (IPv4 fallback)."
            return 0
        fi

        log_error "APK failed to install package : [$PACKAGE_NAME]"
        return 1

    elif [ "$PKG_MANAGER" = "opkg" ]; then
        # Install with opkg bypassing unverified signature warnings
        if opkg install --force-checksum "$PACKAGE_NAME" >/dev/null 2>&1; then
            log_success "Package [$PACKAGE_NAME] installed successfully via OPKG."
            return 0
        fi

        log_error "OPKG failed to install package : [$PACKAGE_NAME]"
        return 1
    fi
}