#!/bin/sh

###############################################################################
# DayPass Installer (Auto-generated via Go Action)
###############################################################################

# Dynamic REPO_URL configuration
if [ -z "${REPO_URL:-}" ]; then
    REPO_URL="https://chamroosh98.github.io/DayPass"
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
    W_LOGO="${BOLD}${WHITE}"
    R_LOGO="${BOLD}${RED}"
    VERSION="v2.1.0-beta" 

    echo

    printf "${W_LOGO}          .=:   :-+++=-.${RESET}\n"
    printf "${W_LOGO}      .-+*##- :*##+==*##=${RESET}\n"
    printf "${W_LOGO}      =#*###:.##+     =*#-    ${RED}____              ${GRAY}____${YELLOW} %s${RESET}\n" "$VERSION"
    printf "${W_LOGO}      .  **#: ***:   .+#*.    ${RED}|  _ \  __ _ _   _${GRAY}|  _ \  __ _ ___ ___${RESET}\n"
    printf "${R_LOGO}        .**#: .+***++*+=.     ${RED}| | | |/ _\` | | | |${GRAY}| |_) / _\` / __/ __|${RESET}\n"
    printf "${R_LOGO}        .***:.+**+=-::::-:    ${RED}| |_| | (_| | |_| |${GRAY}|  __/ (_| \__ \__ \\\\${RESET}\n"
    printf "${R_LOGO}        .***:=+=:      :--.   ${RED}|____/ \__,_|\__, |${GRAY}|_|   \__,_|___/___/${RESET}\n"
    printf "${R_LOGO}        .***::-:       :--.   ${RED}             |___/${RESET}\n"
    printf "${R_LOGO}        .++*. :--:....:--:    ${WHITE}🐱 github.com/Chamroosh98${RESET}\n"
    printf "${R_LOGO}        .+++:  .::::::--:     ${RESET}\n"
    printf "${R_LOGO}       =+++++=     .:::.      ${RESET}\n"
    printf "${R_LOGO}       .......  .::::.        ${RESET}\n"

    echo
    printf "  ${GRAY}───────────────────── 🕊️ Remembering the IRAN Massacre on Jan 8-9, 2026 ─────────────────────${RESET}\n"
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
        log_warn "Standard OpenWrt release file unreadable. Fallback architecture : [$ARCH]"
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

# 📄 Source : package_manager.sh

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
        log_warn "Standard APK installation failed for [$PACKAGE_NAME]. Trying IPv4 fallback..." 2>/dev/null
        if apk add --force-ipv4 --no-cache --allow-untrusted "$PACKAGE_NAME" >/dev/null 2>&1; then
            log_success "Package [$PACKAGE_NAME] installed successfully via APK (IPv4 fallback)." 2>/dev/null
            return 0
        fi

        log_error "APK failed to install package : [$PACKAGE_NAME]" 2>/dev/null
        return 1

    elif [ "$PKG_MANAGER" = "opkg" ]; then
        # Install with opkg bypassing unverified signature warnings
        if opkg install --force-checksum "$PACKAGE_NAME" >/dev/null 2>&1; then
            log_success "Package [$PACKAGE_NAME] installed successfully via OPKG." 2>/dev/null
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

    log_info "Setting up required system components for DayPass (OpenWrt v$OW_MAJOR_VER)..."

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

# 📄 Source : version_check.sh

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
        log_info "OpenWrt Version : ${OPENWRT_VERSION} (Engine: ${PKG_MANAGER})"
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
        printf "  ${YELLOW:-}⚠️  jq is missing! Install via: %s${RESET:-}\n\n" "$PKG_CMD"
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
        printf "  ⬅️ ${CYAN:-}0${RESET:-}) Back to Main Menu\n\n"
        
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
    echo "   1) ☁️ Cloudflare DNS   (1.1.1.1)                          "
    echo "   2) 🔍 Google DNS       (8.8.8.8)                          "
    echo "   3) 🛡️ Quad9 DNS        (9.9.9.9)                          "
    
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

    printf "  ⁉️  Select option [1-%s] (Default: 1) : " "$MAX_OPT"
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
                log_info "Skipping DNS fix."
            fi
            ;;
        *)
            log_info "Skipping DNS fix."
            ;;
    esac
}

# Standalone execution handler
case "$0" in
    *dns_fix.sh) dns_fix_menu ;;
esac

