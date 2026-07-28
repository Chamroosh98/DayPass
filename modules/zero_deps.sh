#!/bin/sh

deploy_system_dependencies()
{
    log_info "Checking and deploying zero-dependencies ..."

    detect_package_manager
    pkg_update

    COMMON_DEPS="ca-bundle ca-certificates curl jq"
    OW24_EXTRA_DEPS="coreutils coreutils-base64 coreutils-nohup coreutils-timeout ip-full unzip resolveip lua libuci-lua luci-compat luci-lib-jsonc luci-lua-runtime lyaml"

    TARGET_PACKAGES="$COMMON_DEPS"

    if [ "$PKG_MANAGER" = "opkg" ] || [ "${OPENWRT_MAJOR:-24}" = "24" ]; then
        log_info "OpenWrt 24 detected: Adding core system & LuCI dependencies..."
        TARGET_PACKAGES="$TARGET_PACKAGES $OW24_EXTRA_DEPS"
    else
        log_info "OpenWrt 25+ detected: Using minimal base tools."
    fi

    for pkg in $TARGET_PACKAGES; do
        case "$pkg" in
            curl) command -v curl >/dev/null 2>&1 && { log_info "Dependency [$pkg] is already available."; continue; } ;;
            jq)   command -v jq >/dev/null 2>&1 && { log_info "Dependency [$pkg] is already available."; continue; } ;;
            unzip) command -v unzip >/dev/null 2>&1 && { log_info "Dependency [$pkg] is already available."; continue; } ;;
            lua)  command -v lua >/dev/null 2>&1 && { log_info "Dependency [$pkg] is already available."; continue; } ;;
        esac

        if command -v pkg_installed >/dev/null 2>&1; then
            if pkg_installed "$pkg"; then
                log_info "Package [$pkg] is already installed."
                continue
            fi
        fi

        log_info "Installing required dependency : [$pkg] ..."
        
        if pkg_install "$pkg"; then
            log_success "Package [$pkg] installed successfully."
        else
            log_warn "Failed or finished with warning while installing [$pkg]."
        fi
    done

    if [ -f /etc/openwrt_release ]; then
        log_info "Checking dnsmasq installation status ..."

        if ! pkg_installed "dnsmasq-full"; then
            log_info "Upgrading dnsmasq to dnsmasq-full ..."
            case "$PKG_MANAGER" in
                opkg)
                    opkg remove dnsmasq --force-depends >/dev/null 2>&1 || true
                    opkg install dnsmasq-full --force-overwrite >/dev/null 2>&1 || true
                    ;;
                apk)
                    apk del dnsmasq >/dev/null 2>&1 || true
                    apk add --allow-untrusted dnsmasq-full >/dev/null 2>&1 || true
                    ;;
            esac
            log_success "dnsmasq-full installed successfully."
        else
            log_success "dnsmasq-full is already present."
        fi
    fi
}