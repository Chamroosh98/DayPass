#!/bin/sh
# DayPass persistent CLI.
# Installs /usr/bin/daypass and handles update, version, and uninstall.
# Safe to source. Subcommands exit. menu/default returns.

DAYPASS_CLI_URL_SUFFIX="/install.sh"
DAYPASS_UPDATE_CHECK_STAMP="/tmp/daypass_update_check"
DAYPASS_UPDATE_INTERVAL=43200 # 12 hours in seconds

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

# Absolute path of the running script, when it is a real file (ignores shells/busybox).
daypass_cli_self() {
    local self=""

    case "$0" in
        sh|-sh|ash|-ash|bash|-bash|dash|-dash|/bin/sh|/bin/ash|/bin/bash)
            return 1
            ;;
        /*|*/*)
            self="$0"
            ;;
        *)
            self=$(command -v "$0" 2>/dev/null || true)
            ;;
    esac
    [ -n "$self" ] && [ -f "$self" ] && [ -r "$self" ] || return 1
    if command -v readlink >/dev/null 2>&1; then
        self=$(readlink -f "$self" 2>/dev/null || printf '%s\n' "$self")
    fi
    case "$self" in
        *busybox*) return 1 ;;
    esac
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

# Check if enough time has passed since the last update check.
_daypass_should_check_update() {
    local now last
    [ -f "$DAYPASS_UPDATE_CHECK_STAMP" ] || return 0
    now=$(date +%s 2>/dev/null || echo 0)
    last=$(cat "$DAYPASS_UPDATE_CHECK_STAMP" 2>/dev/null || echo 0)
    [ $((now - last)) -ge "$DAYPASS_UPDATE_INTERVAL" ]
}

# Oh-My-Zsh style interactive update notifier.
daypass_cli_update_notifier() {
    local dest="$1"
    local url tmp ans remote_ver

    _daypass_should_check_update || return 0
    date +%s > "$DAYPASS_UPDATE_CHECK_STAMP" 2>/dev/null || true

    url="${REPO_URL:-}${DAYPASS_CLI_URL_SUFFIX}"
    tmp="/tmp/daypass.check.$$"

    # Silent fetch; if offline or failed, just skip without bothering the user.
    daypass_cli_fetch "$url" "$tmp" 2>/dev/null || {
        rm -f "$tmp"
        return 0
    }

    # If the remote file is identical to the installed one, no update is needed.
    if cmp -s "$dest" "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        return 0
    fi

    # Verify syntax of the downloaded update before offering it.
    sh -n "$tmp" 2>/dev/null || {
        rm -f "$tmp"
        return 0
    }

    # Try to extract DAYPASS_VERSION from the remote script if defined.
    remote_ver=$(sed -n 's/^DAYPASS_VERSION=["'\'']\{0,1\}\([^"'\'']*\)["'\'']\{0,1\}.*/\1/p' "$tmp" | head -n 1)

    printf '\n  %s🔔 [DayPass Update Notifier]%s\n' "${YELLOW:-}" "${RESET:-}"
    if [ -n "$remote_ver" ] && [ "$remote_ver" != "${DAYPASS_VERSION:-}" ]; then
        printf '  A new version of DayPass is available (%s -> %s)!\n' "${DAYPASS_VERSION:-current}" "$remote_ver"
    else
        printf '  A new build of DayPass is available on the %s channel!\n' "$(daypass_cli_channel)"
    fi
    printf '  Would you like to update now? [y/N]: '
    read -r ans </dev/tty || ans="n"

    case "$ans" in
        y|Y|yes|YES)
            chmod +x "$tmp" || true
            if mv "$tmp" "$dest"; then
                log_success "DayPass updated successfully! Reloading..."
                exec "$dest" "$@"
            else
                log_error "Failed to apply update."
                rm -f "$tmp"
            fi
            ;;
        *)
            rm -f "$tmp"
            printf '  Skipping update. You can manually run '\''daypass update'\'' anytime.\n\n'
            ;;
    esac
}

# Install the persistent CLI once, or check for updates if already installed.
daypass_cli_ensure() {
    local dest self tmp

    dest=$(daypass_cli_dest) || {
        log_warn "Neither /usr/bin nor /usr/sbin is writable. DayPass will run this session only."
        return 0
    }

    self=$(daypass_cli_self 2>/dev/null || true)

    # Case 1: User ran 'daypass' directly from the installed path.
    if [ -n "$self" ] && [ "$self" = "$dest" ]; then
        daypass_cli_update_notifier "$dest"
        return 0
    fi

    # Case 2: Installed file already exists and matches the local running file.
    if [ -n "$self" ] && [ -f "$dest" ] && cmp -s "$self" "$dest" 2>/dev/null; then
        return 0
    fi

    # Case 3: First-time installation (or running from a different local file/pipe).
    tmp="${dest}.new.$$"
    if [ -n "$self" ]; then
        cp "$self" "$tmp" || {
            log_error "Could not copy DayPass to [$dest]."
            rm -f "$tmp"
            return 1
        }
    else
        # If $dest already exists during a pipe run, don't re-download silently; let notifier handle it or update it.
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
    date +%s > "$DAYPASS_UPDATE_CHECK_STAMP" 2>/dev/null || true
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
    if [ -f "$dest" ] && cmp -s "$dest" "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        date +%s > "$DAYPASS_UPDATE_CHECK_STAMP" 2>/dev/null || true
        log_info "DayPass is already up to date!"
        return 0
    fi
    chmod +x "$tmp" || true
    mv "$tmp" "$dest" || {
        log_error "Could not replace [$dest]."
        rm -f "$tmp"
        return 1
    }
    date +%s > "$DAYPASS_UPDATE_CHECK_STAMP" 2>/dev/null || true
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
    rm -f /tmp/daypass_pkg_cache /tmp/daypass_usb_pkg.log /tmp/daypass_update_check /tmp/daypass.new.* /tmp/daypass.check.* 2>/dev/null || true
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