#!/bin/sh
# ============================================================
# DayPass - USB tethering package dependencies
# Checks and installs the kernel drivers and usbmuxd.
# Safe to source. Never calls exit.
# ============================================================

# "<package>:<lsmod name or binary>"
# usbmuxd is a userspace daemon; the others are kernel modules.
USB_TETHER_DEP_MAP="kmod-usb-net-rndis:rndis_host kmod-usb-net-cdc-ether:cdc_ether kmod-usb-net-ipheth:ipheth usbmuxd:usbmuxd"

# 0 when the package is installed, its module is loaded, or (usbmuxd) its binary exists.
# $1 package  $2 module or binary name
usb_dep_present() {
    _ud_pkg="$1"
    _ud_mod="$2"

    if [ "$_ud_pkg" = "usbmuxd" ] && command -v usbmuxd >/dev/null 2>&1; then
        return 0
    fi

    if command -v pkg_installed >/dev/null 2>&1 && pkg_installed "$_ud_pkg"; then
        return 0
    fi

    if [ "$_ud_pkg" != "usbmuxd" ] && [ -n "$_ud_mod" ] \
        && lsmod 2>/dev/null | grep -q "^${_ud_mod} "; then
        return 0
    fi

    return 1
}

# Prints missing package names, one per line. Returns 1 when any are missing.
usb_deps_missing() {
    _ud_missing=0

    for _ud_spec in $USB_TETHER_DEP_MAP; do
        _ud_pkg="${_ud_spec%%:*}"
        _ud_mod="${_ud_spec#*:}"
        if usb_dep_present "$_ud_pkg" "$_ud_mod"; then
            continue
        fi
        printf '%s\n' "$_ud_pkg"
        _ud_missing=1
    done

    return "$_ud_missing"
}

# apk when PKG_MANAGER says so, otherwise whichever binary exists.
_usb_pm() {
    case "${PKG_MANAGER:-}" in
        apk|opkg)
            printf '%s\n' "$PKG_MANAGER"
            return 0
            ;;
    esac
    if command -v apk >/dev/null 2>&1; then
        printf '%s\n' "apk"
        return 0
    fi
    if command -v opkg >/dev/null 2>&1; then
        printf '%s\n' "opkg"
        return 0
    fi
    return 1
}

# Drop a lock only when no package manager process is holding it.
_usb_clear_pkg_lock() {
    if pidof opkg >/dev/null 2>&1 || pidof apk >/dev/null 2>&1; then
        log_warn "A package manager process is already running."
        return 0
    fi
    rm -f /var/lock/opkg.lock /lib/apk/db/lock /var/run/apk.lock /run/apk/db.lock 2>/dev/null
}

# $1 seconds, then the command. Returns 124 when the deadline passes.
# Stdin is closed so opkg/apk cannot wait on a prompt. Output goes to the log.
_usb_run_bounded() {
    _ub_sec="$1"
    _ub_n=0
    _ub_pid=""
    shift

    : >/tmp/daypass_usb_pkg.log
    "$@" </dev/null >>/tmp/daypass_usb_pkg.log 2>&1 &
    _ub_pid=$!
    while kill -0 "$_ub_pid" 2>/dev/null; do
        _ub_n=$((_ub_n + 1))
        if [ "$_ub_n" -ge "$_ub_sec" ]; then
            kill "$_ub_pid" 2>/dev/null
            sleep 1
            kill -9 "$_ub_pid" 2>/dev/null
            wait "$_ub_pid" 2>/dev/null
            return 124
        fi
        sleep 1
    done
    wait "$_ub_pid"
}

_usb_show_pkg_log() {
    [ -s /tmp/daypass_usb_pkg.log ] || return 0
    log_warn "Package manager said:"
    tail -n 6 /tmp/daypass_usb_pkg.log 2>/dev/null | sed 's/^/    /'
}

