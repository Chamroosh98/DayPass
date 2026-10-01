#!/bin/sh

# ============================================================
# DayPass - System Login Banner (/etc/banner)
# Keeps one copy of the stock OpenWrt banner, then writes the
# DayPass banner printed on every SSH / console login.
# ============================================================

SYS_BANNER_FILE="/etc/banner"
SYS_BANNER_BACKUP="/etc/banner.daypass-orig"

# Marker used to tell our own banner apart from the stock one
SYS_BANNER_TAG="DayPass Deployment Toolkit"

# ------------------------------------------------------------
# DayPass version (single source of truth is ui/banner.sh)
# ------------------------------------------------------------
_sys_banner_version() {
    if [ -n "${DAYPASS_VERSION:-}" ]; then
        echo "$DAYPASS_VERSION"
    else
        echo "v2.1.1"
    fi
}

# ------------------------------------------------------------
# Firmware release, e.g. "OpenWrt 24.10.0 r28427-6df0e3d02a"
# ------------------------------------------------------------
_sys_banner_release() {
    if [ -f /etc/openwrt_release ]; then
        (
            . /etc/openwrt_release 2>/dev/null
            printf '%s %s %s' "${DISTRIB_ID:-OpenWrt}" "${DISTRIB_RELEASE:-unknown}" "${DISTRIB_REVISION:-}"
        ) | sed -e 's/  */ /g' -e 's/ *$//'
        return 0
    fi

    if [ -f /etc/os-release ]; then
        (
            . /etc/os-release 2>/dev/null
            printf '%s %s' "${NAME:-OpenWrt}" "${VERSION:-${BUILD_ID:-unknown}}"
        ) | sed -e 's/  */ /g' -e 's/ *$//'
        return 0
    fi

    echo "OpenWrt (release unknown)"
}

# ------------------------------------------------------------
# Build target and CPU arch, e.g. "ath79/generic (mips_24kc)"
# ------------------------------------------------------------
_sys_banner_target() {
    SYS_BANNER_T=""
    SYS_BANNER_A=""

    if [ -f /etc/openwrt_release ]; then
        SYS_BANNER_T=$(
            . /etc/openwrt_release 2>/dev/null
            echo "${DISTRIB_TARGET:-}"
        )
        SYS_BANNER_A=$(
            . /etc/openwrt_release 2>/dev/null
            echo "${DISTRIB_ARCH:-}"
        )
    fi

    [ -z "$SYS_BANNER_A" ] && SYS_BANNER_A="$(uname -m 2>/dev/null)"

    if [ -n "$SYS_BANNER_T" ] && [ -n "$SYS_BANNER_A" ]; then
        echo "$SYS_BANNER_T ($SYS_BANNER_A)"
    elif [ -n "$SYS_BANNER_T" ]; then
        echo "$SYS_BANNER_T"
    elif [ -n "$SYS_BANNER_A" ]; then
        echo "$SYS_BANNER_A"
    else
        echo "unknown target"
    fi
}

