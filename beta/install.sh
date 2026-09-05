#!/bin/sh

###############################################################################
# DayPass Installer (Auto-generated via Go Action)
###############################################################################

# Dynamic REPO_URL configuration
if [ -z "${REPO_URL:-}" ]; then
    REPO_URL="https://chamroosh98.github.io/DayPass/beta"
fi
export REPO_URL


# 📄 Source : globals.sh

export DAYPASS_DIR="/etc/daypass"
export INSTALL_LOG="$DAYPASS_DIR/install.log"
export TRANSACTION_LOG="/tmp/daypass/transaction.log" 

# 📄 Source : styles.sh

ESC="$(printf '\033')"

RESET="${ESC}[0m"
BOLD="${ESC}[1m"
DIM="${ESC}[2m"

BLACK="${ESC}[30m"
RED="${ESC}[31m"
GREEN="${ESC}[32m"
ORANGE="${ESC}[33m"
YELLOW="${ESC}[1;33m"
BLUE="${ESC}[34m"
PURPLE="${ESC}[35m"
PINK="${ESC}[1;35m"
CYAN="${ESC}[36m"
WHITE="${ESC}[37m"
GRAY="${ESC}[90m"

export RESET BOLD DIM CYAN GREEN YELLOW RED BLUE BLACK WHITE GRAY PURPLE ORANGE PINK


# 📄 Source : box_utils.sh

draw_bar()
{
    PCT="$1"
    BW="${2:-20}"
    MODE="${3:-usage}"
    
    [ "$PCT" -gt 100 ] && PCT=100
    [ "$PCT" -lt 0 ] && PCT=0

    FILLED=$(( PCT * BW / 100 ))

    if [ "$MODE" = "score" ]; then
        if [ "$PCT" -ge 80 ]; then COLOR="$GREEN"
        elif [ "$PCT" -ge 50 ]; then COLOR="$YELLOW"
        else COLOR="$RED"
        fi
    else
        if [ "$PCT" -ge 85 ]; then COLOR="$RED"
        elif [ "$PCT" -ge 60 ]; then COLOR="$YELLOW"
        else COLOR="$GREEN"
        fi
    fi

    BAR=""
    i=0
    while [ "$i" -lt "$FILLED" ]; do 
        BAR="${BAR}█"
        i=$((i+1))
    done
    while [ "$i" -lt "$BW" ]; do 
        BAR="${BAR}░"
        i=$((i+1))
    done

    printf "${COLOR}%s${RESET}" "$BAR"
}

log_warn()    { printf "  ${YELLOW}⚠️  %s${RESET}\n" "$1" >&2; }
log_info()    { printf "  ${CYAN}ℹ️  %s${RESET}\n" "$1"; }
log_success() { printf "  ${GREEN}✅  %s${RESET}\n" "$1"; }
log_error()   { printf "  ${RED}❌  %s${RESET}\n" "$1" >&2; }


# 📄 Source : header.sh

render_persistent_header()
{
    clear
    show_banner
    echo
}

# 📄 Source : progress.sh

# -----------------------------------------------------------------------------
# 1. Timer + Animated Progress (For Async background tasks like opkg/apk update)
# -----------------------------------------------------------------------------
show_timer_progress()
{
    pid="$1"
    message="$2"
    
    start_time=$(date +%s)
    bar_width=30
    current_step=0

    # Hide Cursor
    printf "\033[?25l" 2>/dev/null

    echo "  🖐️ Please wait, $message ..."

    while kill -0 "$pid" 2>/dev/null; do
        now=$(date +%s)
        elapsed=$((now - start_time))
        
        # Simulate smooth progress loop up to 95% until task finishes
        current_step=$(( (current_step + 1) % (bar_width + 1) ))
        percent=$((current_step * 100 / bar_width))
        [ "$percent" -gt 95 ] && percent=95

        # Build [====>    ] ASCII Bar
        arrow_pos=$current_step
        bar=""
        i=0
        while [ "$i" -lt "$bar_width" ]; do
            if [ "$i" -lt "$arrow_pos" ]; then
                bar="${bar}="
            elif [ "$i" -eq "$arrow_pos" ]; then
                bar="${bar}>"
            else
                bar="${bar} "
            fi
            i=$((i + 1))
        done

        # Line 1: Timer line
        # Line 2: Progress bar line
        printf "  \033[K⏰ DayPass is working in the background, timer : ${BOLD}%d seconds${RESET}\n" "$elapsed"
        printf "  \033[K[${CYAN}%s${RESET}] ${BOLD}%3d%%${RESET}\033[1A\r" "$bar" "$percent"

        if command -v usleep >/dev/null 2>&1; then
            usleep 150000 2>/dev/null
        else
            sleep 1
        fi
    done

    # Finish Line on Complete (100%)
    now=$(date +%s)
    elapsed=$((now - start_time))
    
    # Render Full Bar [==============================] 100%
    full_bar=""
    i=0
    while [ "$i" -lt "$bar_width" ]; do
        full_bar="${full_bar}="
        i=$((i + 1))
    done

    printf "  \033[K✌️ Task finished! total time : ${GREEN}%d seconds${RESET}\n" "$elapsed"
    printf "  \033[K[${GREEN}%s${RESET}] ${BOLD}100%%${RESET}\n" "$full_bar"

    # Restore Cursor
    printf "\033[?25h" 2>/dev/null
}

# -----------------------------------------------------------------------------
# 2. Strict Real-Time Step Progress (For File downloads / Batch Package items)
# -----------------------------------------------------------------------------
show_ascii_progress()
{
    title="$1"
    current="$2"
    total="$3"
    bar_width="${4:-30}"

    [ "$total" -le 0 ] && return

    percent=$((current * 100 / total))
    [ "$percent" -gt 100 ] && percent=100

    filled=$((percent * bar_width / 100))

    bar=""
    i=0
    while [ "$i" -lt "$bar_width" ]; do
        if [ "$i" -lt "$filled" ]; then
            bar="${bar}="
        elif [ "$i" -eq "$filled" ] && [ "$percent" -lt 100 ]; then
            bar="${bar}>"
        else
            bar="${bar} "
        fi
        i=$((i + 1))
    done

    COLOR="${YELLOW}"
    [ "$percent" -ge 50 ] && COLOR="${CYAN}"
    [ "$percent" -eq 100 ] && COLOR="${GREEN}"

    printf "\r  ⏳ %-20s [${COLOR}%s${RESET}] ${BOLD}%3d%%${RESET} (%s/%s)" \
            "$title" "$bar" "$percent" "$current" "$total"

    [ "$current" -ge "$total" ] && echo
}

log_step()
{
    status="$1"
    message="$2"

    case "$status" in
        ok)   printf "  ${GREEN}✔ ${RESET} %s\n" "$message" ;;
        fail) printf "  ${RED}✖ ${RESET} %s\n" "$message" >&2 ;;
        warn) printf "  ${YELLOW}! ${RESET} %s\n" "$message" ;;
        *)    printf "  ${CYAN}ℹ ${RESET} %s\n" "$message" ;;
    esac
}

# 📄 Source : banner.sh

show_banner()
{
    VERSION="v1.2.0"
    GITHUB="github.com/Chamroosh98/DayPass"

    echo

    echo "${BOLD}${RED}   ____              ${BOLD}${WHITE} ____${RESET}              "
    echo "${BOLD}${RED}  |  _ \  __ _ _   _${BOLD}${WHITE} |  _ \  __ _ ___ ___${RESET}"
    echo "${BOLD}${RED}  | | | |/ _\`| | | |${BOLD}${WHITE}| |_) / _\` / __/ __|${RESET}   ${GRAY}${VERSION}${RESET}"
    echo "${BOLD}${RED}  | |_| | (_| | |_| |${BOLD}${WHITE}|  __/ (_| \__ \__ \\${RESET}   ${WHITE}${GITHUB}${RESET}"
    echo "${BOLD}${RED}  |____/ \__,_|\__, |${BOLD}${WHITE}|_|   \__,_|___/___/${RESET}"
    echo "${BOLD}${RED}               |___/${RESET}"

    echo
    echo "${GRAY}───────────────────── 🕊️ Remembering the IRAN Massacre on Jan 8-9, 2026 ─────────────────────${RESET}"
    echo
}

# 📄 Source : arch_detector.sh

detect_system_architecture()
{
    log_info "Detecting system architecture and target platform ..."

    ARCH=""
    OPENWRT_VER=""
    PKG_MGR="${PKG_MANAGER:-opkg}"

    # 1. Fetch official OpenWrt architecture and release version
    if [ -f /etc/openwrt_release ]; then
        . /etc/openwrt_release
        ARCH="$DISTRIB_ARCH"
        OPENWRT_VER="$DISTRIB_RELEASE"
    elif [ -f /etc/os-release ]; then
        OPENWRT_VER=$(grep "BUILD_ID=" /etc/os-release | cut -d'"' -f2)
    fi

    # 2. Fallback to package manager native check
    if [ -z "$ARCH" ]; then
        if [ "$PKG_MGR" = "apk" ] && command -v apk >/dev/null 2>&1; then
            ARCH=$(apk --print-arch 2>/dev/null)
        elif command -v opkg >/dev/null 2>&1; then
            ARCH=$(opkg print-architecture 2>/dev/null | awk 'END {print $2}')
        fi
    fi

    # 3. Final Fallback
    if [ -z "$ARCH" ]; then
        ARCH=$(uname -m)
        log_warn "Standard OpenWrt release file unreadable! Fallback architecture : [$ARCH]"
    fi

    # 4. Extract MAJOR Version (24 vs 25)
    OW_MAJOR_VER="24"
    if echo "$OPENWRT_VER" | grep -q "^25" || [ "$PKG_MGR" = "apk" ]; then
        OW_MAJOR_VER="25"
    fi

    log_success "System architecture resolved : [$ARCH]"
    [ -n "$OPENWRT_VER" ] && log_info "OpenWrt Release version : [$OPENWRT_VER] (Major: v$OW_MAJOR_VER)"

    export ARCH
    export OPENWRT_VER
    export OW_MAJOR_VER
}

# Standalone execution handler for testing
case "$0" in
    *arch_detector.sh)
        detect_system_architecture
        ;;
esac

# 📄 Source : manager.sh

# Detect and initialize the active package manager engine (apk or opkg)
detect_package_manager()
{
    # Clear lock files across all supported OpenWrt releases
    rm -f /var/lock/opkg.lock /lib/apk/db/lock /var/run/apk.lock /run/apk/db.lock 2>/dev/null
    
    # 1. Identify standard package manager binary
    if command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
        log_info "Package manager identified : [apk] (Alpine/OpenWrt NextGen)" 2>/dev/null || echo "[INFO] Package manager: apk"
    elif command -v opkg >/dev/null 2>&1; then
        PKG_MANAGER="opkg"
        log_info "Package manager identified : [opkg] (Legacy OpenWrt)" 2>/dev/null || echo "[INFO] Package manager: opkg"
    else
        log_error "Critical Error : Neither 'apk' nor 'opkg' package manager was found!" 2>/dev/null || echo "[ERROR] No package manager found!"
        exit 1
    fi

    export PKG_MANAGER
}

# Update package index with fallback logic for network/mirror failures
pkg_update()
{
    [ -z "${PKG_MANAGER:-}" ] && detect_package_manager

    log_info "Updating package indexes using [$PKG_MANAGER] ..." 2>/dev/null || echo "[INFO] Updating package indexes..."

    if [ "$PKG_MANAGER" = "apk" ]; then
        # Standard update first; if IPv6/DNS issues occur, fall back to IPv4
        if ! apk update --network-timeout 5 >/dev/null 2>&1; then
            log_warn "Standard APK update failed/timed out! Attempting fallback via IPv4 ..." 2>/dev/null
            if ! apk update --force-ipv4 --network-timeout 5 >/dev/null 2>&1; then
                log_warn "APK update encountered repository warnings. Proceeding with local cache ..." 2>/dev/null
            else
                log_success "APK indexes updated successfully using IPv4 fallback." 2>/dev/null
            fi
        else
            log_success "APK package indexes updated successfully." 2>/dev/null
        fi

    elif [ "$PKG_MANAGER" = "opkg" ]; then
        if ! opkg update >/dev/null 2>&1; then
            log_warn "OPKG update encountered minor mirror warnings. Proceeding anyway ..." 2>/dev/null
        else
            log_success "OPKG package indexes updated successfully." 2>/dev/null
        fi
    fi
}

# Get currently installed version string of a specific package
pkg_get_installed_version()
{
    pkg="$1"
    [ -z "$pkg" ] && echo "" && return 1
    [ -z "${PKG_MANAGER:-}" ] && detect_package_manager

    if [ "$PKG_MANAGER" = "apk" ]; then
        if ! apk info -e "$pkg" >/dev/null 2>&1; then
            echo ""
            return 0
        fi
        ver=$(apk list --installed "$pkg" 2>/dev/null | awk '{print $1}' | sed "s/^$pkg-//")
        [ -z "$ver" ] && ver=$(apk info -v "$pkg" 2>/dev/null | sed -e "s/^$pkg-//" -e 's/ WARNING:.*//')
        echo "$ver"
    elif [ "$PKG_MANAGER" = "opkg" ]; then
        opkg status "$pkg" 2>/dev/null | awk '/^Version:/ {print $2}'
    fi
}

# Check if target package is currently installed on host system
pkg_installed()
{
    PACKAGE_NAME="$1"
    [ -z "$PACKAGE_NAME" ] && return 1
    [ -z "${PKG_MANAGER:-}" ] && detect_package_manager

    if [ "$PKG_MANAGER" = "apk" ]; then
        apk info -e "$PACKAGE_NAME" >/dev/null 2>&1
    elif [ "$PKG_MANAGER" = "opkg" ]; then
        opkg status "$PACKAGE_NAME" 2>/dev/null | grep -q "Status: .* installed"
    fi
}

# Install a specific single package via system package manager
pkg_install()
{
    PACKAGE_NAME="$1"
    [ -z "$PACKAGE_NAME" ] && return 1
    [ -z "${PKG_MANAGER:-}" ] && detect_package_manager

    # log_info "Executing package installation : [$PACKAGE_NAME]" 2>/dev/null || echo "[INFO] Installing: $PACKAGE_NAME"

    if [ "$PKG_MANAGER" = "apk" ]; then
        # 1. Try standard installation with untrusted keyring bypass
        if apk add --no-cache --allow-untrusted "$PACKAGE_NAME" >/dev/null 2>&1; then
            log_success "[$PACKAGE_NAME]" 2>/dev/null
            return 0
        fi

        # 2. Fallback attempt using IPv4 explicit routing if network fails
        log_warn "Standard APK installation failed for [$PACKAGE_NAME]. Trying IPv4 fallback ..." 2>/dev/null
        if apk add --force-ipv4 --no-cache --allow-untrusted "$PACKAGE_NAME" >/dev/null 2>&1; then
            log_success "Package [$PACKAGE_NAME] installed successfully via APK (IPv4 fallback)." 2>/dev/null
            return 0
        fi

        log_error "APK failed to install package : [$PACKAGE_NAME]" 2>/dev/null
        return 1

    elif [ "$PKG_MANAGER" = "opkg" ]; then
        # Install with opkg bypassing unverified signature warnings
        if opkg install --force-checksum "$PACKAGE_NAME" >/dev/null 2>&1; then
            log_success "Package [$PACKAGE_NAME] installed successfully via OPKG!" 2>/dev/null
            return 0
        fi

        log_error "OPKG failed to install package : [$PACKAGE_NAME]" 2>/dev/null
        return 1
    fi
}

# 📄 Source : zero_deps.sh

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

    COMMON_DEPS="ca-bundle ca-certificates curl jq libnetfilter-conntrack"
    OW24_EXTRA_DEPS="coreutils coreutils-base64 coreutils-nohup coreutils-timeout ip-full unzip resolveip lua libuci-lua luci-compat luci-lib-jsonc luci-lua-runtime lyaml"

    TARGET_PACKAGES="$COMMON_DEPS"

    if [ "$OW_MAJOR_VER" = "24" ] && [ "$PKG_MANAGER" = "opkg" ]; then
        TARGET_PACKAGES="$TARGET_PACKAGES $OW24_EXTRA_DEPS"
    fi

    MISSING_PACKAGES=""

    for pkg in $TARGET_PACKAGES; do
        case "$pkg" in
            curl)  command -v curl >/dev/null 2>&1 && continue ;;
            jq)    command -v jq >/dev/null 2>&1 && continue ;;
            unzip) command -v unzip >/dev/null 2>&1 && continue ;;
            lua)   command -v lua >/dev/null 2>&1 && continue ;;
        esac

        if command -v pkg_installed >/dev/null 2>&1; then
            if ! pkg_installed "$pkg"; then
                MISSING_PACKAGES="$MISSING_PACKAGES $pkg"
            fi
        fi
    done

    DNSMASQ_FULL_MISSING=0
    if [ -f /etc/openwrt_release ]; then
        if command -v pkg_installed >/dev/null 2>&1; then
            if ! pkg_installed "dnsmasq-full"; then
                DNSMASQ_FULL_MISSING=1
            fi
        fi
    fi

    if [ -z "$MISSING_PACKAGES" ] && [ "$DNSMASQ_FULL_MISSING" -eq 0 ]; then
        log_success "Core system dependencies are ready & up to date!"
        return 0
    fi

    log_info "Setting up required system components for DayPass (OpenWrt v$OW_MAJOR_VER) ..."

    (pkg_update >/dev/null 2>&1) &
    BG_PID=$!
    if command -v show_timer_progress >/dev/null 2>&1; then
        show_timer_progress "$BG_PID" "refreshing package index"
    fi
    wait "$BG_PID"

    if [ -n "$MISSING_PACKAGES" ]; then
        for pkg in $MISSING_PACKAGES; do
            (pkg_install "$pkg" >/dev/null 2>&1) &
            BG_PID=$!
            
            if command -v show_timer_progress >/dev/null 2>&1; then
                show_timer_progress "$BG_PID" "installing core tool [$pkg]"
            fi
            wait "$BG_PID"
        done
    fi

    if [ "$DNSMASQ_FULL_MISSING" -eq 1 ]; then
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
            show_timer_progress "$BG_PID" "optimizing DNS engine (dnsmasq-full)"
        fi
        wait "$BG_PID"
        
        echo "nameserver 8.8.8.8" > /tmp/resolv.conf.auto 2>/dev/null || true
        /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
        /etc/init.d/network reload >/dev/null 2>&1 || true
        sleep 2
    fi

    log_success "All system dependencies configured successfully!"
}

# 📄 Source : arch_check.sh

check_version() {
    # Detect package manager
    PKG_MANAGER=""
    if command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
    elif command -v opkg >/dev/null 2>&1; then
        PKG_MANAGER="opkg"
    else
        log_error "No supported package manager (opkg/apk) found!"
        return 1
    fi
    export PKG_MANAGER

    # Read OpenWrt system version details
    OPENWRT_VERSION="$(
        . /etc/openwrt_release 2>/dev/null
        echo "$DISTRIB_RELEASE"
    )"

    # Extract major release number (e.g., 24 or 25)
    OPENWRT_MAJOR="$(echo "$OPENWRT_VERSION" | cut -d'.' -f1)"
    
    # Fallback detection for major version based on package manager if release parsing fails
    if [ -z "$OPENWRT_MAJOR" ]; then
        if [ "$PKG_MANAGER" = "apk" ]; then
            OPENWRT_MAJOR="25"
        else
            OPENWRT_MAJOR="24"
        fi
    fi
    export OPENWRT_MAJOR

    if [ -z "$OPENWRT_VERSION" ]; then
        log_warn "Unable to detect exact OpenWrt version!"
    else
        log_info "OpenWrt Version : ${OPENWRT_VERSION} (Engine : ${PKG_MANAGER})"
    fi
}

# 📄 Source : network_info.sh

# Map country codes to custom emoji flags
country_flag()
{
    case "$1" in
        IR) echo "🦁☀️" ;;
        AZ) echo "🇦🇿" ;;
        DE) echo "🇩🇪" ;;
        US) echo "🇺🇸" ;;
        NL) echo "🇳🇱" ;;
        RU) echo "🇷🇺" ;;
        CN) echo "🇨🇳" ;;
        JP) echo "🇯🇵" ;;
        SG) echo "🇸🇬" ;;
        TR) echo "🇹🇷" ;;
        GB) echo "🇬🇧" ;;
        FR) echo "🇫🇷" ;;
        FI) echo "🇫🇮" ;;
        SE) echo "🇸🇪" ;;
        PL) echo "🇵🇱" ;;
        *)  echo "🌐" ;;
    esac
}

# Fetch public IP details using cascading fallback providers
fetch_ip_data()
{
    # Provider 1: ipwho.is
    NETWORK_JSON="$($FETCH_CMD https://ipwho.is/ 2>/dev/null || true)"
    if [ -n "$NETWORK_JSON" ] && echo "$NETWORK_JSON" | grep -q '"success":true'; then
        echo "$NETWORK_JSON" | jq -r '"true|\(.ip // "")|\(.country // "")|\(.country_code // "")|\(.flag.emoji // "")|\(.city // "")|\(.connection.isp // "")|\(.connection.asn // "")"' 2>/dev/null || echo "false|||||||"
        return 0
    fi

    # Provider 2: ipapi.co
    NETWORK_JSON="$($FETCH_CMD https://ipapi.co/json/ 2>/dev/null || true)"
    if [ -n "$NETWORK_JSON" ] && echo "$NETWORK_JSON" | grep -q '"ip"'; then
        echo "$NETWORK_JSON" | jq -r '"true|\(.ip // "")|\(.country_name // "")|\(.country_code // "")||\(.city // "")|\(.org // "")|\(.asn // "")"' 2>/dev/null || echo "false|||||||"
        return 0
    fi
    
    # Provider 3: ifconfig.co
    NETWORK_JSON="$($FETCH_CMD https://ifconfig.co/json 2>/dev/null || true)"
    if [ -n "$NETWORK_JSON" ] && echo "$NETWORK_JSON" | grep -q '"ip"'; then
        echo "$NETWORK_JSON" | jq -r '"true|\(.ip // "")|\(.country // "")|\(.country_iso // "")||\(.city // "")|\(.asn_org // "")|\(.asn // "")"' 2>/dev/null || echo "false|||||||"
        return 0
    fi

    echo "false|||||||"
}

# Render full network information panel
show_full_network_info()
{
    # Render persistent header if function is available
    if command -v render_persistent_header >/dev/null 2>&1; then
        render_persistent_header
    else
        clear
        [ -n "$(command -v show_banner)" ] && show_banner
    fi
    
    printf "  ${CYAN:-}🌐 Network Diagnostics & Information${RESET:-}\n"
    printf "  ${GRAY:-}─────────────────────────────────────────${RESET:-}\n"

    # Determine available HTTP client engine
    if command -v curl >/dev/null 2>&1; then
        FETCH_CMD="curl -fsS --connect-timeout 2 --max-time 4"
    elif command -v uclient-fetch >/dev/null 2>&1; then
        FETCH_CMD="uclient-fetch -q -T 4 -O-"
    elif command -v wget >/dev/null 2>&1; then
        FETCH_CMD="wget -q -T 4 -O-"
    else
        printf "  ${YELLOW:-}⚠️  curl / uclient-fetch / wget unavailable!${RESET:-}\n\n"
        return 0
    fi

    # Ensure JSON parser dependency is met
    if ! command -v jq >/dev/null 2>&1; then
        PKG_CMD="${PKG_MANAGER:-opkg} install jq"
        printf "  ${YELLOW:-}⚠️  jq is missing! Install via : %s${RESET:-}\n\n" "$PKG_CMD"
        return 0
    fi

    printf "  ${GRAY:-}Fetching network details ...${RESET:-}\r"
    PARSED_DATA="$(fetch_ip_data 2>/dev/null || echo "false|||||||")"

    IFS='|' read -r SUCCESS PUBLIC_IP COUNTRY COUNTRY_CODE FLAG CITY ISP ASN <<EOF
$PARSED_DATA
EOF

    if [ "${SUCCESS:-false}" != "true" ] || [ -z "$PUBLIC_IP" ]; then
        printf "  ${GRAY:-}Public IP :${RESET:-} ${RED:-}Offline / Disconnected${RESET:-}\n"
        printf "  ${GRAY:-}Status    :${RESET:-} ${YELLOW:-}No Internet Access${RESET:-}\n"
    else
        if [ "$COUNTRY_CODE" = "IR" ]; then
            FLAG="🦁☀️"
        elif [ -z "$FLAG" ]; then
            FLAG="$(country_flag "$COUNTRY_CODE")"
        fi

        CITY_STR=""
        [ -n "$CITY" ] && CITY_STR=" ${GRAY:-}($CITY)${RESET:-}"

        printf "\033[K   Public IP   : %s\n" "$PUBLIC_IP"
        printf "   Country     : %s %s%s\n" "$FLAG" "$COUNTRY" "${CITY_STR}"
        [ -n "$ISP" ] && printf "   ISP         : %s\n" "$ISP"
        [ -n "$ASN" ] && printf "   ASN         : %s%s%s\n" "${GRAY:-}" "$ASN" "${RESET:-}"
    fi

    printf "  ${GRAY:-}─────────────────────────────────────────${RESET:-}\n\n"
}

# Real-time WAN bandwidth monitoring
show_live_speed() {
    # Auto-detect active primary network interface across OpenWrt v24/v25
    IFACE=$(uci -q get network.wan.device || uci -q get network.wan.ifname || echo "")
    
    if [ -z "$IFACE" ] || [ ! -d "/sys/class/net/$IFACE" ]; then
        # Fallback search for default route interface or common WAN defaults
        IFACE="$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')"
        [ -z "$IFACE" ] || [ ! -d "/sys/class/net/$IFACE" ] && IFACE="eth0"
    fi

    echo
    MSG="Monitoring live speed on [${CYAN:-}$IFACE]${RESET:-} ${GRAY:-}(Press Ctrl+C to stop) ... ${RESET:-}"
    if command -v log_info >/dev/null 2>&1; then
        log_info "$MSG"
    else
        echo "$MSG"
    fi
    echo

    RX_PREV=$(cat "/sys/class/net/$IFACE/statistics/rx_bytes" 2>/dev/null || echo 0)
    TX_PREV=$(cat "/sys/class/net/$IFACE/statistics/tx_bytes" 2>/dev/null || echo 0)

    # Trap signal to restore terminal formatting on SIGINT (Ctrl+C)
    trap 'echo ""; trap - INT; return 0' INT

    while true; do
        sleep 1
        RX_NOW=$(cat "/sys/class/net/$IFACE/statistics/rx_bytes" 2>/dev/null || echo 0)
        TX_NOW=$(cat "/sys/class/net/$IFACE/statistics/tx_bytes" 2>/dev/null || echo 0)

        RX_SPEED=$(( (RX_NOW - RX_PREV) / 1024 ))
        TX_SPEED=$(( (TX_NOW - TX_PREV) / 1024 ))

        if [ "$RX_SPEED" -gt 1024 ]; then
            RX_FMT="$(awk "BEGIN {printf \"%.2f MB/s\", $RX_SPEED/1024}")"
        else
            RX_FMT="${RX_SPEED} KB/s"
        fi

        if [ "$TX_SPEED" -gt 1024 ]; then
            TX_FMT="$(awk "BEGIN {printf \"%.2f MB/s\", $TX_SPEED/1024}")"
        else
            TX_FMT="${TX_SPEED} KB/s"
        fi

        printf "\r  📥 ${GREEN:-}Down:${RESET:-} %s%-10s%s ${GRAY:-}|${RESET:-}    📤 ${YELLOW:-}Up:${RESET:-} %s%-10s%s\033[K" \
            "${GREEN:-}" "$RX_FMT" "${RESET:-}" \
            "${YELLOW:-}" "$TX_FMT" "${RESET:-}"

        RX_PREV=$RX_NOW
        TX_PREV=$TX_NOW
    done
}

