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

    DNSMASQ_FULL_MISSING=0
    if [ -f /etc/openwrt_release ]; then
        if command -v pkg_installed >/dev/null 2>&1; then
            if ! pkg_installed "dnsmasq-full"; then
                DNSMASQ_FULL_MISSING=1
            fi
        fi
    fi

    if [ -z "$MISSING_PACKAGES" ] && [ "$DNSMASQ_FULL_MISSING" -eq 0 ]; then
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

    if [ "$DNSMASQ_FULL_MISSING" -eq 1 ]; then
        (
            case "$PKG_MANAGER" in
                opkg)
                    opkg remove dnsmasq --force-depends >/dev/null 2>&1 || true
                    opkg install dnsmasq-full libnetfilter-conntrack --force-overwrite >/dev/null 2>&1 || true
                    ;;
                apk)
                    apk del dnsmasq >/dev/null 2>&1 || true
                    apk add --allow-untrusted dnsmasq-full libnetfilter-conntrack >/dev/null 2>&1 || true
                    ;;
            esac
        ) &
        
        BG_PID=$!
        if command -v show_timer_progress >/dev/null 2>&1; then
            show_timer_progress "$BG_PID" "optimizing DNS engine (dnsmasq-full)"
        fi
        wait "$BG_PID"
        
        echo "nameserver 8.8.8.8" > /tmp/resolv.conf.auto 2>/dev/null || true
        /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
        /etc/init.d/network reload >/dev/null 2>&1 || true
        sleep 2
    fi

    log_success "All system dependencies configured successfully!"
}