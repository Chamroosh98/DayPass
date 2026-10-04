#!/bin/sh
# ============================================================
# DayPass - Menu navigation contract
#   0 : Back (sub-menus) / Exit (root menu)
#   q : Quit DayPass from any screen
#   h : Contextual help of the current screen
# ============================================================

# 2 spaces + exactly 60 box-drawing marks. Every screen uses this line.
UI_DIVIDER="  ────────────────────────────────────────────────────────────"
export UI_DIVIDER

# Optional $1 is a color escape (CYAN, GRAY, DIM, ...).
ui_divider() {
    if [ -n "${1:-}" ]; then
        printf '%s%s%s\n' "$1" "$UI_DIVIDER" "${RESET:-}"
    else
        printf '%s\n' "$UI_DIVIDER"
    fi
}

daypass_quit() {
    echo
    printf "  ${GRAY}TNX for using DayPass! =)${RESET}\n"
    stty sane 2>/dev/null
    exit 0
}

# Ctrl-C leaves the terminal usable and ends the session cleanly
daypass_interrupt() {
    trap - INT TERM
    echo
    log_warn "Interrupted."
    daypass_quit
}

# Reads one answer from the terminal into UI_CHOICE. A closed terminal (EOF)
# ends the session instead of looping on empty input forever.
# $1 prompt text
ui_read() {
    printf "  ⁉️ %s : " "$1"
    if ! read -r UI_CHOICE </dev/tty; then
        UI_CHOICE=""
        daypass_quit
    fi
}

# $1 highest option number
ui_prompt() {
    ui_read "Select option [0-$1]"
}

ui_pause() {
    printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
    read -r _ </dev/tty || daypass_quit
}

# $1 "root" | "main" (back to main menu) | anything else (back one level)
ui_nav_footer() {
    _nav_muted="${COLOR_MUTED:-${GRAY:-\033[90m}}"
    case "${1:-}" in
        root) _nav_back="0) Exit DayPass" ;;
        main) _nav_back="0) Back to Main Menu" ;;
        *)    _nav_back="0) Back / Skip" ;;
    esac
    if [ "${1:-}" != "root" ]; then
        _nav_line="$_nav_back   q) Quit DayPass   h) Help"
    else
        _nav_line="$_nav_back   h) Help"
    fi
    echo
    ui_divider
    printf "  ${_nav_muted}%s${RESET}\n" "$_nav_line"
    echo
}

ui_title() {
    echo "  $1"
    ui_divider
}

ui_show_help() {
    if command -v show_help >/dev/null 2>&1; then
        show_help "$1"
    else
        log_warn "Help module not loaded!"
        sleep 1
    fi
}

# Runs a menu/action function when it is loaded; a failing action never
# ends the calling menu loop. $1 function, $2 label for the error message.
ui_run() {
    local fn="$1"
    local label="${2:-$1}"
    if [ "$#" -ge 2 ]; then shift 2; else shift "$#"; fi

    if command -v "$fn" >/dev/null 2>&1; then
        "$fn" "$@" || true
        return 0
    fi
    log_error "$label module not found!"
    sleep 2
    return 1
}

# Handles the shared keys. Returns 0 when the key was consumed, 1 otherwise.
# $1 choice, $2 help module id
ui_nav_common() {
    case "$1" in
        q|Q) daypass_quit ;;
        h|H) ui_show_help "$2"; return 0 ;;
    esac
    return 1
}
