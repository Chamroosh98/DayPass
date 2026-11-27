#!/bin/sh

cleanup_and_exit() {
    printf "\r\033[K"
    echo ""
    
    if command -v log_warn >/dev/null 2>&1; then
        log_warn "Installation cancelled by user. Exiting DayPass ..."
    else
        echo "  ⚠️ Installation cancelled by user. Exiting ..."
    fi

    stty echo 2>/dev/null
    [ -z "${MANIFEST_STAGE:-}" ] || rm -f "$MANIFEST_STAGE"
    
    echo ""
    exit 130
}

stty -echoctl 2>/dev/null || true

trap cleanup_and_exit INT TERM

initialize_installer()
{
    
    # 1. Detect package manager (opkg or apk)
    if command -v detect_package_manager >/dev/null 2>&1; then
        detect_package_manager
    fi

    log_info "Updating package database ..."
    if command -v pkg_update >/dev/null 2>&1; then
        pkg_update >/dev/null 2>&1 || log_warn "Index refresh failed; continuing with cached indexes for menu initialization."
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
    
    # 6. Detect host system target architecture
    if [ -z "${ARCH:-}" ]; then
        detect_system_architecture || return 1
    fi

    if [ -z "$ARCH" ]; then
        log_error "Unable to detect host system architecture!"
        exit 1
    fi

    log_info "Target System Architecture detected : [$ARCH]"

    command -v jq >/dev/null || { log_error "jq is required"; return 1; }
    MANIFEST_STAGE=$(mktemp "$TMP_DIR/manifest.XXXXXX") || return 1
    for client in curl wget uclient-fetch; do
        command -v "$client" >/dev/null || continue
        case "$client" in
            curl) curl -fsSL "$MANIFEST_TARGET_URL" -o "$MANIFEST_STAGE" ;;
            wget) wget -qO "$MANIFEST_STAGE" "$MANIFEST_TARGET_URL" ;;
            uclient-fetch) uclient-fetch -q -O "$MANIFEST_STAGE" "$MANIFEST_TARGET_URL" ;;
        esac || continue
        if jq -es --arg arch "$ARCH" --arg major "${MANIFEST_PATH#v}" '
            length == 1 and (.[0] |
                (.release | tostring | split(".")[0]) == ($major | split("/")[0])
                and any(.architectures[]; .name == $arch))
        ' "$MANIFEST_STAGE" >/dev/null 2>&1; then
            mv "$MANIFEST_STAGE" "$MANIFEST_FILE" || break
            MANIFEST_STAGE=
            break
        fi
    done
    if [ -n "$MANIFEST_STAGE" ]; then
        rm -f "$MANIFEST_STAGE"
        MANIFEST_STAGE=
        log_error "Could not fetch a valid manifest for $ARCH from $MANIFEST_TARGET_URL. Check the connection and retry."
        return 1
    fi

    # 10. Success confirmation & environment export
    log_success "Manifest loaded & verified for architecture : [$ARCH]"

    export ARCH
    export TMP_DIR
    export MANIFEST_FILE
}