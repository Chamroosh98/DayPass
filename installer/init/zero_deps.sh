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

    if [ -z "$probe" ] && [ "$PKG_DB_OK" -eq 1 ] && pkg_installed_live "$1"; then
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
    ui_divider

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

    ui_divider
    printf "  Summary : %d tool(s) ready, %d missing\n" "$PRESENT_COUNT" "$MISSING_COUNT"
    echo
}

# Keep both packages on persistent storage until DNS is running again.
bootstrap_dnsmasq() (
    set -e
    stage="${DAYPASS_DIR:-/etc/daypass}/dns-recovery"
    mkdir -p "$stage" || return 1
    cd "$stage" || return 1
    # Serialize the recovery journal, independently of the native package lock.
    exec 9>transaction.lock || return 1
    flock -n 9 || { log_error "DNS recovery needs an available flock lock."; return 1; }

    dns_installed() {
        case "$PKG_MANAGER" in
            apk) apk info -e "$1" ;;
            opkg) opkg status "$1" | grep -q '^Status: .* installed$' ;;
        esac
    }

    dns_install() {
        case "$PKG_MANAGER" in
            apk) apk add "$1" ;;
            opkg) opkg install "$1" ;;
        esac
    }

    dns_remove() {
        case "$PKG_MANAGER" in
            apk) apk del "$1" ;;
            opkg) opkg remove "$1" ;;
        esac
    }

    dns_backup_valid() {
        backup=$(cat original) || return 1
        case "$backup" in ./*/*) return 1 ;; ./dnsmasq_*.ipk|./dnsmasq-[0-9]*.apk) ;; *) return 1 ;; esac
        [ -s "$backup" ] && [ -s original.sha256 ] &&
            [ "$(sha256sum "$backup")" = "$(cat original.sha256)" ]
    }

    dns_restore_original() {
        dns_backup_valid || return 1
        if dns_installed dnsmasq-full; then dns_remove dnsmasq-full || return 1; fi
        dns_install "$backup" && dns_installed dnsmasq && /etc/init.d/dnsmasq restart
    }

    if [ -f pending ]; then
        grep -Eqx "restore|fresh" pending || return 1
        if dns_installed dnsmasq-full && /etc/init.d/dnsmasq restart; then
            rm -f pending
            return 0
        fi
        if grep -qx restore pending; then
            dns_restore_original || return 1
        fi
        rm -f pending
        log_warn "Recovered the previous DNS configuration. Retry bootstrap."
        return 1
    fi

    rm -f original original.sha256 ./*.ipk ./*.apk || return 1
    packages=dnsmasq-full
    if dns_installed dnsmasq; then
        packages="dnsmasq dnsmasq-full"
        version=$(pkg_get_installed_version dnsmasq)
        [ -n "$version" ] || return 1
    fi
    for pkg in $packages; do
        case "$PKG_MANAGER" in
            apk) request="$pkg"; [ "$pkg" != dnsmasq ] || request="dnsmasq=$version"
                apk fetch "$request" || return 1; set -- "./$pkg"-[0-9]*.apk ;;
            opkg) opkg download "$pkg" || return 1; set -- "./${pkg}_"*.ipk ;;
        esac
        [ "$#" -eq 1 ] && [ -s "$1" ] || return 1
        if [ "$pkg" = dnsmasq ]; then
            case "$PKG_MANAGER" in
                apk)
                    [ "$1" = "./dnsmasq-$version.apk" ] && apk verify "$1" || return 1 ;;
                opkg)
                    case "$1" in "./dnsmasq_${version}_"*.ipk) ;; *) return 1 ;; esac
                    digest=$(opkg info dnsmasq | awk -v ver="$version" '
                        BEGIN {RS=""; FS="\n"}
                        {v=""; h=""; for(i=1;i<=NF;i++) {
                            if($i ~ /^Version: /) v=substr($i,10)
                            if($i ~ /^SHA256sum: /) h=substr($i,12)
                        }; if(v==ver && h!="") {print h; exit}}')
                    [ -n "$digest" ] && printf '%s  %s\n' "$digest" "$1" | sha256sum -c - || return 1 ;;
            esac
            printf '%s\n' "$1" > original && sha256sum "$1" > original.sha256 || return 1
        else
            replacement=$1
        fi
    done
    mode=fresh
    if [ "$packages" != dnsmasq-full ]; then
        dns_backup_valid && [ -s "$(cat original)" ] || return 1
        mode=restore
    fi
    printf '%s\n' "$mode" > pending.new && mv pending.new pending &&
        grep -qx "$mode" pending && sync || return 1
    if [ "$mode" = restore ]; then dns_remove dnsmasq || return 1; fi
    if dns_install "$replacement" && dns_installed dnsmasq-full && /etc/init.d/dnsmasq restart; then
        rm -f pending original ./*.ipk ./*.apk
        return 0
    fi
    log_error "DNS installation failed. Restoring the previous package."
    if [ "$mode" = restore ]; then
        dns_restore_original || return 1
    fi
    rm -f pending
    return 1
)

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

    if [ -f "${DAYPASS_DIR:-/etc/daypass}/dns-recovery/pending" ]; then
        bootstrap_dnsmasq || return 1
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
    if command -v pkg_installed_live >/dev/null 2>&1; then
        PKG_DB_OK=1
    else
        log_warn "Package database helper [pkg_installed] unavailable : validating with binary probes only!"
    fi

    log_info "Checking which required tools are already installed ..."
    scan_required_tools

    DNSMASQ_FULL_MISSING=0
    if [ -f /etc/openwrt_release ] && [ "$PKG_DB_OK" -eq 1 ]; then
        if ! pkg_installed_live "dnsmasq-full"; then
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

    pkg_update || {
        local refresh_status=$?
        log_error "Cannot refresh $PKG_MANAGER indexes for required dependencies."
        return "$refresh_status"
    }

    if [ -n "$MISSING_PACKAGES" ]; then
        for pkg in $MISSING_PACKAGES; do
            (pkg_install "$pkg" repair >> "$DEP_LOG" 2>&1) &
            BG_PID=$!

            if command -v ui_spinner >/dev/null 2>&1; then
                ui_spinner "$BG_PID" "Installing [$pkg] ..."
                INSTALL_STATUS=$?
            elif command -v show_timer_progress >/dev/null 2>&1; then
                show_timer_progress "$BG_PID" "installing core tool [$pkg]"
                wait "$BG_PID"
                INSTALL_STATUS=$?
            else
                wait "$BG_PID"
                INSTALL_STATUS=$?
            fi

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
            VERIFY_FAILED=1
            UNVERIFIED_TOOLS="$UNVERIFIED_TOOLS $pkg"
            log_error "Required dependency [$pkg] unavailable: $TOOL_REASON"
        fi
    done

    if [ "$VERIFY_FAILED" -eq 1 ]; then
        log_warn "Some required tools could not be verified after installation :${UNVERIFIED_TOOLS}"
        log_warn "DayPass may not work correctly until they are installed."
        return 1
    fi

    if [ "$DNSMASQ_FULL_MISSING" -eq 1 ]; then
        bootstrap_dnsmasq || return 1
        log_success "dnsmasq-full installed and DNS service restarted."
    elif [ "$PKG_DB_OK" -eq 1 ]; then
        log_success "dnsmasq-full is already present."
    fi

    # Final verdict : a required tool that still has no binary is a real failure,
    # not something to report as a success.
    log_success "All system dependencies configured successfully!"
}