_usb_dep_update() {
    _ub_pm=""
    _ub_st=1

    _ub_pm=$(_usb_pm) || return 1
    _usb_clear_pkg_lock
    log_info "Updating package indexes..."

    case "$_ub_pm" in
        apk)
            _usb_run_bounded 40 apk update --no-interactive --network-timeout 15
            _ub_st=$?
            if [ "$_ub_st" -ne 0 ] && [ "$_ub_st" -ne 124 ]; then
                _ua_flag=""
                if command -v pkg_ipv4_flag >/dev/null 2>&1; then
                    _ua_flag=$(pkg_ipv4_flag apk) || _ua_flag=""
                fi
                if [ -n "$_ua_flag" ]; then
                    log_warn "apk update did not finish. Retrying with $_ua_flag."
                    _usb_run_bounded 40 apk update "$_ua_flag" --no-interactive --network-timeout 15
                    _ub_st=$?
                else
                    log_warn "apk has no IPv4-only option on this build. Not retrying with a forced address family."
                fi
            fi
            ;;
        opkg)
            _usb_run_bounded 40 opkg update
            _ub_st=$?
            if [ "$_ub_st" -ne 0 ] && [ "$_ub_st" -ne 124 ]; then
                log_warn "opkg update did not finish. Retrying with --force-ipv4."
                _usb_run_bounded 40 opkg update --force-ipv4
                _ub_st=$?
            fi
            ;;
    esac

    if [ "$_ub_st" -eq 124 ]; then
        log_warn "Package index update timed out. The feed did not answer."
        _usb_show_pkg_log
        return 1
    fi
    if [ "$_ub_st" -ne 0 ]; then
        log_warn "Package index update failed. Install will try the local cache."
        _usb_show_pkg_log
        return 1
    fi
    log_success "Package indexes updated."
    return 0
}

# $1 package. Returns 0 on install, 1 when the install failed or timed out.
_usb_dep_install_one() {
    _ud_pkg="$1"
    _ub_pm=""
    _ub_st=1

    [ -n "$_ud_pkg" ] || return 1
    if command -v pkg_installed >/dev/null 2>&1 && pkg_installed "$_ud_pkg"; then
        printf '  [✓] %s is already installed. Skipping.\n' "$_ud_pkg"
        return 0
    fi
    _ub_pm=$(_usb_pm) || return 1
    log_info "Installing $_ud_pkg ..."

    case "$_ub_pm" in
        apk)
            _usb_run_bounded 90 apk add --no-interactive --no-cache --allow-untrusted --network-timeout 20 "$_ud_pkg"
            _ub_st=$?
            if [ "$_ub_st" -ne 0 ] && [ "$_ub_st" -ne 124 ]; then
                _ua_flag=""
                if command -v pkg_ipv4_flag >/dev/null 2>&1; then
                    _ua_flag=$(pkg_ipv4_flag apk) || _ua_flag=""
                fi
                if [ -n "$_ua_flag" ]; then
                    log_warn "apk add failed for $_ud_pkg. Retrying with $_ua_flag."
                    _usb_run_bounded 90 apk add "$_ua_flag" --no-interactive --no-cache --allow-untrusted --network-timeout 20 "$_ud_pkg"
                    _ub_st=$?
                else
                    log_warn "apk has no IPv4-only option on this build. Not retrying $_ud_pkg with a forced address family."
                fi
            fi
            ;;
        opkg)
            _usb_run_bounded 90 opkg install --force-checksum --force-overwrite "$_ud_pkg"
            _ub_st=$?
            if [ "$_ub_st" -ne 0 ] && [ "$_ub_st" -ne 124 ]; then
                log_warn "opkg install failed for $_ud_pkg. Retrying with --force-ipv4."
                _usb_run_bounded 90 opkg install --force-ipv4 --force-checksum --force-overwrite "$_ud_pkg"
                _ub_st=$?
            fi
            ;;
    esac

    if [ "$_ub_st" -eq 124 ]; then
        log_warn "Timed out installing $_ud_pkg."
        _usb_show_pkg_log
        return 1
    fi
    if [ "$_ub_st" -ne 0 ]; then
        log_warn "Could not install $_ud_pkg."
        _usb_show_pkg_log
        return 1
    fi
    log_success "$_ud_pkg installed."
    command -v pkg_cache_add >/dev/null 2>&1 && pkg_cache_add "$_ud_pkg"
    return 0
}