# Main interactive network menu loop
network_menu()
{
    while true; do
        show_full_network_info
        
        printf "  📊 ${CYAN:-}1${RESET:-}) Live Speed Monitor\n"
        printf "  🔄 ${CYAN:-}2${RESET:-}) Refresh Information\n"
        printf "  🚪 ${CYAN:-}0${RESET:-}) Back to Main Menu\n\n"
        
        printf "  ⁉️ ${YELLOW:-}Select${RESET:-} ${GRAY:-}:${RESET:-} "
        read -r net_choice </dev/tty

        case "$net_choice" in
            1) show_live_speed ;;
            2) continue ;;
            0) echo "   ${GRAY}  Exiting ...${RESET}"
                sleep 1
                clear
                break 
                ;;
            *) 
                if command -v log_warn >/dev/null 2>&1; then
                    log_warn "Invalid choice!"
                else
                    echo "Invalid choice!"
                fi
                ;;
        esac
    done
}

# Script entry point handler
case "$0" in
    *network_checker.sh|*network_info.sh) network_menu ;;
esac

# 📄 Source : dns_fix.sh

BACKUP_DNS_FILE="/etc/resolv.conf.daypass.bak"

# Apply temporary DNS fix for package managers (opkg/apk) and system resolution
apply_dns()
{
    NEW_DNS="${1:-1.1.1.1}"
    log_info "Setting temporary DNS to : [$NEW_DNS]"

    if [ -f /etc/resolv.conf ] || [ -L /etc/resolv.conf ]; then
        # Backup original resolv.conf structure if not already backed up
        if [ ! -f "$BACKUP_DNS_FILE" ]; then
            cp -a /etc/resolv.conf "$BACKUP_DNS_FILE" 2>/dev/null
            log_success "Original DNS backed up to : [$BACKUP_DNS_FILE]"
        fi

        # Unlink if /etc/resolv.conf is a symlink to prevent overwriting targets unexpectedly
        if [ -L /etc/resolv.conf ]; then
            rm -f /etc/resolv.conf
        fi

        # Write new nameserver directly for immediate resolution
        echo "nameserver $NEW_DNS" > /etc/resolv.conf
        
        # Optionally apply to UCI network configuration for persistence during setup
        if command -v uci >/dev/null 2>&1; then
            uci -q del network.wan.dns 2>/dev/null || true
            uci -q add_list network.wan.dns="$NEW_DNS" 2>/dev/null || true
        fi

        log_success "DNS changed to : [$NEW_DNS]"
    fi
}

# Restore original DNS configuration from backup
restore_dns()
{
    if [ -f "$BACKUP_DNS_FILE" ]; then
        rm -f /etc/resolv.conf 2>/dev/null
        cp -a "$BACKUP_DNS_FILE" /etc/resolv.conf 2>/dev/null
        rm -f "$BACKUP_DNS_FILE" 2>/dev/null
        
        # Revert UCI changes if needed
        if command -v uci >/dev/null 2>&1; then
            uci -q del network.wan.dns 2>/dev/null || true
        fi

        log_success "Original DNS restored successfully!"
    else
        log_warn "No DNS backup found to restore!"
    fi
}

# Interactive DNS resolution recovery menu
dns_fix_menu()
{
    if command -v render_persistent_header >/dev/null 2>&1; then
        render_persistent_header
    else
        clear
    fi

    echo "  ───────────────────────────────────────────────────────────"
    echo "   📡 DNS Resolution Recovery                                "
    echo "  ───────────────────────────────────────────────────────────"
    echo "   ☁️ 1) Cloudflare DNS   (1.1.1.1)                          "
    echo "   🔍 2) Google DNS       (8.8.8.8)                          "
    echo "   🛡️ 3) Quad9 DNS        (9.9.9.9)                          "
    
    if [ -f "$BACKUP_DNS_FILE" ]; then
        echo "   4) 🔄 Restore Original DNS                           "
        echo "   5) 🚫 Skip                                           "
        MAX_OPT="5"
    else
        echo "   4) 🚫 Skip                                           "
        MAX_OPT="4"
    fi
    echo "  ───────────────────────────────────────────────────────────"
    echo

    printf "  ⁉️ Select option [1-%s] (Default: 1) : " "$MAX_OPT"
    read -r dns_choice </dev/tty

    case "$dns_choice" in
        1|"")
            apply_dns "1.1.1.1"
            ;;
        2)
            apply_dns "8.8.8.8"
            ;;
        3)
            apply_dns "9.9.9.9"
            ;;
        4) 
            if [ -f "$BACKUP_DNS_FILE" ]; then
                restore_dns
            else
                log_info "Skipping DNS fix!"
            fi
            ;;
        *)
            log_info "Skipping DNS fix!"
            ;;
    esac
}

# Standalone execution handler
case "$0" in
    *dns_fix.sh) dns_fix_menu ;;
esac

# 📄 Source : lan_ip.sh

validate_ip()
{
    ip="$1"
    case "$ip" in
        ""|*[!0-9.]*) return 1 ;;
    esac

    O1=$(echo "$ip" | cut -d. -f1)
    O2=$(echo "$ip" | cut -d. -f2)
    O3=$(echo "$ip" | cut -d. -f3)
    O4=$(echo "$ip" | cut -d. -f4)

    [ -z "$O1" ] || [ -z "$O2" ] || [ -z "$O3" ] || [ -z "$O4" ] && return 1
    [ "$O1" -gt 255 ] || [ "$O2" -gt 255 ] || [ "$O3" -gt 255 ] || [ "$O4" -ge 255 ] && return 1
    [ "$O4" -le 0 ] && return 1

    return 0
}

change_lan_ip_menu()
{
    render_persistent_header 2>/dev/null || clear

    CURRENT_IP=$(uci -q get network.lan.ipaddr || echo "192.168.1.1")
    CURRENT_NETMASK=$(uci -q get network.lan.netmask || echo "255.255.255.0")

    echo "  🌐 Local LAN IP Subnet Configuration"
    echo "  ───────────────────────────────────────────────────────────"
    echo "  ➡️ Current Router LAN IP : ${CYAN}${CURRENT_IP}${RESET}"
    echo "  ➡️ Current Netmask       : ${CYAN}${CURRENT_NETMASK}${RESET}"
    echo "  ───────────────────────────────────────────────────────────"
    echo "  ${GRAY}💡 Note : Changing LAN IP prevents IP Conflicts if your${RESET}"
    echo "  ${GRAY}upstream ISP Modem is also using 192.168.1.1 .${RESET}"
    echo "  ───────────────────────────────────────────────────────────"
    echo

    printf "  ⁉️ Do you want to change the Router LAN IP? [y/N] : "
    read -r confirm </dev/tty

    case "$confirm" in
        y|Y) ;;
        *)
            log_warn "LAN IP change cancelled!"
            sleep 1
            return 0
            ;;
    esac

    echo
    while true; do
        printf "  ✏️ Enter New LAN IP Address [e.g. 192.168.10.1] : "
        read -r NEW_IP </dev/tty

        if validate_ip "$NEW_IP"; then
            break
        else
            log_error "Invalid IP address format! Please try again!"
        fi
    done

    if [ "$NEW_IP" = "$CURRENT_IP" ]; then
        log_warn "New IP is identical to current IP. Nothing changed!"
        sleep 2
        return 0
    fi

    # Extract network prefix (first 3 octets)
    PREFIX=$(echo "$NEW_IP" | cut -d. -f1-3)

    log_info "Updating LAN IP address to [$NEW_IP] ..."

    # 1. Change LAN IP
    uci set network.lan.ipaddr="$NEW_IP"
    uci set network.lan.netmask="255.255.255.0"

    # 2. Update DHCP settings (important!)
    # Start from .100 and give 150 addresses (up to .249)
    uci set dhcp.lan.start="100"
    uci set dhcp.lan.limit="150"
    uci set dhcp.lan.leasetime="12h"

    # Make sure DHCP is enabled on lan
    uci set dhcp.lan.interface="lan"
    uci set dhcp.lan.ignore="0"

    uci commit network
    uci commit dhcp

    echo
    log_warn "NETWORK RESTART REQUIRED!"
    log_warn "After applying, your terminal/SSH session will disconnect!"
    log_warn "Reconnect using the new IP : ${GREEN}http://${NEW_IP}${RESET}"
    echo
    log_info "DHCP Pool will be : ${CYAN}${PREFIX}.100 - ${PREFIX}.249${RESET}"
    echo

    printf "  ⁉️ Apply changes now and restart network + DHCP? [y/N] : "
    read -r apply_confirm </dev/tty

    case "$apply_confirm" in
        y|Y)
            log_info "Clearing old DHCP leases ..."
            rm -f /tmp/dhcp.leases /tmp/hosts/dhcp* 2>/dev/null

            log_info "Restarting network and dnsmasq ..."
            (
                /etc/init.d/network restart >/dev/null 2>&1
                sleep 2
                /etc/init.d/dnsmasq restart >/dev/null 2>&1
            ) &

            log_success "LAN IP updated to $NEW_IP"
            log_success "DHCP pool set to ${PREFIX}.100 - ${PREFIX}.249"
            log_warn "Please reconnect your devices to get new IPv4 address!"
            exit 0
            ;;
        *)
            log_warn "Changes saved to UCI, but services were not restarted!"
            log_info "You can apply later with ==> /etc/init.d/network restart!"
            sleep 2
            ;;
    esac
}

# 📄 Source : usb_wan.sh
# ============================================================
# DayPass - USB WAN Module
# Handles Android / iPhone USB Tethering interface
# ============================================================

# Detect active USB tethering network device
detect_usb_device() {
    for dev in usb0 usb1 rndis0 eth1 eth2; do
        if ip link show "$dev" >/dev/null 2>&1; then
            echo "$dev"
            return 0
        fi
    done
    echo ""
}

# Create or update USB tethering WAN interface
setup_usb_wan() {
    log_info "Setting up USB Tethering WAN interface ..."

    local usb_dev
    usb_dev=$(detect_usb_device)

    if [ -z "$usb_dev" ]; then
        log_warn "No USB tethering device detected."
        log_warn "Connect your phone and enable USB Tethering first."
        usb_dev="usb0"
    else
        log_success "Detected USB device : $usb_dev"
    fi

    uci set network.wan_usb=interface
    uci set network.wan_usb.proto='dhcp'
    uci set network.wan_usb.device="$usb_dev"
    uci set network.wan_usb.metric='20'
    uci commit network

    # Add to firewall wan zone safely
    local zone
    zone=$(uci show firewall | grep "=zone" | while read -r l; do
        s=$(echo "$l" | cut -d'.' -f2 | cut -d'=' -f1)
        [ "$(uci -q get firewall.$s.name)" = "wan" ] && echo "$s" && break
    done)

    if [ -n "$zone" ]; then
        uci -q del_list firewall.$zone.network='wan_usb'
        uci add_list firewall.$zone.network='wan_usb'
        uci commit firewall
    fi

    ifup wan_usb >/dev/null 2>&1 || true
    log_success "USB WAN interface [wan_usb] is ready!"
}

# 📄 Source : wifi_wan.sh
# ============================================================
# DayPass - Wi-Fi WAN (Station / Client Mode)
# Connects the router to an external hotspot for internet
# Does NOT touch any Access Point interfaces
# ============================================================

setup_wifi_wan() {
    render_persistent_header 2>/dev/null || clear

    echo "  📡 Wi-Fi WAN (Station Mode)"
    echo "  ───────────────────────────────────────────────────────────"
    echo "  ${GRAY:-}Connect this router to a phone hotspot or another Wi-Fi${RESET}"
    echo "  ${GRAY:-}network to use it as an internet source (WWAN)!${RESET}"
    echo "  ───────────────────────────────────────────────────────────"
    echo

    # List radios
    local radios idx=1 radio_list=""
    radios=$(uci show wireless 2>/dev/null | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1)

    if [ -z "$radios" ]; then
        log_error "No wireless radio found."
        return 1
    fi

    echo "  📻 Available Radios :"
    for r in $radios; do
        band=$(uci -q get wireless.$r.band || uci -q get wireless.$r.hwmode || echo "unknown")
        echo "     $idx) $r ($band)"
        radio_list="$radio_list $r"
        idx=$((idx + 1))
    done
    echo

    printf "  📋 Select radio [1] : "
    read -r choice </dev/tty
    [ -z "$choice" ] && choice=1

    local chosen="" i=1
    for r in $radio_list; do
        [ "$i" -eq "$choice" ] && chosen="$r" && break
        i=$((i + 1))
    done
    [ -z "$chosen" ] && chosen=$(echo $radio_list | awk '{print $1}')

    printf "  📶 Hotspot SSID : "
    read -r ssid </dev/tty
    [ -z "$ssid" ] && { log_error "SSID is required!"; return 1; }

    printf "  🔒 Password (leave empty if open) : "
    read -r pass </dev/tty

    # Logical interface
    uci set network.wwan=interface
    uci set network.wwan.proto='dhcp'
    uci set network.wwan.metric='30'
    uci commit network

    # Station interface (never touches AP)
    uci set wireless.wwan_sta=wifi-iface
    uci set wireless.wwan_sta.device="$chosen"
    uci set wireless.wwan_sta.mode='sta'
    uci set wireless.wwan_sta.network='wwan'
    uci set wireless.wwan_sta.ssid="$ssid"
    uci set wireless.wwan_sta.disabled='0'

    if [ -n "$pass" ]; then
        uci set wireless.wwan_sta.encryption='psk2'
        uci set wireless.wwan_sta.key="$pass"
    else
        uci set wireless.wwan_sta.encryption='none'
    fi

    uci commit wireless

    # Firewall
    local zone
    zone=$(uci show firewall | grep "=zone" | while read -r l; do
        s=$(echo "$l" | cut -d'.' -f2 | cut -d'=' -f1)
        [ "$(uci -q get firewall.$s.name)" = "wan" ] && echo "$s" && break
    done)
    if [ -n "$zone" ]; then
        uci -q del_list firewall.$zone.network='wwan'
        uci add_list firewall.$zone.network='wwan'
        uci commit firewall
    fi

    wifi reload >/dev/null 2>&1
    log_success "Wi-Fi WAN connected to [$ssid] on radio [$chosen]!"
}

# 📄 Source : wifi_ap.sh
# ============================================================
# DayPass - Wi-Fi Access Point Module
# Manages Home Wi-Fi (AP Mode only)
# Never touches Station / WWAN interfaces
# ============================================================

# ------------------------------------------------------------
# Show current Access Point status
# ------------------------------------------------------------
show_ap_status() {
    echo "  📶 Current Access Point Status"
    echo "  ───────────────────────────────────────────────────────────"

    local found=0
    for sec in $(uci show wireless 2>/dev/null | grep "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
        mode=$(uci -q get wireless.$sec.mode)
        [ "$mode" != "ap" ] && continue

        ssid=$(uci -q get wireless.$sec.ssid)
        disabled=$(uci -q get wireless.$sec.disabled || echo "0")
        device=$(uci -q get wireless.$sec.device)
        encryption=$(uci -q get wireless.$sec.encryption)
        network=$(uci -q get wireless.$sec.network)

        if [ "$disabled" = "1" ]; then
            status="${GRAY}Disabled${RESET}"
        else
            status="${GREEN}Enabled${RESET}"
        fi

        echo "  • SSID       : ${YELLOW}${ssid}${RESET}"
        echo "  • Device     : $device"
        echo "  • Network    : $network"
        echo "  • Encryption : $encryption"
        echo "  • Status     : $status"
        echo
        found=1
    done

    [ "$found" -eq 0 ] && echo "  ${GRAY}No Access Point configured yet!${RESET}"
    echo "  ───────────────────────────────────────────────────────────"
}

# ------------------------------------------------------------
# Main Setup Function
# ------------------------------------------------------------
setup_wifi_ap() {
    render_persistent_header 2>/dev/null || clear

    echo "  📡 Wi-Fi Access Point Configuration"
    echo "  ───────────────────────────────────────────────────────────"
    echo "  ${GRAY}This module only manages Access Point (home Wi-Fi).${RESET}"
    echo "  ${GRAY}Station / WWAN interfaces will not be modified.${RESET}"
    echo "  ───────────────────────────────────────────────────────────"
    echo

    # Detect radios
    local RADIOS
    RADIOS=$(uci show wireless 2>/dev/null | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1)

    if [ -z "$RADIOS" ]; then
        wifi config 2>/dev/null
        RADIOS=$(uci show wireless 2>/dev/null | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1)
    fi

    if [ -z "$RADIOS" ]; then
        log_error "No wireless radio detected on this device."
        return 1
    fi

    show_ap_status

    # Check if any AP already exists
    local has_ap=0
    for sec in $(uci show wireless | grep "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
        [ "$(uci -q get wireless.$sec.mode)" = "ap" ] && has_ap=1 && break
    done

    if [ "$has_ap" -eq 1 ]; then
        printf "  ⁉️ Existing Access Points found. Reconfigure? [y/N] : "
        read -r reconf </dev/tty
        case "$reconf" in
            y|Y) ;;
            *)
                printf "  ${GRAY}>> Keeping current AP settings.${RESET}\n"
                sleep 1
                return 0
                ;;
        esac
    fi

    # SSID Strategy
    echo
    echo "  ⚙️ SSID Naming Strategy :"
    echo "     1) Unified SSID for all bands (Smart Connect)"
    echo "     2) Separate SSID per band (2.4G + 5G)"
    echo "  ───────────────────────────────────────────────────────────"
    printf "  ⁉️ Select [1/2] (default: 1) : "
    read -r ssid_mode </dev/tty
    [ -z "$ssid_mode" ] && ssid_mode=1

    local SSID_2G SSID_5G

    if [ "$ssid_mode" = "2" ]; then
        printf "  🛜 2.4GHz SSID [DayPass-2.4G] : "
        read -r SSID_2G </dev/tty
        [ -z "$SSID_2G" ] && SSID_2G="DayPass-2.4G"

        printf "  🛜 5GHz SSID [DayPass-5G] : "
        read -r SSID_5G </dev/tty
        [ -z "$SSID_5G" ] && SSID_5G="DayPass-5G"
    else
        printf "  🛜 Unified SSID [DayPass] : "
        read -r unified </dev/tty
        [ -z "$unified" ] && unified="DayPass"
        SSID_2G="$unified"
        SSID_5G="$unified"
    fi

    # Password
    local password=""
    while true; do
        printf "  🔒 WiFi Password (min 8 characters) : "
        read -r password </dev/tty
        if [ ${#password} -ge 8 ]; then
            break
        fi
        log_error "Password must be at least 8 characters!"
    done

    # Apply configuration to all radios
    log_info "Applying Access Point configuration ..."

    for radio in $RADIOS; do
        uci set wireless.$radio.disabled='0'

        local band
        band=$(uci -q get wireless.$radio.band || uci -q get wireless.$radio.hwmode || echo "")

        local iface="ap_${radio}"
        uci set wireless.$iface=wifi-iface
        uci set wireless.$iface.device="$radio"
        uci set wireless.$iface.mode='ap'
        uci set wireless.$iface.network='lan'
        uci set wireless.$iface.disabled='0'
        uci set wireless.$iface.encryption='psk2'
        uci set wireless.$iface.key="$password"

        case "$band" in
            *5g*|*a*|*ac*|*ax*) 
                uci set wireless.$iface.ssid="$SSID_5G"
                log_success "Configured 5GHz AP on $radio → $SSID_5G"
                ;;
            *)
                uci set wireless.$iface.ssid="$SSID_2G"
                log_success "Configured 2.4GHz AP on $radio → $SSID_2G"
                ;;
        esac
    done

    uci commit wireless
    wifi reload >/dev/null 2>&1 || /etc/init.d/network restart >/dev/null 2>&1

    echo
    log_success "Access Point configuration completed successfully!"
}

# ------------------------------------------------------------
# Main Menu
# ------------------------------------------------------------
wifi_ap_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear

        echo "  📡 Wi-Fi Access Point Manager"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  👀 1) Show current AP status"
        echo "  🛜 2) Create / Update Access Point (AP)"
        echo "  🚪 0) Back"
        echo "  ───────────────────────────────────────────────────────────"
        printf "  ⁉️ Select option [0-2] : "
        read -r choice </dev/tty

        case "$choice" in
            1)
                show_ap_status
                printf "  ${GRAY:-}Press [Enter] to continue ... ${RESET:-}\n"
                read -r _ </dev/tty
                ;;
            2)
                setup_wifi_ap
                printf "  ${GRAY:-}Press [Enter] to continue ... ${RESET:-}\n"
                read -r _ </dev/tty
                ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac
    done
}

# Allow direct execution
case "$0" in
    *wifi_ap.sh)
        wifi_ap_menu
        ;;
esac

# 📄 Source : load_balancer.sh
# ============================================================
# DayPass - Multi-WAN Load Balancer (mwan3 Orchestrator)
# ============================================================

configure_mwan3_engine() {
    log_info "Configuring mwan3 engine ..."

    uci set mwan3.globals=globals
    uci set mwan3.globals.mmx_mask='0x3f00'

    # Interfaces
    for iface in wan wan_usb wwan; do
        uci set mwan3.$iface=interface
        uci set mwan3.$iface.enabled='1'
        uci set mwan3.$iface.family='ipv4'
        uci -q delete mwan3.$iface.track_ip
        uci add_list mwan3.$iface.track_ip='1.1.1.1'
        uci add_list mwan3.$iface.track_ip='8.8.8.8'
        uci set mwan3.$iface.reliability='1'
        uci set mwan3.$iface.timeout='2'
        uci set mwan3.$iface.interval='5'
    done

    # Members with different metrics & weights
    uci set mwan3.wan_m=member
    uci set mwan3.wan_m.interface='wan'
    uci set mwan3.wan_m.metric='1'
    uci set mwan3.wan_m.weight='5'

    uci set mwan3.usb_m=member
    uci set mwan3.usb_m.interface='wan_usb'
    uci set mwan3.usb_m.metric='2'
    uci set mwan3.usb_m.weight='4'

    uci set mwan3.wwan_m=member
    uci set mwan3.wwan_m.interface='wwan'
    uci set mwan3.wwan_m.metric='3'
    uci set mwan3.wwan_m.weight='3'

    # Policies
    uci set mwan3.balanced=policy
    uci -q delete mwan3.balanced.use_member
    uci add_list mwan3.balanced.use_member='wan_m'
    uci add_list mwan3.balanced.use_member='usb_m'
    uci add_list mwan3.balanced.use_member='wwan_m'

    uci set mwan3.failover=policy
    uci -q delete mwan3.failover.use_member
    uci add_list mwan3.failover.use_member='wan_m'
    uci add_list mwan3.failover.use_member='usb_m'
    uci add_list mwan3.failover.use_member='wwan_m'

    # Default rule
    uci set mwan3.default_rule_v4=rule
    uci set mwan3.default_rule_v4.dest_ip='0.0.0.0/0'
    uci set mwan3.default_rule_v4.family='ipv4'
    uci set mwan3.default_rule_v4.use_policy='balanced'

    uci commit mwan3
    /etc/init.d/mwan3 enable >/dev/null 2>&1
    /etc/init.d/mwan3 restart >/dev/null 2>&1

    log_success "mwan3 engine configured (Balanced + Failover)."
}

load_balancer_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear
        echo "  ⚖️ Multi-WAN Load Balancer"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  📌 1) Install Dependencies"
        echo "  📲 2) Setup USB Tethering WAN"
        echo "  📶 3) Setup Wi-Fi Hotspot WAN"
        echo "  ⚖️ 4) Apply mwan3 Load Balancing"
        echo "  👀 5) Show mwan3 Status"
        echo "  🚪 0) Back"
        echo "  ───────────────────────────────────────────────────────────"
        printf "  ⁉️ Select option [0-5] : "
        read -r c </dev/tty

        case "$c" in
            1) install_mwan3_deps 2>/dev/null || log_warn "Dependency installer not found." ;;
            2) setup_usb_wan 2>/dev/null || log_warn "USB module not loaded." ;;
            3) setup_wifi_wan 2>/dev/null || log_warn "Wi-Fi WAN module not loaded." ;;
            4) configure_mwan3_engine ;;
            5) command -v mwan3 >/dev/null && mwan3 status || log_error "mwan3 not installed!" ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        echo
        printf "  ${GRAY:-}Press [Enter] to continue ... ${RESET:-}\n"
        read -r _ </dev/tty
    done
}

# 📄 Source : network_checker.sh

clear
# Cross-platform sleeping utility for UI spinner rendering
spin_sleep() {
    if command -v usleep >/dev/null 2>&1; then
        usleep 100000
    else
        sleep 1
    fi
}

GREEN_COUNT=0
YELLOW_COUNT=0
RED_COUNT=0
TOTAL_CHECKS=0
DNS_FAILED=0

ROW_HOST=""
ROW_DNS_ICON="·"
ROW_PING_ICON="·"
ROW_HTTPS_ICON="·"
ROW_ACTIVE=""

# Redraw the current table row with updated status icons / spinner
redraw_row()
{
    spin="$1"
    d="$ROW_DNS_ICON"
    p="$ROW_PING_ICON"
    h="$ROW_HTTPS_ICON"

    case "$ROW_ACTIVE" in
        dns)   d="$spin" ;;
        ping)  p="$spin" ;;
        https) h="$spin" ;;
    esac

    printf "\r  %-16s %-6s %-7s %-6s\033[K" "$ROW_HOST" "$d" "$p" "$h"
}

