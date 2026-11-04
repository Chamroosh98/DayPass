#!/bin/sh
# ============================================================
# DayPass - Wi-Fi Client Menu
# ============================================================

_wifi_format_band() {
    case "$1" in
        *5g*|*a*|*ac*|*ax*) printf "5 GHz (802.11 a/ac/ax)" ;;
        *)                  printf "2.4 GHz (802.11 b/g/n)" ;;
    esac
}

wifi_client_wizard() {
    local radios idx radio_list r band choice chosen
    local scan_file="/tmp/daypass_wifi_scan.txt"
    
    while true; do
        render_persistent_header
        ui_title "📡 Wi-Fi WAN (Station Mode) Setup"
        
        radios=$(uci show wireless 2>/dev/null | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1)
        if [ -z "$radios" ]; then
            log_error "No wireless radio found."
            ui_pause
            return 1
        fi

        echo "  📻 Available Radios:"
        idx=1
        radio_list=""
        for r in $radios; do
            band=$(uci -q get wireless.$r.band || uci -q get wireless.$r.hwmode || echo "unknown")
            band=$(_wifi_format_band "$band")
            printf "     %s) %-10s %s[%s]%s\n" "$idx" "$r" "${GRAY}" "$band" "${RESET}"
            radio_list="$radio_list $r"
            idx=$((idx + 1))
        done
        
        ui_nav_footer
        ui_prompt "$((idx - 1))"
        choice="$UI_CHOICE"

        case "$choice" in
            0) return 0 ;;
            q|Q) daypass_quit ;;
            h|H) ui_show_help "wifi_client"; continue ;;
            ''|*[!0-9]*) log_warn "Invalid selection"; continue ;;
        esac
        
        if [ "$choice" -ge 1 ] && [ "$choice" -lt "$idx" ]; then
            chosen=$(echo $radio_list | cut -d' ' -f"$choice")
            break
        fi
    done

    # Scanning Phase
    echo
    wifi_scan_networks "$chosen" &
    _scan_pid=$!
    
    ui_spinner "$_scan_pid" "Scanning Wi-Fi networks on $chosen ..." || true
    wait "$_scan_pid" 2>/dev/null || true
    
    if [ ! -s "$scan_file" ]; then
        log_warn "No Wi-Fi networks found nearby or radio is busy."
        ui_pause
        return 0
    fi

    # Network Selection Phase
    local net_count net_choice target_ssid target_enc target_sig
    while true; do
        render_persistent_header
        ui_title "📶 Select Wi-Fi Network"
        
        idx=1
        while IFS='|' read -r ssid sig enc; do
            printf "  %2d) %-25s %s[%s dBm]%s\n" "$idx" "$ssid" "${GRAY}" "$sig" "${RESET}"
            idx=$((idx + 1))
        done < "$scan_file"
        net_count=$((idx - 1))
        
        ui_nav_footer
        ui_prompt "$net_count"
        net_choice="$UI_CHOICE"
        
        case "$net_choice" in
            0) rm -f "$scan_file"; return 0 ;;
            q|Q) rm -f "$scan_file"; daypass_quit ;;
            h|H) ui_show_help "wifi_client"; continue ;;
            ''|*[!0-9]*) log_warn "Invalid selection"; continue ;;
        esac
        
        if [ "$net_choice" -ge 1 ] && [ "$net_choice" -le "$net_count" ]; then
            local selected_line=$(sed -n "${net_choice}p" "$scan_file")
            target_ssid=$(echo "$selected_line" | cut -d'|' -f1)
            target_sig=$(echo "$selected_line" | cut -d'|' -f2)
            target_enc=$(echo "$selected_line" | cut -d'|' -f3)
            break
        fi
    done
    rm -f "$scan_file"

    # Password Phase
    local target_pass=""
    if [ "$target_enc" = "psk" ]; then
        while true; do
            printf "\n  🔒 Enter Password for [${YELLOW}%s${RESET}]: " "$target_ssid"
            read -r target_pass </dev/tty
            
            if [ ${#target_pass} -ge 8 ]; then
                break
            else
                log_error "Password must be at least 8 characters long!"
            fi
        done
    else
        log_info "Open network selected. No password required."
    fi

    # Connect
    echo
    wifi_connect_client "$chosen" "$target_ssid" "$target_enc" "$target_pass"
    ui_pause
}

wifi_client_menu() {
    local found=0 mode ssid disabled

    while true; do
        render_persistent_header
        ui_title "🌐 Wi-Fi WAN (Station Mode) Manager"
        
        # پیدا کردن تمام اینترفیس‌های وای‌فای که در حالت sta (Station/Client) هستند
        found=0
        for sec in $(uci show wireless 2>/dev/null | grep "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
            mode=$(uci -q get wireless.$sec.mode)
            [ "$mode" != "sta" ] && continue
            
            ssid=$(uci -q get wireless.$sec.ssid)
            disabled=$(uci -q get wireless.$sec.disabled || echo "0")
            
            if [ "$found" -eq 0 ]; then
                printf "  ${BOLD}${CYAN}📊 Active Wi-Fi Client Status:${RESET}\n"
            fi
            
            if [ "$disabled" = "1" ]; then
                printf "    📶 SSID    ${GRAY}»${RESET} ${YELLOW}%-20s${RESET} ${GRAY}[Disabled]${RESET}\n" "$ssid"
            else
                printf "    📶 SSID    ${GRAY}»${RESET} ${YELLOW}%-20s${RESET} ${GREEN}[Connected]${RESET}\n" "$ssid"
            fi
            found=$((found + 1))
        done

        if [ "$found" -eq 0 ]; then
            printf "  ${GRAY}  No Wi-Fi Client configured.${RESET}\n"
        fi
        echo
        
        echo "  🔍 1) Scan and Connect to a Wi-Fi Network"
        echo "  ❌ 2) Disconnect and Remove ALL Wi-Fi Clients"
        
        ui_nav_footer
        ui_prompt 2
        
        case "$UI_CHOICE" in
            1) wifi_client_wizard ;;
            2) 
                # حذف تمام اینترفیس‌های کلاینت (sta) از UCI
                for sec in $(uci show wireless 2>/dev/null | grep "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
                    mode=$(uci -q get wireless.$sec.mode)
                    if [ "$mode" = "sta" ]; then
                        uci -q delete wireless.$sec
                    fi
                done
                uci commit wireless
                wifi reload >/dev/null 2>&1
                log_success "All Wi-Fi Client configurations removed."
                ui_pause
                ;;
            0) return 0 ;;
            q|Q) daypass_quit ;;
            h|H) ui_show_help "wifi_client" ;;
            *) log_warn "Invalid option" ;;
        esac
    done
}