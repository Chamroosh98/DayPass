#!/bin/sh

show_banner()
{
    W_LOGO="${BOLD}${WHITE}"
    R_LOGO="${BOLD}${RED}"
    VERSION="v2.1.0"

    echo

    printf "%b          .=:   :-+++=-.%b\n" "${W_LOGO}" "${RESET}"
    printf "%b      .-+*##- :*##+==*##=%b\n" "${W_LOGO}" "${RESET}"
    printf "%b      =#*###:.##+     =*#-    %b ____              %b____%b %s%b\n" "${W_LOGO}" "${RED}" "${GRAY}" "${YELLOW}" "$VERSION" "${RESET}"
    printf "%b      .  **#: ***:   .+#*.    %b|  _ \\  __ _ _   _%b|  _ \\  __ _ ___ ___%b\n" "${W_LOGO}" "${RED}" "${GRAY}" "${RESET}"
    printf "%b        .**#: .+***++*+=.     %b| | | |/ _\` || | |%b| |_) / _\` / __/ __|%b\n" "${R_LOGO}" "${RED}" "${GRAY}" "${RESET}"
    printf "%b        .***:.+**+=-::::-:    %b| |_| | (_| | |_| |%b|  __/ (_| \\__ \\__ \\\\%b\n" "${R_LOGO}" "${RED}" "${GRAY}" "${RESET}"
    printf "%b        .***:=+=:      :--.   %b|____/ \\__,_|\\__, |%b|_|   \\__,_|___/___/%b\n" "${R_LOGO}" "${RED}" "${GRAY}" "${RESET}"
    printf "%b        .***::-:       :--.   %b             |___/%b\n" "${R_LOGO}" "${RED}" "${RESET}"
    printf "%b        .++*. :--:....:--:    %b🐱 github.com/Chamroosh98%b\n" "${R_LOGO}" "${WHITE}" "${RESET}"
    printf "%b        .+++:  .::::::--:     %b\n" "${R_LOGO}" "${RESET}"
    printf "%b       =+++++=     .:::.      %b\n" "${R_LOGO}" "${RESET}"
    printf "%b       .......  .::::.        %b\n" "${R_LOGO}" "${RESET}"

    echo
    printf "  %b───────────────────── 🕊️ Remembering the IRAN Massacre on Jan 8-9, 2026 ─────────────────────%b\n" "${GRAY}" "${RESET}"
}