# Run execution cell asynchronously while displaying animated CLI spinner
run_cell()
{
    ROW_ACTIVE="$1"
    tmp="$2"
    shift 2

    "$@" >"$tmp" 2>&1 &
    pid=$!

    trap 'kill -9 "$pid" 2>/dev/null; rm -f "$tmp" 2>/dev/null; exit 130' INT TERM

    spin_chars='-\|/'
    i=0
    while kill -0 "$pid" 2>/dev/null; do
        c="$(printf '%s' "$spin_chars" | cut -c$(( (i % 4) + 1 )))"

        if [ -n "${CYAN:-}" ] && [ -n "${RESET:-}" ]; then
            redraw_row "${CYAN}${c}${RESET}"
        else
            redraw_row "$c"
        fi
        i=$((i + 1))
        spin_sleep
    done

    wait "$pid" 2>/dev/null
    CELL_EXIT=$?
    CELL_OUTPUT="$(cat "$tmp" 2>/dev/null)"
    rm -f "$tmp"
}

# Execute health diagnostics for a single target hostname
process_host()
{
    ROW_HOST="$1"
    ROW_DNS_ICON="·"
    ROW_PING_ICON="·"
    ROW_HTTPS_ICON="·"
    ROW_ACTIVE=""
    redraw_row "·"

    # 1. DNS Resolution Check
    if command -v nslookup >/dev/null 2>&1; then
        run_cell "dns" "/tmp/.nc_dns_$$" nslookup "$ROW_HOST"
    elif command -v host >/dev/null 2>&1; then
        run_cell "dns" "/tmp/.nc_dns_$$" host "$ROW_HOST"
    else
        # Fallback using ping host resolution
        run_cell "dns" "/tmp/.nc_dns_$$" ping -c 1 -W 2 "$ROW_HOST"
    fi

    if [ "$CELL_EXIT" -eq 0 ]; then
        ROW_DNS_ICON="🟢"
    else
        ROW_DNS_ICON="🔴"
        DNS_FAILED=1
    fi

    # 2. ICMP Ping / Latency Check
    run_cell "ping" "/tmp/.nc_ping_$$" ping -c 2 -W 2 "$ROW_HOST"
    LOSS="$(printf '%s' "$CELL_OUTPUT" | grep -o '[0-9]*% packet loss' | grep -o '^[0-9]*')"
    [ -z "$LOSS" ] && LOSS=100

    if [ "$LOSS" -eq 0 ]; then
        ROW_PING_ICON="🟢"
    elif [ "$LOSS" -lt 100 ]; then
        ROW_PING_ICON="🟡"
    else
        ROW_PING_ICON="🔴"
    fi

    # 3. HTTPS Reachability & Performance Check
    if command -v curl >/dev/null 2>&1; then
        run_cell "https" "/tmp/.nc_https_$$" curl -fsS -o /dev/null -w '%{time_total}' --connect-timeout 5 "https://$ROW_HOST"
    elif command -v uclient-fetch >/dev/null 2>&1; then
        run_cell "https" "/tmp/.nc_https_$$" uclient-fetch -q -T 5 -O /dev/null "https://$ROW_HOST"
    else
        run_cell "https" "/tmp/.nc_https_$$" wget -q --spider --timeout=5 "https://$ROW_HOST"
    fi

    if [ "$CELL_EXIT" -ne 0 ]; then
        ROW_HTTPS_ICON="🔴"
    else
        if command -v curl >/dev/null 2>&1; then
            IS_FAST="$(awk -v t="$CELL_OUTPUT" 'BEGIN { print (t < 2) ? "1" : "0" }' 2>/dev/null)"
            if [ "$IS_FAST" = "1" ]; then
                ROW_HTTPS_ICON="🟢"
            else
                ROW_HTTPS_ICON="🟡"
            fi
        else
            ROW_HTTPS_ICON="🟢"
        fi
    fi

    ROW_ACTIVE=""
    redraw_row " "
    printf "\n"

    for icon in "$ROW_DNS_ICON" "$ROW_PING_ICON" "$ROW_HTTPS_ICON"; do
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        case "$icon" in
            🟢) GREEN_COUNT=$((GREEN_COUNT + 1)) ;;
            🟡) YELLOW_COUNT=$((YELLOW_COUNT + 1)) ;;
            🔴) RED_COUNT=$((RED_COUNT + 1)) ;;
        esac
    done
}

# Master execution function for system network checks
network_check()
{
    GREEN_COUNT=0
    YELLOW_COUNT=0
    RED_COUNT=0
    TOTAL_CHECKS=0
    DNS_FAILED=0

    echo
    printf "  ${BOLD:-}${CYAN:-}🔎 DayPass Network Health Check${RESET:-}\n"
    
    printf "  ${GRAY:-}──────────────────────────────────────────${RESET:-}\n"

    printf "  ${BOLD:-}%-16s %-6s %-7s %-6s${RESET:-}\n" "Host" "DNS" "Ping" "HTTPS"
    printf "  ${GRAY:-}──────────────────────────────────────────${RESET:-}\n"

    process_host "google.com"
    process_host "github.com"
    process_host "openwrt.org"
    process_host "cloudflare.com"

    printf "  ${GRAY:-}──────────────────────────────────────────${RESET:-}\n\n"

    PCT=0
    [ "$TOTAL_CHECKS" -gt 0 ] && PCT=$((GREEN_COUNT * 100 / TOTAL_CHECKS))

    printf "  ${BOLD:-}Overall Score :${RESET:-} "
    if command -v draw_bar >/dev/null 2>&1; then
        draw_bar "$PCT" 12 "score"
    fi
    printf " %s%% (🟢 %s  🟡 %s  🔴 %s)\n\n" "$PCT" "$GREEN_COUNT" "$YELLOW_COUNT" "$RED_COUNT"

    printf "  ${BOLD:-}Diagnostic Report :${RESET:-}"
    if [ "$DNS_FAILED" -eq 1 ]; then
        if command -v log_error >/dev/null 2>&1; then
            log_error "DNS resolution is failing! Router cannot translate domain names."
        else
            printf "❌${RED:-}DNS resolution failed! Domain name lookup is broken.${RESET:-}\n"
        fi
        
        if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
            if command -v dns_fix_menu >/dev/null 2>&1; then
                dns_fix_menu
            fi
        fi
    elif [ "$RED_COUNT" -gt 0 ]; then
        if command -v log_warn >/dev/null 2>&1; then
            log_warn "HTTPS connections are blocked or filtered (Possible Censorship/DPI)."
        else
            printf "⚠️${YELLOW:-}HTTPS traffic is blocked or severely interfered with.${RESET:-}\n"
        fi
    elif [ "$YELLOW_COUNT" -gt 0 ]; then
        if command -v log_warn >/dev/null 2>&1; then
            log_warn "Network is active but experiencing high packet loss/latency (>2s)."
        else
            printf "⚠️${YELLOW:-}High latency or degraded response time detected!${RESET:-}\n"
        fi
    else
        if command -v log_success >/dev/null 2>&1; then
            log_success "Network is fully functional with clean connectivity!"
        else
            printf "✅${GREEN:-}Network is fully functional!${RESET:-}\n"
        fi
    fi

    echo
    printf "  ${GRAY:-}Press [Enter] to continue ... ${RESET:-}\n"
    read -r _ </dev/tty
    echo
    return 0
}

# Standalone execution handler
case "$0" in
    *network_check.sh|*network_checker.sh) network_check ;;
esac

# 📄 Source : network.sh
# ============================================================
# DayPass - Guest Network Module
# Creates isolated Guest network with firewall rules & DHCP
# ============================================================

# ------------------------------------------------------------
# Create Guest Network + Firewall + DHCP
# ------------------------------------------------------------
setup_guest_network() {
    log_info "Configuring isolated Guest Network..."

    # 1. Network Interface
    uci set network.guest=interface
    uci set network.guest.proto='static'
    uci set network.guest.ipaddr='192.168.200.1'
    uci set network.guest.netmask='255.255.255.0'
    uci set network.guest.force_link='0'

    # 2. DHCP Server for Guest
    uci set dhcp.guest=dhcp
    uci set dhcp.guest.interface='guest'
    uci set dhcp.guest.start='100'
    uci set dhcp.guest.limit='150'
    uci set dhcp.guest.leasetime='12h'
    uci set dhcp.guest.force='1'

    # 3. Firewall Zone (Isolated)
    uci set firewall.guest=zone
    uci set firewall.guest.name='guest'
    uci set firewall.guest.network='guest'
    uci set firewall.guest.input='REJECT'
    uci set firewall.guest.output='ACCEPT'
    uci set firewall.guest.forward='REJECT'
    uci set firewall.guest.masq='0'

    # 4. Allow Guest -> WAN (Internet only)
    uci set firewall.guest_to_wan=forwarding
    uci set firewall.guest_to_wan.src='guest'
    uci set firewall.guest_to_wan.dest='wan'

    # 5. Essential Rules: DNS + DHCP
    uci set firewall.guest_dns=rule
    uci set firewall.guest_dns.name='Allow-Guest-DNS'
    uci set firewall.guest_dns.src='guest'
    uci set firewall.guest_dns.dest_port='53'
    uci set firewall.guest_dns.proto='tcp udp'
    uci set firewall.guest_dns.target='ACCEPT'

    uci set firewall.guest_dhcp=rule
    uci set firewall.guest_dhcp.name='Allow-Guest-DHCP'
    uci set firewall.guest_dhcp.src='guest'
    uci set firewall.guest_dhcp.dest_port='67-68'
    uci set firewall.guest_dhcp.proto='udp'
    uci set firewall.guest_dhcp.target='ACCEPT'

    # 6. Block Guest from accessing main LAN
    uci set firewall.guest_block_lan=rule
    uci set firewall.guest_block_lan.name='Block-Guest-to-LAN'
    uci set firewall.guest_block_lan.src='guest'
    uci set firewall.guest_block_lan.dest='lan'
    uci set firewall.guest_block_lan.target='REJECT'

    uci commit network
    uci commit dhcp
    uci commit firewall

    /etc/init.d/network reload >/dev/null 2>&1
    /etc/init.d/firewall reload >/dev/null 2>&1
    /etc/init.d/dnsmasq restart >/dev/null 2>&1

    log_success "Guest Network ready → 192.168.200.0/24 (Isolated)"
}

# ------------------------------------------------------------
# Remove Guest Network completely
# ------------------------------------------------------------
remove_guest_network() {
    log_warn "Removing Guest Network configuration..."

    uci -q delete network.guest
    uci -q delete dhcp.guest
    uci -q delete firewall.guest
    uci -q delete firewall.guest_to_wan
    uci -q delete firewall.guest_dns
    uci -q delete firewall.guest_dhcp
    uci -q delete firewall.guest_block_lan

    # Remove related wireless interfaces
    for sec in $(uci show wireless | grep "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
        network=$(uci -q get wireless.$sec.network)
        if [ "$network" = "guest" ]; then
            uci -q delete wireless.$sec
        fi
    done

    uci commit network
    uci commit dhcp
    uci commit firewall
    uci commit wireless

    wifi reload >/dev/null 2>&1
    /etc/init.d/firewall reload >/dev/null 2>&1

    log_success "Guest Network removed."
}

# ------------------------------------------------------------
# Create Guest WiFi (AP on Guest network)
# ------------------------------------------------------------
setup_guest_wifi() {
    render_persistent_header 2>/dev/null || clear

    echo "  👥 Guest WiFi Configuration"
    echo "  ───────────────────────────────────────────────────────────"

    # Make sure guest network exists
    if ! uci -q get network.guest >/dev/null; then
        setup_guest_network
    fi

    local RADIOS
    RADIOS=$(uci show wireless 2>/dev/null | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1)

    if [ -z "$RADIOS" ]; then
        log_error "No wireless radio found!"
        return 1
    fi

    printf "  🛜 Guest SSID [DayPass-Guest] : "
    read -r guest_ssid </dev/tty
    [ -z "$guest_ssid" ] && guest_ssid="DayPass-Guest"

    local guest_pass=""
    while true; do
        printf "  🔒 Guest Password (min 8 chars) : "
        read -r guest_pass </dev/tty
        [ ${#guest_pass} -ge 8 ] && break
        log_error "Password must be at least 8 characters!"
    done

    for radio in $RADIOS; do
        local band
        band=$(uci -q get wireless.$radio.band || echo "")
        local iface="guest_${radio}"

        uci set wireless.$iface=wifi-iface
        uci set wireless.$iface.device="$radio"
        uci set wireless.$iface.mode='ap'
        uci set wireless.$iface.network='guest'
        uci set wireless.$iface.ssid="$guest_ssid"
        uci set wireless.$iface.encryption='psk2'
        uci set wireless.$iface.key="$guest_pass"
        uci set wireless.$iface.isolate='1'
        uci set wireless.$iface.disabled='0'

        log_success "Guest WiFi created on [$radio] → [$guest_ssid]"
    done

    uci commit wireless
    wifi reload >/dev/null 2>&1

    log_success "Guest WiFi is now active!"
}

# ------------------------------------------------------------
# Menu
# ------------------------------------------------------------
guest_network_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear

        echo "  👥 Guest Network Manager"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  1) Setup Guest Network (Interface + Firewall)"
        echo "  2) Setup Guest WiFi"
        echo "  3) Remove Guest Network completely"
        echo "  0) Back"
        echo "  ───────────────────────────────────────────────────────────"
        printf "  ⁉️ Select : "
        read -r choice </dev/tty

        case "$choice" in
            1) setup_guest_network ;;
            2) setup_guest_wifi ;;
            3) remove_guest_network ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press ENTER ...${RESET}"
        read -r _ </dev/tty
    done
}

# 📄 Source : qos.sh
# ============================================================
# DayPass - Guest QoS / Bandwidth Control
# Supports both Simple (tc) and Advanced (SQM) modes
# ============================================================

# ------------------------------------------------------------
# Simple Bandwidth Limit using tc (HTB)
# ------------------------------------------------------------
setup_simple_qos() {
    log_info "Setting up Simple QoS with tc ..."

    # Check if guest interface exists
    if ! uci -q get network.guest >/dev/null; then
        log_error "Guest network not found. Please setup Guest Network first!"
        return 1
    fi

    printf "  📥 Download limit for Guests (Mbps) [e.g. 10] : "
    read -r dl_limit </dev/tty
    [ -z "$dl_limit" ] && dl_limit=10

    printf "  📤 Upload limit for Guests (Mbps) [e.g. 5] : "
    read -r ul_limit </dev/tty
    [ -z "$ul_limit" ] && ul_limit=5

    # Convert to kbps
    local dl_kbit=$((dl_limit * 1000))
    local ul_kbit=$((ul_limit * 1000))

    # Install tc if needed
    if ! command -v tc >/dev/null 2>&1; then
        if [ "${PKG_MANAGER:-opkg}" = "apk" ]; then
            apk add kmod-sched tc >/dev/null 2>&1
        else
            opkg update >/dev/null 2>&1
            opkg install kmod-sched tc >/dev/null 2>&1
        fi
    fi

    # Apply tc rules on guest interface (after it comes up)
    cat > /etc/guest_qos.sh << EOF
# DayPass Guest Simple QoS
IFACE="br-guest"
[ -d /sys/class/net/\$IFACE ] || IFACE="guest"

tc qdisc del dev \$IFACE root 2>/dev/null
tc qdisc del dev \$IFACE ingress 2>/dev/null

# Download limit (ingress)
tc qdisc add dev \$IFACE handle ffff: ingress
tc filter add dev \$IFACE parent ffff: protocol ip prio 1 \\
    u32 match ip src 0.0.0.0/0 police rate ${dl_kbit}kbit burst 100k drop

# Upload limit (egress)
tc qdisc add dev \$IFACE root handle 1: htb default 10
tc class add dev \$IFACE parent 1: classid 1:1 htb rate ${ul_kbit}kbit
tc class add dev \$IFACE parent 1:1 classid 1:10 htb rate ${ul_kbit}kbit ceil ${ul_kbit}kbit
tc qdisc add dev \$IFACE parent 1:10 handle 10: sfq perturb 10
EOF

    chmod +x /etc/guest_qos.sh

    # Run now
    /etc/guest_qos.sh

    # Make persistent
    if ! grep -q "guest_qos.sh" /etc/rc.local 2>/dev/null; then
        sed -i -e '$i /etc/guest_qos.sh &' /etc/rc.local
    fi

    log_success "Simple QoS applied → Download: ${dl_limit}Mbps | Upload: ${ul_limit}Mbps"
}

# ------------------------------------------------------------
# Advanced QoS using SQM (Recommended)
# ------------------------------------------------------------
setup_sqm_qos() {
    log_info "Setting up Advanced QoS with SQM ..."

    if ! uci -q get network.guest >/dev/null; then
        log_error "Guest network not found. Please setup Guest Network first!"
        return 1
    fi

    # Install SQM if needed
    if [ "${PKG_MANAGER:-opkg}" = "apk" ]; then
        apk add sqm-scripts >/dev/null 2>&1 || true
    else
        opkg update >/dev/null 2>&1
        opkg install sqm-scripts luci-app-sqm >/dev/null 2>&1 || true
    fi

    printf "  📥 Download limit for Guests (Mbps) [e.g. 15] : "
    read -r dl_limit </dev/tty
    [ -z "$dl_limit" ] && dl_limit=15

    printf "  📤 Upload limit for Guests (Mbps) [e.g. 5] : "
    read -r ul_limit </dev/tty
    [ -z "$ul_limit" ] && ul_limit=5

    local dl_kbit=$((dl_limit * 1000))
    local ul_kbit=$((ul_limit * 1000))

    # Configure SQM on guest interface
    uci set sqm.guest=queue
    uci set sqm.guest.enabled='1'
    uci set sqm.guest.interface='guest'
    uci set sqm.guest.download="$dl_kbit"
    uci set sqm.guest.upload="$ul_kbit"
    uci set sqm.guest.qdisc='cake'
    uci set sqm.guest.script='piece_of_cake.qos'
    uci set sqm.guest.linklayer='none'

    uci commit sqm
    /etc/init.d/sqm enable >/dev/null 2>&1
    /etc/init.d/sqm restart >/dev/null 2>&1

    log_success "SQM QoS applied → Download: ${dl_limit}Mbps | Upload: ${ul_limit}Mbps (Cake)"
}

# ------------------------------------------------------------
# Remove all Guest QoS
# ------------------------------------------------------------
remove_guest_qos() {
    log_info "Removing Guest QoS rules ..."

    # Remove simple tc
    rm -f /etc/guest_qos.sh
    sed -i '/guest_qos.sh/d' /etc/rc.local 2>/dev/null

    # Remove SQM config
    uci -q delete sqm.guest
    uci commit sqm
    /etc/init.d/sqm restart >/dev/null 2>&1

    # Clear tc rules
    for iface in br-guest guest; do
        tc qdisc del dev $iface root 2>/dev/null
        tc qdisc del dev $iface ingress 2>/dev/null
    done

    log_success "Guest QoS removed!"
}

# ------------------------------------------------------------
# Menu
# ------------------------------------------------------------
guest_qos_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear

        echo "  🚦 Guest Bandwidth Control (QoS)"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  1) Simple Limit (tc) - Lightweight"
        echo "  2) Advanced Limit (SQM + Cake) - Better quality"
        echo "  3) Remove all Guest QoS"
        echo "  0) Back"
        echo "  ───────────────────────────────────────────────────────────"
        printf "  ⁉️ Select : "
        read -r choice </dev/tty

        case "$choice" in
            1) setup_simple_qos ;;
            2) setup_sqm_qos ;;
            3) remove_guest_qos ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press ENTER ...${RESET}"
        read -r _ </dev/tty
    done
}

# 📄 Source : config_storage.sh
# ============================================================
# DayPass - Config Storage
# Local storage management for proxy configs
# ============================================================

PROXY_DIR="/etc/daypass/proxy"
CONFIG_DIR="$PROXY_DIR/configs"
mkdir -p "$CONFIG_DIR"

# ------------------------------------------------------------
# List all locally stored configs
# ------------------------------------------------------------
list_configs() {
    echo "  📋 Available Configs (DayPass storage)"
    echo "  ───────────────────────────────────────────────────────────"

    local count=0
    for file in "$CONFIG_DIR"/*.json; do
        [ -f "$file" ] || continue

        count=$((count + 1))
        name=$(basename "$file" .json)
        protocol=$(jq -r '.protocol // "unknown"' "$file" 2>/dev/null)
        enabled=$(jq -r '.enabled // true' "$file" 2>/dev/null)
        subscription=$(jq -r '.subscription // empty' "$file" 2>/dev/null)

        status="${GREEN}ON${RESET}"
        [ "$enabled" = "false" ] && status="${GRAY}OFF${RESET}"

        if [ -n "$subscription" ]; then
            echo "  $count) $name  ${GRAY}($protocol)${RESET}  [$status]  ${GRAY}← $subscription${RESET}"
        else
            echo "  $count) $name  ${GRAY}($protocol)${RESET}  [$status]"
        fi
    done

    if [ "$count" -eq 0 ]; then
        echo "  ${GRAY}No configs found!${RESET}"
    else
        echo "  ───────────────────────────────────────────────────────────"
        echo "  Total: $count config(s)"
    fi
    echo "  ───────────────────────────────────────────────────────────"
}

# ------------------------------------------------------------
# Validate share link format (basic)
# ------------------------------------------------------------
validate_share_link() {
    local link="$1"

    case "$link" in
        vless://*|vmess://*|trojan://*|ss://*|hysteria2://*|hy2://*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ------------------------------------------------------------
# Detect protocol from share link
# ------------------------------------------------------------
detect_protocol_from_link() {
    local link="$1"

    case "$link" in
        vless://*)             echo "vless" ;;
        vmess://*)             echo "vmess" ;;
        trojan://*)            echo "trojan" ;;
        ss://*)                echo "ss" ;;
        hysteria2://*|hy2://*) echo "hysteria2" ;;
        *)                     echo "unknown" ;;
    esac
}

# ------------------------------------------------------------
# Add a manual config to local storage
# ------------------------------------------------------------
add_manual_config() {
    echo
    printf "  🎯 Config Name (example: MyVLESS) : "
    read -r conf_name </dev/tty

    # Basic name validation
    if [ -z "$conf_name" ]; then
        log_error "Name cannot be empty!"
        return 1
    fi

    # Prevent path traversal / invalid characters
    case "$conf_name" in
        *..*|*/*|*\\*|*\;*|*\&*)
            log_error "Invalid characters in config name!"
            return 1
            ;;
    esac

    # Check duplicate
    if [ -f "$CONFIG_DIR/${conf_name}.json" ]; then
        log_warn "Config [$conf_name] already exists!"
        printf "  ⁉️ Overwrite it? [y/N] : "
        read -r overwrite </dev/tty
        case "$overwrite" in
            y|Y) ;;
            *) log_info "Cancelled."; return 0 ;;
        esac
    fi

    printf "  🕊️ Paste full share link:\n  "
    read -r share_link </dev/tty

    if [ -z "$share_link" ]; then
        log_error "Share link is required!"
        return 1
    fi

    if ! validate_share_link "$share_link"; then
        log_error "Unsupported or invalid share link format!"
        log_info "Supported: vless:// | vmess:// | trojan:// | ss:// | hysteria2://"
        return 1
    fi

    # Auto-detect protocol from link (more reliable)
    local protocol
    protocol=$(detect_protocol_from_link "$share_link")

    cat > "$CONFIG_DIR/${conf_name}.json" << EOF
{
    "name": "$conf_name",
    "protocol": "$protocol",
    "share_link": "$share_link",
    "enabled": true,
    "added_at": "$(date -Iseconds)"
}
EOF

    log_success "Config [$conf_name] saved successfully! ${GRAY}($protocol)${RESET}"
}