# ------------------------------------------------------------
# Banner template. Quoted heredoc: backslashes and backticks of
# the ASCII art stay literal and the @...@ fields are filled in
# by system_banner_render.
# ------------------------------------------------------------
_sys_banner_template() {
    cat <<'DAYPASS_BANNER_EOF'
 ---------------------------------------------------------------------
     ____               ____
    |  _ \  __ _ _   _ |  _ \  __ _ ___ ___
    | | | |/ _` | | | || |_) / _` / __/ __|
    | |_| | (_| | |_| ||  __/ (_| \__ \__ \
    |____/ \__,_|\__, ||_|   \__,_|___/___/  @VERSION@
                 |___/
 ---------------------------------------------------------------------
  DayPass Deployment Toolkit - proxy, tunnel and network manager
  Firmware : @RELEASE@
  Target   : @TARGET@
 ---------------------------------------------------------------------

DAYPASS_BANNER_EOF
}

# ------------------------------------------------------------
# Print the banner with the current system values filled in
# ------------------------------------------------------------
system_banner_render() {
    SYS_BANNER_VER=$(_sys_banner_version | tr -d '|')
    SYS_BANNER_REL=$(_sys_banner_release | tr -d '|')
    SYS_BANNER_TGT=$(_sys_banner_target | tr -d '|')
    SYS_BANNER_DATE=$(date '+%Y-%m-%d' 2>/dev/null)
    [ -n "$SYS_BANNER_DATE" ] || SYS_BANNER_DATE="unknown date"

    _sys_banner_template | sed \
        -e "s|@VERSION@|$SYS_BANNER_VER|g" \
        -e "s|@RELEASE@|$SYS_BANNER_REL|g" \
        -e "s|@TARGET@|$SYS_BANNER_TGT|g" \
        -e "s|@DATE@|$SYS_BANNER_DATE|g"
}

# ------------------------------------------------------------
# True when /etc/banner is the DayPass one
# ------------------------------------------------------------
system_banner_is_daypass() {
    [ -f "$SYS_BANNER_FILE" ] || return 1
    grep -qF "$SYS_BANNER_TAG" "$SYS_BANNER_FILE" 2>/dev/null
}

# ------------------------------------------------------------
# One-line state for menus and logs
# ------------------------------------------------------------
system_banner_status() {
    if system_banner_is_daypass; then
        if [ -f "$SYS_BANNER_BACKUP" ]; then
            echo "DayPass banner installed (original kept at $SYS_BANNER_BACKUP)"
        else
            echo "DayPass banner installed (no backup of the original)"
        fi
    elif [ -f "$SYS_BANNER_FILE" ]; then
        echo "stock OpenWrt banner"
    else
        echo "no $SYS_BANNER_FILE on this system"
    fi
}

# ------------------------------------------------------------
# Install (or refresh) the DayPass banner
# ------------------------------------------------------------
install_system_banner() {
    SYS_BANNER_TMP="$SYS_BANNER_FILE.daypass-new"

    if ! system_banner_render > "$SYS_BANNER_TMP" 2>/dev/null; then
        rm -f "$SYS_BANNER_TMP" 2>/dev/null
        log_error "Failed to build the DayPass login banner!"
        return 1
    fi

    if [ ! -s "$SYS_BANNER_TMP" ]; then
        rm -f "$SYS_BANNER_TMP" 2>/dev/null
        log_error "Generated login banner is empty, keeping the current one!"
        return 1
    fi

    # Nothing to do when the installed banner already matches
    if [ -f "$SYS_BANNER_FILE" ] && cmp -s "$SYS_BANNER_TMP" "$SYS_BANNER_FILE"; then
        rm -f "$SYS_BANNER_TMP" 2>/dev/null
        log_info "DayPass login banner is already up to date."
        return 0
    fi

    # Keep the stock banner the first time only, so repeated installs
    # never overwrite the backup with our own banner.
    if [ ! -f "$SYS_BANNER_BACKUP" ] && [ -f "$SYS_BANNER_FILE" ] && ! system_banner_is_daypass; then
        if cp "$SYS_BANNER_FILE" "$SYS_BANNER_BACKUP" 2>/dev/null; then
            log_info "Original banner backed up to : [$SYS_BANNER_BACKUP]"
        else
            rm -f "$SYS_BANNER_TMP" 2>/dev/null
            log_error "Could not back up [$SYS_BANNER_FILE], banner left unchanged!"
            return 1
        fi
    fi

    if ! mv "$SYS_BANNER_TMP" "$SYS_BANNER_FILE" 2>/dev/null; then
        rm -f "$SYS_BANNER_TMP" 2>/dev/null
        log_error "Failed to write [$SYS_BANNER_FILE]!"
        return 1
    fi

    chmod 644 "$SYS_BANNER_FILE" 2>/dev/null
    log_success "DayPass login banner installed to [$SYS_BANNER_FILE]!"
    log_info "It shows on the next SSH or console login."
    return 0
}

# ------------------------------------------------------------
# Put the stock OpenWrt banner back
# ------------------------------------------------------------
restore_system_banner() {
    if [ ! -f "$SYS_BANNER_BACKUP" ]; then
        log_warn "No banner backup found at [$SYS_BANNER_BACKUP]."
        log_info "The original banner is restored by a firmware upgrade or factory reset."
        return 1
    fi

    if ! cp "$SYS_BANNER_BACKUP" "$SYS_BANNER_FILE" 2>/dev/null; then
        log_error "Failed to restore [$SYS_BANNER_FILE] from the backup!"
        return 1
    fi

    rm -f "$SYS_BANNER_BACKUP" 2>/dev/null
    chmod 644 "$SYS_BANNER_FILE" 2>/dev/null
    log_success "Original OpenWrt login banner restored!"
    return 0
}

# ------------------------------------------------------------
# Called after a deployment: install the banner unless the user
# opted out with DAYPASS_SKIP_BANNER=1
# ------------------------------------------------------------
system_banner_post_install() {
    [ "${DAYPASS_SKIP_BANNER:-0}" = "1" ] && return 0
    install_system_banner
}

# ------------------------------------------------------------
# Interactive entry used by the maintenance menu
# ------------------------------------------------------------
system_banner_manage() {
    echo
    printf "  🪧 ${BOLD}SSH / Console Login Banner${RESET}\n"
    echo "  ───────────────────────────────────────────────────────────"
    printf "  📄 Banner file : ${CYAN}%s${RESET}\n" "$SYS_BANNER_FILE"
    printf "  🫀 Current     : ${GRAY}%s${RESET}\n" "$(system_banner_status)"
    echo "  ───────────────────────────────────────────────────────────"
    printf "  ${GRAY}[i] Install / refresh the DayPass banner${RESET}\n"
    printf "  ${GRAY}[p] Preview it without writing anything${RESET}\n"
    printf "  ${GRAY}[r] Restore the original OpenWrt banner${RESET}\n"
    echo
    printf "  ⁉️ ${YELLOW}Action${RESET} ${GRAY}(i/p/r, [Enter] cancel) :${RESET} "
    read -r SYS_BANNER_CMD </dev/tty || daypass_quit

    case "$SYS_BANNER_CMD" in
        i|I) install_system_banner ;;
        p|P)
            echo
            system_banner_render
            ;;
        r|R) restore_system_banner ;;
        q|Q) daypass_quit ;;
        *)   log_info "Login banner left unchanged." ;;
    esac
}

# Standalone execution handler
case "$0" in
    *banner.sh)
        case "${1:-install}" in
            install) install_system_banner ;;
            restore) restore_system_banner ;;
            render)  system_banner_render ;;
            status)  system_banner_status ;;
        esac
        ;;
esac