# $1 package name -> kernel module or usbmuxd binary, or empty
_usb_pkg_mod() {
    case "$1" in
        usbmuxd)               printf '%s\n' "usbmuxd" ;;
        kmod-usb-net-rndis)    printf '%s\n' "rndis_host" ;;
        kmod-usb-net-cdc-ether) printf '%s\n' "cdc_ether" ;;
        kmod-usb-net-cdc-ncm)  printf '%s\n' "cdc_ncm" ;;
        kmod-usb-net-ipheth)   printf '%s\n' "ipheth" ;;
        *)                     printf '%s\n' "" ;;
    esac
}

# 0 only when $1 is actually on the router (opkg list-installed or apk).
# DayPass records, lsmod, and binaries are not proof of the package.
_usb_pkg_installed() {
    _ud_pkg="$1"

    [ -n "$_ud_pkg" ] || return 1
    if command -v opkg >/dev/null 2>&1; then
        opkg list-installed "$_ud_pkg" 2>/dev/null | grep -q "^${_ud_pkg} " && return 0
    fi
    if command -v apk >/dev/null 2>&1 && apk info -e "$_ud_pkg" >/dev/null 2>&1; then
        return 0
    fi
    # OpenWrt ships NCM as kmod-usb-net-cdc-ncm; treat either name as present.
    case "$_ud_pkg" in
        kmod-usb-net-ncm)
            if command -v opkg >/dev/null 2>&1; then
                opkg list-installed kmod-usb-net-cdc-ncm 2>/dev/null | grep -q "^kmod-usb-net-cdc-ncm " && return 0
            fi
            if command -v apk >/dev/null 2>&1 && apk info -e kmod-usb-net-cdc-ncm >/dev/null 2>&1; then
                return 0
            fi
            ;;
        kmod-usb-net-cdc-ncm)
            if command -v opkg >/dev/null 2>&1; then
                opkg list-installed kmod-usb-net-ncm 2>/dev/null | grep -q "^kmod-usb-net-ncm " && return 0
            fi
            if command -v apk >/dev/null 2>&1 && apk info -e kmod-usb-net-ncm >/dev/null 2>&1; then
                return 0
            fi
            ;;
    esac
    return 1
}

# Prints missing package names for $1 (android|ios|modem|full).
_usb_set_missing() {
    _ud_pkg=""
    _ud_mod=""

    for _ud_pkg in $(usb_driver_packages "$1"); do
        _ud_mod=$(_usb_pkg_mod "$_ud_pkg")
        _usb_pkg_installed "$_ud_pkg" "$_ud_mod" && continue
        printf '%s\n' "$_ud_pkg"
    done
}

# 0 when USB host controller packages are on the router (core + usb2 or usb3).
_usb_host_controller_present() {
    _usb_pkg_installed kmod-usb-core || return 1
    _usb_pkg_installed kmod-usb2 && return 0
    _usb_pkg_installed kmod-usb3 && return 0
    return 1
}

# Prints installed | partial | missing for $1 driver set.
# [✔ Installed] only when every required package is on the router.
usb_driver_set_state() {
    _ud_hit=0
    _ud_miss=0
    _ud_pkg=""
    _ud_list=""

    case "$1" in
        android)
            _ud_list="kmod-usb-net-rndis kmod-usb-net-cdc-ether kmod-usb-net-ncm"
            ;;
        ios)
            _ud_list="kmod-usb-net-ipheth usbmuxd libimobiledevice"
            ;;
        *)
            _ud_list=$(usb_driver_packages "$1")
            ;;
    esac

    for _ud_pkg in $_ud_list; do
        if _usb_pkg_installed "$_ud_pkg"; then
            _ud_hit=$((${_ud_hit:-0} + 1))
        else
            _ud_miss=$((${_ud_miss:-0} + 1))
        fi
    done
    if [ "${_ud_hit:-0}" -eq 0 ]; then
        printf '%s\n' "missing"
    elif [ "${_ud_miss:-0}" -eq 0 ] && _usb_host_controller_present; then
        printf '%s\n' "installed"
    else
        printf '%s\n' "partial"
    fi
}

