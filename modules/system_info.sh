#!/bin/sh

detect_arch()
{
    ARCH=""

    # 1. Primary method: Read DISTRIB_ARCH directly from release file
    if [ -f /etc/openwrt_release ]; then
        . /etc/openwrt_release
        ARCH="${DISTRIB_ARCH:-}"
    fi

    # 2. Secondary fallback: Query package managers (apk for v25 / opkg for v24)
    if [ -z "$ARCH" ]; then
        if command -v apk >/dev/null 2>&1; then
            ARCH="$(apk --print-arch 2>/dev/null)"
        elif command -v opkg >/dev/null 2>&1; then
            ARCH="$(opkg print-architecture 2>/dev/null | awk 'NR==1{print $2}')"
        fi
    fi

    # 3. Final fallback: Map kernel architecture (uname -m) to standard OpenWrt targets
    if [ -z "$ARCH" ]; then
        case "$(uname -m)" in
            armv7l)  ARCH="arm_cortex-a7_neon-vfpv4" ;;
            aarch64) ARCH="aarch64_generic" ;;
            x86_64)  ARCH="x86_64" ;;
            *)       ARCH="$(uname -m)" ;;
        esac
    fi

    export ARCH
}

show_system_info_content()
{
    detect_arch
    
    OW_VER="Unknown"
    if [ -f /etc/openwrt_release ]; then
        . /etc/openwrt_release
        OW_VER="${DISTRIB_RELEASE:-Unknown}"
    fi

    TOTAL_RAM_MB=$(get_total_ram_mb)
    FREE_RAM_MB=$(get_free_ram_mb)
    USED_RAM_MB=$((TOTAL_RAM_MB - FREE_RAM_MB))
    
    MEM_PCT=0
    [ "$TOTAL_RAM_MB" -gt 0 ] && MEM_PCT=$((USED_RAM_MB * 100 / TOTAL_RAM_MB))

    TOTAL_STO_MB=$(get_total_storage_mb)
    FREE_STO_MB=$(get_free_storage_mb)
    USED_STO_MB=$((TOTAL_STO_MB - FREE_STO_MB))
    
    STO_PCT=0
    [ "$TOTAL_STO_MB" -gt 0 ] && STO_PCT=$((USED_STO_MB * 100 / TOTAL_STO_MB))

    # Tree-Style Clean Rendering
    printf " 🖥️  ${BOLD}System Overview${RESET}\n"
    printf " ├── 🩻 Architecture : ${CYAN}%s${RESET}\n" "$ARCH"
    printf " ├── 💡 OpenWrt      : ${CYAN}%s${RESET}\n" "$OW_VER"
    
    printf " ├── 🧠 Memory       : "
    draw_bar "$MEM_PCT" 16 "usage"
    printf " ${BOLD}%3d%%${RESET} (%s/%s MB)\n" "$MEM_PCT" "$USED_RAM_MB" "$TOTAL_RAM_MB"

    printf " └── 💾 Storage      : "
    draw_bar "$STO_PCT" 16 "usage"
    printf " ${BOLD}%3d%%${RESET} (%s/%s MB)\n" "$STO_PCT" "$USED_STO_MB" "$TOTAL_STO_MB"
    echo
}

show_system_info()
{
    echo
    show_system_info_content
}

# Standalone execution handler
case "$0" in
    *system_info.sh) show_system_info ;;
esac