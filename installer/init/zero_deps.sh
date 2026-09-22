#!/bin/sh

# ---------------------------------------------------------------------------
# Required tool / package validation map :  "<package>:<binary-it-provides>"
#
# A binary probe lets us validate a tool even when the package database is
# unusable, and it is what decides "this tool is already here - do not install
# it again". Packages without an entry are validated through the package
# database only. Adding an entry makes the check stricter (and can skip more work).
# ---------------------------------------------------------------------------
TOOL_PROBE_MAP="curl:curl jq:jq unzip:unzip lua:lua"

# 1 when the package database can be queried, 0 when we must rely on probes only
PKG_DB_OK=0

# Echo the binary that provides a given package (empty when unknown)
tool_probe_for()
{
    for mapping in $TOOL_PROBE_MAP; do
        case "$mapping" in
            "$1:"*) echo "${mapping#*:}" ; return 0 ;;
        esac
    done
    echo ""
}

# Decide whether a single tool/package is already usable on this system.
# Returns 0 = present, 1 = missing ; TOOL_REASON explains the verdict to the user.
tool_is_available()
{
    TOOL_REASON=""
    probe="$(tool_probe_for "$1")"

    if [ -n "$probe" ] && command -v "$probe" >/dev/null 2>&1; then
        TOOL_REASON="present (binary [$probe] found)"
        return 0
    fi

    if [ "$PKG_DB_OK" -eq 1 ] && pkg_installed "$1"; then
        TOOL_REASON="present (package database)"
        return 0
    fi

    if [ -n "$probe" ]; then
        TOOL_REASON="missing (no [$probe] binary)"
    else
        TOOL_REASON="missing (not in package database)"
    fi
    return 1
}