usb_driver_badge() {
    case "$1" in
        installed) printf '%s%s[✔ Installed]%s' "$GREEN" "$BOLD" "$RESET" ;;
        partial)   printf '%s[⚡ Partial]%s' "$YELLOW" "$RESET" ;;
        *)         printf '%s[✖ Not Installed]%s' "$GRAY" "$RESET" ;;
    esac
}

# $1 emoji  $2 ASCII option text (e.g. "1) Android ...")  $3 state
# Emoji stays outside %-s so printf width cannot clip it. Badges share one column.
_usb_driver_menu_row() {
    printf "  %s %-*s  %b\n" "$1" 48 "$2" "$(usb_driver_badge "$3")"
}

# $1 android | ios | modem | full
usb_driver_packages() {
    case "$1" in
        android)
            printf '%s\n' "kmod-usb-net-rndis kmod-usb-net-cdc-ether kmod-usb-net-cdc-ncm"
            ;;
        ios)
            printf '%s\n' "kmod-usb-net-ipheth usbmuxd"
            ;;
        modem)
            printf '%s\n' "kmod-usb-net-qmi-wwan kmod-usb-net-cdc-mbim kmod-usb-net-huawei-cdc-ncm usb-modeswitch usbutils"
            ;;
        full)
            printf '%s %s %s\n' \
                "$(usb_driver_packages android)" \
                "$(usb_driver_packages ios)" \
                "$(usb_driver_packages modem)"
            ;;
        *)
            return 1
            ;;
    esac
}

# Install only packages still missing from $1. Skips opkg update when the set is complete.
usb_install_driver_set() {
    _ud_set="$1"
    _ud_list=""
    _ud_failed=0

    usb_driver_packages "$_ud_set" >/dev/null || return 1
    _ud_list=$(_usb_set_missing "$_ud_set")
    [ -n "$_ud_list" ] || return 0

    _usb_dep_update || true
    for _ud_pkg in $_ud_list; do
        _usb_dep_install_one "$_ud_pkg" || _ud_failed=1
    done
    [ "$_ud_failed" -eq 0 ]
}

# $1 set  $2 already-installed sentence  $3 success  $4 warn
_usb_offer_driver_set() {
    _ud_set="$1"
    _ud_already="$2"
    _ud_ok="$3"
    _ud_bad="$4"

    if [ "$(usb_driver_set_state "$_ud_set")" = "installed" ]; then
        echo "  ℹ️ $_ud_already"
        return 0
    fi

    if usb_install_driver_set "$_ud_set"; then
        log_success "$_ud_ok"
        log_info "If your phone isn't detected after plugging it in, reboot the router once - newly installed USB kernel modules sometimes don't bind to the port until the next boot."
    else
        log_warn "$_ud_bad"
    fi
}

_usb_dep_remove_one() {
    _ud_pkg="$1"
    _ud_had=0

    if command -v opkg >/dev/null 2>&1 \
        && opkg list-installed "$_ud_pkg" 2>/dev/null | grep -q "^${_ud_pkg} "; then
        _ud_had=1
        opkg remove "$_ud_pkg" >/dev/null 2>&1 || return 1
    fi
    if command -v apk >/dev/null 2>&1 && apk info -e "$_ud_pkg" >/dev/null 2>&1; then
        _ud_had=1
        apk del "$_ud_pkg" >/dev/null 2>&1 || return 1
    fi
    [ "$_ud_had" -eq 0 ] && return 0
    if command -v opkg >/dev/null 2>&1 \
        && opkg list-installed "$_ud_pkg" 2>/dev/null | grep -q "^${_ud_pkg} "; then
        return 1
    fi
    if command -v apk >/dev/null 2>&1 && apk info -e "$_ud_pkg" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# Packages DayPass may have installed, plus common tether/modem extras.
usb_purge_package_list() {
    printf '%s %s %s %s\n' \
        "$(usb_driver_packages full 2>/dev/null)" \
        "kmod-usb-net-ncm kmod-usb-net-cdc-eem kmod-usb-net-cdc-subset" \
        "libimobiledevice libplist libusbmuxd" \
        "kmod-usb-serial-option kmod-usb-serial-wwan kmod-usb-wwan"
}

# Remove Android, iOS, modem, and extra tether packages. Missing names are fine.
usb_purge_driver_packages() {
    _ud_failed=0
    _ud_seen=" "
    _ud_pkg=""

    for _ud_pkg in $(usb_purge_package_list); do
        case " $_ud_seen " in
            *" $_ud_pkg "*) continue ;;
        esac
        _ud_seen="$_ud_seen $_ud_pkg "
        _usb_dep_remove_one "$_ud_pkg" || _ud_failed=1
    done
    [ "$_ud_failed" -eq 0 ]
}

