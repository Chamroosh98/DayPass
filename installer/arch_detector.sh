#!/bin/sh

detect_system_architecture()
{
    log_info "Detecting system architecture and target platform ..."

    ARCH=""
    OPENWRT_VER=""
    PKG_MGR="${PKG_MANAGER:-opkg}"

    # 1. Fetch official OpenWrt architecture and release version
    if [ -f /etc/openwrt_release ]; then
        . /etc/openwrt_release
        ARCH="$DISTRIB_ARCH"
        OPENWRT_VER="$DISTRIB_RELEASE"
    elif [ -f /etc/os-release ]; then
        OPENWRT_VER=$(grep "BUILD_ID=" /etc/os-release | cut -d'"' -f2)
    fi

    # 2. Fallback to package manager native check
    if [ -z "$ARCH" ]; then
        if [ "$PKG_MGR" = "apk" ] && command -v apk >/dev/null 2>&1; then
            ARCH=$(apk --print-arch 2>/dev/null)
        elif command -v opkg >/dev/null 2>&1; then
            ARCH=$(opkg print-architecture 2>/dev/null | awk 'END {print $2}')
        fi
    fi

    # 3. Final Fallback
    if [ -z "$ARCH" ]; then
        ARCH=$(uname -m)
        log_warn "Standard OpenWrt release file unreadable. Fallback architecture : [$ARCH]"
    fi

    # 4. Extract MAJOR Version (24 vs 25)
    OW_MAJOR_VER="24"
    if echo "$OPENWRT_VER" | grep -q "^25" || [ "$PKG_MGR" = "apk" ]; then
        OW_MAJOR_VER="25"
    fi

    log_success "System architecture resolved : [$ARCH]"
    [ -n "$OPENWRT_VER" ] && log_info "OpenWrt Release version : [$OPENWRT_VER] (Major: v$OW_MAJOR_VER)"

    export ARCH
    export OPENWRT_VER
    export OW_MAJOR_VER
}

# Standalone execution handler for testing
case "$0" in
    *arch_detector.sh)
        detect_system_architecture
        ;;
esac