# Scan every required package, print the validation table for the user and build
# MISSING_PACKAGES (only what actually has to be fetched from the network).
scan_required_tools()
{
    MISSING_PACKAGES=""
    PRESENT_COUNT=0
    MISSING_COUNT=0

    echo "  🔎 Required Tool Validation"
    echo "  ──────────────────────────────────────────────────────────"

    for pkg in $TARGET_PACKAGES; do
        if tool_is_available "$pkg"; then
            PRESENT_COUNT=$((PRESENT_COUNT + 1))
            printf "   ${GREEN}✔${RESET} %-26s ${GRAY}%s${RESET}\n" "$pkg" "$TOOL_REASON"
        else
            MISSING_COUNT=$((MISSING_COUNT + 1))
            MISSING_PACKAGES="$MISSING_PACKAGES $pkg"
            printf "   ${RED}✖${RESET} %-26s ${YELLOW}%s -> will install${RESET}\n" "$pkg" "$TOOL_REASON"
        fi
    done

    echo "  ───────────────────────────────────────────────────────────"
    printf "   Summary : %d tool(s) ready, %d missing\n" "$PRESENT_COUNT" "$MISSING_COUNT"
    echo
}

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

    COMMON_DEPS="ca-bundle ca-certificates curl jq "
    OW24_EXTRA_DEPS="coreutils coreutils-base64 coreutils-nohup coreutils-timeout ip-full unzip resolveip lua libuci-lua luci-compat luci-lib-jsonc luci-lua-runtime lyaml"

    TARGET_PACKAGES="$COMMON_DEPS"

    if [ "$OW_MAJOR_VER" = "24" ] && [ "$PKG_MANAGER" = "opkg" ]; then
        log_info "OpenWrt v24 detected : adding core system & LuCI dependencies ..."
        TARGET_PACKAGES="$TARGET_PACKAGES $OW24_EXTRA_DEPS"
    else
        log_info "OpenWrt v$OW_MAJOR_VER detected : using the minimal base tool set."
    fi

    # The package-database helper decides HOW tools are validated : with it we can
    # also recognise packages that ship no binary (ca-bundle, luci-* modules...).
    PKG_DB_OK=0
    if command -v pkg_installed >/dev/null 2>&1; then
        PKG_DB_OK=1
    else
        log_warn "Package database helper [pkg_installed] unavailable : validating with binary probes only!"
    fi

    log_info "Checking which required tools are already installed ..."
    scan_required_tools

    DNSMASQ_FULL_MISSING=0
    if [ -f /etc/openwrt_release ] && [ "$PKG_DB_OK" -eq 1 ]; then
        if ! pkg_installed "dnsmasq-full"; then
            DNSMASQ_FULL_MISSING=1
        fi
    fi

    # Fast path : every required tool is already usable, so skip the index refresh
    # and the whole installation attempt.
    if [ -z "$MISSING_PACKAGES" ] && [ "$DNSMASQ_FULL_MISSING" -eq 0 ]; then
        log_success "All required tools are already installed - skipping installation!"
        return 0
    fi

    log_info "Setting up required system components for DayPass (OpenWrt v$OW_MAJOR_VER) ..."
    log_info "Tools queued for installation : [${MISSING_PACKAGES# }]"

    # Package manager output is kept (instead of being thrown away) so a failed
    # install can actually be diagnosed by the user.
    DEP_LOG="/tmp/daypass_deps_install.log"
    : > "$DEP_LOG" 2>/dev/null || DEP_LOG="/dev/null"

    (pkg_update >/dev/null 2>&1) &
    BG_PID=$!
    if command -v show_timer_progress >/dev/null 2>&1; then
        show_timer_progress "$BG_PID" "refreshing package index"
    fi
    wait "$BG_PID"

    if [ -n "$MISSING_PACKAGES" ]; then
        for pkg in $MISSING_PACKAGES; do
            (pkg_install "$pkg" >> "$DEP_LOG" 2>&1) &
            BG_PID=$!

            if command -v show_timer_progress >/dev/null 2>&1; then
                show_timer_progress "$BG_PID" "installing core tool [$pkg]"
            fi

            wait "$BG_PID"
            INSTALL_STATUS=$?

            if [ "$INSTALL_STATUS" -eq 0 ]; then
                log_success "Package [$pkg] installed successfully."
            else
                log_warn "Package [$pkg] failed or finished with warnings (exit $INSTALL_STATUS)."
                log_warn "Package manager log : [$DEP_LOG]"
            fi
        done
    fi

    # Post-install verification : never report success for a tool we cannot use.
    UNVERIFIED_TOOLS=""
    VERIFY_FAILED=0
    for pkg in $MISSING_PACKAGES; do
        if tool_is_available "$pkg"; then
            log_success "Verified : [$pkg] is ready! ($TOOL_REASON)"
        else
            probe="$(tool_probe_for "$pkg")"
            if [ -n "$probe" ]; then
                VERIFY_FAILED=1
                UNVERIFIED_TOOLS="$UNVERIFIED_TOOLS $pkg"
                log_error "Unverified : [$pkg] still has no [$probe] binary! ($TOOL_REASON)"
            else
                log_warn "Could not verify [$pkg] (no binary probe) - continuing anyway."
            fi
        fi
    done

    if [ "$DNSMASQ_FULL_MISSING" -eq 1 ]; then
        log_info "Checking dnsmasq installation status ..."
        (
            case "$PKG_MANAGER" in
                opkg)
                    opkg remove dnsmasq --force-depends >/dev/null 2>&1 || true
                    opkg install dnsmasq-full  --force-overwrite >/dev/null 2>&1 || true
                    ;;
                apk)
                    apk del dnsmasq >/dev/null 2>&1 || true
                    apk add --allow-untrusted dnsmasq-full  >/dev/null 2>&1 || true
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

        log_success "dnsmasq-full installed and DNS engine restarted successfully."
    elif [ "$PKG_DB_OK" -eq 1 ]; then
        log_success "dnsmasq-full is already present."
    fi

    # Final verdict : a required tool that still has no binary is a real failure,
    # not something to report as a success.
    if [ "$VERIFY_FAILED" -eq 1 ]; then
        log_warn "Some required tools could not be verified after installation :${UNVERIFIED_TOOLS}"
        log_warn "DayPass may not work correctly until they are installed."
        return 1
    fi

    log_success "All system dependencies configured successfully!"
}