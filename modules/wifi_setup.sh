#!/bin/sh

wifi_menu()
{
    render_persistent_header 2>/dev/null || clear

    echo "  📶 WiFi Configuration & Setup                            "
    echo "  ───────────────────────────────────────────────────────────"
    
    # Check if wireless package or uci wifi exists
    if ! command -v wifi >/dev/null 2>&1 && [ ! -f /etc/config/wireless ]; then
        log_error "No wireless hardware or package detected on this router!"
        sleep 2
        return 1
    fi

    # Detect Radios
    RADIOS=""
    if [ -f /etc/config/wireless ]; then
        RADIOS=$(uci show wireless | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1)
    fi

    if [ -z "$RADIOS" ]; then
        # Detect/generate wifi configuration if not created yet
        wifi config 2>/dev/null
        RADIOS=$(uci show wireless 2>/dev/null | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1)
    fi

    if [ -z "$RADIOS" ]; then
        log_error "Unable to detect WiFi radios!"
        sleep 2
        return 1
    fi

    echo "  🔍 Detected WiFi Interfaces:"
    for r in $RADIOS; do
        BAND=$(uci -q get "wireless.$r.band" || echo "unknown")
        HTMODE=$(uci -q get "wireless.$r.htmode" || echo "auto")
        echo "   ├─ 📻 Radio: $r ($BAND / $HTMODE)"
    done
    echo "  ───────────────────────────────────────────────────────────"
    echo

    printf "  ⁉️ Do you want to enable WiFi on detected bands? [y/N] : "
    read -r confirm </dev/tty

    case "$confirm" in
        y|Y) ;;
        *)
            log_warn "WiFi configuration cancelled by user!"
            sleep 1
            return 0
            ;;
    esac

    echo
    printf "  ✏️ Enter SSID Name (WiFi Name) [Default: DayPass]: "
    read -r user_ssid </dev/tty
    [ -z "$user_ssid" ] && user_ssid="DayPass"

    while true; do
        printf "  🔑 Enter WiFi Password (Min 8 chars) : "
        read -r user_pass </dev/tty
        if [ ${#user_pass} -ge 8 ]; then
            break
        else
            log_error "Password must be at least 8 characters long!"
        fi
    done

    echo
    log_info "Configuring WiFi interfaces ..."

    # Configure each radio interface
    idx=0
    for radio in $RADIOS; do
        # Enable Radio Hardware
        uci set "wireless.$radio.disabled"='0'

        # Detect band type or assign suffix
        hwmode=$(uci -q get "wireless.$radio.band" || uci -q get "wireless.$radio.hwmode" || echo "")
        
        IFACE_NAME="wifinet${idx}"
        
        # Check existing iface or create new
        if uci -q get "wireless.default_$radio" >/dev/null; then
            IFACE_KEY="default_$radio"
        else
            IFACE_KEY="$IFACE_NAME"
            uci set "wireless.$IFACE_KEY"=wifi-iface
            uci set "wireless.$IFACE_KEY.device"="$radio"
            uci set "wireless.$IFACE_KEY.mode"='ap'
            uci set "wireless.$IFACE_KEY.network"='lan'
        fi

        # Differentiate 2.4G vs 5G SSID if multiple radios exist
        CURR_SSID="$user_ssid"
        case "$hwmode" in
            *5g*|*a*|*ac*|*ax*) CURR_SSID="${user_ssid}_5G" ;;
            *2g*|*b*|*g*|*n*)   CURR_SSID="${user_ssid}_2.4G" ;;
            *)
                [ "$idx" -gt 0 ] && CURR_SSID="${user_ssid}_5G"
                ;;
        esac

        uci set "wireless.$IFACE_KEY.ssid"="$CURR_SSID"
        uci set "wireless.$IFACE_KEY.encryption"='psk2'
        uci set "wireless.$IFACE_KEY.key"="$user_pass"
        uci set "wireless.$IFACE_KEY.disabled"='0'

        log_success "Configured [$radio] -> SSID: $CURR_SSID"
        idx=$((idx + 1))
    done

    uci commit wireless
    
    log_info "Reloading Wireless Subsystem..."
    wifi reload 2>/dev/null || wifi 2>/dev/null || /etc/init.d/network restart

    echo
    log_success "WiFi successfully configured and enabled!"
    echo
    printf "  ${GRAY}Press [ENTER] to continue ...${RESET}"
    read -r _ </dev/tty
}