# 📄 Source : wifi_setup.sh

setup_guest_firewall_and_network()
{
    log_info "Configuring Isolated Guest Network Zone..."

    # 1. Create Guest Network Interface
    uci set network.guest=interface
    uci set network.guest.proto='static'
    uci set network.guest.ipaddr='192.168.200.1'
    uci set network.guest.netmask='255.255.255.0'

    # 2. Setup DHCP for Guest Zone
    uci set dhcp.guest=dhcp
    uci set dhcp.guest.interface='guest'
    uci set dhcp.guest.start='100'
    uci set dhcp.guest.limit='150'
    uci set dhcp.guest.leasetime='12h'

    # 3. Setup Firewall Zone (Isolate from LAN, allow WAN/Internet & DNS/DHCP)
    uci set firewall.guest=zone
    uci set firewall.guest.name='guest'
    uci set firewall.guest.network='guest'
    uci set firewall.guest.input='REJECT'
    uci set firewall.guest.output='ACCEPT'
    uci set firewall.guest.forward='REJECT'

    # Allow Forwarding to WAN
    uci set firewall.guest_forward_wan=forwarding
    uci set firewall.guest_forward_wan.src='guest'
    uci set firewall.guest_forward_wan.dest='wan'

    # Allow DNS & DHCP Requests
    uci set firewall.guest_dns=rule
    uci set firewall.guest_dns.name='Allow Guest DNS'
    uci set firewall.guest_dns.src='guest'
    uci set firewall.guest_dns.dest_port='53'
    uci set firewall.guest_dns.proto='tcpudp'
    uci set firewall.guest_dns.target='ACCEPT'

    uci set firewall.guest_dhcp=rule
    uci set firewall.guest_dhcp.name='Allow Guest DHCP'
    uci set firewall.guest_dhcp.src='guest'
    uci set firewall.guest_dhcp.dest_port='67-68'
    uci set firewall.guest_dhcp.proto='udp'
    uci set firewall.guest_dhcp.target='ACCEPT'

    uci commit network
    uci commit dhcp
    uci commit firewall
    /etc/init.d/network restart >/dev/null 2>&1
    /etc/init.d/firewall restart >/dev/null 2>&1
}