usb_driver_menu() {
    while true; do
        if command -v render_persistent_header >/dev/null 2>&1; then
            render_persistent_header
        fi
        if command -v ui_title >/dev/null 2>&1; then
            ui_title "📌 USB drivers"
        else
            echo "  📌 USB drivers"
            command -v ui_divider >/dev/null 2>&1 && ui_divider
        fi
        echo
        _usb_driver_menu_row "📱" "1) Android Drivers (RNDIS / CDC-Ether / NCM)" \
            "$(usb_driver_set_state android)"
        _usb_driver_menu_row "🍏" "2) iPhone/iOS Drivers (ipheth & usbmuxd)" \
            "$(usb_driver_set_state ios)"
        _usb_driver_menu_row "📦" "3) Full Hardware Suite (Android + iOS + Modems)" \
            "$(usb_driver_set_state full)"
        if command -v ui_nav_footer >/dev/null 2>&1; then
            ui_nav_footer
        fi
        if command -v ui_read >/dev/null 2>&1; then
            ui_read "Select option"
        else
            printf "  Select option : "
            read -r UI_CHOICE </dev/tty || return 0
        fi
        case "$UI_CHOICE" in
            1)
                _usb_offer_driver_set android \
                    "Android USB drivers are already installed on this router! Skipping download." \
                    "Android USB drivers are installed." \
                    "Some Android USB drivers could not be installed."
                ;;
            2)
                _usb_offer_driver_set ios \
                    "iPhone USB drivers are already installed on this router! Skipping download." \
                    "iPhone USB drivers are installed." \
                    "Some iPhone USB drivers could not be installed."
                ;;
            3)
                _usb_offer_driver_set full \
                    "Full USB hardware suite is already installed on this router! Skipping download." \
                    "Full USB hardware suite is installed." \
                    "Some USB packages could not be installed."
                ;;
            0|'') return 0 ;;
            q|Q)
                command -v daypass_quit >/dev/null 2>&1 && daypass_quit
                return 0
                ;;
            h|H)
                command -v ui_show_help >/dev/null 2>&1 && ui_show_help "hardware"
                ;;
            *) log_warn "Invalid option!" ;;
        esac
        command -v ui_pause >/dev/null 2>&1 && ui_pause
    done
}

# Silent check. Installs only what is missing.
# Returns 0 when every dependency is present afterwards, 1 otherwise.
# Does not exit the caller.
ensure_usb_tether_deps() {
    _ud_missing=""
    _ud_failed=0

    for _ud_spec in $USB_TETHER_DEP_MAP; do
        _ud_pkg="${_ud_spec%%:*}"
        _ud_mod="${_ud_spec#*:}"
        usb_dep_present "$_ud_pkg" "$_ud_mod" && continue
        _ud_missing="$_ud_missing $_ud_pkg"
    done

    [ -n "$_ud_missing" ] || return 0

    _usb_dep_update || true

    for _ud_pkg in $_ud_missing; do
        _usb_dep_install_one "$_ud_pkg" || _ud_failed=1
    done

    for _ud_spec in $USB_TETHER_DEP_MAP; do
        _ud_pkg="${_ud_spec%%:*}"
        _ud_mod="${_ud_spec#*:}"
        usb_dep_present "$_ud_pkg" "$_ud_mod" || _ud_failed=1
    done

    [ "$_ud_failed" -eq 0 ]
}