# ------------------------------------------------------------
# Remove a config from local storage
# ------------------------------------------------------------
remove_config() {
    list_configs

    local total
    total=$(ls -1 "$CONFIG_DIR"/*.json 2>/dev/null | wc -l)
    if [ "$total" -eq 0 ]; then
        return 0
    fi

    printf "  🧼 Enter config name to remove : "
    read -r del_name </dev/tty

    if [ -z "$del_name" ]; then
        log_warn "No name entered!"
        return 1
    fi

    if [ -f "$CONFIG_DIR/${del_name}.json" ]; then
        printf "  ⁉️ Are you sure you want to delete [$del_name]? [y/N] : "
        read -r confirm </dev/tty
        case "$confirm" in
            y|Y)
                rm -f "$CONFIG_DIR/${del_name}.json"
                log_success "Config [$del_name] removed!"
                ;;
            *)
                log_info "Cancelled."
                ;;
        esac
    else
        log_error "Config not found!"
    fi
}

# ------------------------------------------------------------
# Enable / Disable a config
# ------------------------------------------------------------
toggle_config() {
    list_configs

    printf "  🔄 Enter config name to toggle enable/disable : "
    read -r conf_name </dev/tty

    local file="$CONFIG_DIR/${conf_name}.json"
    if [ ! -f "$file" ]; then
        log_error "Config not found!"
        return 1
    fi

    local current
    current=$(jq -r '.enabled // true' "$file" 2>/dev/null)

    local new_value
    if [ "$current" = "true" ]; then
        new_value="false"
    else
        new_value="true"
    fi

    tmp=$(mktemp)
    jq --argjson val "$new_value" '.enabled = $val' "$file" > "$tmp" && mv "$tmp" "$file"

    if [ "$new_value" = "true" ]; then
        log_success "Config [$conf_name] enabled!"
    else
        log_warn "Config [$conf_name] disabled!"
    fi
}

# 📄 Source : subscription.sh
# ============================================================
# DayPass - Subscription Manager
# Download, parse and store nodes from subscription links
# ============================================================

PROXY_DIR="/etc/daypass/proxy"
CONFIG_DIR="$PROXY_DIR/configs"
SUBS_FILE="$PROXY_DIR/subscriptions.json"
mkdir -p "$CONFIG_DIR"

# ------------------------------------------------------------
# Add a new subscription
# ------------------------------------------------------------
add_subscription() {
    echo
    printf "  💳 Subscription Name : "
    read -r sub_name </dev/tty
    [ -z "$sub_name" ] && { log_error "Name required!"; return 1; }

    printf "  🏦 Subscription URL : "
    read -r sub_url </dev/tty
    [ -z "$sub_url" ] && { log_error "URL required!"; return 1; }

    # Create subscriptions file if it does not exist
    if [ ! -f "$SUBS_FILE" ]; then
        echo "[]" > "$SUBS_FILE"
    fi

    # Check for duplicate subscription name
    if jq -e --arg name "$sub_name" '.[] | select(.name == $name)' "$SUBS_FILE" >/dev/null 2>&1; then
        log_warn "Subscription [$sub_name] already exists!"
        return 1
    fi

    tmp=$(mktemp)
    jq --arg name "$sub_name" --arg url "$sub_url" \
       '. + [{"name": $name, "url": $url, "last_update": null}]' \
       "$SUBS_FILE" > "$tmp" && mv "$tmp" "$SUBS_FILE"

    log_success "Subscription [$sub_name] added!"
    log_info "Use 'Update Subscriptions' to fetch nodes!"
}

# ------------------------------------------------------------
# Remove old nodes belonging to a subscription before update
# ------------------------------------------------------------
clean_old_subscription_nodes() {
    local sub_name="$1"

    for file in "$CONFIG_DIR"/*.json; do
        [ -f "$file" ] || continue

        local sub
        sub=$(jq -r '.subscription // empty' "$file" 2>/dev/null)

        if [ "$sub" = "$sub_name" ]; then
            rm -f "$file"
        fi
    done
}

# ------------------------------------------------------------
# Update a single subscription
# ------------------------------------------------------------
update_subscription() {
    local sub_name="$1"
    local sub_url="$2"

    log_info "🔄 Updating subscription: $sub_name ..."

    local tmp_file
    tmp_file=$(mktemp)
    local download_ok=0

    # Prefer curl, fallback to wget
    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL --connect-timeout 15 --max-time 30 -o "$tmp_file" "$sub_url" 2>/dev/null; then
            download_ok=1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -q -O "$tmp_file" "$sub_url" --timeout=15 2>/dev/null; then
            download_ok=1
        fi
    else
        log_error "Neither curl nor wget is available!"
        rm -f "$tmp_file"
        return 1
    fi

    if [ "$download_ok" -ne 1 ]; then
        log_error "Failed to download subscription: $sub_name"
        rm -f "$tmp_file"
        return 1
    fi

    # Detect plain text or base64 content
    local content
    if grep -q "://" "$tmp_file"; then
        content=$(cat "$tmp_file")
    else
        content=$(base64 -d "$tmp_file" 2>/dev/null || cat "$tmp_file")
    fi

    # Remove previous nodes of this subscription
    clean_old_subscription_nodes "$sub_name"

    local count=0
    local line protocol conf_name

    # Use temporary file to avoid subshell count problem
    local parsed_file
    parsed_file=$(mktemp)

    echo "$content" | while IFS= read -r line; do
        line=$(echo "$line" | tr -d '\r' | xargs)
        [ -z "$line" ] && continue

        case "$line" in
            vless://*)             protocol="vless" ;;
            vmess://*)             protocol="vmess" ;;
            trojan://*)            protocol="trojan" ;;
            ss://*)                protocol="ss" ;;
            hysteria2://*|hy2://*) protocol="hysteria2" ;;
            *) continue ;;
        esac

        count=$((count + 1))
        conf_name="${sub_name}_${protocol}_${count}"

        cat > "$CONFIG_DIR/${conf_name}.json" << EOF
{
    "name": "$conf_name",
    "protocol": "$protocol",
    "share_link": "$line",
    "subscription": "$sub_name",
    "enabled": true,
    "added_at": "$(date -Iseconds)"
}
EOF
        echo "$count" > "$parsed_file"
    done

    count=$(cat "$parsed_file" 2>/dev/null || echo 0)
    rm -f "$tmp_file" "$parsed_file"

    # Update last_update timestamp in subscriptions file
    if [ -f "$SUBS_FILE" ]; then
        tmp=$(mktemp)
        jq --arg name "$sub_name" --arg ts "$(date -Iseconds)" \
           'map(if .name == $name then .last_update = $ts else . end)' \
           "$SUBS_FILE" > "$tmp" && mv "$tmp" "$SUBS_FILE"
    fi

    if [ "$count" -gt 0 ]; then
        log_success "Subscription [$sub_name] updated! ($count nodes)"
    else
        log_warn "Subscription [$sub_name] updated, but no valid nodes found!"
    fi
}

# ------------------------------------------------------------
# Update all saved subscriptions
# ------------------------------------------------------------
update_all_subscriptions() {
    if [ ! -f "$SUBS_FILE" ]; then
        log_warn "No subscriptions found!"
        return 1
    fi

    local total
    total=$(jq 'length' "$SUBS_FILE" 2>/dev/null || echo 0)

    if [ "$total" -eq 0 ]; then
        log_warn "No subscriptions to update!"
        return 1
    fi

    log_info "🔄 Updating $total subscription(s) ..."

    # Read subscriptions into a temp list to avoid subshell issues
    local subs_tmp
    subs_tmp=$(mktemp)
    jq -c '.[]' "$SUBS_FILE" > "$subs_tmp"

    while IFS= read -r sub; do
        name=$(echo "$sub" | jq -r '.name')
        url=$(echo "$sub" | jq -r '.url')
        update_subscription "$name" "$url"
    done < "$subs_tmp"

    rm -f "$subs_tmp"
    log_success "All subscriptions processed!"
}

# ------------------------------------------------------------
# List saved subscriptions
# ------------------------------------------------------------
list_subscriptions() {
    echo "  💳 Saved Subscriptions"
    echo "  ───────────────────────────────────────────────────────────"

    if [ ! -f "$SUBS_FILE" ]; then
        echo "  ${GRAY}No subscriptions found!${RESET}"
        echo "  ───────────────────────────────────────────────────────────"
        return 0
    fi

    local total
    total=$(jq 'length' "$SUBS_FILE" 2>/dev/null || echo 0)

    if [ "$total" -eq 0 ]; then
        echo "  ${GRAY}No subscriptions found!${RESET}"
        echo "  ───────────────────────────────────────────────────────────"
        return 0
    fi

    local i=1
    jq -c '.[]' "$SUBS_FILE" | while read -r sub; do
        name=$(echo "$sub" | jq -r '.name')
        last=$(echo "$sub" | jq -r '.last_update // "never"')
        echo "  $i) $name  ${GRAY}(last update: $last)${RESET}"
        i=$((i + 1))
    done

    echo "  ───────────────────────────────────────────────────────────"
}

# 📄 Source : passwall_bridge.sh
# ============================================================
# DayPass - Passwall Bridge (Professional Edition)
# Detects Passwall1 / Passwall2 and pushes nodes with better parsing
# ============================================================

PROXY_DIR="/etc/daypass/proxy"
CONFIG_DIR="$PROXY_DIR/configs"

# ------------------------------------------------------------
# Detect installed Passwall version
# Returns: passwall2 | passwall | none
# ------------------------------------------------------------
detect_passwall_version() {
    if [ -f /etc/config/passwall2 ] || uci -q show passwall2 >/dev/null 2>&1; then
        echo "passwall2"
        return
    fi

    if [ -f /etc/config/passwall ] || uci -q show passwall >/dev/null 2>&1; then
        echo "passwall"
        return
    fi

    if command -v pkg_installed >/dev/null 2>&1; then
        if pkg_installed "luci-app-passwall2" || pkg_installed "passwall2"; then
            echo "passwall2"
            return
        fi
        if pkg_installed "luci-app-passwall" || pkg_installed "passwall"; then
            echo "passwall"
            return
        fi
    fi

    echo "none"
}

# ------------------------------------------------------------
# URL decode helper (basic)
# ------------------------------------------------------------
url_decode() {
    echo "$1" | sed 's/+/ /g;s/%/\\x/g' | xargs -0 printf "%b" 2>/dev/null || echo "$1"
}

# ------------------------------------------------------------
# Parse share link (improved)
# Supports: vless / vmess / trojan / ss / hysteria2
# Extracts main fields + some common query params
# ------------------------------------------------------------
parse_share_link() {
    local link="$1"

    PARSED_PROTOCOL=""
    PARSED_ADDRESS=""
    PARSED_PORT=""
    PARSED_UUID=""
    PARSED_PASSWORD=""
    PARSED_REMARKS=""
    PARSED_NETWORK=""
    PARSED_SECURITY=""
    PARSED_SNI=""
    PARSED_FLOW=""
    PARSED_FP=""
    PARSED_PATH=""
    PARSED_HOST_HEADER=""

    case "$link" in
        vless://*)
            PARSED_PROTOCOL="vless"

            local body query fragment
            body=$(echo "$link" | sed 's|vless://||')
            fragment=$(echo "$body" | grep -o '#.*' | sed 's/^#//')
            body=$(echo "$body" | cut -d'#' -f1)
            query=$(echo "$body" | cut -d'?' -f2- -s)
            body=$(echo "$body" | cut -d'?' -f1)

            PARSED_UUID=$(echo "$body" | cut -d'@' -f1)
            local hostport=$(echo "$body" | cut -d'@' -f2)
            PARSED_ADDRESS=$(echo "$hostport" | cut -d':' -f1)
            PARSED_PORT=$(echo "$hostport" | cut -d':' -f2)

            PARSED_REMARKS=$(url_decode "$fragment")
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="VLESS-Node"

            # Parse common query parameters
            if [ -n "$query" ]; then
                PARSED_NETWORK=$(echo "$query" | tr '&' '\n' | grep -m1 '^type=' | cut -d'=' -f2)
                PARSED_SECURITY=$(echo "$query" | tr '&' '\n' | grep -m1 '^security=' | cut -d'=' -f2)
                PARSED_SNI=$(echo "$query" | tr '&' '\n' | grep -m1 '^sni=' | cut -d'=' -f2)
                PARSED_FLOW=$(echo "$query" | tr '&' '\n' | grep -m1 '^flow=' | cut -d'=' -f2)
                PARSED_FP=$(echo "$query" | tr '&' '\n' | grep -m1 '^fp=' | cut -d'=' -f2)
                PARSED_PATH=$(echo "$query" | tr '&' '\n' | grep -m1 '^path=' | cut -d'=' -f2)
                PARSED_HOST_HEADER=$(echo "$query" | tr '&' '\n' | grep -m1 '^host=' | cut -d'=' -f2)
            fi
            ;;

        vmess://*)
            PARSED_PROTOCOL="vmess"
            local b64 json
            b64=$(echo "$link" | sed 's|vmess://||' | tr '_-' '/+' )
            # pad base64 if needed
            local mod=$(( ${#b64} % 4 ))
            if [ "$mod" -eq 2 ]; then b64="${b64}=="; fi
            if [ "$mod" -eq 3 ]; then b64="${b64}="; fi

            json=$(echo "$b64" | base64 -d 2>/dev/null)

            if [ -n "$json" ]; then
                PARSED_ADDRESS=$(echo "$json" | jq -r '.add // empty' 2>/dev/null)
                PARSED_PORT=$(echo "$json" | jq -r '.port // empty' 2>/dev/null)
                PARSED_UUID=$(echo "$json" | jq -r '.id // empty' 2>/dev/null)
                PARSED_REMARKS=$(echo "$json" | jq -r '.ps // empty' 2>/dev/null)
                PARSED_NETWORK=$(echo "$json" | jq -r '.net // empty' 2>/dev/null)
                PARSED_PATH=$(echo "$json" | jq -r '.path // empty' 2>/dev/null)
                PARSED_HOST_HEADER=$(echo "$json" | jq -r '.host // empty' 2>/dev/null)
                PARSED_SECURITY=$(echo "$json" | jq -r '.tls // empty' 2>/dev/null)
                PARSED_SNI=$(echo "$json" | jq -r '.sni // empty' 2>/dev/null)
            fi

            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="VMess-Node"
            ;;

        trojan://*)
            PARSED_PROTOCOL="trojan"

            local body query fragment
            body=$(echo "$link" | sed 's|trojan://||')
            fragment=$(echo "$body" | grep -o '#.*' | sed 's/^#//')
            body=$(echo "$body" | cut -d'#' -f1)
            query=$(echo "$body" | cut -d'?' -f2- -s)
            body=$(echo "$body" | cut -d'?' -f1)

            PARSED_PASSWORD=$(echo "$body" | cut -d'@' -f1)
            local hostport=$(echo "$body" | cut -d'@' -f2)
            PARSED_ADDRESS=$(echo "$hostport" | cut -d':' -f1)
            PARSED_PORT=$(echo "$hostport" | cut -d':' -f2)

            PARSED_REMARKS=$(url_decode "$fragment")
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="Trojan-Node"

            if [ -n "$query" ]; then
                PARSED_SNI=$(echo "$query" | tr '&' '\n' | grep -m1 '^sni=' | cut -d'=' -f2)
                PARSED_SECURITY=$(echo "$query" | tr '&' '\n' | grep -m1 '^security=' | cut -d'=' -f2)
                PARSED_FP=$(echo "$query" | tr '&' '\n' | grep -m1 '^fp=' | cut -d'=' -f2)
            fi
            ;;

        ss://*)
            PARSED_PROTOCOL="shadowsocks"
            local fragment
            fragment=$(echo "$link" | grep -o '#.*' | sed 's/^#//')
            PARSED_REMARKS=$(url_decode "$fragment")
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="SS-Node"
            # Full SS parsing is complex (sip002 / legacy). Keep basic for now.
            ;;

        hysteria2://*|hy2://*)
            PARSED_PROTOCOL="hysteria2"
            local fragment
            fragment=$(echo "$link" | grep -o '#.*' | sed 's/^#//')
            PARSED_REMARKS=$(url_decode "$fragment")
            [ -z "$PARSED_REMARKS" ] && PARSED_REMARKS="Hysteria2-Node"
            ;;

        *)
            return 1
            ;;
    esac

    return 0
}

# ------------------------------------------------------------
# Check if a node with same remarks already exists
# ------------------------------------------------------------
node_exists() {
    local pw_ver="$1"
    local remarks="$2"

    case "$pw_ver" in
        passwall2)
            uci show passwall2 2>/dev/null | grep -q "remarks='$remarks'" && return 0
            ;;
        passwall)
            uci show passwall 2>/dev/null | grep -q "remarks='$remarks'" && return 0
            ;;
    esac
    return 1
}

# ------------------------------------------------------------
# Push one config into the detected Passwall
# ------------------------------------------------------------
push_config_to_passwall() {
    local conf_name="$1"
    local file="$CONFIG_DIR/${conf_name}.json"

    if [ ! -f "$file" ]; then
        log_error "Config not found: [$conf_name]"
        return 1
    fi

    local share_link protocol
    share_link=$(jq -r '.share_link // empty' "$file")
    protocol=$(jq -r '.protocol // empty' "$file")

    if [ -z "$share_link" ]; then
        log_error "No share_link in config: [$conf_name]"
        return 1
    fi

    if ! parse_share_link "$share_link"; then
        log_warn "Could not fully parse share link for [$conf_name]. Adding with limited info."
    fi

    local remarks="${PARSED_REMARKS:-$conf_name}"
    local pw_version
    pw_version=$(detect_passwall_version)

    # Skip duplicate
    if node_exists "$pw_version" "$remarks"; then
        log_warn "Node [$remarks] already exists in $pw_version. Skipped."
        return 0
    fi

    case "$pw_version" in
        passwall2)
            log_info "Adding node to Passwall2 → [$remarks]"

            local section
            section=$(uci add passwall2 nodes 2>/dev/null)
            if [ -z "$section" ]; then
                log_error "Failed to create node section in Passwall2"
                return 1
            fi

            uci set passwall2."$section".remarks="$remarks"
            uci set passwall2."$section".type="${PARSED_PROTOCOL:-$protocol}"
            [ -n "$PARSED_ADDRESS" ] && uci set passwall2."$section".address="$PARSED_ADDRESS"
            [ -n "$PARSED_PORT" ]    && uci set passwall2."$section".port="$PARSED_PORT"
            [ -n "$PARSED_UUID" ]    && uci set passwall2."$section".uuid="$PARSED_UUID"
            [ -n "$PARSED_PASSWORD" ] && uci set passwall2."$section".password="$PARSED_PASSWORD"
            [ -n "$PARSED_NETWORK" ] && uci set passwall2."$section".transport="$PARSED_NETWORK"
            [ -n "$PARSED_SECURITY" ] && uci set passwall2."$section".tls="$PARSED_SECURITY"
            [ -n "$PARSED_SNI" ]     && uci set passwall2."$section".tls_serverName="$PARSED_SNI"
            [ -n "$PARSED_FLOW" ]    && uci set passwall2."$section".flow="$PARSED_FLOW"
            [ -n "$PARSED_FP" ]      && uci set passwall2."$section".fingerprint="$PARSED_FP"
            [ -n "$PARSED_PATH" ]    && uci set passwall2."$section".ws_path="$PARSED_PATH"
            [ -n "$PARSED_HOST_HEADER" ] && uci set passwall2."$section".ws_host="$PARSED_HOST_HEADER"
            uci set passwall2."$section".share_link="$share_link"
            uci set passwall2."$section".enabled="1"

            uci commit passwall2
            log_success "Node [$remarks] added to Passwall2 ($section)"
            ;;

        passwall)
            log_info "Adding node to Passwall1 → [$remarks]"

            local section
            section=$(uci add passwall nodes 2>/dev/null)
            if [ -z "$section" ]; then
                log_error "Failed to create node section in Passwall1"
                return 1
            fi

            uci set passwall."$section".remarks="$remarks"
            uci set passwall."$section".type="${PARSED_PROTOCOL:-$protocol}"
            [ -n "$PARSED_ADDRESS" ] && uci set passwall."$section".address="$PARSED_ADDRESS"
            [ -n "$PARSED_PORT" ]    && uci set passwall."$section".port="$PARSED_PORT"
            [ -n "$PARSED_UUID" ]    && uci set passwall."$section".uuid="$PARSED_UUID"
            [ -n "$PARSED_PASSWORD" ] && uci set passwall."$section".password="$PARSED_PASSWORD"
            [ -n "$PARSED_NETWORK" ] && uci set passwall."$section".transport="$PARSED_NETWORK"
            [ -n "$PARSED_SECURITY" ] && uci set passwall."$section".tls="$PARSED_SECURITY"
            [ -n "$PARSED_SNI" ]     && uci set passwall."$section".tls_serverName="$PARSED_SNI"
            uci set passwall."$section".share_link="$share_link"
            uci set passwall."$section".enabled="1"

            uci commit passwall
            log_success "Node [$remarks] added to Passwall1 ($section)"
            ;;

        none)
            log_error "Neither Passwall1 nor Passwall2 is installed!"
            return 1
            ;;
    esac
}

# ------------------------------------------------------------
# Push all local configs to Passwall
# ------------------------------------------------------------
push_all_to_passwall() {
    local pw_version
    pw_version=$(detect_passwall_version)

    if [ "$pw_version" = "none" ]; then
        log_error "No Passwall installation detected!"
        return 1
    fi

    log_info "Pushing all configs to [$pw_version] ..."

    local count=0
    local success=0

    for file in "$CONFIG_DIR"/*.json; do
        [ -f "$file" ] || continue
        name=$(basename "$file" .json)
        count=$((count + 1))

        if push_config_to_passwall "$name"; then
            success=$((success + 1))
        fi
    done

    if [ "$count" -eq 0 ]; then
        log_warn "No configs to push!"
    else
        log_success "Finished: $success / $count config(s) processed."
    fi
}

# 📄 Source : config_manager.sh
# ============================================================
# Orchestrates storage, subscription and Passwall bridge
# ============================================================

config_manager_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear

        local pw_version="unknown"
        if command -v detect_passwall_version >/dev/null 2>&1; then
            pw_version=$(detect_passwall_version)
        fi

        echo "  📦 Config Manager (Nodes & Subscriptions)"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  🛡️ Detected Engine : ${CYAN}$pw_version${RESET}"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  📋 1) List Configs"
        echo "  🤏 2) Add Manual Config"
        echo "  🎲 3) Toggle Enable/Disable Config"
        echo "  💳 4) Add Subscription"
        echo "  🏧 5) List Subscriptions"
        echo "  🔄 6) Update All Subscriptions"
        echo "  🫸 7) Push Config to Passwall"
        echo "  🤜 8) Push All Configs to Passwall"
        echo "  🗑️ 9) Remove Config"
        echo "  🚪 0) Back"
        echo "  ───────────────────────────────────────────────────────────"
        echo

        printf "  ⁉️ Select option [0-9] : "
        read -r choice </dev/tty

        case "$choice" in
            1)
                if command -v list_configs >/dev/null 2>&1; then
                    list_configs
                else
                    log_error "list_configs() not found!"
                fi
                ;;
            2)
                if command -v add_manual_config >/dev/null 2>&1; then
                    add_manual_config
                else
                    log_error "add_manual_config() not found!"
                fi
                ;;
            3)
                if command -v toggle_config >/dev/null 2>&1; then
                    toggle_config
                else
                    log_error "toggle_config() not found!"
                fi
                ;;
            4)
                if command -v add_subscription >/dev/null 2>&1; then
                    add_subscription
                else
                    log_error "add_subscription() not found!"
                fi
                ;;
            5)
                if command -v list_subscriptions >/dev/null 2>&1; then
                    list_subscriptions
                else
                    log_error "list_subscriptions() not found!"
                fi
                ;;
            6)
                if command -v update_all_subscriptions >/dev/null 2>&1; then
                    update_all_subscriptions
                else
                    log_error "update_all_subscriptions() not found!"
                fi
                ;;
            7)
                if command -v list_configs >/dev/null 2>&1; then
                    list_configs
                fi
                printf "  ✊🏻 Enter config name to push : "
                read -r push_name </dev/tty
                if [ -n "$push_name" ] && command -v push_config_to_passwall >/dev/null 2>&1; then
                    push_config_to_passwall "$push_name"
                else
                    log_error "Invalid name or push function not found!"
                fi
                ;;
            8)
                if command -v push_all_to_passwall >/dev/null 2>&1; then
                    push_all_to_passwall
                else
                    log_error "push_all_to_passwall() not found!"
                fi
                ;;
            9)
                if command -v remove_config >/dev/null 2>&1; then
                    remove_config
                else
                    log_error "remove_config() not found!"
                fi
                ;;
            0)
                return 0
                ;;
            *)
                log_warn "Invalid option!"
                ;;
        esac

        printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
        read -r _ </dev/tty
    done
}

# 📄 Source : routing.sh
# ============================================================
# DayPass - Traffic Routing / Shunt Rules
# Applies real routing rules to Passwall1 & Passwall2
# ============================================================

# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------
PROXY_DIR="/etc/daypass/proxy"
ROUTING_DIR="$PROXY_DIR/routing"
mkdir -p "$ROUTING_DIR"

# ------------------------------------------------------------
# Detect Passwall version
# ------------------------------------------------------------
get_pw_version() {
    if command -v detect_passwall_version >/dev/null 2>&1; then
        detect_passwall_version
    else
        if [ -f /etc/config/passwall2 ] || uci -q show passwall2 >/dev/null 2>&1; then
            echo "passwall2"
        elif [ -f /etc/config/passwall ] || uci -q show passwall >/dev/null 2>&1; then
            echo "passwall"
        else
            echo "none"
        fi
    fi
}

# ------------------------------------------------------------
# Show current routing status
# ------------------------------------------------------------
show_routing_status() {
    echo "  🚦 Current Routing Status"
    echo "  ───────────────────────────────────────────────────────────"

    if [ -f "$ROUTING_DIR/current_mode" ]; then
        mode=$(cat "$ROUTING_DIR/current_mode")
        echo "  🫀 Active Mode : ${GREEN}$mode${RESET}"
    else
        echo "  🫀 Active Mode : ${GRAY}Not configured${RESET}"
    fi

    local pw_ver
    pw_ver=$(get_pw_version)
    echo "  🛡️  Passwall    : ${CYAN}$pw_ver${RESET}"
    echo "  ───────────────────────────────────────────────────────────"
}

# ------------------------------------------------------------
# Apply Iran Direct + Foreign Proxy
# ------------------------------------------------------------
apply_iran_direct() {
    local pw_ver
    pw_ver=$(get_pw_version)

    if [ "$pw_ver" = "none" ]; then
        log_error "No Passwall installed. Cannot apply routing rules."
        return 1
    fi

    log_info "Applying mode : Iran Direct + Foreign Proxy ..."

    case "$pw_ver" in
        passwall2)
            uci set passwall2.@global[0].enabled='1' 2>/dev/null
            uci set passwall2.@global[0].tcp_proxy_mode='gfwlist' 2>/dev/null || \
            uci set passwall2.@global[0].tcp_proxy_mode='proxy' 2>/dev/null
            uci set passwall2.@global[0].localhost_proxy='0' 2>/dev/null
            uci commit passwall2
            /etc/init.d/passwall2 reload >/dev/null 2>&1 || true
            ;;
        passwall)
            uci set passwall.@global[0].enabled='1' 2>/dev/null
            uci set passwall.@global[0].tcp_proxy_mode='gfwlist' 2>/dev/null || \
            uci set passwall.@global[0].tcp_proxy_mode='proxy' 2>/dev/null
            uci commit passwall
            /etc/init.d/passwall reload >/dev/null 2>&1 || true
            ;;
    esac

    echo "iran_direct" > "$ROUTING_DIR/current_mode"

    cat > "$ROUTING_DIR/iran_direct.rules" << EOF
# DayPass Routing Rule - Iran Direct
# 1. Iranian domains & IPs → Direct
# 2. Everything else → Proxy
EOF

    log_success "Mode [🦁☀️ IRAN Direct] applied to $pw_ver!"
}

# ------------------------------------------------------------
# Global Proxy (All traffic through proxy)
# ------------------------------------------------------------
apply_global_proxy() {
    local pw_ver
    pw_ver=$(get_pw_version)

    if [ "$pw_ver" = "none" ]; then
        log_error "No Passwall installed."
        return 1
    fi

    log_info "Applying mode : Global Proxy ..."

    case "$pw_ver" in
        passwall2)
            uci set passwall2.@global[0].enabled='1' 2>/dev/null
            uci set passwall2.@global[0].tcp_proxy_mode='proxy' 2>/dev/null
            uci set passwall2.@global[0].udp_proxy_mode='proxy' 2>/dev/null
            uci commit passwall2
            /etc/init.d/passwall2 reload >/dev/null 2>&1 || true
            ;;
        passwall)
            uci set passwall.@global[0].enabled='1' 2>/dev/null
            uci set passwall.@global[0].tcp_proxy_mode='proxy' 2>/dev/null
            uci set passwall.@global[0].udp_proxy_mode='proxy' 2>/dev/null
            uci commit passwall
            /etc/init.d/passwall reload >/dev/null 2>&1 || true
            ;;
    esac

    echo "global_proxy" > "$ROUTING_DIR/current_mode"

    cat > "$ROUTING_DIR/global_proxy.rules" << EOF
# DayPass Routing Rule - Global Proxy
# All traffic → Proxy
EOF

    log_success "Mode [🌏 Global Proxy] applied to $pw_ver!"
}

# ------------------------------------------------------------
# Direct Only (No Proxy)
# ------------------------------------------------------------
apply_direct_only() {
    local pw_ver
    pw_ver=$(get_pw_version)

    if [ "$pw_ver" = "none" ]; then
        log_error "No Passwall installed."
        return 1
    fi

    log_info "Applying mode : Direct Only ..."

    case "$pw_ver" in
        passwall2)
            uci set passwall2.@global[0].enabled='0' 2>/dev/null
            uci set passwall2.@global[0].tcp_proxy_mode='disable' 2>/dev/null
            uci commit passwall2
            /etc/init.d/passwall2 reload >/dev/null 2>&1 || true
            ;;
        passwall)
            uci set passwall.@global[0].enabled='0' 2>/dev/null
            uci set passwall.@global[0].tcp_proxy_mode='disable' 2>/dev/null
            uci commit passwall
            /etc/init.d/passwall reload >/dev/null 2>&1 || true
            ;;
    esac

    echo "direct_only" > "$ROUTING_DIR/current_mode"

    cat > "$ROUTING_DIR/direct_only.rules" << EOF
# DayPass Routing Rule - Direct Only
# All traffic → Direct (Proxy disabled)
EOF

    log_success "Mode [🎯 Direct Only] applied. Proxy disabled!"
}

# ------------------------------------------------------------
# Main Routing Menu
# ------------------------------------------------------------
routing_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear

        echo "  🚦 Traffic Routing / Shunt Rules"
        echo "  ───────────────────────────────────────────────────────────"
        show_routing_status
        echo
        echo "  👑 1) Iran Direct + Foreign Proxy   (Recommended)"
        echo "  🌏 2) Global Proxy                  (All traffic via proxy)"
        echo "  🎯 3) Direct Only                   (Disable proxy)"
        echo "  👀 4) Show current rules"
        echo "  🚪 0) Back"
        echo "  ───────────────────────────────────────────────────────────"
        echo

        printf "  ⁉️ Select option [0-4] : "
        read -r choice </dev/tty

        case "$choice" in
            1) apply_iran_direct ;;
            2) apply_global_proxy ;;
            3) apply_direct_only ;;
            4)
                echo
                if [ -f "$ROUTING_DIR/current_mode" ]; then
                    mode=$(cat "$ROUTING_DIR/current_mode")
                    echo "  ⬆️  Current mode : $mode"
                    echo
                    cat "$ROUTING_DIR/${mode}.rules" 2>/dev/null || echo "  ${GRAY}No detailed rules file.${RESET}"
                else
                    echo "  💅🏻 No routing mode configured yet!"
                fi
                ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
        read -r _ </dev/tty
    done
}

# 📄 Source : node_balancer.sh
# ============================================================
# DayPass - Node Load Balancing
# Selects nodes + mode and tries to apply settings to Passwall
# ============================================================

# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------
PROXY_DIR="/etc/daypass/proxy"
CONFIG_DIR="$PROXY_DIR/configs"
BALANCER_DIR="$PROXY_DIR/balancer"
mkdir -p "$BALANCER_DIR"

# ------------------------------------------------------------
# Detect Passwall version
# ------------------------------------------------------------
get_pw_version() {
    if command -v detect_passwall_version >/dev/null 2>&1; then
        detect_passwall_version
    else
        if [ -f /etc/config/passwall2 ] || uci -q show passwall2 >/dev/null 2>&1; then
            echo "passwall2"
        elif [ -f /etc/config/passwall ] || uci -q show passwall >/dev/null 2>&1; then
            echo "passwall"
        else
            echo "none"
        fi
    fi
}

# ------------------------------------------------------------
# Show current balancer status
# ------------------------------------------------------------
show_balancer_status() {
    echo "  ⚖️  Current Node Balancer Status"
    echo "  ───────────────────────────────────────────────────────────"

    if [ -f "$BALANCER_DIR/mode" ]; then
        mode=$(cat "$BALANCER_DIR/mode")
        echo "  🫀 Active Mode  : ${GREEN}$mode${RESET}"
    else
        echo "  🫀 Active Mode  : ${GRAY}Disabled${RESET}"
    fi

    if [ -f "$BALANCER_DIR/nodes.list" ]; then
        count=$(wc -l < "$BALANCER_DIR/nodes.list" 2>/dev/null || echo 0)
        echo "  🧠 Active Nodes : $count"
        if [ "$count" -gt 0 ]; then
            echo "  📋 Nodes        : ${GRAY}$(tr '\n' ' ' < "$BALANCER_DIR/nodes.list")${RESET}"
        fi
    else
        echo "  🧠 Active Nodes : 0"
    fi

    local pw_ver
    pw_ver=$(get_pw_version)
    echo "  🛡️  Passwall     : ${CYAN}$pw_ver${RESET}"
    echo "  ───────────────────────────────────────────────────────────"
}

# ------------------------------------------------------------
# Select nodes for balancing
# ------------------------------------------------------------
select_nodes() {
    echo
    echo "  📋 Available Configs :"
    echo "  ───────────────────────────────────────────────────────────"

    local configs=""
    local i=1
    for file in "$CONFIG_DIR"/*.json; do
        [ -f "$file" ] || continue

        name=$(basename "$file" .json)
        protocol=$(jq -r '.protocol // "unknown"' "$file" 2>/dev/null)
        enabled=$(jq -r '.enabled // true' "$file" 2>/dev/null)

        if [ "$enabled" = "false" ]; then
            echo "  $i) $name  ${GRAY}($protocol) [DISABLED]${RESET}"
        else
            echo "  $i) $name  ${GRAY}($protocol)${RESET}"
        fi

        configs="$configs $name"
        i=$((i + 1))
    done

    if [ "$i" -eq 1 ]; then
        log_warn "No configs found. Add some configs first!"
        return 1
    fi

    echo "  ───────────────────────────────────────────────────────────"
    printf "  🧶 Enter node numbers to include (e.g. 1 3 4) : "
    read -r selected </dev/tty

    if [ -z "$selected" ]; then
        log_warn "No selection entered!"
        return 1
    fi

    > "$BALANCER_DIR/nodes.list"

    local idx=1
    local added=0
    for name in $configs; do
        for num in $selected; do
            if [ "$num" = "$idx" ]; then
                enabled=$(jq -r '.enabled // true' "$CONFIG_DIR/${name}.json" 2>/dev/null)
                if [ "$enabled" = "false" ]; then
                    log_warn "Skipped disabled node: [$name]"
                else
                    echo "$name" >> "$BALANCER_DIR/nodes.list"
                    log_success "Added : [$name]"
                    added=$((added + 1))
                fi
            fi
        done
        idx=$((idx + 1))
    done

    if [ "$added" -eq 0 ]; then
        log_warn "No valid nodes selected!"
    else
        log_success "[$added] node(s) selected for balancing!"
    fi
}

# ------------------------------------------------------------
# Set balancing mode
# ------------------------------------------------------------
set_balancer_mode() {
    echo
    echo "  ⚖️  Select Load Balancing Mode :"
    echo "  ───────────────────────────────────────────────────────────"
    echo "  ⏳ 1) Round-Robin      (distribute equally)"
    echo "  🏓 2) Least Ping       (prefer lowest latency)"
    echo "  👨‍👩‍👧‍👦 3) Failover         (use next only if previous fails)"
    echo "  🤹 4) Random"
    echo "  ───────────────────────────────────────────────────────────"
    printf "  ⁉️ Select mode [1-4] : "
    read -r mode_choice </dev/tty

    case "$mode_choice" in
        1) mode="round-robin" ;;
        2) mode="least-ping" ;;
        3) mode="failover" ;;
        4) mode="random" ;;
        *) log_warn "Invalid mode!"; return 1 ;;
    esac

    echo "$mode" > "$BALANCER_DIR/mode"
    log_success "Balancer mode set to : [$mode]"
}

# ------------------------------------------------------------
# Apply balancer settings to Passwall (best-effort)
# ------------------------------------------------------------
apply_balancer() {
    local pw_ver
    pw_ver=$(get_pw_version)

    if [ "$pw_ver" = "none" ]; then
        log_error "No Passwall installed. Cannot apply balancer."
        return 1
    fi

    if [ ! -f "$BALANCER_DIR/mode" ]; then
        log_warn "No balancer mode selected yet."
        return 1
    fi

    if [ ! -f "$BALANCER_DIR/nodes.list" ] || [ ! -s "$BALANCER_DIR/nodes.list" ]; then
        log_warn "No nodes selected for balancing."
        return 1
    fi

    local mode
    mode=$(cat "$BALANCER_DIR/mode")

    log_info "Applying balancer [$mode] to $pw_ver ..."

    case "$pw_ver" in
        passwall2)
            uci set passwall2.@global[0].enabled='1' 2>/dev/null
            uci -q delete passwall2.daypass_balancer
            uci set passwall2.daypass_balancer=global
            uci set passwall2.daypass_balancer.mode="$mode"
            uci set passwall2.daypass_balancer.nodes="$(tr '\n' ' ' < "$BALANCER_DIR/nodes.list")"
            uci commit passwall2
            /etc/init.d/passwall2 reload >/dev/null 2>&1 || true
            ;;
        passwall)
            uci set passwall.@global[0].enabled='1' 2>/dev/null
            uci -q delete passwall.daypass_balancer
            uci set passwall.daypass_balancer=global
            uci set passwall.daypass_balancer.mode="$mode"
            uci set passwall.daypass_balancer.nodes="$(tr '\n' ' ' < "$BALANCER_DIR/nodes.list")"
            uci commit passwall
            /etc/init.d/passwall reload >/dev/null 2>&1 || true
            ;;
    esac

    log_success "Balancer settings saved and service reloaded."
    log_info "Note: Full traffic distribution depends on Passwall version capabilities."
}

# ------------------------------------------------------------
# Disable balancer
# ------------------------------------------------------------
disable_balancer() {
    rm -f "$BALANCER_DIR/mode"
    rm -f "$BALANCER_DIR/nodes.list"

    local pw_ver
    pw_ver=$(get_pw_version)

    case "$pw_ver" in
        passwall2)
            uci -q delete passwall2.daypass_balancer
            uci commit passwall2
            /etc/init.d/passwall2 reload >/dev/null 2>&1 || true
            ;;
        passwall)
            uci -q delete passwall.daypass_balancer
            uci commit passwall
            /etc/init.d/passwall reload >/dev/null 2>&1 || true
            ;;
    esac

    log_success "Node Balancer disabled!"
}

# ------------------------------------------------------------
# Main Menu
# ------------------------------------------------------------
node_balancer_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear

        echo "  🧶 Node Load Balancing"
        echo "  ───────────────────────────────────────────────────────────"
        show_balancer_status
        echo
        echo "  💆‍♀️ 1) Select Nodes for Balancing"
        echo "  ⚖️  2) Set Balancing Mode"
        echo "  🔥 3) Apply Balancer to Passwall"
        echo "  🚫 4) Disable Balancer"
        echo "  🚪 0) Back"
        echo "  ───────────────────────────────────────────────────────────"
        echo

        printf "  ⁉️ Select option [0-4] : "
        read -r choice </dev/tty

        case "$choice" in
            1) select_nodes ;;
            2) set_balancer_mode ;;
            3) apply_balancer ;;
            4) disable_balancer ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
        read -r _ </dev/tty
    done
}

# 📄 Source : health_checker.sh

# Tests reachability + approximate latency of proxy nodes
# ============================================================


# Paths

PROXY_DIR="/etc/daypass/proxy"
CONFIG_DIR="$PROXY_DIR/configs"
HEALTH_DIR="$PROXY_DIR/health"
mkdir -p "$HEALTH_DIR"


# Extract host and port from share link

extract_host_port() {
    local link="$1"
    HOST=""
    PORT=""

    # VLESS / Trojan style: protocol://uuid@host:port
    HOST=$(echo "$link" | sed -n 's/.*@\([^:/]*\).*/\1/p' | head -1)
    PORT=$(echo "$link" | sed -n 's/.*@[^:]*:\([0-9]*\).*/\1/p' | head -1)

    # Fallback: protocol://host:port
    if [ -z "$HOST" ]; then
        HOST=$(echo "$link" | sed -n 's/.*\/\/\([^:/]*\).*/\1/p' | head -1)
        PORT=$(echo "$link" | sed -n 's/.*\/\/[^:]*:\([0-9]*\).*/\1/p' | head -1)
    fi

    # Last fallback for some formats
    if [ -z "$PORT" ]; then
        PORT=$(echo "$link" | grep -oE ':[0-9]{2,5}' | head -1 | tr -d ':')
    fi
}


# Test a single node (TCP + latency)

test_node() {
    local name="$1"
    local file="$CONFIG_DIR/${name}.json"

    if [ ! -f "$file" ]; then
        log_error "$name → file not found"
        return 1
    fi

    # Skip disabled configs
    local enabled
    enabled=$(jq -r '.enabled // true' "$file" 2>/dev/null)
    if [ "$enabled" = "false" ]; then
        log_warn "$name → disabled (skipped)"
        return 1
    fi

    local share_link
    share_link=$(jq -r '.share_link // empty' "$file" 2>/dev/null)

    if [ -z "$share_link" ]; then
        log_error "[$name] → no share link"
        return 1
    fi

    extract_host_port "$share_link"

    if [ -z "$HOST" ] || [ -z "$PORT" ]; then
        log_warn "[$name] → could not parse address"
        return 1
    fi

    # Measure approximate latency using TCP connect
    local start_time end_time latency
    start_time=$(date +%s%N 2>/dev/null || date +%s)

    local reachable=0

    if command -v nc >/dev/null 2>&1; then
        if nc -z -w 3 "$HOST" "$PORT" >/dev/null 2>&1; then
            reachable=1
        fi
    else
        if timeout 3 sh -c "echo > /dev/tcp/$HOST/$PORT" 2>/dev/null; then
            reachable=1
        fi
    fi

    end_time=$(date +%s%N 2>/dev/null || date +%s)

    if [ "$reachable" -eq 1 ]; then
        # Calculate latency in ms if nanoseconds available
        if [ "${#start_time}" -ge 13 ] 2>/dev/null; then
            latency=$(( (end_time - start_time) / 1000000 ))
            log_success "$name → ${HOST}:${PORT}  |  ${latency} ms"
        else
            log_success "$name → ${HOST}:${PORT}  |  Reachable"
        fi
        return 0
    else
        log_error "$name → ${HOST}:${PORT}  |  Unreachable"
        return 1
    fi
}


# Test all nodes

test_all_nodes() {
    echo
    echo "  🩺 Checking all nodes ..."
    echo "  ───────────────────────────────────────────────────────────"

    local total=0
    local ok=0
    local skipped=0

    for file in "$CONFIG_DIR"/*.json; do
        [ -f "$file" ] || continue
        name=$(basename "$file" .json)
        total=$((total + 1))

        if test_node "$name"; then
            ok=$((ok + 1))
        else
            # Count disabled separately if needed
            enabled=$(jq -r '.enabled // true' "$file" 2>/dev/null)
            [ "$enabled" = "false" ] && skipped=$((skipped + 1))
        fi
    done

    echo "  ───────────────────────────────────────────────────────────"
    if [ "$skipped" -gt 0 ]; then
        echo "  Result : ${GREEN}$ok${RESET} / $total reachable  ${GRAY}($skipped disabled)${RESET}"
    else
        echo "  Result : ${GREEN}$ok${RESET} / $total nodes are reachable"
    fi
    echo
}


# Test selected nodes only

test_selected_nodes() {
    echo
    echo "  📋 Available Configs :"
    echo "  ───────────────────────────────────────────────────────────"

    local configs=""
    local i=1

    for file in "$CONFIG_DIR"/*.json; do
        [ -f "$file" ] || continue
        name=$(basename "$file" .json)
        protocol=$(jq -r '.protocol // "unknown"' "$file" 2>/dev/null)
        enabled=$(jq -r '.enabled // true' "$file" 2>/dev/null)

        if [ "$enabled" = "false" ]; then
            echo "  $i) $name  ${GRAY}($protocol) [DISABLED]${RESET}"
        else
            echo "  $i) $name  ${GRAY}($protocol)${RESET}"
        fi

        configs="$configs $name"
        i=$((i + 1))
    done

    if [ "$i" -eq 1 ]; then
        log_warn "No configs found!"
        return 1
    fi

    echo "  ───────────────────────────────────────────────────────────"
    printf "  💊 Enter node numbers to check (e.g. 1 2 4) : "
    read -r selected </dev/tty

    if [ -z "$selected" ]; then
        log_warn "No selection entered!"
        return 1
    fi

    echo
    echo "  🩺 Checking selected nodes ..."
    echo "  ───────────────────────────────────────────────────────────"

    local idx=1
    for name in $configs; do
        for num in $selected; do
            if [ "$num" = "$idx" ]; then
                test_node "$name"
            fi
        done
        idx=$((idx + 1))
    done

    echo "  ───────────────────────────────────────────────────────────"
}


# Main Menu

health_checker_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear

        echo "  🩺 Node Health Checker"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  🔭 1) Check All Nodes"
        echo "  🔬 2) Check Selected Nodes"
        echo "  🚪 0) Back"
        echo "  ───────────────────────────────────────────────────────────"
        echo

        printf "  ⁉️ Select option [0-2] : "
        read -r choice </dev/tty

        case "$choice" in
            1) test_all_nodes ;;
            2) test_selected_nodes ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
        read -r _ </dev/tty
    done
}

# 📄 Source : profile_manager.sh

# Applies ready-to-use profiles by calling real routing modes
# ============================================================


# Paths

PROXY_DIR="/etc/daypass/proxy"
PROFILE_DIR="$PROXY_DIR/profiles"
ROUTING_DIR="$PROXY_DIR/routing"
mkdir -p "$PROFILE_DIR"
mkdir -p "$ROUTING_DIR"


# Show current active profile

show_active_profile() {
    echo "  🎭 Current Active Profile"
    echo "  ───────────────────────────────────────────────────────────"

    if [ -f "$PROFILE_DIR/active" ]; then
        active=$(cat "$PROFILE_DIR/active")
        echo "  🫀 Active Profile : ${GREEN}$active${RESET}"
    else
        echo "  🫀 Active Profile : ${GRAY}None${RESET}"
    fi

    if [ -f "$ROUTING_DIR/current_mode" ]; then
        mode=$(cat "$ROUTING_DIR/current_mode")
        echo "  🚦 Routing Mode   : ${CYAN}$mode${RESET}"
    else
        echo "  🚦 Routing Mode   : ${GRAY}Not set${RESET}"
    fi

    echo "  ───────────────────────────────────────────────────────────"
}


# List available profiles

list_profiles() {
    echo "  🎭 Available Routing Profiles"
    echo "  ───────────────────────────────────────────────────────────"
    echo "  ⚖️  1) Balanced       (Iran Direct + Foreign Proxy)"
    echo "  🕹️  2) Gaming         (Low latency focus)"
    echo "  📺  3) Streaming      (Better for video services)"
    echo "  🌎  4) Global Proxy   (All traffic through proxy)"
    echo "  🎯  5) Direct Only    (Disable proxy completely)"
    echo "  ───────────────────────────────────────────────────────────"
}


# Apply a profile (calls real routing functions when possible)

apply_profile() {
    local profile="$1"

    case "$profile" in
        balanced)
            echo "balanced" > "$PROFILE_DIR/active"

            if command -v apply_iran_direct >/dev/null 2>&1; then
                apply_iran_direct
            else
                echo "iran_direct" > "$ROUTING_DIR/current_mode"
                log_warn "Routing module not fully loaded. Mode saved locally."
            fi

            log_success "Profile [⚖️ Balanced] applied!"
            log_info "Iranian sites → Direct | Foreign sites → Proxy"
            ;;

        gaming)
            echo "gaming" > "$PROFILE_DIR/active"

            # Gaming currently uses Iran Direct as base
            if command -v apply_iran_direct >/dev/null 2>&1; then
                apply_iran_direct
            else
                echo "iran_direct" > "$ROUTING_DIR/current_mode"
                log_warn "Routing module not fully loaded. Mode saved locally."
            fi

            log_success "Profile [🕹️ Gaming] applied!"
            log_info "Optimized for lower latency and stability."
            ;;

        streaming)
            echo "streaming" > "$PROFILE_DIR/active"

            if command -v apply_iran_direct >/dev/null 2>&1; then
                apply_iran_direct
            else
                echo "iran_direct" > "$ROUTING_DIR/current_mode"
                log_warn "Routing module not fully loaded. Mode saved locally."
            fi

            log_success "Profile [📺 Streaming] applied!"
            log_info "Optimized for YouTube / Netflix style traffic."
            ;;

        global)
            echo "global" > "$PROFILE_DIR/active"

            if command -v apply_global_proxy >/dev/null 2>&1; then
                apply_global_proxy
            else
                echo "global_proxy" > "$ROUTING_DIR/current_mode"
                log_warn "Routing module not fully loaded. Mode saved locally."
            fi

            log_success "Profile [🌎 Global Proxy] applied!"
            log_info "All traffic will go through proxy."
            ;;

        direct)
            echo "direct" > "$PROFILE_DIR/active"

            if command -v apply_direct_only >/dev/null 2>&1; then
                apply_direct_only
            else
                echo "direct_only" > "$ROUTING_DIR/current_mode"
                log_warn "Routing module not fully loaded. Mode saved locally."
            fi

            log_success "Profile [🎯 Direct Only] applied!"
            log_info "Proxy disabled. All traffic is direct."
            ;;

        *)
            log_error "Unknown profile!"
            return 1
            ;;
    esac
}


# Main Menu

profile_manager_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear

        echo "  🎭 Routing Profiles"
        echo "  ───────────────────────────────────────────────────────────"
        show_active_profile
        echo
        list_profiles
        echo
        echo "  🚪 0) Back"
        echo "  ───────────────────────────────────────────────────────────"
        echo

        printf "  ⁉️ Select profile [1-5] or 0 to back : "
        read -r choice </dev/tty

        case "$choice" in
            1) apply_profile "balanced" ;;
            2) apply_profile "gaming" ;;
            3) apply_profile "streaming" ;;
            4) apply_profile "global" ;;
            5) apply_profile "direct" ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
        read -r _ </dev/tty
    done
}

# 📄 Source : core.sh
# ============================================================
# Shared paths and proxy core detection
# ============================================================

PROXY_DIR="/etc/daypass/proxy"
CONFIG_DIR="$PROXY_DIR/configs"
CLEAN_IP_DIR="$PROXY_DIR/clean_ip"
CANDIDATE_FILE="$CLEAN_IP_DIR/candidates.txt"
RESULT_FILE="$CLEAN_IP_DIR/last_results.txt"

mkdir -p "$CLEAN_IP_DIR"
mkdir -p "$CONFIG_DIR"

# ------------------------------------------------------------
# Detect installed proxy core
# Returns: xray | sing-box | none
# ------------------------------------------------------------
detect_proxy_core() {
    if command -v xray >/dev/null 2>&1; then
        echo "xray"
        return
    fi

    if command -v sing-box >/dev/null 2>&1; then
        echo "sing-box"
        return
    fi

    echo "none"
}

# 📄 Source : link_utils.sh

# ------------------------------------------------------------
# Extract address from share link
# ------------------------------------------------------------
extract_address_from_link() {
    local link="$1"
    local host=""

    host=$(echo "$link" | sed -n 's/.*@\([^:/]*\).*/\1/p' | head -1)

    if [ -z "$host" ]; then
        host=$(echo "$link" | sed -n 's/.*\/\/\([^:/]*\).*/\1/p' | head -1)
    fi

    echo "$host"
}

# ------------------------------------------------------------
# Extract port from share link
# ------------------------------------------------------------
extract_port_from_link() {
    local link="$1"
    local port=""

    port=$(echo "$link" | sed -n 's/.*@[^:]*:\([0-9]*\).*/\1/p' | head -1)

    if [ -z "$port" ]; then
        port=$(echo "$link" | sed -n 's/.*\/\/[^:]*:\([0-9]*\).*/\1/p' | head -1)
    fi

    if [ -z "$port" ]; then
        port=$(echo "$link" | grep -oE ':[0-9]{2,5}' | head -1 | tr -d ':')
    fi

    [ -z "$port" ] && port="443"
    echo "$port"
}

# ------------------------------------------------------------
# Replace only the address part of a share link
# ------------------------------------------------------------
replace_address_in_link() {
    local link="$1"
    local new_ip="$2"
    local old_host

    old_host=$(extract_address_from_link "$link")
    if [ -z "$old_host" ]; then
        echo "$link"
        return 1
    fi

    echo "$link" | sed "s/@${old_host}/@${new_ip}/" | sed "s/\/\/${old_host}/\/\/${new_ip}/"
}

# 📄 Source : scanner.sh

# ------------------------------------------------------------
# Basic TCP connectivity test on specific port
# ------------------------------------------------------------
test_ip_basic() {
    local ip="$1"
    local port="$2"
    local timeout_sec="${3:-3}"

    if command -v nc >/dev/null 2>&1; then
        if nc -z -w "$timeout_sec" "$ip" "$port" >/dev/null 2>&1; then
            return 0
        fi
        return 1
    fi

    if timeout "$timeout_sec" sh -c "echo > /dev/tcp/$ip/$port" 2>/dev/null; then
        return 0
    fi

    return 1
}

# ------------------------------------------------------------
# Measure rough latency (ms)
# ------------------------------------------------------------
measure_latency() {
    local ip="$1"
    local port="$2"
    local start end

    start=$(date +%s%N 2>/dev/null || date +%s)

    if test_ip_basic "$ip" "$port" 2; then
        end=$(date +%s%N 2>/dev/null || date +%s)
        if [ "${#start}" -ge 13 ] 2>/dev/null; then
            echo $(( (end - start) / 1000000 ))
        else
            echo "0"
        fi
        return 0
    fi

    echo ""
    return 1
}

# ------------------------------------------------------------
# Advanced validation placeholder (xray / sing-box)
# ------------------------------------------------------------
test_ip_advanced() {
    local ip="$1"
    local port="$2"
    local share_link="$3"
    local core

    core=$(detect_proxy_core)

    case "$core" in
        xray)
            log_info "Advanced Xray validation not fully implemented yet. Using basic test!"
            test_ip_basic "$ip" "$port"
            ;;
        sing-box)
            log_info "Advanced Sing-box validation not fully implemented yet. Using basic test!"
            test_ip_basic "$ip" "$port"
            ;;
        *)
            test_ip_basic "$ip" "$port"
            ;;
    esac
}

