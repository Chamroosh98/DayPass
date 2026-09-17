#!/bin/sh

deploy_system_dependencies()
{
    detect_package_manager
    
    if [ -z "$OW_MAJOR_VER" ]; then
        if [ "$PKG_MANAGER" = "apk" ]; then
            OW_MAJOR_VER="25"
        else
            OW_MAJOR_VER="24"
        fi
    fi

    COMMON_DEPS="ca-bundle ca-certificates curl jq libnetfilter-conntrack"
    OW24_EXTRA_DEPS="coreutils coreutils-base64 coreutils-nohup coreutils-timeout ip-full unzip resolveip lua libuci-lua luci-compat luci-lib-jsonc luci-lua-runtime lyaml"

    TARGET_PACKAGES="$COMMON_DEPS"

    if [ "$OW_MAJOR_VER" = "24" ] && [ "$PKG_MANAGER" = "opkg" ]; then
        TARGET_PACKAGES="$TARGET_PACKAGES $OW24_EXTRA_DEPS"
    fi

    MISSING_PACKAGES=""

    for pkg in $TARGET_PACKAGES; do
        case "$pkg" in
            curl)  command -v curl >/dev/null 2>&1 && continue ;;
            jq)    command -v jq >/dev/null 2>&1 && continue ;;
            unzip) command -v unzip >/dev/null 2>&1 && continue ;;
            lua)   command -v lua >/dev/null 2>&1 && continue ;;
        esac

        if command -v pkg_installed >/dev/null 2>&1; then
            if ! pkg_installed "$pkg"; then
                MISSING_PACKAGES="$MISSING_PACKAGES $pkg"
            fi
        fi
    done

    # Keep the firmware dnsmasq (DHCP/DNS). Never remove it to install dnsmasq-full:
    # a failed swap leaves LAN without DHCP and drops SSH from DHCP clients.
    if command -v log_info >/dev/null 2>&1; then
        if command -v pkg_installed >/dev/null 2>&1 && pkg_installed "dnsmasq-full"; then
            log_info "DNS engine : dnsmasq-full (already present, left unchanged)"
        else
            log_info "DNS engine : firmware dnsmasq (not replaced)"
        fi
    fi

    if [ -z "$MISSING_PACKAGES" ]; then
        log_success "Core system dependencies are ready & up to date!"
        return 0
    fi

    log_info "Setting up required system components for DayPass (OpenWrt v$OW_MAJOR_VER) ..."

    (pkg_update >/dev/null 2>&1) &
    BG_PID=$!
    if command -v show_timer_progress >/dev/null 2>&1; then
        show_timer_progress "$BG_PID" "refreshing package index"
    fi
    wait "$BG_PID"

    if [ -n "$MISSING_PACKAGES" ]; then
        for pkg in $MISSING_PACKAGES; do
            (pkg_install "$pkg" >/dev/null 2>&1) &
            BG_PID=$!
            
            if command -v show_timer_progress >/dev/null 2>&1; then
                show_timer_progress "$BG_PID" "installing core tool [$pkg]"
            fi
            wait "$BG_PID"
        done
    fi

    log_success "All system dependencies configured successfully!"
}