#!/bin/sh

# Architecture & Target Detector Module for OpenWrt 24 (opkg) & OpenWrt 25 (apk)
# Matches system architecture against DayPass configuration JSONs

detect_system_architecture()
{
    log_info "Detecting system architecture and target platform ..."

    ARCH=""
    OPENWRT_VER=""
    PKG_MGR="${PKG_MANAGER:-opkg}"

    # 1. Fetch official OpenWrt architecture from os-release / openwrt_release
    if [ -f /etc/openwrt_release ]; then
        # Read DISTRIB_ARCH (e.g., aarch64_cortex-a53, mips_24kc, x86_64)
        ARCH=$(grep "DISTRIB_ARCH=" /etc/openwrt_release | cut -d"'" -f2)
        OPENWRT_VER=$(grep "DISTRIB_RELEASE=" /etc/openwrt_release | cut -d"'" -f2)
    elif [ -f /etc/os-release ]; then
        OPENWRT_VER=$(grep "BUILD_ID=" /etc/os-release | cut -d'"' -f2)
    fi

    # 2. Fallback to package manager native architecture check
    if [ -z "$ARCH" ]; then
        if [ "$PKG_MGR" = "apk" ] && command -v apk >/dev/null 2>&1; then
            ARCH=$(apk --print-arch 2>/dev/null)
        elif command -v opkg >/dev/null 2>&1; then
            ARCH=$(opkg print-architecture 2>/dev/null | awk 'END {print $2}')
        fi
    fi

    # 3. Final Fallback to POSIX uname machine hardware name
    if [ -z "$ARCH" ]; then
        UNAME_ARCH=$(uname -m)
        case "$UNAME_ARCH" in
            aarch64|arm64)       ARCH="aarch64_cortex-a53" ;;
            armv7l|armv7)        ARCH="arm_cortex-a7_neon-vfpv4" ;;
            mips)                ARCH="mips_24kc" ;;
            mipsel)              ARCH="mipsel_24kc" ;;
            x86_64)              ARCH="x86_64" ;;
            i686|i386)           ARCH="i386_pentium4" ;;
            *)                   ARCH="$UNAME_ARCH" ;;
        esac
        log_warn "Standard OpenWrt release file unreadable. Fallback mapped architecture to : [$ARCH]"
    fi

    # Normalize architecture name if using APK on OpenWrt 25 (e.g. mapping aarch64_cortex-a53 -> aarch64)
    if [ "$PKG_MGR" = "apk" ]; then
        case "$ARCH" in
            aarch64*) ARCH="aarch64" ;;
            arm*)     ARCH="armv7" ;;
            mips*)    ARCH="mips" ;;
            x86_64*)  ARCH="x86_64" ;;
        esac
    fi

    # 4. Verify against architecture configuration files
    CONFIG_JSON=""
    if [ "$PKG_MGR" = "apk" ]; then
        CONFIG_JSON="config/architectures_25.json"
    else
        CONFIG_JSON="config/architectures_24.json"
    fi

    if [ -f "$CONFIG_JSON" ] && command -v jq >/dev/null 2>&1; then
        MATCH_FOUND=$(jq -r --arg arch "$ARCH" '.architectures[]? | select(.name == $arch) | .name' "$CONFIG_JSON" 2>/dev/null)
        if [ -n "$MATCH_FOUND" ] && [ "$MATCH_FOUND" != "null" ]; then
            log_success "Architecture [$ARCH] verified against [$CONFIG_JSON]."
        else
            log_warn "Architecture [$ARCH] was not explicitly found in [$CONFIG_JSON]. Proceeding with generic profile."
        fi
    fi

    log_success "System architecture resolved : [$ARCH]"
    [ -n "$OPENWRT_VER" ] && log_info "OpenWrt Release version : [$OPENWRT_VER]"

    export ARCH
    export OPENWRT_VER
}

# Standalone execution handler for testing
case "$0" in
    *arch_detector.sh)
        detect_system_architecture
        ;;
esac