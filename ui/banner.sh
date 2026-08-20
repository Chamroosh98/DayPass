#!/bin/sh

show_banner()
{
    # Color Definitions
    BOLD="\033[1m"
    RED="\033[31m"
    WHITE="\033[37m"
    GRAY="\033[90m"
    CYAN="\033[36m"
    RESET="\033[0m"

    VERSION="v1.2.0"
    GITHUB="github.com/Chamroosh98"

    echo
    printf "  %b____              %b____%b                     %b%s%b\n" "${BOLD}${RED}" "${BOLD}${WHITE}" "${RESET}" "${GRAY}" "$VERSION" "${RESET}"
    printf "  %b|  _ \\  __ _ _   _%b|  _ \\  __ _ ___ ___%b\n" "${BOLD}${RED}" "${BOLD}${WHITE}" "${RESET}"
    printf "  %b| | | |/ _\` | | | |%b| |_) / _\` / __/ __|%b\n" "${BOLD}${RED}" "${BOLD}${WHITE}" "${RESET}"
    printf "  %b| |_| | (_| | |_| |%b|  __/ (_| \\__ \\__ \\%b\n" "${BOLD}${RED}" "${BOLD}${WHITE}" "${RESET}"
    printf "  %b|____/ \\__, |\\__, |%b|_|   \\__,_|___/___/%b\n" "${BOLD}${RED}" "${BOLD}${WHITE}" "${RESET}"
    printf "  %b       |___/ |___/%b\n" "${BOLD}${RED}" "${RESET}"
    echo
    printf "  %b🔗 GitHub: %bhttps://%s%b\n" "${WHITE}" "${CYAN}" "${GITHUB}" "${RESET}"
    echo
    printf "  %b───────────────────── 🕊️ Remembering the IRAN Massacre on Jan 8-9, 2026 ─────────────────────%b\n" "${GRAY}" "${RESET}"
    echo
}

show_banner