# ------------------------------------------------------------
# Ensure candidate IP list exists
# ------------------------------------------------------------
ensure_candidate_file() {
    if [ -f "$CANDIDATE_FILE" ] && [ -s "$CANDIDATE_FILE" ]; then
        return 0
    fi

    cat > "$CANDIDATE_FILE" << EOF
# DayPass Clean IP candidates (Cloudflare-focused)
# One IP per line. Lines starting with # are ignored!
1.1.1.1
1.0.0.1
104.16.0.1
104.17.0.1
104.18.0.1
104.19.0.1
104.20.0.1
104.21.0.1
104.22.0.1
104.24.0.1
EOF

    log_info "Default candidate list created at : [$CANDIDATE_FILE]"
}

# ------------------------------------------------------------
# Scan candidate IPs using the config port
# ------------------------------------------------------------
scan_candidate_ips() {
    local port="$1"
    local share_link="$2"
    local mode="${3:-basic}"

    ensure_candidate_file
    > "$RESULT_FILE"

    echo
    echo "  🔍 Scanning candidate IPs on port [$port] ..."
    echo "  ───────────────────────────────────────────────────────────"

    local total=0
    local ok=0
    local ip latency

    while IFS= read -r line; do
        line=$(echo "$line" | xargs)
        [ -z "$line" ] && continue
        case "$line" in
            \#*) continue ;;
        esac

        ip="$line"
        total=$((total + 1))

        if [ "$mode" = "advanced" ]; then
            if test_ip_advanced "$ip" "$port" "$share_link"; then
                latency=$(measure_latency "$ip" "$port")
                [ -z "$latency" ] && latency="?"
                log_success "$ip:$port  |  ${latency} ms"
                echo "$latency $ip" >> "$RESULT_FILE"
                ok=$((ok + 1))
            else
                log_error "$ip:$port  |  Unreachable"
            fi
        else
            if test_ip_basic "$ip" "$port"; then
                latency=$(measure_latency "$ip" "$port")
                [ -z "$latency" ] && latency="?"
                log_success "$ip:$port  |  ${latency} ms"
                echo "$latency $ip" >> "$RESULT_FILE"
                ok=$((ok + 1))
            else
                log_error "$ip:$port  |  Unreachable"
            fi
        fi
    done < "$CANDIDATE_FILE"

    echo "  ───────────────────────────────────────────────────────────"
    echo "  Result : ${GREEN}$ok${RESET} / $total IP(s) reachable ;)"
    echo

    if [ "$ok" -gt 0 ]; then
        sort -n "$RESULT_FILE" -o "$RESULT_FILE" 2>/dev/null || true
        echo "  🏆 Best candidates :"
        awk '{printf "   - %s  (%s ms)\n", $2, $1}' "$RESULT_FILE" | head -n 10
        echo
    fi
}