wifi_menu()
{
    render_persistent_header 2>/dev/null || clear

    echo "   🛜 Advanced WiFi & Guest Network Setup                    "
    echo "  ───────────────────────────────────────────────────────────"

    RADIOS=""
    if [ -f /etc/config/wireless ]; then
        RADIOS=$(uci show wireless | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1)
    fi

    if [ -z "$RADIOS" ]; then
        wifi config 2>/dev/null
        RADIOS=$(uci show wireless 2>/dev/null | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1)
    fi

    if [ -z "$RADIOS" ]; then
        log_error "No wireless hardware detected!"
        sleep 2
        return 1
    fi

    # UX Improvement: Ask SSID Strategy
    echo "  ⚙️ How do you want to configure your Main WiFi SSIDs?"
    echo "   1) Single SSID for All Bands (Smart Connect / Unified Name)"
    echo "   2) Custom SSID per Band (e.g., Home_2.4G and Home_5G)"
    echo "  ───────────────────────────────────────────────────────────"
    printf "  Select Option [1/2] : "
    read -r ssid_mode </dev/tty

    MAIN_SSID_2G=""
    MAIN_SSID_5G=""
    
    if [ "$ssid_mode" = "2" ]; then
        printf "  ✏️ Enter 2.4GHz SSID Name [Default: DayPass-2.4G]: "
        read -r MAIN_SSID_2G </dev/tty
        [ -z "$MAIN_SSID_2G" ] && MAIN_SSID_2G="DayPass-2.4G"

        printf "  ✏️ Enter 5GHz SSID Name [Default: DayPass-5G]: "
        read -r MAIN_SSID_5G </dev/tty
        [ -z "$MAIN_SSID_5G" ] && MAIN_SSID_5G="DayPass-5G"
    else
        printf "  ✏️ Enter Unified SSID Name [Default: DayPass-WiFi]: "
        read -r unified_ssid </dev/tty
        [ -z "$unified_ssid" ] && unified_ssid="DayPass-WiFi"
        MAIN_SSID_2G="$unified_ssid"
        MAIN_SSID_5G="$unified_ssid"
    fi

    while true; do
        printf "  🔑 Enter Main WiFi Password (Min 8 chars) : "
        read -r user_pass </dev/tty
        if [ ${#user_pass} -ge 8 ]; then
            break
        else
            log_error "Password must be at least 8 characters long!"
        fi
    done

    # Configure Main WiFi
    idx=0
    for radio in $RADIOS; do
        uci set "wireless.$radio.disabled"='0'
        band=$(uci -q get "wireless.$radio.band" || uci -q get "wireless.$radio.hwmode" || echo "")

        IFACE_KEY="default_$radio"
        if ! uci -q get "wireless.$IFACE_KEY" >/dev/null; then
            IFACE_KEY="wifinet${idx}"
            uci set "wireless.$IFACE_KEY"=wifi-iface
            uci set "wireless.$IFACE_KEY.device"="$radio"
            uci set "wireless.$IFACE_KEY.mode"='ap'
            uci set "wireless.$IFACE_KEY.network"='lan'
        fi

        # Assign SSID based on Band
        case "$band" in
            *5g*|*a*|*ac*|*ax*) CHOSEN_SSID="$MAIN_SSID_5G" ;;
            *)                  CHOSEN_SSID="$MAIN_SSID_2G" ;;
        esac

        uci set "wireless.$IFACE_KEY.ssid"="$CHOSEN_SSID"
        uci set "wireless.$IFACE_KEY.encryption"='psk2'
        uci set "wireless.$IFACE_KEY.key"="$user_pass"
        uci set "wireless.$IFACE_KEY.disabled"='0'

        log_success "Configured Main WiFi [$radio] -> $CHOSEN_SSID"
        idx=$((idx + 1))
    done

    # Ask for Guest WiFi
    echo
    echo "  ───────────────────────────────────────────────────────────"
    printf "  👥 Do you want to enable an Isolated Guest WiFi Network? [y/N] : "
    read -r enable_guest </dev/tty

    case "$enable_guest" in
        y|Y)
            setup_guest_firewall_and_network

            printf "  ✏️ Enter Guest WiFi SSID [Default: DayPass-Guest]: "
            read -r guest_ssid </dev/tty
            [ -z "$guest_ssid" ] && guest_ssid="DayPass-Guest"

            while true; do
                printf "  🔑 Enter Guest WiFi Password (Min 8 chars) : "
                read -r guest_pass </dev/tty
                if [ ${#guest_pass} -ge 8 ]; then
                    break
                else
                    log_error "Guest Password must be at least 8 characters long!"
                fi
            done

            for radio in $RADIOS; do
                band=$(uci -q get "wireless.$radio.band" || uci -q get "wireless.$radio.hwmode" || echo "")
                GUEST_IFACE="guest_$radio"

                # Differentiate Guest SSID per band if using custom mode
                CURR_GUEST_SSID="$guest_ssid"
                if [ "$ssid_mode" = "2" ]; then
                    case "$band" in
                        *5g*|*a*|*ac*|*ax*) CURR_GUEST_SSID="${guest_ssid}_5G" ;;
                        *)                  CURR_GUEST_SSID="${guest_ssid}_2.4G" ;;
                    esac
                fi

                uci set "wireless.$GUEST_IFACE"=wifi-iface
                uci set "wireless.$GUEST_IFACE.device"="$radio"
                uci set "wireless.$GUEST_IFACE.mode"='ap'
                uci set "wireless.$GUEST_IFACE.network"='guest'
                uci set "wireless.$GUEST_IFACE.ssid"="$CURR_GUEST_SSID"
                uci set "wireless.$GUEST_IFACE.encryption"='psk2'
                uci set "wireless.$GUEST_IFACE.key"="$guest_pass"
                uci set "wireless.$GUEST_IFACE.isolate"='1' # Prevent client-to-client traffic
                uci set "wireless.$GUEST_IFACE.disabled"='0'

                log_success "Configured Guest WiFi [$radio] -> $CURR_GUEST_SSID"
            done
            ;;
        *)
            log_info "Guest WiFi setup skipped."
            ;;
    esac

    uci commit wireless
    wifi reload 2>/dev/null || /etc/init.d/network restart

    echo
    log_success "WiFi Settings Applied Successfully!"
    echo
    printf "  ${GRAY}Press [ENTER] to continue ...${RESET}"
    read -r _ </dev/tty
}

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

    echo "  🌐 Local LAN IP Subnet Configuration                    "
    echo "  ───────────────────────────────────────────────────────────"
    echo "  📌 Current Router LAN IP : ${CYAN}${CURRENT_IP}${RESET}"
    echo "  ───────────────────────────────────────────────────────────"
    echo "  💡 Note : Changing LAN IP prevents 'IP Conflicts' if your"
    echo "     upstream ISP Modem is also using 192.168.1.1."
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
            log_error "Invalid IP address format! Please try again."
        fi
    done

    if [ "$NEW_IP" = "$CURRENT_IP" ]; then
        log_warn "New IP is identical to current IP. Nothing changed."
        sleep 2
        return 0
    fi

    log_info "Updating LAN IP address to [$NEW_IP]..."

    uci set network.lan.ipaddr="$NEW_IP"
    uci commit network

    echo
    log_warn "NETWORK RESTART REQUIRED!"
    log_warn "After applying, your terminal/SSH session will disconnect."
    log_warn "Reconnect to LuCI / SSH using the new IP: ${GREEN}http://${NEW_IP}${RESET}"
    echo

    printf "  ⁉️ Apply changes now and restart network? [y/N] : "
    read -r apply_confirm </dev/tty

    case "$apply_confirm" in
        y|Y)
            log_info "Restarting network stack..."
            (/etc/init.d/network restart >/dev/null 2>&1 &)
            log_success "LAN IP updated to $NEW_IP! Goodbye!"
            exit 0
            ;;
        *)
            log_warn "Changes saved to UCI, but network restart skipped."
            sleep 2
            ;;
    esac
}

