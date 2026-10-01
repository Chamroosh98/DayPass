#!/bin/sh
# ============================================================
# DayPass - Menu navigation contract
#   0 : Back (sub-menus) / Exit (root menu)
#   q : Quit DayPass from any screen
#   h : Contextual help of the current screen
# ============================================================

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
    ui_read "Select option [0-$1], [q] Quit or [h] Help"
}

ui_pause() {
    printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
    read -r _ </dev/tty || daypass_quit
}

# $1 "root" | "main" (back to main menu) | anything else (back one level)
ui_nav_footer() {
    case "${1:-}" in
        root) printf "  🚪 ${YELLOW}0)${RESET} ${WHITE}Exit DayPass${RESET}\n" ;;
        main) printf "  🚪 ${YELLOW}0)${RESET} ${WHITE}Back to Main Menu${RESET}\n" ;;
        *)    printf "  🚪 ${YELLOW}0)${RESET} ${WHITE}Back${RESET}\n" ;;
    esac
    printf "  ${DIM}${CYAN}   q)${RESET} ${WHITE}Quit DayPass${RESET}   ${DIM}${CYAN}h)${RESET} ${WHITE}Help${RESET}\n"
    echo "  ───────────────────────────────────────────────────────────"
    echo
}

ui_title() {
    echo "  $1"
    echo "  ───────────────────────────────────────────────────────────"
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
