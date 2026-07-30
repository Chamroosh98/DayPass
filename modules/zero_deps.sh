#!/bin/sh

deploy_system_dependencies()
{
    log_info "Checking and deploying zero-dependencies ..."

    detect_package_manager

    # 1. Update Package Index with Dynamic Timer & Progress
    (pkg_update >/dev/null 2>&1) &
    BG_PID=$!
    if command -v show_timer_progress >/dev/null 2>&1; then
        show_timer_progress "$BG_PID" "updating package repository index"
    fi
    wait "$BG_PID"

    # Added libnetfilter-conntrack to prevent dnsmasq-full shared library crash
    COMMON_DEPS="ca-bundle ca-certificates curl jq libnetfilter-conntrack"
    OW24_EXTRA_DEPS="coreutils coreutils-base64 coreutils-nohup coreutils-timeout ip-full unzip resolveip lua libuci-lua luci-compat luci-lib-jsonc luci-lua-runtime lyaml"

    TARGET_PACKAGES="$COMMON_DEPS"

    if [ "$PKG_MANAGER" = "opkg" ] || [ "${OPENWRT_MAJOR:-24}" = "24" ]; then
        log_info "OpenWrt 24 detected: Adding core system & LuCI dependencies ..."
        TARGET_PACKAGES="$TARGET_PACKAGES $OW24_EXTRA_DEPS"
    else
        log_info "OpenWrt 25+ detected: Using minimal base tools."
    fi

    # 2. Iterate and Deploy Core System Dependencies
    for pkg in $TARGET_PACKAGES; do
        case "$pkg" in
            curl) command -v curl >/dev/null 2>&1 && { log_info "Dependency [$pkg] is already available."; continue; } ;;
            jq)   command -v jq >/dev/null 2>&1 && { log_info "Dependency [$pkg] is already available."; continue; } ;;
            unzip) command -v unzip >/dev/null 2>&1 && { log_info "Dependency [$pkg] is already available."; continue; } ;;
            lua)  command -v lua >/dev/null 2>&1 && { log_info "Dependency [$pkg] is already available."; continue; } ;;
        esac

        if command -v pkg_installed >/dev/null 2>&1; then
            if pkg_installed "$pkg"; then
                log_info "Package [$pkg] is already installed!"
                continue
            fi
        fi

        # Run Package Installation in Background with Progress UI
        (pkg_install "$pkg" >/dev/null 2>&1) &
        BG_PID=$!
        
        if command -v show_timer_progress >/dev/null 2>&1; then
            show_timer_progress "$BG_PID" "installing dependency [$pkg]"
        fi
        wait "$BG_PID"
        INSTALL_STATUS=$?

        if [ "$INSTALL_STATUS" -eq 0 ]; then
            log_success "Package [$pkg] installed successfully."
        else
            log_warn "Failed or finished with warning while installing [$pkg]."
        fi
    done

    # 3. Upgrade dnsmasq to dnsmasq-full safely for OpenWrt
    if [ -f /etc/openwrt_release ]; then
        log_info "Checking dnsmasq installation status ..."

        if ! pkg_installed "dnsmasq-full"; then
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
                show_timer_progress "$BG_PID" "upgrading to dnsmasq-full engine"
            fi
            wait "$BG_PID"
            
            # Post-installation DNS & Network Safety Reload
            log_info "Reloading DNS resolver and Network stack ..."
            /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
            /etc/init.d/network reload >/dev/null 2>&1 || true
            sleep 3

            # Network Connection Recovery Guardrail
            if ! nslookup chamroosh98.github.io >/dev/null 2>&1; then
                log_warn "DNS resolution momentary lag detected. Refreshing WAN link..."
                ifup wan >/dev/null 2>&1 || true
                sleep 3
            fi

            log_success "dnsmasq-full installed and DNS engine restarted successfully."
        else
            log_success "dnsmasq-full is already present."
            
            # Ensure libnetfilter-conntrack is present even if dnsmasq-full was already installed
            if ! pkg_installed "libnetfilter-conntrack"; then
                pkg_install "libnetfilter-conntrack" >/dev/null 2>&1 || true
                /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
            fi
        fi
    fi
}