# 📄 Source : load_balancer.sh

install_mwan3_deps()
{
    log_info "Installing Load Balancer & USB Tethering dependencies ..."

    PKGS_OPKG="mwan3 luci-app-mwan3 bmon kmod-usb-net-rndis kmod-usb-net-cdc-ncm kmod-nls-base kmod-usb-core kmod-usb-net kmod-usb-net-cdc-ether kmod-usb2 kmod-usb-net-ipheth usbmuxd libimobiledevice usbutils"
    PKGS_APK="mwan3 luci-app-mwan3 bmon kmod-usb-net-rndis kmod-usb-net-cdc-ncm kmod-nls-base kmod-usb-core kmod-usb-net kmod-usb-net-cdc-ether kmod-usb2 kmod-usb-net-ipheth usbmuxd libimobiledevice usbutils"

    if [ "${PKG_MANAGER:-opkg}" = "apk" ]; then
        apk update >/dev/null 2>&1
        for pkg in $PKGS_APK; do
            apk add "$pkg" >/dev/null 2>&1 || log_warn "Failed or already installed: $pkg"
        done
    else
        opkg update >/dev/null 2>&1
        for pkg in $PKGS_OPKG; do
            opkg install "$pkg" >/dev/null 2>&1 || log_warn "Failed or already installed: $pkg"
        done
    fi

    # Enable usbmuxd autostart for iOS Tethering
    if command -v usbmuxd >/dev/null 2>&1; then
        if ! grep -q "usbmuxd" /etc/rc.local 2>/dev/null; then
            sed -i -e "\$i usbmuxd -v &" /etc/rc.local
        fi
        usbmuxd -v >/dev/null 2>&1 &
    fi

    log_success "Dependencies installed successfully!"
}

setup_usb_tethering_interface()
{
    log_info "Setting up USB Tethering WAN Interface (wan_usb) ..."
    
    # Check for usb0 device
    USB_DEV=""
    if ip link show usb0 >/dev/null 2>&1; then
        USB_DEV="usb0"
    elif ip link show eth1 >/dev/null 2>&1; then
        USB_DEV="eth1"
    fi

    if [ -z "$USB_DEV" ]; then
        log_warn "No USB Tethering device detected (usb0/eth1)!"
        log_warn "Make sure your Android/iPhone USB Tethering is enabled."
        USB_DEV="usb0" # Fallback assign
    fi

    uci set network.wan_usb=interface
    uci set network.wan_usb.proto='dhcp'
    uci set network.wan_usb.device="$USB_DEV"
    uci set network.wan_usb.metric='20' # Higher metric for secondary WAN
    
    # Firewalld Zone Setup
    uci add_list firewall.@zone[1].network='wan_usb' 2>/dev/null || true

    uci commit network
    uci commit firewall
    log_success "Created interface [wan_usb] attached to $USB_DEV"
}

