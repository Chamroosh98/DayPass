#!/bin/sh

# 🛑 SIGINT / SIGTERM Handler
cleanup_and_exit() {
    printf "\r\033[K"
    echo ""
    
    if command -v log_warn >/dev/null 2>&1; then
        log_warn "Installation cancelled by user. Exiting DayPass..."
    else
        echo "⚠️ Installation cancelled by user. Exiting..."
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

    log_info "Downloading architecture manifest from : [$REPO_URL/manifest.json]"
    
    # 4. Download manifest using resilient fallback mechanisms (curl -> wget -> uclient-fetch)
    DOWNLOAD_SUCCESS=0

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$REPO_URL/manifest.json" -o "$MANIFEST_FILE" && DOWNLOAD_SUCCESS=1
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$MANIFEST_FILE" "$REPO_URL/manifest.json" && DOWNLOAD_SUCCESS=1
    elif command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -q -O "$MANIFEST_FILE" "$REPO_URL/manifest.json" && DOWNLOAD_SUCCESS=1
    else
        log_error "No network download utility found (curl, wget, or uclient-fetch)!"
        exit 1
    fi

    # 5. Verify downloaded file presence and size
    if [ "$DOWNLOAD_SUCCESS" -ne 1 ] || [ ! -s "$MANIFEST_FILE" ]; then
        log_error "Failed to download or received empty manifest from [$REPO_URL/manifest.json]"
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
        log_warn "Available architectures in current manifest:"
        
        jq -r '.architectures[].name' "$MANIFEST_FILE" 2>/dev/null | sed 's/^/   • /'
        
        exit 1
    fi

    # 10. Success confirmation & environment export
    log_success "Manifest loaded & verified for architecture : [$ARCH]"

    export ARCH
    export TMP_DIR
    export MANIFEST_FILE
}