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

_usb_dep_update() {
    if command -v pkg_update >/dev/null 2>&1; then
        pkg_update >/dev/null 2>&1 || true
        return 0
    fi
    if command -v opkg >/dev/null 2>&1; then
        opkg update >/dev/null 2>&1 || true
        return 0
    fi
    if command -v apk >/dev/null 2>&1; then
        apk update >/dev/null 2>&1 || true
        return 0
    fi
    return 1
}

# $1 package. Returns 0 on install, 1 when every installer failed.
_usb_dep_install_one() {
    _ud_pkg="$1"

    if command -v pkg_install >/dev/null 2>&1; then
        pkg_install "$_ud_pkg" >/dev/null 2>&1 && return 0
    fi
    if command -v opkg >/dev/null 2>&1; then
        opkg install "$_ud_pkg" >/dev/null 2>&1 && return 0
    fi
    if command -v apk >/dev/null 2>&1; then
        apk add --allow-untrusted "$_ud_pkg" >/dev/null 2>&1 && return 0
    fi
    return 1
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

# Install one named set. Returns 1 when any package is still missing.
usb_install_driver_set() {
    _ud_set="$1"
    _ud_list=$(usb_driver_packages "$_ud_set") || return 1
    _ud_failed=0

    _usb_dep_update || true
    for _ud_pkg in $_ud_list; do
        _ud_mod=""
        case "$_ud_pkg" in
            usbmuxd) _ud_mod="usbmuxd" ;;
            kmod-usb-net-rndis) _ud_mod="rndis_host" ;;
            kmod-usb-net-cdc-ether) _ud_mod="cdc_ether" ;;
            kmod-usb-net-cdc-ncm) _ud_mod="cdc_ncm" ;;
            kmod-usb-net-ipheth) _ud_mod="ipheth" ;;
        esac
        usb_dep_present "$_ud_pkg" "$_ud_mod" && continue
        _usb_dep_install_one "$_ud_pkg" || _ud_failed=1
    done
    [ "$_ud_failed" -eq 0 ]
}

_usb_dep_remove_one() {
    _ud_pkg="$1"
    if command -v pkg_installed >/dev/null 2>&1 && ! pkg_installed "$_ud_pkg"; then
        return 0
    fi
    if command -v opkg >/dev/null 2>&1 && opkg remove "$_ud_pkg" >/dev/null 2>&1; then
        return 0
    fi
    if command -v apk >/dev/null 2>&1 && apk del "$_ud_pkg" >/dev/null 2>&1; then
        return 0
    fi
    command -v pkg_installed >/dev/null 2>&1 && ! pkg_installed "$_ud_pkg"
}

# Remove the Android, iOS and modem packages. Missing packages are fine.
usb_purge_driver_packages() {
    _ud_failed=0
    for _ud_pkg in $(usb_driver_packages full); do
        _usb_dep_remove_one "$_ud_pkg" || _ud_failed=1
    done
    [ "$_ud_failed" -eq 0 ]
}

usb_driver_menu() {
    while true; do
        if command -v render_persistent_header >/dev/null 2>&1; then
            render_persistent_header
        fi
        echo "  USB drivers"
        echo "  1) Android Drivers (RNDIS / CDC-Ether / NCM) (~150KB)"
        echo "  2) iPhone/iOS Drivers (ipheth & usbmuxd) (~1.2MB)"
        echo "  3) Full Hardware Suite (Android + iOS + Modems)"
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
                usb_install_driver_set android \
                    && log_success "Android USB drivers are installed." \
                    || log_warn "Some Android USB drivers could not be installed."
                ;;
            2)
                usb_install_driver_set ios \
                    && log_success "iPhone USB drivers are installed." \
                    || log_warn "Some iPhone USB drivers could not be installed."
                ;;
            3)
                usb_install_driver_set full \
                    && log_success "Full USB hardware suite is installed." \
                    || log_warn "Some USB packages could not be installed."
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