setup_wifi_wwan_interface()
{
    render_persistent_header 2>/dev/null || clear
    echo "  📡 Setup Wi-Fi Repeater / Hotspot (WWAN)                  "
    echo "  ───────────────────────────────────────────────────────────"

    RADIO=$(uci show wireless 2>/dev/null | grep "=wifi-device" | head -n1 | cut -d'.' -f2 | cut -d'=' -f1)
    if [ -z "$RADIO" ]; then
        log_error "No Wi-Fi radio hardware available for Wireless WAN!"
        return 1
    fi

    printf "  ✏️ Enter Target Wi-Fi SSID (Hotspot Name) : "
    read -r target_ssid </dev/tty
    [ -z "$target_ssid" ] && return 1

    printf "  🔑 Enter Target Wi-Fi Password : "
    read -r target_pass </dev/tty

    # Setup Wireless Station (Client)
    uci set network.wwan=interface
    uci set network.wwan.proto='dhcp'
    uci set network.wwan.metric='30'

    IFACE_KEY="sta_$RADIO"
    uci set wireless.$IFACE_KEY=wifi-iface
    uci set wireless.$IFACE_KEY.device="$RADIO"
    uci set wireless.$IFACE_KEY.mode='sta'
    uci set wireless.$IFACE_KEY.network='wwan'
    uci set wireless.$IFACE_KEY.ssid="$target_ssid"
    if [ -n "$target_pass" ]; then
        uci set wireless.$IFACE_KEY.encryption='psk2'
        uci set wireless.$IFACE_KEY.key="$target_pass"
    else
        uci set wireless.$IFACE_KEY.encryption='none'
    fi

    uci add_list firewall.@zone[1].network='wwan' 2>/dev/null || true

    uci commit network
    uci commit wireless
    uci commit firewall
    wifi reload 2>/dev/null || /etc/init.d/network restart
    log_success "Wi-Fi WWAN interface configured to join [$target_ssid]!"
}

configure_mwan3_engine()
{
    log_info "Configuring mwan3 Load Balancing & Failover Rules..."

    # Enable mwan3 global
    uci set mwan3.globals=globals
    uci set mwan3.globals.mmx_mask='0x3f00'

    # 1. Primary Ethernet WAN
    uci set mwan3.wan=interface
    uci set mwan3.wan.enabled='1'
    uci set mwan3.wan.family='ipv4'
    uci add_list mwan3.wan.track_ip='1.1.1.1'
    uci add_list mwan3.wan.track_ip='8.8.8.8'
    uci set mwan3.wan.reliability='1'
    uci set mwan3.wan.count='1'
    uci set mwan3.wan.timeout='2'

    # 2. USB WAN
    uci set mwan3.wan_usb=interface
    uci set mwan3.wan_usb.enabled='1'
    uci set mwan3.wan_usb.family='ipv4'
    uci add_list mwan3.wan_usb.track_ip='1.0.0.1'
    uci add_list mwan3.wan_usb.track_ip='8.8.4.4'
    uci set mwan3.wan_usb.reliability='1'
    uci set mwan3.wan_usb.count='1'
    uci set mwan3.wan_usb.timeout='2'

    # 3. WWAN (Wi-Fi)
    uci set mwan3.wwan=interface
    uci set mwan3.wwan.enabled='1'
    uci set mwan3.wwan.family='ipv4'
    uci add_list mwan3.wwan.track_ip='9.9.9.9'
    uci set mwan3.wwan.reliability='1'

    # Define Members (Weights)
    uci set mwan3.wan_m1=member
    uci set mwan3.wan_m1.interface='wan'
    uci set mwan3.wan_m1.metric='1'
    uci set mwan3.wan_m1.weight='3'

    uci set mwan3.usb_m1=member
    uci set mwan3.usb_m1.interface='wan_usb'
    uci set mwan3.usb_m1.metric='1'
    uci set mwan3.usb_m1.weight='3'

    uci set mwan3.wwan_m1=member
    uci set mwan3.wwan_m1.interface='wwan'
    uci set mwan3.wwan_m1.metric='1'
    uci set mwan3.wwan_m1.weight='2'

    # Create Combined Balanced Policy
    uci set mwan3.balanced=policy
    uci add_list mwan3.balanced.use_member='wan_m1'
    uci add_list mwan3.balanced.use_member='usb_m1'
    uci add_list mwan3.balanced.use_member='wwan_m1'

    # Apply Policy to Default Rule
    uci set mwan3.default_rule=rule
    uci set mwan3.default_rule.dest_ip='0.0.0.0/0'
    uci set mwan3.default_rule.use_policy='balanced'

    uci commit mwan3
    /etc/init.d/mwan3 enable
    /etc/init.d/mwan3 restart
    log_success "mwan3 Engine successfully configured and started!"
}

