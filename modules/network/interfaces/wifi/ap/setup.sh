#!/bin/sh
# ============================================================
# DayPass - Wi-Fi AP Setup
# ============================================================

setup_wifi_ap() (
    render_persistent_header
    ui_title "📡 Wi-Fi Access Point Configuration"
    echo "  ${GRAY}This module only manages Access Point (home Wi-Fi).${RESET}"
    echo "  ${GRAY}Station / WWAN interfaces will not be modified.${RESET}"
    ui_divider
    echo

    local RADIOS
    RADIOS=$(uci show wireless 2>/dev/null | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1)

    if [ -z "$RADIOS" ]; then
        log_error "No wireless radio detected on this device."
        return 1
    fi

    show_ap_status

    echo
    echo "  ⚙️ SSID Naming Strategy :"
    echo "     1) Unified SSID for all bands (Smart Connect)"
    echo "     2) Separate SSID per band (2.4G + 5G)"
    ui_divider
    
    ui_prompt 2
    local ssid_mode="$UI_CHOICE"
    [ -z "$ssid_mode" ] && ssid_mode=1

    local SSID_2G SSID_5G unified

    if [ "$ssid_mode" = "2" ]; then
        printf "  🛜 2.4GHz SSID [DayPass-2.4G] : "
        read -r SSID_2G </dev/tty || return 1
        [ -z "$SSID_2G" ] && SSID_2G="DayPass-2.4G"

        printf "  🛜 5GHz SSID [DayPass-5G] : "
        read -r SSID_5G </dev/tty || return 1
        [ -z "$SSID_5G" ] && SSID_5G="DayPass-5G"
    else
        printf "  🛜 Unified SSID [DayPass] : "
        read -r unified </dev/tty || return 1
        [ -z "$unified" ] && unified="DayPass"
        SSID_2G="$unified"
        SSID_5G="$unified"
    fi

    local password=""
    while true; do
        printf "  🔒 WiFi Password (min 8 characters) : "
        read -r password </dev/tty || return 1
        if [ ${#password} -ge 8 ]; then
            break
        fi
        log_error "Password must be at least 8 characters!"
    done

    log_info "Applying Access Point configuration ..."

    local radio band ssid created="" previous snapshots state
    snapshots=$(mktemp -d /tmp/daypass_ap.XXXXXX) || return 1
    trap 'for previous in $created; do rm -f "$snapshots/$previous"; done; rmdir "$snapshots"' EXIT
    for radio in $RADIOS; do
        band=$(uci -q get "wireless.$radio.band" || uci -q get "wireless.$radio.hwmode")
        case "$band" in
            5g|11a) ssid="$SSID_5G" ;;
            2g|11g|11b) ssid="$SSID_2G" ;;
            *) log_warn "Skipping $radio with unsupported band."; continue ;;
        esac
        if ! wifi_create_owned_iface "$radio" ap lan "$ssid" psk2 "$password"; then
            for previous in $created; do
                state=$(uci show "wireless.daypass_ap_$previous") &&
                    [ "$state" = "$(cat "$snapshots/$previous")" ] &&
                    wifi_remove_owned_iface "daypass_ap_$previous" ap ||
                    log_error "Rollback incomplete on $previous."
            done
            return 1
        fi
        created="$created $radio"
        uci show "wireless.daypass_ap_$radio" > "$snapshots/$radio" || return 1
    done
    [ -n "$created" ] || return 1
    log_success "DayPass AP configuration applied."
)