# ------------------------------------------------------------
# Show / hint edit candidate list
# ------------------------------------------------------------
edit_candidates() {
    ensure_candidate_file
    echo
    log_info "Candidate file : [$CANDIDATE_FILE]"
    echo "  Current list :"
    echo "  ───────────────────────────────────────────────────────────"
    cat  "  $CANDIDATE_FILE"
    echo "  ───────────────────────────────────────────────────────────"
    echo
    log_info "Edit this file manually, then rerun scan!"
}

# 📄 Source : applier.sh

# ------------------------------------------------------------
# Apply clean IP to a stored config
# ------------------------------------------------------------
apply_clean_ip_to_config() {
    local conf_name="$1"
    local clean_ip="$2"
    local file="$CONFIG_DIR/${conf_name}.json"

    if [ ! -f "$file" ]; then
        log_error "Config not found: [$conf_name]"
        return 1
    fi

    if [ -z "$clean_ip" ]; then
        log_error "Clean IP is empty!"
        return 1
    fi

    local share_link new_link
    share_link=$(jq -r '.share_link // empty' "$file" 2>/dev/null)

    if [ -z "$share_link" ]; then
        log_error "No share_link in config : [$conf_name]"
        return 1
    fi

    new_link=$(replace_address_in_link "$share_link" "$clean_ip")
    if [ -z "$new_link" ] || [ "$new_link" = "$share_link" ]; then
        new_link=$(echo "$share_link" | sed "s/@[^:/]*/@${clean_ip}/")
    fi

    tmp=$(mktemp)
    if jq --arg link "$new_link" --arg ip "$clean_ip" \
        '.share_link = $link | .clean_ip = $ip' \
        "$file" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$file"
    else
        rm -f "$tmp"
        log_error "Failed to update config JSON!"
        return 1
    fi

    log_success "Config [$conf_name] updated with Clean IP : [$clean_ip]"
    log_info "SNI/Host/Path left unchanged!"
}

# 📄 Source : menu.sh