load_balancer_menu()
{
    render_persistent_header 2>/dev/null || clear

    echo "  ⚖️ Multi-WAN Load Balancer Setup (mwan3)                 "
    echo "  ───────────────────────────────────────────────────────────"
    echo "  1) 📦 Install Dependencies (mwan3, USB Tethering drivers) "
    echo "  2) 📱 Configure USB Tethering WAN (Android / iPhone)      "
    echo "  3) 📡 Configure Wi-Fi Hotspot WAN (WWAN Client Mode)      "
    echo "  4) ⚡ Auto-Setup Combined Load Balancing (Balanced Policy)"
    echo "  5) 📊 Show Live WAN Status & Monitor                       "
    echo "  ───────────────────────────────────────────────────────────"
    echo

    printf "  ⁉️ Select option [1-5] : "
    read -r choice </dev/tty

    case "$choice" in
        1)
            install_mwan3_deps
            ;;
        2)
            setup_usb_tethering_interface
            ;;
        3)
            setup_wifi_wwan_interface
            ;;
        4)
            configure_mwan3_engine
            ;;
        5)
            if command -v mwan3 >/dev/null 2>&1; then
                mwan3 status
            else
                log_error "mwan3 is not installed!"
            fi
            ;;
        *)
            log_warn "Invalid choice!"
            ;;
    esac

    echo
    printf "  ${GRAY}Press [ENTER] to return to menu ...${RESET}"
    read -r _ </dev/tty
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
    printf "  ${YELLOW}⚠️ The following packages will be REMOVED:${RESET}\n"
    printf "  ${CYAN}%s${RESET}\n\n" "$INSTALLED_PKGS"

    printf "  Are you sure you want to purge these packages? [y/N]: "
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
        log_info "Factory reset aborted."
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
        
        printf "  🛠️  ${BOLD}DayPass Maintenance & Recovery${RESET}\n"
        printf "  ──────────────────────────────────────────────────\n"
        printf "  🧹 1) Purge DayPass Installed Packages\n"
        printf "  🗑️ 2) Clean Temporary Cache & Downloads\n"
        printf "  💾 3) Backup System Configuration\n"
        printf "  🚨 4) Factory Reset OpenWrt (Firstboot)\n"
        printf "  🚪 0) Back to Main Menu\n\n"

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
    log_info "=================================================="
    log_info "Initiating Post-Install Service Operations"
    log_info "=================================================="
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
        log_success "DNS subsystem reloaded."
    fi

    # 3. Reload firewall rules
    if service_exists "firewall"; then
        log_info "Reloading system firewall rules ..."
        /etc/init.d/firewall reload >/dev/null 2>&1
        log_success "Firewall rules updated."
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
            printf "⚠️${YELLOW:-}High latency or degraded response time detected.${RESET:-}\n"
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

# 📄 Source : install_core.sh

# 🛑 SIGINT / SIGTERM Handler
cleanup_and_exit() {
    printf "\r\033[K"
    echo ""
    
    if command -v log_warn >/dev/null 2>&1; then
        log_warn "Installation cancelled by user. Exiting DayPass ..."
    else
        echo "⚠️ Installation cancelled by user. Exiting ..."
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
        log_error "REPO_URL environment variable is not defined!"
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
        log_error "Failed to download or received empty manifest from [$MANIFEST_TARGET_URL]"
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
    log_info "Manifest Metadata -> Release: [$MANIFEST_REL] | Generated At: [$MANIFEST_GEN]"

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
    echo "  📊 DayPass Deployment Efficiency Summary"
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

    echo "  🖥️  System Hardware & Resource Status"
    echo "  ──────────────────────────────────────────────────────────"
    printf "   🩻 Architecture      : ${CYAN}%s${RESET}\n" "${ARCH:-N/A}"
    printf "   💡 OpenWrt System    : ${CYAN}%s%s [%s]${RESET}\n" "$OW_VER" "$OW_DATE" "${PKG_MANAGER:-opkg}"
    echo "  ──────────────────────────────────────────────────────────"
    printf "   🧠 Total RAM         : %s\n" "$(human_readable_bytes "$tot_ram_b")"
    printf "   📈 Used RAM          : ${YELLOW}%s${RESET}\n" "$(human_readable_bytes "$used_ram_b")"
    printf "   🟢 Free RAM          : ${GREEN}%s${RESET}\n" "$(human_readable_bytes "$free_ram_b")"
    echo "  ──────────────────────────────────────────────────────────"
    printf "   💾 Total Storage     : %s\n" "$(human_readable_bytes "$tot_flash_b")"
    printf "   📉 Used Storage      : ${YELLOW}%s${RESET}\n" "$(human_readable_bytes "$used_flash_b")"
    printf "   🟢 Free Storage      : ${GREEN}%s${RESET}\n" "$(human_readable_bytes "$free_flash_b")"
    echo "  ──────────────────────────────────────────────────────────"
    echo

    printf "  ${GRAY}Press [ENTER] to return to main menu ...${RESET}"
    read -r _ </dev/tty
}

