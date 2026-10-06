#!/bin/sh
# DayPass persistent CLI.
# Installs /usr/bin/daypass and handles update, version, and uninstall.
# Safe to source. Subcommands exit. menu/default returns.

DAYPASS_CLI_URL_SUFFIX="/install.sh"

# beta when REPO_URL ends in /beta, otherwise stable.
daypass_cli_channel() {
    case "${REPO_URL:-}" in
        */beta|*/beta/) printf '%s\n' "beta" ;;
        *)               printf '%s\n' "stable" ;;
    esac
}

# Install path. /usr/sbin when /usr/bin is not writable. Empty when neither is.
daypass_cli_dest() {
    if [ -w /usr/bin ] || [ -w /usr/bin/daypass ]; then
        printf '%s\n' "/usr/bin/daypass"
        return 0
    fi
    if [ -w /usr/sbin ] || [ -w /usr/sbin/daypass ]; then
        printf '%s\n' "/usr/sbin/daypass"
        return 0
    fi
    return 1
}

# Absolute path of the running script, when it is a real file.
daypass_cli_self() {
    local self=""

    case "$0" in
        /*) self="$0" ;;
        */*) self="$0" ;;
        *)
            self=$(command -v "$0" 2>/dev/null || true)
            ;;
    esac
    [ -n "$self" ] && [ -f "$self" ] && [ -r "$self" ] || return 1
    if command -v readlink >/dev/null 2>&1; then
        self=$(readlink -f "$self" 2>/dev/null || printf '%s\n' "$self")
    fi
    printf '%s\n' "$self"
}

daypass_cli_fetch() {
    local url="$1"
    local dest="$2"

    if command -v wget >/dev/null 2>&1; then
        wget -qO "$dest" "$url" && return 0
    fi
    if command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -q -O "$dest" "$url" && return 0
    fi
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$dest" "$url" && return 0
    fi
    return 1
}

# Copy the running script onto the persistent CLI path.
# A pipe has no file to copy, so the same REPO_URL/install.sh is fetched again.
daypass_cli_ensure() {
    local dest self tmp

    dest=$(daypass_cli_dest) || {
        log_warn "Neither /usr/bin nor /usr/sbin is writable. DayPass will run this session only."
        return 0
    }

    self=$(daypass_cli_self 2>/dev/null || true)
    if [ -n "$self" ] && [ "$self" = "$dest" ]; then
        return 0
    fi
    if [ -n "$self" ] && [ -f "$dest" ] && cmp -s "$self" "$dest" 2>/dev/null; then
        return 0
    fi

    tmp="${dest}.new.$$"
    if [ -n "$self" ]; then
        cp "$self" "$tmp" || {
            log_error "Could not copy DayPass to [$dest]."
            rm -f "$tmp"
            return 1
        }
    else
        daypass_cli_fetch "${REPO_URL:-}${DAYPASS_CLI_URL_SUFFIX}" "$tmp" || {
            log_error "Could not download DayPass to [$dest]."
            rm -f "$tmp"
            return 1
        }
        sh -n "$tmp" || {
            log_error "Downloaded DayPass failed the syntax check. [$dest] was not changed."
            rm -f "$tmp"
            return 1
        }
    fi
    chmod +x "$tmp" || true
    mv "$tmp" "$dest" || {
        log_error "Could not install [$dest]."
        rm -f "$tmp"
        return 1
    }
    printf '  %s✅ DayPass persistent CLI installed! You can now simply run '\''daypass'\'' anytime.%s\n' \
        "${GREEN:-}" "${RESET:-}"
    return 0
}

daypass_cli_version() {
    local dest hash="unavailable"

    dest=$(daypass_cli_dest 2>/dev/null || true)
    [ -n "$dest" ] && [ -f "$dest" ] || dest=$(daypass_cli_self 2>/dev/null || true)
    if [ -n "$dest" ] && [ -f "$dest" ]; then
        if command -v sha256sum >/dev/null 2>&1; then
            hash=$(sha256sum "$dest" 2>/dev/null | awk '{ print substr($1, 1, 12) }')
        elif command -v md5sum >/dev/null 2>&1; then
            hash=$(md5sum "$dest" 2>/dev/null | awk '{ print substr($1, 1, 12) }')
        fi
    fi
    printf '  DayPass %s\n' "${DAYPASS_VERSION:-unknown}"
    printf '  Channel : %s\n' "$(daypass_cli_channel)"
    printf '  Build   : %s\n' "${hash:-unavailable}"
}

daypass_cli_update() {
    local dest url tmp

    dest=$(daypass_cli_dest) || {
        log_error "Neither /usr/bin nor /usr/sbin is writable. Cannot update daypass."
        return 1
    }
    url="${REPO_URL:-}${DAYPASS_CLI_URL_SUFFIX}"
    tmp="/tmp/daypass.new.$$"
    log_info "Fetching [$url] ..."
    daypass_cli_fetch "$url" "$tmp" || {
        log_error "Download failed."
        rm -f "$tmp"
        return 1
    }
    sh -n "$tmp" || {
        log_error "Downloaded script failed sh -n. [$dest] was not changed."
        rm -f "$tmp"
        return 1
    }
    chmod +x "$tmp" || true
    mv "$tmp" "$dest" || {
        log_error "Could not replace [$dest]."
        rm -f "$tmp"
        return 1
    }
    log_success "daypass updated at [$dest]."
    return 0
}

daypass_cli_uninstall() {
    local removed=0 path

    for path in /usr/bin/daypass /usr/sbin/daypass; do
        if [ -e "$path" ]; then
            rm -f "$path" && removed=1
            log_success "Removed [$path]."
        fi
    done
    rm -f /tmp/daypass_pkg_cache /tmp/daypass_usb_pkg.log /tmp/daypass.new.* 2>/dev/null || true
    if [ "$removed" -eq 0 ]; then
        log_warn "daypass was not installed."
        return 1
    fi
    log_success "DayPass CLI removed. Router configuration was left in place."
    return 0
}

# update, version, and uninstall exit. menu and no argument install the CLI and return.
daypass_cli_dispatch() {
    case "${1:-}" in
        update)
            daypass_cli_update
            exit $?
            ;;
        version|-v|--version)
            daypass_cli_version
            exit 0
            ;;
        uninstall)
            daypass_cli_uninstall
            exit $?
            ;;
        menu|"")
            daypass_cli_ensure || true
            return 0
            ;;
        *)
            printf '  Usage: daypass [menu|update|version|uninstall]\n'
            exit 1
            ;;
    esac
}