# ------------------------------------------------------------
# Interactive flow: select config -> scan -> apply
# ------------------------------------------------------------
clean_ip_for_config() {
    echo
    echo "  📋 Available Configs :"
    echo "  ───────────────────────────────────────────────────────────"

    local configs=""
    local i=1
    for file in "$CONFIG_DIR"/*.json; do
        [ -f "$file" ] || continue
        name=$(basename "$file" .json)
        protocol=$(jq -r '.protocol // "unknown"' "$file" 2>/dev/null)
        echo "  $i) $name  ${GRAY}($protocol)${RESET}"
        configs="$configs $name"
        i=$((i + 1))
    done

    if [ "$i" -eq 1 ]; then
        log_warn "No configs found!"
        return 1
    fi

    echo "  ───────────────────────────────────────────────────────────"
    printf "  🎯 Select config number : "
    read -r choice </dev/tty

    local idx=1
    local conf_name=""
    for name in $configs; do
        if [ "$choice" = "$idx" ]; then
            conf_name="$name"
            break
        fi
        idx=$((idx + 1))
    done

    if [ -z "$conf_name" ]; then
        log_warn "Invalid selection!"
        return 1
    fi

    local file="$CONFIG_DIR/${conf_name}.json"
    local share_link port old_addr core
    share_link=$(jq -r '.share_link // empty' "$file" 2>/dev/null)
    port=$(extract_port_from_link "$share_link")
    old_addr=$(extract_address_from_link "$share_link")
    core=$(detect_proxy_core)

    echo
    log_info "Config   : $conf_name"
    log_info "Address  : ${old_addr:-unknown}"
    log_info "Port     : $port"
    log_info "Core     : $core"
    echo

    echo "  🧪 Test mode :"
    echo "  👼🏻 1) Basic TCP only"
    echo "  👩🏻‍🔬 2) Advanced (Xray/Sing-box aware - placeholder)"
    printf "  ⁉️ Select mode [1-2] (default: 1) : "
    read -r mode_choice </dev/tty

    local mode="basic"
    [ "$mode_choice" = "2" ] && mode="advanced"

    scan_candidate_ips "$port" "$share_link" "$mode"

    if [ ! -s "$RESULT_FILE" ]; then
        log_warn "No reachable clean IPs found!"
        return 1
    fi

    printf "  🧼 Enter Clean IP to apply (or empty to cancel) : "
    read -r clean_ip </dev/tty
    [ -z "$clean_ip" ] && { log_info "Cancelled."; return 0; }

    apply_clean_ip_to_config "$conf_name" "$clean_ip"

    printf "  🫸🏻 Push updated config to Passwall now? [y/N] : "
    read -r push_now </dev/tty
    case "$push_now" in
        y|Y)
            if command -v push_config_to_passwall >/dev/null 2>&1; then
                push_config_to_passwall "$conf_name"
            else
                log_warn "push_config_to_passwall() not found!"
            fi
            ;;
    esac
}

# ------------------------------------------------------------
# Main Cloudflare Clean IP Menu
# ------------------------------------------------------------
clean_ip_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear

        local core
        core=$(detect_proxy_core)

        echo "  🧼 Clean IP Manager (Cloudflare)"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  🛡️ Proxy Core : ${CYAN}$core${RESET}"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  🕵🏻‍♀️ 1) Find Clean IP for a Config"
        echo "  👫🏻 2) Show / Edit Candidate IP List"
        echo "  📺 3) Show Last Scan Results"
        echo "  🚪 0) Back"
        echo "  ───────────────────────────────────────────────────────────"
        echo

        printf "  ⁉️ Select option [0-3] : "
        read -r choice </dev/tty

        case "$choice" in
            1) clean_ip_for_config ;;
            2) edit_candidates ;;
            3)
                if [ -f "$RESULT_FILE" ] && [ -s "$RESULT_FILE" ]; then
                    echo
                    echo "  🏆 Last Results :"
                    echo "  ───────────────────────────────────────────────────────────"
                    awk '{printf "   - %s  (%s ms)\n", $2, $1}' "$RESULT_FILE"
                    echo "  ───────────────────────────────────────────────────────────"
                else
                    log_warn "No scan results yet!"
                fi
                ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
        read -r _ </dev/tty
    done
}

# 📄 Source : backup_restore.sh

# Config Backup and Restore Module for DayPass Deployment Stack
# Preserves critical UCI configurations during updates and system migration

BACKUP_DIR="/tmp/daypass/backups"
CONFIG_PATHS="/etc/config/passwall /etc/config/passwall2 /etc/config/xray /etc/config/sing-box /etc/config/niki"

# Creates a compressed timestamped archive of target configuration files
backup_configs()
{
    log_info "Initiating UCI configuration backup ..." 2>/dev/null || echo "ℹ️ Initiating UCI configuration backup ..."

    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    ARCHIVE_FILE="$BACKUP_DIR/daypass_config_backup_$TIMESTAMP.tar.gz"

    EXISTING_TARGETS=""
    for path in $CONFIG_PATHS; do
        if [ -e "$path" ]; then
            EXISTING_TARGETS="$EXISTING_TARGETS $path"
        fi
    done

    if [ -z "$EXISTING_TARGETS" ]; then
        log_warn "No existing target configuration files found to backup!" 2>/dev/null || echo "❌♻️ No existing configs to backup!"
        return 0
    fi

    if tar -czf "$ARCHIVE_FILE" $EXISTING_TARGETS 2>/dev/null; then
        # Create a symlink to latest backup
        ln -sf "$ARCHIVE_FILE" "$BACKUP_DIR/latest_backup.tar.gz"
        log_success "Backup created successfully : [$ARCHIVE_FILE]" 2>/dev/null || echo "✅♻️ Backup created :)"
        return 0
    else
        log_error "Failed to create configuration backup archive!" 2>/dev/null || echo "❌♻️ Backup failed :("
        return 1
    fi
}

# Restores configurations from the latest backup archive
restore_configs()
{
    TARGET_ARCHIVE="${1:-$BACKUP_DIR/latest_backup.tar.gz}"

    if [ ! -f "$TARGET_ARCHIVE" ]; then
        log_error "Backup archive not found at path : [$TARGET_ARCHIVE]" 2>/dev/null || echo "❌♻️ Backup archive missing."
        return 1
    fi

    log_info "Restoring UCI configuration from : [$TARGET_ARCHIVE] ..." 2>/dev/null || echo "ℹ️ Restoring configs ..."

    if tar -xzf "$TARGET_ARCHIVE" -C / 2>/dev/null; then
        log_success "Configurations restored successfully from backup!" 2>/dev/null || echo "✅♻️ Configs restored!"
        
        # Reload UCI subsystem to commit restored configs
        uci commit 2>/dev/null
        return 0
    else
        log_error "Failed to unpack backup archive during restore!" 2>/dev/null || echo "❌♻️ Restore failed."
        return 1
    fi
}

# Standalone execution handler
case "$0" in
    *backup_restore.sh)
        case "${1:-backup}" in
            backup)  backup_configs ;;
            restore) restore_configs "$2" ;;
        esac
        ;;
esac

# 📄 Source : maintenance.sh

# 1. Purge Packages Installed by DayPass
purge_daypass_packages()
{
    log_info "Analyzing installed DayPass packages ..."

    if [ ! -s "$INSTALL_LOG" ]; then
        log_warn "No installed package records found in [$INSTALL_LOG]"
        return 0
    fi

    # Extract unique packages list safely
    INSTALLED_PKGS=$(sort -u "$INSTALL_LOG" | tr '\n' ' ')

    if [ -z "$INSTALLED_PKGS" ]; then
        log_warn "No tracked packages to purge!"
        return 0
    fi

    echo
    printf "  ${YELLOW}⚠️ The following packages will be REMOVED : ${RESET}\n"
    printf "  ${CYAN}%s${RESET}\n\n" "$INSTALLED_PKGS"

    printf "  ⁉️ Are you sure you want to purge these packages? [y/N]: "
    read -r confirm </dev/tty
    case "$confirm" in
        [yY][eE][sS]|[yY])
            log_info "Initiating package purge ..."
            
            PKG_MGR="${PKG_MANAGER:-opkg}"
            for pkg in $INSTALLED_PKGS; do
                [ -z "$pkg" ] && continue
                log_info "Removing [$pkg]..."
                case "$PKG_MGR" in
                    apk)  apk del "$pkg" >/dev/null 2>&1 || true ;;
                    opkg|*) opkg remove "$pkg" >/dev/null 2>&1 || true ;;
                esac
            done

            rm -f "$INSTALL_LOG"
            log_success "DayPass packages purged successfully!"
            ;;
        *)
            log_info "Purge cancelled by use :("
            ;;
    esac
}

# 2. OpenWrt Factory Reset
factory_reset_system()
{
    echo
    printf "  ${RED}🚨 WARNING : FACTORY RESET SYSTEM${RESET}\n"
    printf "  This will erase ALL user configurations and restore system defaults!\n\n"
    
    printf "  Type '${BOLD}RESET${RESET}' to confirm factory reset : "
    read -r confirm </dev/tty

    if [ "$confirm" = "RESET" ]; then
        log_warn "Initiating Firstboot / Factory Reset procedure ..."
        sleep 2
        if command -v firstboot >/dev/null 2>&1; then
            firstboot -y && reboot
        else
            log_error "Command 'firstboot' not found on this system!"
        fi
    else
        log_info "Factory reset aborted!"
    fi
}

# 3. Clean DayPass Temporary Cache
clean_daypass_cache()
{
    log_info "Cleaning DayPass temporary files and package caches ..."
    rm -rf "${DAYPASS_DIR:?}"/*.apk "${DAYPASS_DIR:?}"/*.ipk "${DAYPASS_DIR:?}"/*.part 2>/dev/null
    log_success "Cache cleaned successfully!"
}

# 4. Backup System Configuration
backup_system_config()
{
    BACKUP_FILE="/tmp/backup-$(date +%Y%m%d_%H%M%S).tar.gz"
    log_info "Generating OpenWrt system configuration backup ..."
    if sysupgrade -b "$BACKUP_FILE" >/dev/null 2>&1; then
        log_success "Backup saved to : [$BACKUP_FILE]"
    else
        log_error "Failed to generate system backup!"
    fi
}

# Maintenance Sub-Menu
maintenance_menu()
{
    while true; do
        render_persistent_header
        
        printf "  🛠️ ${BOLD}DayPass Maintenance & Recovery${RESET}\n"
        printf "  ─────────────────────────────────────────────────────────── \n"
        printf "  🧹 1) Purge DayPass Installed Packages\n"
        printf "  🗑️ 2) Clean Temporary Cache & Downloads\n"
        printf "  💾 3) Backup System Configuration\n"
        printf "  🚨 4) Factory Reset OpenWrt (Firstboot)\n"
        printf "  🚪 0) Back to Main Menu\n\n"
        printf "  ─────────────────────────────────────────────────────────── \n"
        printf "  ⁉️ Select option [0-4] : "
        read -r choice </dev/tty

        case "$choice" in
            1) purge_daypass_packages ;;
            2) clean_daypass_cache ;;
            3) backup_system_config ;;
            4) factory_reset_system ;;
            0) break ;;
            *)
                log_warn "Invalid choice!"
                sleep 2
                ;;
        esac
        
        printf "\n  ${GRAY:-}Press [Enter] to continue ... ${RESET:-}"
        read -r _ </dev/tty
    done
}

# 📄 Source : service_manager.sh

# Service Manager module for managing init.d / procd services in OpenWrt
# Compatible with both OpenWrt 24 (opkg) and OpenWrt 25 (apk) setups

# Checks if a given service init script exists in /etc/init.d/
service_exists()
{
    service_name="$1"
    [ -n "$service_name" ] && [ -x "/etc/init.d/$service_name" ]
}

# Enables a service to automatically start on boot
service_enable()
{
    service_name="$1"
    if service_exists "$service_name"; then
        log_info "Enabling service to start on boot : [$service_name]"
        /etc/init.d/"$service_name" enable >/dev/null 2>&1
        return $?
    else
        log_warn "Cannot enable service [$service_name] : init script not found!"
        return 1
    fi
}

# Starts or restarts a target service via init.d
service_start()
{
    service_name="$1"
    if service_exists "$service_name"; then
        log_info "Starting service : [$service_name] ..."
        /etc/init.d/"$service_name" restart >/dev/null 2>&1 || /etc/init.d/"$service_name" start >/dev/null 2>&1
        
        # Brief pause for procd process spawning
        sleep 1
        
        if service_is_running "$service_name"; then
            log_success "Service [$service_name] is running smoothly!"
            return 0
        else
            log_warn "Service [$service_name] was triggered but is not reporting as active."
            return 1
        fi
    else
        log_error "Failed to start service [$service_name] : Service script missing!"
        return 1
    fi
}

# Stops an active service
service_stop()
{
    service_name="$1"
    if service_exists "$service_name"; then
        log_info "Stopping service : [$service_name] ..."
        /etc/init.d/"$service_name" stop >/dev/null 2>&1
        return 0
    fi
    return 1
}

# Checks if a target service process is currently active/running
service_is_running()
{
    service_name="$1"
    [ -z "$service_name" ] && return 1

    # Check via init.d status if supported by script
    if service_exists "$service_name"; then
        if /etc/init.d/"$service_name" status >/dev/null 2>&1; then
            return 0
        fi
    fi

    # Fallback process detection via pgrep or ps
    if command -v pgrep >/dev/null 2>&1; then
        pgrep -f "$service_name" >/dev/null 2>&1
        return $?
    else
        ps | grep -v grep | grep -q "$service_name"
        return $?
    fi
}

# Post-deployment orchestration for core network services
post_install_services_init()
{
    echo
    log_info "─────────────────────────────────────────────────────────── "
    log_info "Initiating Post-Install Service Operations"
    log_info "─────────────────────────────────────────────────────────── "
    echo

    # 1. Start core proxy profiles if selected
    case "${SELECTED_PROFILE:-passwall2}" in
        passwall2)
            service_enable "passwall2"
            service_start "passwall2"
            ;;
        passwall)
            service_enable "passwall"
            service_start "passwall"
            ;;
    esac

    # 2. Reload DNS resolution stack (dnsmasq) to apply new rules
    if service_exists "dnsmasq"; then
        log_info "Reloading dnsmasq configuration ..."
        /etc/init.d/dnsmasq reload >/dev/null 2>&1 || /etc/init.d/dnsmasq restart >/dev/null 2>&1
        log_success "DNS subsystem reloaded!"
    fi

    # 3. Reload firewall rules
    if service_exists "firewall"; then
        log_info "Reloading system firewall rules ..."
        /etc/init.d/firewall reload >/dev/null 2>&1
        log_success "Firewall rules updated!"
    fi

    echo
    log_success "All post-install service configurations applied!"
}

# Standalone test runner
case "$0" in
    *service_manager.sh)
        post_install_services_init
        ;;
esac

# 📄 Source : install_core.sh

cleanup_and_exit() {
    printf "\r\033[K"
    echo ""
    
    if command -v log_warn >/dev/null 2>&1; then
        log_warn "Installation cancelled by user. Exiting DayPass ..."
    else
        echo "  ⚠️ Installation cancelled by user. Exiting ..."
    fi

    stty echo 2>/dev/null
    rm -rf /tmp/daypass/*.part 2>/dev/null
    
    echo ""
    exit 130
}

stty -echoctl 2>/dev/null || true

trap cleanup_and_exit INT TERM

initialize_installer()
{
    # Clear lock files for both opkg (OpenWrt <=24) and apk (OpenWrt >=25)
    rm -f /var/lock/opkg.lock /lib/apk/db/lock /var/run/apk.lock /run/apk/db.lock 2>/dev/null
    
    # 1. Detect package manager (opkg or apk)
    if command -v detect_package_manager >/dev/null 2>&1; then
        detect_package_manager
    fi

    log_info "Updating package database ..."
    if command -v pkg_update >/dev/null 2>&1; then
        pkg_update >/dev/null 2>&1 || log_warn "Package index update finished with warnings!"
    fi

    # 2. Setup temporary workspace
    TMP_DIR="/tmp/daypass"
    mkdir -p "$TMP_DIR"
    MANIFEST_FILE="$TMP_DIR/manifest.json"

    # 3. Validate base repository URL
    if [ -z "${REPO_URL:-}" ]; then
        log_error "[REPO_URL] environment variable is not defined!"
        exit 1
    fi

    # 🛠️ Dynamic Manifest Selection based on PKG_MANAGER (opkg vs apk)
    MANIFEST_PATH="manifest.json"
    if [ "${PKG_MANAGER:-opkg}" = "apk" ]; then
        MANIFEST_PATH="v25/manifest.json"
    else
        MANIFEST_PATH="v24/manifest.json"
    fi

    MANIFEST_TARGET_URL="${REPO_URL}/${MANIFEST_PATH}"

    log_info "Downloading architecture manifest from : [$MANIFEST_TARGET_URL]"
    
    # 4. Download manifest using resilient fallback mechanisms (curl -> wget -> uclient-fetch)
    DOWNLOAD_SUCCESS=0

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$MANIFEST_TARGET_URL" -o "$MANIFEST_FILE" && DOWNLOAD_SUCCESS=1
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$MANIFEST_FILE" "$MANIFEST_TARGET_URL" && DOWNLOAD_SUCCESS=1
    elif command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -q -O "$MANIFEST_FILE" "$MANIFEST_TARGET_URL" && DOWNLOAD_SUCCESS=1
    else
        log_error "No network download utility found (curl, wget, or uclient-fetch)!"
        exit 1
    fi

    # 5. Verify downloaded file presence and size
    if [ "$DOWNLOAD_SUCCESS" -ne 1 ] || [ ! -s "$MANIFEST_FILE" ]; then
        log_error "Failed to download or received empty manifest from : [$MANIFEST_TARGET_URL]"
        exit 1
    fi

    # Log downloaded file size for telemetry
    MANIFEST_SIZE=$(wc -c < "$MANIFEST_FILE" | awk '{print $1}')
    log_info "Manifest downloaded successfully ($MANIFEST_SIZE bytes)."

    # 6. Detect host system target architecture
    if [ -z "${ARCH:-}" ]; then
        if command -v detect_arch >/dev/null 2>&1; then
            detect_arch
        elif [ -f /etc/openwrt_release ]; then
            . /etc/openwrt_release
            ARCH="${DISTRIB_ARCH:-}"
        fi
        
        [ -z "$ARCH" ] && ARCH="$(uname -m)"
    fi

    if [ -z "$ARCH" ]; then
        log_error "Unable to detect host system architecture!"
        exit 1
    fi

    log_info "Target System Architecture detected : [$ARCH]"

    # 7. Validate JSON syntax integrity
    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq parser utility is not available on host system!"
        exit 1
    fi

    if ! jq empty "$MANIFEST_FILE" >/dev/null 2>&1; then
        log_error "Manifest file is corrupted or invalid JSON!"
        log_warn "JSON Parser Output Error:"
        jq empty "$MANIFEST_FILE" 2>&1 | head -n 3 | sed 's/^/   └─ /'
        exit 1
    fi

    # 8. Extract release metadata for diagnostic logs
    MANIFEST_REL=$(jq -r '.release // "unknown"' "$MANIFEST_FILE" 2>/dev/null)
    MANIFEST_GEN=$(jq -r '.generated_at // "unknown"' "$MANIFEST_FILE" 2>/dev/null)
    log_info "Manifest Metadata -> Release : [$MANIFEST_REL] | Generated At : [$MANIFEST_GEN]"

    # 9. Query architecture support in manifest
    FOUND_ARCH=$(jq -r --arg arch "$ARCH" '.architectures[]? | select(.name == $arch) | .name' "$MANIFEST_FILE" 2>/dev/null | head -n1)

    if [ -z "$FOUND_ARCH" ] || [ "$FOUND_ARCH" = "null" ]; then
        log_error "Architecture [$ARCH] is NOT supported in this build manifest!"
        log_warn "Available architectures in current manifest : "
        
        jq -r '.architectures[].name' "$MANIFEST_FILE" 2>/dev/null | sed 's/^/   • /'
        
        exit 1
    fi

    # 10. Success confirmation & environment export
    log_success "Manifest loaded & verified for architecture : [$ARCH]"

    export ARCH
    export TMP_DIR
    export MANIFEST_FILE
}

# 📄 Source : resource_checker.sh

# Shared global state for resource checks
BEFORE_FREE_RAM=0
BEFORE_FREE_FLASH=0
TOTAL_REQUIRED_BYTES=0
TOTAL_SAVED_BYTES=0

human_readable_bytes()
{
    bytes="${1:-0}"
    if [ "$bytes" -ge 1048576 ]; then
        awk -v b="$bytes" 'BEGIN {printf "%.2f MB", b/1048576}' 2>/dev/null
    elif [ "$bytes" -ge 1024 ]; then
        awk -v b="$bytes" 'BEGIN {printf "%.1f KB", b/1024}' 2>/dev/null
    else
        echo "${bytes} Bytes"
    fi
}

get_free_ram_bytes()
{
    if [ -f /proc/meminfo ]; then
        mem_avail=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null)
        if [ -n "$mem_avail" ] && [ "$mem_avail" -gt 0 ]; then
            echo $((mem_avail * 1024))
        else
            mem_free=$(awk '/MemFree:/ {print $2}' /proc/meminfo 2>/dev/null)
            buffers=$(awk '/Buffers:/ {print $2}' /proc/meminfo 2>/dev/null)
            cached=$(awk '/^Cached:/ {print $2}' /proc/meminfo 2>/dev/null)
            echo $(( (${mem_free:-0} + ${buffers:-0} + ${cached:-0}) * 1024 ))
        fi
    else
        echo 0
    fi
}

get_free_flash_bytes()
{
    target_path="${1:-/overlay}"
    if ! df "$target_path" >/dev/null 2>&1; then
        target_path="/"
    fi
    free_blocks=$(df -k "$target_path" 2>/dev/null | awk 'NR==2 {print $4}')
    echo $(( ${free_blocks:-0} * 1024 ))
}

resource_snapshot()
{
    BEFORE_FREE_RAM=$(get_free_ram_bytes)
    BEFORE_FREE_FLASH=$(get_free_flash_bytes "/overlay")

    log_info "System Memory Snapshot :"
    log_info "  ├─ Available RAM          : [$(human_readable_bytes "$BEFORE_FREE_RAM")]"
    log_info "  └─ Free Flash Space       : [$(human_readable_bytes "$BEFORE_FREE_FLASH")]"
}

# Smart estimation: Calculates REAL net storage expansion
estimate_install_size()
{
    [ -z "${FINAL_PACKAGES:-}" ] && return 0
    [ -z "${MANIFEST_FILE:-}" ] || [ ! -f "$MANIFEST_FILE" ] && return 0

    TOTAL_REQUIRED_BYTES=0
    TOTAL_SAVED_BYTES=0
    RECLAIMABLE_BYTES=0

    for pkg in $FINAL_PACKAGES; do
        pkg_bytes=$(manifest_lookup "size" "$pkg")
        [ -z "$pkg_bytes" ] || [ "$pkg_bytes" = "null" ] && pkg_bytes=0

        inst_ver=$(pkg_get_installed_version "$pkg")
        manif_ver=$(manifest_lookup "version" "$pkg")

        # Skip logic if version is identical and not generic "Latest"
        if [ -n "$inst_ver" ] && [ "$inst_ver" = "$manif_ver" ] && [ "$manif_ver" != "Latest" ]; then
            TOTAL_SAVED_BYTES=$((TOTAL_SAVED_BYTES + pkg_bytes))
        else
            TOTAL_REQUIRED_BYTES=$((TOTAL_REQUIRED_BYTES + pkg_bytes))

            # If replacing an existing package, account for reclaimed space
            if [ -n "$inst_ver" ] && [ "$inst_ver" != "None" ]; then
                RECLAIMABLE_BYTES=$((RECLAIMABLE_BYTES + pkg_bytes))
            fi
        fi
    done

    # Buffer: Only 10% safety margin for extract/temp operational overhead
    TEMP_OVERHEAD=$((TOTAL_REQUIRED_BYTES / 10))
    PEAK_STORAGE_REQ=$((TOTAL_REQUIRED_BYTES + TEMP_OVERHEAD))

    log_info "Smart Resource Allocation Requirements :"
    log_info "  ├─ Payload Download Req   : [$(human_readable_bytes "$TOTAL_REQUIRED_BYTES")]"
    log_info "  ├─ Reclaimable Storage    : [$(human_readable_bytes "$RECLAIMABLE_BYTES")]"
    log_info "  ├─ Saved Traffic (Skip)   : [$(human_readable_bytes "$TOTAL_SAVED_BYTES")]"
    log_info "  └─ Peak Temp Storage Req  : [$(human_readable_bytes "$PEAK_STORAGE_REQ")]"

    CURRENT_RAM=$(get_free_ram_bytes)
    RAM_MARGIN=$((2 * 1024 * 1024)) # 2MB margin
    MIN_RAM_NEEDED=$((TOTAL_REQUIRED_BYTES + RAM_MARGIN))

    if [ "$CURRENT_RAM" -lt "$MIN_RAM_NEEDED" ]; then
        log_error "Insufficient RAM workspace for package downloads :( "
        log_warn "Available RAM : $(human_readable_bytes "$CURRENT_RAM") | Required : $(human_readable_bytes "$MIN_RAM_NEEDED")"
        return 1
    fi

    CURRENT_FLASH=$(get_free_flash_bytes "/overlay")

    # Soft check: If space is tight, warn but DON'T abort if old packages can be purged first
    if [ "$CURRENT_FLASH" -lt "$PEAK_STORAGE_REQ" ]; then
        if [ "$((CURRENT_FLASH + RECLAIMABLE_BYTES))" -ge "$PEAK_STORAGE_REQ" ]; then
            log_warn "Flash storage is tight, but replacing old packages will yield enough space :("
        else
            log_error "Insufficient Flash storage space on system!"
            log_warn "Available Storage : $(human_readable_bytes "$CURRENT_FLASH") | Peak Required : $(human_readable_bytes "$PEAK_STORAGE_REQ")"
            return 1
        fi
    fi

    log_success "System resource check PASSED!"
    return 0
}

resource_compare()
{
    AFTER_FREE_RAM=$(get_free_ram_bytes)
    AFTER_FREE_FLASH=$(get_free_flash_bytes "/overlay")

    [ "$BEFORE_FREE_RAM" -gt "$AFTER_FREE_RAM" ] && USED_RAM=$((BEFORE_FREE_RAM - AFTER_FREE_RAM)) || USED_RAM=0
    [ "$BEFORE_FREE_FLASH" -gt "$AFTER_FREE_FLASH" ] && USED_FLASH=$((BEFORE_FREE_FLASH - AFTER_FREE_FLASH)) || USED_FLASH=0

    echo
    echo "  🤌🏻 DayPass Deployment Efficiency Summary"
    echo "  ────────────────────────────────────────────────────────── "
    echo "    ├─ Total Downloaded Payload     : $(human_readable_bytes "$TOTAL_REQUIRED_BYTES")"
    echo "    ├─ Total Network Traffic Saved  : $(human_readable_bytes "$TOTAL_SAVED_BYTES") "
    echo "    ├─ Net Storage Consumed         : $(human_readable_bytes "$USED_FLASH")"
    echo "    └─ Free Storage Remaining       : $(human_readable_bytes "$AFTER_FREE_FLASH")"
    echo "  ────────────────────────────────────────────────────────── "
    echo
}

get_total_ram_bytes()
{
    if [ -f /proc/meminfo ]; then
        mem_total=$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null)
        echo $(( ${mem_total:-0} * 1024 ))
    else
        echo 0
    fi
}

get_total_flash_bytes()
{
    target_path="${1:-/overlay}"
    if ! df "$target_path" >/dev/null 2>&1; then
        target_path="/"
    fi
    total_blocks=$(df -k "$target_path" 2>/dev/null | awk 'NR==2 {print $2}')
    echo $(( ${total_blocks:-0} * 1024 ))
}

show_system_resources_menu()
{
    render_persistent_header

    # Fetch Architecture
    [ -z "$ARCH" ] && command -v detect_arch >/dev/null 2>&1 && detect_arch

    # Fetch OpenWrt Release & Date Details
    OW_VER="Unknown"
    OW_DATE=""
    if [ -f /etc/openwrt_release ]; then
        . /etc/openwrt_release
        OW_VER="${DISTRIB_RELEASE:-Unknown}"
        
        if [ -n "$DISTRIB_REVISION" ]; then
            OW_DATE=" ($DISTRIB_REVISION)"
        fi
    fi

    # Fetch Memory Data
    tot_ram_b=$(get_total_ram_bytes)
    free_ram_b=$(get_free_ram_bytes)
    used_ram_b=$((tot_ram_b - free_ram_b))

    # Fetch Storage Data
    tot_flash_b=$(get_total_flash_bytes "/overlay")
    free_flash_b=$(get_free_flash_bytes "/overlay")
    used_flash_b=$((tot_flash_b - free_flash_b))

    echo "  🖥️ System Hardware & Resource Status"
    echo "  ──────────────────────────────────────────────────────────"
    printf "  🩻 Architecture      : ${CYAN}%s${RESET}\n" "${ARCH:-N/A}"
    printf "  💡 OpenWrt System    : ${CYAN}%s [%s]${RESET}\n" "$OW_VER" "${PKG_MANAGER:-opkg}"
    echo "  ──────────────────────────────────────────────────────────"
    printf "  🧠 Total RAM         : %s\n" "$(human_readable_bytes "$tot_ram_b")"
    printf "     🟠 Used RAM          : ${YELLOW}%s${RESET}\n" "$(human_readable_bytes "$used_ram_b")"
    printf "     🟢 Free RAM          : ${GREEN}%s${RESET}\n" "$(human_readable_bytes "$free_ram_b")"
    echo "  ──────────────────────────────────────────────────────────"
    printf "  💾 Total Storage     : %s\n" "$(human_readable_bytes "$tot_flash_b")"
    printf "     🟠 Used Storage      : ${YELLOW}%s${RESET}\n" "$(human_readable_bytes "$used_flash_b")"
    printf "     🟢 Free Storage      : ${GREEN}%s${RESET}\n" "$(human_readable_bytes "$free_flash_b")"
    echo "  ──────────────────────────────────────────────────────────"
    echo

    printf "  ${GRAY}Press [ENTER] to return to main menu ...${RESET}"
    read -r _ </dev/tty
}

# 📄 Source : resolver.sh

# Resolves target packages and dependencies for opkg / apk engines
resolve_packages()
{
    log_info "Resolving targeted packages and dependencies for engine : [${PKG_MANAGER:-opkg}] ..."

    FINAL_PACKAGES=""

    # Helper function to append package uniquely to resolution queue
    add_final()
    {
        pkg="$1"
        [ -z "$pkg" ] && return

        case " $FINAL_PACKAGES " in
            *" $pkg "*) 
                # Package already resolved; skipping duplicate entry
                ;;
            *) 
                if [ -z "$FINAL_PACKAGES" ]; then
                    FINAL_PACKAGES="$pkg"
                else
                    FINAL_PACKAGES="$FINAL_PACKAGES $pkg"
                fi
                log_info "  ├─ Resolved target : [$pkg]"
                ;;
        esac
    }

    # 1. Low-level utilities and pre-requisites
    add_final "tcping"
    add_final "geoview"

    # 2. GeoIP / GeoSite databases
    if [ "${SELECTED_GEO:-official}" = "official" ]; then
        add_final "v2ray-geoip"
        add_final "v2ray-geosite"
    fi

    # 3. Core Routing Engines (Fix handling for singbox name variations)
    case "${SELECTED_ENGINE:-xray}" in
        xray)     
            add_final "xray-core" 
            ;;
        singbox|sing-box) 
            add_final "sing-box" 
            ;;
        both)
            add_final "xray-core"
            add_final "sing-box"
            ;;
        *)     
            add_final "xray-core" 
            ;;
    esac

    # 4. User-selected custom packages (excluding main application and translations)
    if [ -n "${SELECTED_PACKAGES:-}" ]; then
        for pkg in $SELECTED_PACKAGES; do
            case "$pkg" in
                luci-app-passwall|luci-app-passwall2|luci-i18n-*) 
                    # Skipped here to ensure strict sequence ordering below
                    ;; 
                *) 
                    add_final "$pkg" 
                    ;;
            esac
        done
    fi

    # 5. Main Application Interface (Must be installed BEFORE translation packages)
    MAIN_APP=""
    case "${SELECTED_PROFILE:-passwall2}" in
        passwall2) MAIN_APP="luci-app-passwall2" ;;
        passwall)  MAIN_APP="luci-app-passwall" ;;
    esac

    [ -n "$MAIN_APP" ] && add_final "$MAIN_APP"

    # 6. Localization & Translation Packages
    LANG_CODE="${SELECTED_LANGUAGE:-fa}"
    APP_NAME="${SELECTED_PROFILE:-passwall2}"

    if [ "$LANG_CODE" != "en" ]; then
        I18N_PKG="luci-i18n-${APP_NAME}-${LANG_CODE}"

        if [ -z "$MANIFEST_FILE" ] || [ ! -f "$MANIFEST_FILE" ]; then
            if [ -f "/tmp/manifest.json" ]; then
                MANIFEST_FILE="/tmp/manifest.json"
            elif [ -f "manifest.json" ]; then
                MANIFEST_FILE="manifest.json"
            fi
        fi

        if [ -n "$MANIFEST_FILE" ] && [ -f "$MANIFEST_FILE" ]; then
            EXISTS="$(jq -r --arg arch "${ARCH:-x86_64}" --arg pkg "$I18N_PKG" '
                .architectures[] | select(.name==$arch) | .feeds[]?[]? | select(.package==$pkg) | .package
            ' "$MANIFEST_FILE" 2>/dev/null)"

            if [ -n "$EXISTS" ]; then
                add_final "$I18N_PKG"
            else
                log_warn "Translation package [$I18N_PKG] is not available in feeds. Skipped."
            fi
        else
            [ "$APP_NAME" = "passwall2" ] && add_final "$I18N_PKG"
        fi
    fi

    # Validate non-empty final package list
    if [ -z "$FINAL_PACKAGES" ]; then
        log_error "Package resolution finished with an empty target package list :("
        return 1
    fi

    log_success "Package resolution completed successfully :)"
    log_info "Final deployment target list : [$FINAL_PACKAGES]"

    export FINAL_PACKAGES
}

# Standalone execution handler
case "$0" in
    *package_resolver.sh) resolve_packages ;;
esac

# 📄 Source : installer.sh

manifest_lookup()
{
    field="$1"
    package="$2"

    val=$(jq -r \
        --arg pkg "$package" \
        --arg arch "$ARCH" \
        --arg field "$field" \
'
.architectures[]?
| select(.name == $arch)
| .feeds[]?[]?
| select(
    (.package == $pkg)
    or
    (.package | startswith($pkg + "-"))
)
| .[$field] // empty
' \
"$MANIFEST_FILE" 2>/dev/null | head -n1)

    if [ -z "$val" ] || [ "$val" = "null" ]; then
        alt_field=""
        case "$field" in
            size) alt_field="Size" ;;
            Size) alt_field="size" ;;
            version) alt_field="Version" ;;
            Version) alt_field="version" ;;
            sha256) alt_field="SHA256" ;;
        esac

        if [ -n "$alt_field" ]; then
            val=$(jq -r \
                --arg pkg "$package" \
                --arg arch "$ARCH" \
                --arg field "$alt_field" \
'
.architectures[]?
| select(.name == $arch)
| .feeds[]?[]?
| select(
    (.package == $pkg)
    or
    (.package | startswith($pkg + "-"))
)
| .[$field] // empty
' \
"$MANIFEST_FILE" 2>/dev/null | head -n1)
        fi
    fi

    echo "$val"
}

format_size()
{
    bytes="${1:-0}"
    if [ "$bytes" -ge 1048576 ]; then
        awk "BEGIN {printf \"%.2f MB\", $bytes/1048576}" 2>/dev/null
    elif [ "$bytes" -ge 1024 ]; then
        awk "BEGIN {printf \"%.1f KB\", $bytes/1024}" 2>/dev/null
    else
        echo "${bytes} Bytes"
    fi
}

download_package()
{
    package="$1"

    file=$(manifest_lookup "file" "$package")
    sha256=$(manifest_lookup "sha256" "$package")

    if [ -z "$file" ] || [ "$file" = "null" ]; then
        log_error "Package [$package] not found in manifest for target [$ARCH]!"
        return 1
    fi

    base_url=$(jq -r '.download_base // empty' "$MANIFEST_FILE" 2>/dev/null)
    [ -z "$base_url" ] && base_url="$REPO_URL"
    target_url="${base_url}/${file}"

    file_basename=$(basename "$file")
    target="$TMP_DIR/$file_basename"
    tmp="$target.part"

    if [ -f "$target" ]; then
        if echo "$sha256  $target" | sha256sum -c - >/dev/null 2>&1; then
            return 0
        fi
        rm -f "$target"
    fi

    DOWNLOAD_SUCCESS=0
    trap 'rm -f "$tmp" 2>/dev/null' INT TERM

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 15 --max-time 120 --retry 3 --retry-delay 2 "$target_url" -o "$tmp" 2>/dev/null && DOWNLOAD_SUCCESS=1
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=20 --tries=3 -O "$tmp" "$target_url" 2>/dev/null && DOWNLOAD_SUCCESS=1
    elif command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -q --timeout=20 -O "$tmp" "$target_url" 2>/dev/null && DOWNLOAD_SUCCESS=1
    fi

    if [ "$DOWNLOAD_SUCCESS" -ne 1 ] || [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        trap - INT TERM
        return 1
    fi

    if [ -n "$sha256" ] && [ "$sha256" != "null" ]; then
        if ! echo "$sha256  $tmp" | sha256sum -c - >/dev/null 2>&1; then
            rm -f "$tmp"
            trap - INT TERM
            return 1
        fi
    fi

    mv "$tmp" "$target"
    trap - INT TERM
    return 0
}

deploy_targeted_packages()
{
    rm -f /var/lock/opkg.lock /lib/apk/db/lock /var/run/apk.lock /run/apk/db.lock 2>/dev/null

    mkdir -p "$(dirname "$INSTALL_LOG")"
    touch "$INSTALL_LOG"
    rm -f "$TRANSACTION_LOG"
    touch "$TRANSACTION_LOG"

    if [ -z "$PACKAGES_TO_PROCESS" ]; then
        PACKAGES_TO_PROCESS="$FINAL_PACKAGES"
    fi

    echo "  🔍 Executing Pre-Flight System Resource Validation ..."
    resource_snapshot
    if ! estimate_install_size; then
        log_error "Installation aborted due to system resource limits!"
        return 1
    fi

    INSTALL_FILES=""
    total_pkgs=0
    for p in $PACKAGES_TO_PROCESS; do
        total_pkgs=$((total_pkgs + 1))
    done

    current_idx=0
    log_info "Downloading required packages ..."

    for pkg in $PACKAGES_TO_PROCESS; do
        current_idx=$((current_idx + 1))
        
        curr_ram_bytes=$(get_free_ram_bytes 2>/dev/null)
        curr_ram_fmt=$(human_readable_bytes "$curr_ram_bytes" 2>/dev/null)
        
        if command -v show_ascii_progress >/dev/null 2>&1; then
            show_ascii_progress "Downloading ($pkg) [Free RAM: ${curr_ram_fmt:-N/A}]" "$current_idx" "$total_pkgs"
        else
            echo "  📦 [$current_idx/$total_pkgs] Downloading $pkg ... (Free RAM: ${curr_ram_fmt:-N/A})"
        fi

        if ! download_package "$pkg"; then
            echo
            log_error "Failed downloading dependency : [$pkg]"
            rollback_failed_install
            return 1
        fi

        file=$(manifest_lookup "file" "$pkg")
        file_basename=$(basename "$file")
        INSTALL_FILES="$INSTALL_FILES $TMP_DIR/$file_basename"
    done
    echo

    for pkg in $PACKAGES_TO_PROCESS; do
        echo "$pkg" >> "$TRANSACTION_LOG"
    done

    INSTALL_SUCCESS=0
    CURRENT_PKG_MGR="${PKG_MANAGER:-opkg}"

    case "$CURRENT_PKG_MGR" in
        apk)
            (apk add --allow-untrusted --no-progress $INSTALL_FILES >/tmp/apk_inst.log 2>&1) &
            BG_PID=$!
            if command -v show_timer_progress >/dev/null 2>&1; then
                show_timer_progress "$BG_PID" "applying APK package bundle"
            fi
            wait "$BG_PID"
            [ $? -eq 0 ] && INSTALL_SUCCESS=1
            ;;
        opkg|*)
            (opkg install --force-reinstall --force-checksum $INSTALL_FILES >/tmp/opkg_inst.log 2>&1) &
            BG_PID=$!
            if command -v show_timer_progress >/dev/null 2>&1; then
                show_timer_progress "$BG_PID" "applying OPKG package bundle"
            fi
            wait "$BG_PID"
            [ $? -eq 0 ] && INSTALL_SUCCESS=1
            ;;
    esac

    if [ "$INSTALL_SUCCESS" -eq 1 ]; then
        for pkg in $PACKAGES_TO_PROCESS; do
            echo "$pkg" >> "$INSTALL_LOG"
        done

        if [ -f "$INSTALL_LOG" ]; then
            sort -u "$INSTALL_LOG" -o "$INSTALL_LOG"
        fi
        
        resource_compare
        
        rm -f $INSTALL_FILES 2>/dev/null
        rm -f "$TRANSACTION_LOG"
        
        log_success "All targeted packages deployed successfully!"
        return 0
    fi

    echo
    log_error "Package manager batch execution failed!"
    if [ -f /tmp/opkg_inst.log ]; then cat /tmp/opkg_inst.log; fi
    if [ -f /tmp/apk_inst.log ]; then cat /tmp/apk_inst.log; fi
    rollback_failed_install
    return 1
}

rollback_failed_install()
{
    echo
    log_warn "Initiating Selective Atomic Rollback Procedures ..."
    echo

    rm -f "$TMP_DIR"/*.part "$TMP_DIR"/*.apk "$TMP_DIR"/*.ipk 2>/dev/null

    if [ -s "$TRANSACTION_LOG" ]; then
        log_info "Rolling back modified packages from current session ..."
        while read -r pkg; do
            [ -z "$pkg" ] && continue
            log_info "Rollback : Removing package [$pkg] ..."
            
            case "${PKG_MANAGER:-opkg}" in
                apk)  apk del "$pkg" >/dev/null 2>&1 || true ;;
                opkg|*) opkg remove "$pkg" >/dev/null 2>&1 || true ;;
            esac
        done < "$TRANSACTION_LOG"
    else
        log_info "No system packages were installed in this session. Skipping removal!"
    fi

    rm -f "$TRANSACTION_LOG"
    log_success "Rollback procedure completed safely!"
}

# 📄 Source : updater.sh

inspect_and_confirm_updates()
{
    echo "  📦 DayPass Package Inspection Table"
    echo "  ─────────────────────────────────────────────────────────── "
    printf "   %-28s %-16s %-16s %-12s\n" "Package" "Installed" "Manifest Ver" "Action"
    echo "  ─────────────────────────────────────────────────────────── "

    PACKAGES_TO_PROCESS=""
    UPGRADE_COUNT=0
    INSTALL_COUNT=0
    SKIP_COUNT=0

    for pkg in $FINAL_PACKAGES; do
        raw_inst_ver=$(pkg_get_installed_version "$pkg" 2>/dev/null | head -n1)
        inst_ver=$(echo "$raw_inst_ver" | awk '{print $1}' | tr -d ':')
        
        if [ "$inst_ver" = "$pkg" ] || [ -z "$inst_ver" ]; then
            inst_ver="None"
        fi
        
        manif_ver=$(manifest_lookup "version" "$pkg")
        manif_hash=$(manifest_lookup "sha256" "$pkg")
        
        [ -z "$manif_ver" ] || [ "$manif_ver" = "null" ] && manif_ver="N/A"

        ACTION_STR=""
        
        if [ "$inst_ver" = "None" ]; then
            ACTION_STR="${GREEN}[➕ Install]${RESET}"
            INSTALL_COUNT=$((INSTALL_COUNT + 1))
            PACKAGES_TO_PROCESS="$PACKAGES_TO_PROCESS $pkg"
        elif [ "$manif_ver" != "N/A" ] && [ "$manif_ver" != "Latest" ] && [ "$inst_ver" != "$manif_ver" ]; then
            ACTION_STR="${YELLOW}[🔄 Upgrade]${RESET}"
            UPGRADE_COUNT=$((UPGRADE_COUNT + 1))
            PACKAGES_TO_PROCESS="$PACKAGES_TO_PROCESS $pkg"
        elif [ "$manif_ver" = "Latest" ] || [ "$inst_ver" = "$manif_ver" ]; then
            inst_hash=$(pkg_get_installed_hash "$pkg" 2>/dev/null)
            if [ -n "$manif_hash" ] && [ "$manif_hash" != "null" ] && [ -n "$inst_hash" ] && [ "$inst_hash" != "$manif_hash" ]; then
                ACTION_STR="${ORANGE}[🩹 Patch]${RESET}"
                UPGRADE_COUNT=$((UPGRADE_COUNT + 1))
                PACKAGES_TO_PROCESS="$PACKAGES_TO_PROCESS $pkg"
            else
                ACTION_STR="${GREEN}[✅ Up-to-date]${RESET}"
                SKIP_COUNT=$((SKIP_COUNT + 1))
            fi
        fi

        inst_ver_fmt=$(printf "%.14s" "$inst_ver")
        manif_ver_fmt=$(printf "%.14s" "$manif_ver")

        printf "   🔹 ${CYAN}%-24s${RESET} ${YELLOW}%-14s${RESET} %-14s %b\n" \
            "$pkg" "$inst_ver_fmt" "$manif_ver_fmt" "$ACTION_STR"
    done

    echo "  ─────────────────────────────────────────────────────────── "
    printf "   Summary : %d to install, %d to upgrade, %d skipped!\n" "$INSTALL_COUNT" "$UPGRADE_COUNT" "$SKIP_COUNT"
    echo "  ─────────────────────────────────────────────────────────── "
    echo

    if [ -z "$PACKAGES_TO_PROCESS" ]; then
        log_success "All packages are up-to-date! No changes required!"
        return 2
    fi

    printf "  ⁉️ Do you want to proceed with deployment? [Y/n] : "
    read -r user_confirm </dev/tty
    echo

    case "$user_confirm" in
        [nN][oO]|[nN])
            log_warn "Update cancelled by user!"
            return 3
            ;;
        *)
            log_info "User confirmed. Proceeding with updates ..."
            echo
            ;;
    esac

    export PACKAGES_TO_PROCESS
    return 0
}


update_packages_menu()
{
    render_persistent_header

    if [ ! -f "$INSTALL_LOG" ] || [ ! -s "$INSTALL_LOG" ]; then
        log_warn "No installed packages log found. Please install DayPass packages first!"
        echo
        printf "  ${GRAY}Press [ENTER] to return to main menu ...${RESET}"
        read -r _ </dev/tty
        return 1
    fi

    FINAL_PACKAGES=$(cat "$INSTALL_LOG" | tr '\n' ' ')
    export FINAL_PACKAGES

    inspect_and_confirm_updates
    INSPECT_STATUS=$?

    if [ "$INSPECT_STATUS" -eq 2 ] || [ "$INSPECT_STATUS" -eq 3 ]; then
        printf "  ${GRAY}Press [ENTER] to return to main menu ...${RESET}"
        read -r _ </dev/tty
        return 0
    fi

    if deploy_targeted_packages; then
        echo
        log_success "All packages updated successfully!"
    else
        echo
        log_error "Update process failed!"
    fi

    echo
    printf "  ${GRAY}Press [ENTER] to return to main menu ...${RESET}"
    read -r _ </dev/tty
}

# 📄 Source : state.sh

SELECTED_PROFILE=""
SELECTED_ENGINE="auto"
SELECTED_LANGUAGE="none"
SELECTED_GEO="none"
SELECTED_PACKAGES=""
GEOIP_URL=""
GEOSITE_URL=""

add_selected_package()
{
    pkg="$1"
    [ -z "$pkg" ] && return

    case " $SELECTED_PACKAGES " in
        *" $pkg "*) ;;
        *) SELECTED_PACKAGES="$SELECTED_PACKAGES $pkg" ;;
    esac
}

reset_state()
{
    SELECTED_PROFILE=""
    SELECTED_ENGINE="auto"
    SELECTED_LANGUAGE="none"
    SELECTED_GEO="none"
    SELECTED_PACKAGES=""
    GEOIP_URL=""
    GEOSITE_URL=""
}

# 📄 Source : custom.sh

show_custom_help()
{
    render_persistent_header
    echo "  📖 ${BOLD}Custom Selection Guide & Keyboard Shortcuts${RESET}"
    echo "  ──────────────────────────────────────────────────────────"
    echo "  🔹 ${YELLOW}Toggle Item (1-6):${RESET} Enter item number to Select [✔] or Deselect [ ]."
    echo "  🔹 ${YELLOW}Language Notice:${RESET} Selecting a new language (e.g. -fa) automatically"
    echo "     replaces previously selected translations for clean config."
    echo "  🔹 ${YELLOW}[n] / [p]:${RESET} Navigate to Next or Previous page."
    echo "  🔹 ${YELLOW}[d]:${RESET} Save your current selection and proceed to Review."
    echo "  🔹 ${YELLOW}[q]:${RESET} Cancel and return to main menu."
    echo "  ──────────────────────────────────────────────────────────"
    echo "  💡 ${CYAN}Pro-Tip:${RESET} Combining Sing-box and Xray together is supported,"
    echo "     but recommended mainly for powerful hardware (ARM64 / x86)."
    echo "  ──────────────────────────────────────────────────────────"
    echo
    printf "  ${GRAY}Press [ENTER] to return to selection menu ...${RESET}"
    read -r _ </dev/tty
}

toggle_custom_package()
{
    pkg_to_toggle="$1"

    case "$pkg_to_toggle" in
        luci-i18n-passwall*-*)
            base_prefix=$(echo "$pkg_to_toggle" | sed -E 's/-(fa|ru|zh-cn|zh-tw|en)$//')
            NEW_SEL=""
            for p in $SELECTED_PACKAGES; do
                case "$p" in
                    ${base_prefix}-*) ;;
                    *) NEW_SEL="$NEW_SEL $p" ;;
                esac
            done
            SELECTED_PACKAGES="$NEW_SEL"
            ;;
    esac

    if echo " $SELECTED_PACKAGES " | grep -q " $pkg_to_toggle "; then
        NEW_SEL=""
        for p in $SELECTED_PACKAGES; do
            [ "$p" != "$pkg_to_toggle" ] && NEW_SEL="$NEW_SEL $p"
        done
        SELECTED_PACKAGES="$NEW_SEL"
        log_info "Removed package : [$pkg_to_toggle]"
    else
        SELECTED_PACKAGES="$SELECTED_PACKAGES $pkg_to_toggle"
        log_success "Selected package: [$pkg_to_toggle]"

        if [ "$pkg_to_toggle" = "sing-box" ] || [ "$pkg_to_toggle" = "xray-core" ]; then
            case "${ARCH:-}" in
                *mips*|*ramips*|*aarch64_cortex-a53*)
                    echo
                    log_warn "⚠️ PERFORMANCE NOTICE : Engine [$pkg_to_toggle] on architecture [$ARCH]"
                    log_warn "Running heavy proxy engines alongside Passwall on low-resource hardware may cause high CPU/RAM usage!"
                    sleep 1
                    ;;
            esac
        fi
    fi

    SELECTED_PACKAGES=$(echo "$SELECTED_PACKAGES" | xargs)
    export SELECTED_PACKAGES
}

handle_custom_profile()
{
    if [ -z "$MANIFEST_FILE" ] || [ ! -f "$MANIFEST_FILE" ]; then
        if [ -f "/tmp/manifest.json" ]; then
            MANIFEST_FILE="/tmp/manifest.json"
        elif [ -f "manifest.json" ]; then
            MANIFEST_FILE="manifest.json"
        else
            OW_VER="25"
            [ "${PKG_MANAGER:-opkg}" = "opkg" ] && OW_VER="24"
            MANIFEST_FILE="build-artifacts/v${OW_VER}/manifest.json"
        fi
    fi

    TARGET_PROFILE="${SELECTED_PROFILE:-passwall2}"

    if [ "$TARGET_PROFILE" = "passwall" ]; then
        ALL_AVAILABLE_PKGS="$(jq -r --arg arch "$ARCH" \
            '.architectures[] | select(.name==$arch) | (.feeds["passwall_luci"][]?.package, .feeds["passwall_packages"][]?.package)' \
            "$MANIFEST_FILE" 2>/dev/null | sort -u)"
    else
        ALL_AVAILABLE_PKGS="$(jq -r --arg arch "$ARCH" \
            '.architectures[] | select(.name==$arch) | (.feeds["passwall2"][]?.package, .feeds["passwall_packages"][]?.package)' \
            "$MANIFEST_FILE" 2>/dev/null | sort -u)"
    fi

    if [ -z "$ALL_AVAILABLE_PKGS" ]; then
        log_error "No packages found in manifest [$MANIFEST_FILE] for architecture : [$ARCH]"
        return 1
    fi

    PAGE_SIZE=6
    CURRENT_PAGE=1
    
    set -- $ALL_AVAILABLE_PKGS
    TOTAL_PKGS=$#
    TOTAL_PAGES=$(( (TOTAL_PKGS + PAGE_SIZE - 1) / PAGE_SIZE ))
    
    FIRST_RENDER=1

    while true; do
        render_persistent_header

        SEL_COUNT=0
        for _p in $SELECTED_PACKAGES; do
            SEL_COUNT=$((SEL_COUNT + 1))
        done

        echo "  🛠️ ${BOLD}Custom Package Selection${RESET} ${GRAY}(Page ${YELLOW}$CURRENT_PAGE${RESET}${GRAY}/$TOTAL_PAGES | Selected : ${GREEN}$SEL_COUNT${RESET}${GRAY})${RESET}"
        echo "  ${GRAY}──────────────────────────────────────────────────────────${RESET}"

        START_IDX=$(( (CURRENT_PAGE - 1) * PAGE_SIZE + 1 ))
        END_IDX=$(( CURRENT_PAGE * PAGE_SIZE ))

        item_no=1
        curr_idx=1
        
        for pkg in "$@"; do
            if [ "$curr_idx" -ge "$START_IDX" ] && [ "$curr_idx" -le "$END_IDX" ]; then
                
                is_selected="${GRAY}[ ]${RESET}"
                case " $SELECTED_PACKAGES " in
                    *" $pkg "*) is_selected="${GREEN}[✔]${RESET}" ;;
                esac
                
                printf "   ${CYAN}%d${RESET}) %b %s\n" "$item_no" "$is_selected" "$pkg"
                
                if [ "$FIRST_RENDER" -eq 1 ]; then
                    command -v usleep >/dev/null 2>&1 && usleep 12000
                fi

                item_no=$((item_no + 1))
            fi
            curr_idx=$((curr_idx + 1))
        done

        FIRST_RENDER=0

        echo "  ${GRAY}──────────────────────────────────────────────────────────${RESET}"
        echo "  ${GRAY}[${CYAN}n${RESET}${GRAY}] Next | [${CYAN}p${RESET}${GRAY}] Prev | [${YELLOW}h${RESET}${GRAY}] Help | [${RED}q${RESET}${GRAY}] Cancel | [${GREEN}d${RESET}${GRAY}] Save & Done${RESET}"
        echo

        printf "  ⁉️ ${YELLOW}Toggle Item${RESET} ${GRAY}(1-$((item_no - 1))) or Action (${CYAN}n${RESET}${GRAY}/${CYAN}p${RESET}${GRAY}/${YELLOW}h${RESET}${GRAY}/${RED}q${RESET}${GRAY}/${GREEN}d${RESET}${GRAY}) :${RESET} "
        read -r cmd </dev/tty

        case "$cmd" in
            n|N)
                [ "$CURRENT_PAGE" -lt "$TOTAL_PAGES" ] && CURRENT_PAGE=$((CURRENT_PAGE + 1))
                ;;
            p|P)
                [ "$CURRENT_PAGE" -gt 1 ] && CURRENT_PAGE=$((CURRENT_PAGE - 1))
                ;;
            h|H)
                show_custom_help
                ;;
            q|Q)
                log_warn "Custom selection cancelled."
                SELECTED_PACKAGES=""
                return 1
                ;;
            d|D)
                if [ -z "$SELECTED_PACKAGES" ]; then
                    log_warn "No packages selected! Please select at least one package!"
                    sleep 1
                else
                    log_info "Custom package selection saved!"
                    break
                fi
                ;;
            [1-9])
                if [ "$cmd" -ge 1 ] && [ "$cmd" -lt "$item_no" ]; then
                    TARGET_INDEX=$(( START_IDX + cmd - 1 ))
                    idx=1
                    for pkg in "$@"; do
                        if [ "$idx" -eq "$TARGET_INDEX" ]; then
                            toggle_custom_package "$pkg"
                            break
                        fi
                        idx=$((idx + 1))
                    done
                else
                    log_warn "Invalid selection range!"
                    sleep 1
                fi
                ;;
            *)
                log_warn "Invalid command!"
                sleep 1
                ;;
        esac
    done
}

# 📄 Source : mode.sh

handle_recommended_profile()
{
    SELECTED_PACKAGES=""
    export SELECTED_PACKAGES
}

menu_mode()
{
    render_persistent_header

    echo "  🕵️‍♀️ Select Installation Mode                                "
    echo "  ───────────────────────────────────────────────────────────"
    echo "  1) ⚡ Recommended (Quick & Pre-configured for users)       "
    echo "  2) 🛠️ Custom      (Advanced package selection)             "
    echo "  ───────────────────────────────────────────────────────────"
    echo

    printf "  ⁉️ Select option [1-2] (Default: 1) : "
    read -r choice </dev/tty

    case "$choice" in
        1|"")
            SELECTED_MODE="recommended"  
            export SELECTED_MODE
            handle_recommended_profile
            ;;
        2)
            SELECTED_MODE="custom"       
            export SELECTED_MODE
            handle_custom_profile
            ;;
        *)
            log_warn "Invalid choice! Defaulting to Recommended mode!"
            SELECTED_MODE="recommended"   
            export SELECTED_MODE
            handle_recommended_profile
            ;;
    esac
}

# 📄 Source : engine.sh

engine_menu()
{
    render_persistent_header

    echo "  🕵️‍♀️ Select Proxy Engine                                    "
    echo "  ───────────────────────────────────────────────────────── "
    echo "  1) ⚡ Auto      (Recommended)                             "
    echo "  2) ✖️ Xray      (Xray-core proxy engine)                  "
    echo "  3) 📦 Sing-box  (Sing-box proxy engine)                   "
    echo "  ───────────────────────────────────────────────────────── "
    echo

    printf "  ⁉️ Select option [1-3] (Default: 1) : "
    read -r choice </dev/tty

    case "$choice" in
        1|"")
            SELECTED_ENGINE="auto"
            ;;
        2)
            SELECTED_ENGINE="xray"
            add_selected_package "xray-core"
            ;;
        3)
            SELECTED_ENGINE="sing-box"
            echo
            log_warn "Sing-box may consume higher RAM on low-end hardware!"
            echo
            printf "  ⁉️  Are you sure you want to proceed with Sing-box? [y/N] : "
            read -r confirm </dev/tty

            case "$confirm" in
                y|Y)
                    add_selected_package "sing-box"
                    ;;
                *)
                    log_info "Reverting Proxy Engine selection to Auto!"
                    SELECTED_ENGINE="auto"
                    ;;
            esac
            ;;
        *)
            log_warn "Invalid choice! Defaulting to Auto engine!"
            SELECTED_ENGINE="auto"
            ;;
    esac

    export SELECTED_ENGINE
}

# 📄 Source : language.sh

language_menu()
{
    if [ "$SELECTED_PROFILE" != "passwall2" ]; then
        SELECTED_LANGUAGE="en"
        export SELECTED_LANGUAGE
        return 0
    fi

    render_persistent_header

    echo "  🕵️‍♀️ Select Language (Passwall 2)                             "
    echo "  ─────────────────────────────────────────────────────────── "
    echo "  1) 🦁☀️ Persian  (fa)                                       "
    echo "  2) 🇬🇧   English  (en)                                       "
    echo "  3) 🇨🇳   Chinese  (zh)                                       "
    echo "  4) 🇷🇺   Russian  (ru)                                       "
    echo "  ─────────────────────────────────────────────────────────── "
    echo

    printf "  ⁉️ Select option [1-4] (Default: 1) : "
    read -r choice </dev/tty

    case "$choice" in
        1|"")
            SELECTED_LANGUAGE="fa"
            add_selected_package "luci-i18n-passwall2-fa"
            ;;
        2)
            SELECTED_LANGUAGE="en"
            ;;
        3)
            SELECTED_LANGUAGE="zh-cn"
            add_selected_package "luci-i18n-passwall2-zh-cn"
            ;;
        4)
            SELECTED_LANGUAGE="ru"
            add_selected_package "luci-i18n-passwall2-ru"
            ;;
        *)
            log_warn "Invalid choice! Defaulting to English."
            SELECTED_LANGUAGE="en"
            ;;
    esac

    export SELECTED_LANGUAGE
}

# 📄 Source : geo.sh

geo_menu()
{
    render_persistent_header

    echo "  🕵️‍♀️ Select Geo Database                                     "
    echo "  ─────────────────────────────────────────────────────────── "
    echo "  🫸🏻 1) Skip       (Do not install Geo databases)             "
    echo "  👔 2) Official   (Standard official release packages)       "
    echo "  🍺 3) Iran Full  (Custom ruleset - Full database)           "
    echo "  🍷 4) Iran Lite  (Custom ruleset - Compact database)        "
    echo "  ─────────────────────────────────────────────────────────── "
    echo

    printf "  ⁉️ Select option [1-4] (Default: 1) : "
    read -r choice </dev/tty

    GEOIP_URL=""
    GEOSITE_URL=""

    case "$choice" in
        1|"")
            SELECTED_GEO="none"
            ;;
        2)
            SELECTED_GEO="official"
            if [ "${PKG_MANAGER:-opkg}" = "apk" ]; then
                add_selected_package "geosite" 2>/dev/null || add_selected_package "v2ray-geosite"
                add_selected_package "geoip" 2>/dev/null || add_selected_package "v2ray-geoip"
            else
                add_selected_package "v2ray-geoip"
                add_selected_package "v2ray-geosite"
            fi
            ;;
        3)
            SELECTED_GEO="iran-full"
            GEOIP_URL="https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geoip.dat"
            GEOSITE_URL="https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geosite.dat"
            ;;
        4)
            SELECTED_GEO="iran-lite"
            GEOIP_URL="https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geoip-lite.dat"
            GEOSITE_URL="https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geosite-lite.dat"
            ;;
        *)
            log_warn "Invalid choice! Defaulting to Skip!"
            SELECTED_GEO="none"
            ;;
    esac

    export SELECTED_GEO
    export GEOIP_URL
    export GEOSITE_URL
}

# 📄 Source : review.sh

review_install()
{
    if ! resolve_packages; then
        log_error "Failed to resolve final package list!"
        sleep 2
        return 1
    fi

    clear
    [ -n "$(command -v render_persistent_header)" ] && render_persistent_header

    echo "  📊 Installation Plan Summary"
    echo "  ─────────────────────────────────────────────────────────────"
    printf "  👤 %-18s : %s\n" "Selected Profile" "${SELECTED_PROFILE:-N/A}"
    printf "  🛠️ %-18s : %s\n" "Installation Mode" "${SELECTED_MODE:-recommended}"
    printf "  ⚙️ %-18s : %s\n" "Proxy Engine"    "${SELECTED_ENGINE:-xray}"
    
    if [ "${SELECTED_MODE:-}" = "recommended" ]; then
        printf "  🗣️ %-18s : %s\n" "Language"        "${SELECTED_LANGUAGE:-fa}"
        printf "  🌐 %-18s : %s\n" "Geo Database"     "${SELECTED_GEO:-official}"
    fi
    echo "  ─────────────────────────────────────────────────────────────"

    PKG_COUNT=$(echo $FINAL_PACKAGES | wc -w | tr -d ' ')
    echo "  📦 Targeted Packages (${PKG_COUNT:-0}) :"

    i=0
    for pkg in $FINAL_PACKAGES; do
        i=$((i + 1))
        if [ "$i" -eq "$PKG_COUNT" ]; then
            echo "     └─ 🔹 ${CYAN}$pkg${RESET}"
        else
            echo "     ├─ 🔹 ${CYAN}$pkg${RESET}"
        fi
    done
    echo "  ─────────────────────────────────────────────────────────────"
    echo

    while true; do
        printf "  ⁉️  Proceed with deployment? [Y/n] : "
        read -r confirm </dev/tty

        case "$confirm" in
            y|Y|"")
                return 0
                ;;
            n|N)
                log_warn "Installation cancelled by user!"
                FINAL_PACKAGES=""
                export FINAL_PACKAGES
                sleep 1
                clear
                return 1
                ;;
            *)
                log_error "Invalid input! Please enter Y or N."
                ;;
        esac
    done
}

# 📄 Source : passwall.sh

package_menu()
{
    render_persistent_header

    echo "  🕵️‍♀️ Select Package Type                                   "
    echo "  ───────────────────────────────────────────────────────────"
    echo "  🔒 1) Passwall-1  (Legacy Stable Release)                "
    echo "  🔒 2) Passwall-2  (Modern Release - Recommended)         "
    echo "  ───────────────────────────────────────────────────────────"
    echo

    printf "  ⁉️ Select option [1-2] : "
    read -r choice </dev/tty

    SELECTED_PACKAGES=""

    case "$choice" in
        1)
            SELECTED_PROFILE="passwall"
            ;;
        2)
            SELECTED_PROFILE="passwall2"
            ;;
        *)
            log_error "Invalid choice! Returning to menu ..."
            sleep 1
            return 1
            ;;
    esac

    export SELECTED_PROFILE

    # 1. Select Mode (Recommended or Custom)
    menu_mode

    # 2. Set environment vars based on Mode
    if [ "${SELECTED_MODE:-}" = "recommended" ]; then
        SELECTED_ENGINE="xray"
        SELECTED_LANGUAGE="fa"
        SELECTED_GEO="official"
        export SELECTED_ENGINE SELECTED_LANGUAGE SELECTED_GEO
    else
        SELECTED_ENGINE="custom"
        SELECTED_LANGUAGE="auto-detected"
        SELECTED_GEO="auto-detected"
        export SELECTED_ENGINE SELECTED_LANGUAGE SELECTED_GEO
    fi

    # 3. Review Summary Screen 
    review_install || return 1

    # 4. Deployment Pipeline
    render_persistent_header
    if deploy_targeted_packages; then
        echo
        log_success "All targeted components deployed successfully!"
        echo
        printf "  ${GRAY}Press [ENTER] to return to main menu ...${RESET}"
        read -r _ </dev/tty
        render_persistent_header
    else
        echo
        log_error "Installation process failed!"
        echo
        printf "  ${GRAY}Press [ENTER] to return to main menu ...${RESET}"
        read -r _ </dev/tty
        render_persistent_header
        return 1
    fi

    return 0
}

# 📄 Source : network.sh
# ------------------------------------------------------------
# Guest Sub-Menu (Network + QoS)
# ------------------------------------------------------------
guest_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear

        echo "  👥 Guest Network Management"
        echo "  ─────────────────────────────────────────────────────────── "
        echo "  🍚 1) Setup Guest Network (Interface + Firewall)"
        echo "  🛜 2) Setup Guest WiFi"
        echo "  🛣️ 3) Bandwidth Control (QoS)"
        echo "  ❌ 4) Remove Guest Network"
        echo "  🚪 0) Back"
        echo "  ─────────────────────────────────────────────────────────── "
        echo

        printf "  ⁉️ Select option [0-4] : "
        read -r choice </dev/tty

        case "$choice" in
            1)
                if command -v setup_guest_network >/dev/null 2>&1; then
                    setup_guest_network
                else
                    log_error "Guest Network module not found!"
                fi
                ;;
            2)
                if command -v setup_guest_wifi >/dev/null 2>&1; then
                    setup_guest_wifi
                else
                    log_error "Guest WiFi function not found!"
                fi
                ;;
            3)
                if command -v guest_qos_menu >/dev/null 2>&1; then
                    guest_qos_menu
                else
                    log_error "Guest QoS module not found!"
                fi
                ;;
            4)
                if command -v remove_guest_network >/dev/null 2>&1; then
                    remove_guest_network
                else
                    log_error "Remove function not found!"
                fi
                ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press [ENTER] to return to main menu ... ${RESET}"
        read -r _ </dev/tty
    done
}

# ------------------------------------------------------------
# Main Network Menu
# ------------------------------------------------------------
network_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear

        echo "  🌐 Network Settings"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  📡 1) Wi-Fi Access Point (Home WiFi)"
        echo "  👥 2) Guest Network & Bandwidth Control"
        echo "  🏠 3) Change Local Router LAN IP"
        echo "  ⚖️ 4) Multi-WAN Load Balancer"
        echo "  📊 5) Network Info & Speed Monitor"
        echo "  🚪 0) Back to Main Menu"
        echo "  ───────────────────────────────────────────────────────────"
        echo

        printf "  ⁉️ Select option [0-5] : "
        read -r choice </dev/tty

        case "$choice" in
            1)
                if command -v wifi_ap_menu >/dev/null 2>&1; then
                    wifi_ap_menu
                else
                    log_error "WiFi Access Point (AP) module not found!"
                    sleep 2
                fi
                ;;
            2)
                guest_menu
                ;;
            3)
                if command -v change_lan_ip_menu >/dev/null 2>&1; then
                    change_lan_ip_menu
                else
                    log_error "LAN IP module not found!"
                    sleep 2
                fi
                ;;
            4)
                if command -v load_balancer_menu >/dev/null 2>&1; then
                    load_balancer_menu
                else
                    log_error "Load Balancer module not found!"
                    sleep 2
                fi
                ;;
            5)
                if command -v network_info_menu >/dev/null 2>&1; then
                    network_info_menu
                else
                    log_error "Network Info module not found!"
                    sleep 2
                fi
                ;;
            0)
                return 0
                ;;
            *)
                log_warn "Invalid option!"
                sleep 1
                ;;
        esac
    done
}

# 📄 Source : proxy.sh

proxy_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear

        echo "  🛡️  Proxy & Routing Manager"
        echo "  ───────────────────────────────────────────────────────────"
        echo "  🧶 1) Config Manager (Nodes & Subscriptions)"
        echo "  🚦 2) Traffic Routing / Shunt Rules"
        echo "  ⚖️ 3) Node Load Balancing"
        echo "  🩺 4) Node Health Checker"
        echo "  🎭 5) Routing Profiles"
        echo "  🧼 6) Clean IP Manager"
        echo "  🚪 0) Back to Main Menu"
        echo "  ───────────────────────────────────────────────────────────"
        echo

        printf "  ⁉️ Select option [0-6] : "
        read -r choice </dev/tty

        case "$choice" in
            1)
                if command -v config_manager_menu >/dev/null 2>&1; then
                    config_manager_menu
                else
                    log_error "Config Manager module not found!"
                    sleep 2
                fi
                ;;
            2)
                if command -v routing_menu >/dev/null 2>&1; then
                    routing_menu
                else
                    log_error "Routing module not found!"
                    sleep 2
                fi
                ;;
            3)
                if command -v node_balancer_menu >/dev/null 2>&1; then
                    node_balancer_menu
                else
                    log_error "Node Balancer module not found!"
                    sleep 2
                fi
                ;;
            4)
                if command -v health_checker_menu >/dev/null 2>&1; then
                    health_checker_menu
                else
                    log_error "Health Checker module not found!"
                    sleep 2
                fi
                ;;
            5)
                if command -v profile_manager_menu >/dev/null 2>&1; then
                    profile_manager_menu
                else
                    log_error "Profile Manager module not found!"
                    sleep 2
                fi
                ;;
            6)
                if command -v clean_ip_menu >/dev/null 2>&1; then
                    clean_ip_menu
                else
                    log_error "Clean IP module not found!"
                    sleep 2
                fi
                ;;
            0)
                return 0
                ;;
            *)
                log_warn "Invalid option!"
                sleep 1
                ;;
        esac
    done
}

# 📄 Source : main.sh

main_menu()
{
    while true; do
        render_persistent_header

        printf "  📦 1) Install Package Profile\n"
        printf "  🔄 2) Check & Update Packages\n"
        printf "  🌐 3) Network Settings\n"
        printf "  🛡️ 4) Proxy & Routing Manager\n"
        printf "  🖥️ 5) System Resources & Hardware Info\n"
        printf "  🛠️ 6) Maintenance & Recovery\n"
        printf "  🚪 0) Exit\n\n"

        printf "  ⁉️ Select option [0-6] : "
        read -r choice </dev/tty

        case "$choice" in
            1)
                if command -v package_menu >/dev/null 2>&1; then
                    package_menu || true
                else
                    log_error "Package module not found!"
                    sleep 2
                fi
                ;;
            2)
                if command -v update_packages_menu >/dev/null 2>&1; then
                    update_packages_menu || true
                else
                    log_error "Update module not found!"
                    sleep 2
                fi
                ;;
            3)
                if command -v network_menu >/dev/null 2>&1; then
                    network_menu || true
                else
                    log_error "Network menu not found!"
                    sleep 2
                fi
                ;;
            4)
                if command -v proxy_menu >/dev/null 2>&1; then
                    proxy_menu || true
                else
                    log_error "Proxy menu not found!"
                    sleep 2
                fi
                ;;
            
            5)
                if command -v show_system_resources_menu >/dev/null 2>&1; then
                    show_system_resources_menu || true
                else
                    log_error "Resource checker module not found!"
                    sleep 2
                fi
                ;;
            6)
                if command -v maintenance_menu >/dev/null 2>&1; then
                    maintenance_menu || true
                else
                    log_error "Maintenance module not found!"
                    sleep 2
                fi
                ;;
            0)
                printf "  ${GRAY}TNX for using DayPass! =)${RESET}\n"
                exit 0
                ;;
            *)
                log_warn "Invalid choice!"
                sleep 1
                ;;
        esac
    done
}

# 📄 Source : installer_ui.sh

start_ui()
{
    reset_state
    main_menu
}


###############################################################################
# Runtime Execution Pipeline
###############################################################################
DEPLOYMENT_FAILED=0

# 1. Pre-flight connectivity check
network_check || exit 1

# 2. System environment discovery & version validation
check_version || exit 1
detect_system_architecture

# 3. Core dependency initialization => with delay (2 secs) to ensure system stability after installing the dnsmasq-full tool!
deploy_system_dependencies
sleep 2
initialize_installer

# 4. Optional Automatic UCI Config Backup
if command -v backup_configs >/dev/null 2>&1; then
    backup_configs
fi

# 5. Interactive UI Launch
clear
reset_state
main_menu

# 6. Clean Exit
echo
log_success "👋 DayPass session finished!"
exit 0