# 📄 Source : package_resolver.sh

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

# 📄 Source : package_installer.sh

manifest_lookup()
{
    field="$1"
    package="$2"

    # جستجوی پویا در تمام Feedها به جای .packages[]
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
        log_error "Installation aborted due to system resource limits."
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
            echo "  📦 [$current_idx/$total_pkgs] Downloading $pkg... (Free RAM: ${curr_ram_fmt:-N/A})"
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
    log_warn "=================================================="
    log_warn "Initiating Selective Atomic Rollback Procedures ..."
    log_warn "=================================================="
    echo

    rm -f "$TMP_DIR"/*.part "$TMP_DIR"/*.apk "$TMP_DIR"/*.ipk 2>/dev/null

    if [ -s "$TRANSACTION_LOG" ]; then
        log_info "Rolling back modified packages from current session..."
        while read -r pkg; do
            [ -z "$pkg" ] && continue
            log_info "Rollback: Removing package [$pkg] ..."
            
            case "${PKG_MANAGER:-opkg}" in
                apk)  apk del "$pkg" >/dev/null 2>&1 || true ;;
                opkg|*) opkg remove "$pkg" >/dev/null 2>&1 || true ;;
            esac
        done < "$TRANSACTION_LOG"
    else
        log_info "No system packages were installed in this session. Skipping removal."
    fi

    rm -f "$TRANSACTION_LOG"
    log_success "Rollback procedure completed safely!"
}

# 📄 Source : package_updater.sh

inspect_and_confirm_updates()
{
    echo "  📦 DayPass Package Inspection Table"
    echo "  ──────────────────────────────────────────────────────────────────────────────────────────"
    printf "   %-28s %-16s %-16s %-12s\n" "Package" "Installed" "Manifest Ver" "Action"
    echo "  ──────────────────────────────────────────────────────────────────────────────────────────"

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

    echo "  ──────────────────────────────────────────────────────────────────────────────────────────"
    printf "   Summary: %d to install, %d to upgrade, %d skipped!\n" "$INSTALL_COUNT" "$UPGRADE_COUNT" "$SKIP_COUNT"
    echo "  ──────────────────────────────────────────────────────────────────────────────────────────"
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

# منوی اصلی ورود به آپدیت
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

# 📄 Source : menu_custom.sh

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

# 📄 Source : menu_mode.sh

handle_recommended_profile()
{
    SELECTED_PACKAGES=""
    export SELECTED_PACKAGES
}

menu_mode()
{
    render_persistent_header

    echo "    🕵️‍♀️ Select Installation Mode                              "
    echo "  ───────────────────────────────────────────────────────────"
    echo "    1) ⚡ Recommended (Quick & Pre-configured for users)     "
    echo "    2) 🛠️ Custom      (Advanced package selection)           "
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

# 📄 Source : engine_menu.sh

engine_menu()
{
    render_persistent_header

    echo "    🕵️‍♀️  Select Proxy Engine                                  "
    echo "  ───────────────────────────────────────────────────────────"
    echo "    1) ⚡ Auto      (Recommended)                            "
    echo "    2) ✖️ Xray      (Xray-core proxy engine)                 "
    echo "    3) 📦 Sing-box  (Sing-box proxy engine)                  "
    echo "  ───────────────────────────────────────────────────────────"
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
                    log_info "Reverting Proxy Engine selection to Auto."
                    SELECTED_ENGINE="auto"
                    ;;
            esac
            ;;
        *)
            log_warn "Invalid choice! Defaulting to Auto engine."
            SELECTED_ENGINE="auto"
            ;;
    esac

    export SELECTED_ENGINE
}

# 📄 Source : menu_language.sh

language_menu()
{
    if [ "$SELECTED_PROFILE" != "passwall2" ]; then
        SELECTED_LANGUAGE="en"
        export SELECTED_LANGUAGE
        return 0
    fi

    render_persistent_header

    echo "    🕵️‍♀️ Select Language (Passwall 2)                          "
    echo "  ───────────────────────────────────────────────────────────"
    echo "    1) 🦁☀️ Persian  (fa)                                    "
    echo "    2) 🇬🇧   English  (en)                                    "
    echo "    3) 🇨🇳   Chinese  (zh-cn)                                 "
    echo "    4) 🇷🇺   Russian  (ru)                                    "
    echo "  ───────────────────────────────────────────────────────────"
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

# 📄 Source : menu_geo.sh

geo_menu()
{
    render_persistent_header

    echo "    🕵️‍♀️ Select Geo Database                                   "
    echo "  ───────────────────────────────────────────────────────────"
    echo "    1) Skip       (Do not install Geo databases)             "
    echo "    2) Official   (Standard official release packages)       "
    echo "    3) Iran Full  (Custom ruleset - Full database)           "
    echo "    4) Iran Lite  (Custom ruleset - Compact database)        "
    echo "  ───────────────────────────────────────────────────────────"
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
            log_warn "Invalid choice! Defaulting to Skip."
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

# 📄 Source : menu_package.sh

package_menu()
{
    render_persistent_header

    echo "    🕵️‍♀️ Select Package Type                                   "
    echo "  ───────────────────────────────────────────────────────────"
    echo "    🔒 1) Passwall-1  (Legacy Stable Release)                "
    echo "    🔒 2) Passwall-2  (Modern Release - Recommended)         "
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

# 📄 Source : main_menu.sh

main_menu()
{
    while true; 
        do

            render_persistent_header
            
            printf "  📦 1) Install Package Profile\n"
            printf "  🔄 2) Check & Update Packages\n"
            printf "  📡 3) Configure WiFi & Guest Networks\n"
            printf "  🌐 4) Change Local Router LAN IP\n"
            printf "  ⚖️ 5) Multi-WAN Load Balancer (USB Tethering / Wi-Fi WAN)\n"
            printf "  🖥️ 6) Network Info & Speed Monitor\n"
            printf "  📊 7) System Resources & Hardware Info\n"
            printf "  🛠️ 8) Maintenance & Recovery\n"
            printf "  🚪 0) Exit\n\n"

            printf "  ⁉️ Select option [0-8] : "
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
                    if command -v wifi_menu >/dev/null 2>&1; then
                        wifi_menu || true
                    else
                        log_error "WiFi setup module not found!"
                        sleep 2
                    fi
                    ;;
                4)
                    if command -v change_lan_ip_menu >/dev/null 2>&1; then
                        change_lan_ip_menu || true
                    else
                        log_error "LAN IP module not found!"
                        sleep 2
                    fi
                    ;;
                5)
                    if command -v load_balancer_menu >/dev/null 2>&1; then
                        load_balancer_menu || true
                    else
                        log_error "Load Balancer module not found!"
                        sleep 2
                    fi
                    ;;
                6)
                    if command -v network_menu >/dev/null 2>&1; then
                        network_menu || true
                    else
                        log_error "Network monitor module not found!"
                        sleep 2
                    fi
                    ;;
                7)
                    if command -v show_system_resources_menu >/dev/null 2>&1; then
                        show_system_resources_menu || true
                    else
                        log_error "Resource checker module not found!"
                        sleep 2
                    fi
                    ;;
                8)
                    if command -v maintenance_menu >/dev/null 2>&1; then
                        maintenance_menu || true
                    else
                        log_error "Maintenance module not found!"
                        sleep 2
                    fi
                    ;;
                0)
                    printf "  ${GRAY:-}TNX for using DayPass! =)  \n${RESET:-}"
                    exit 0
                    ;;
                *)
                    log_warn "Invalid choice!"
                    sleep 2
                    clear
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

