#!/bin/sh

show_banner()
{
    W_LOGO="${BOLD}${WHITE}"
    R_LOGO="${BOLD}${RED}"
    VERSION="v2.1.0-beta" # یا متغیر پروژه شما $DAYPASS_VERSION

    echo

    printf "${W_LOGO}          .=:   :-+++=-.      ${CYAN}____              ____${RESET}\n"
    printf "${W_LOGO}      .-+*##- :*##+==*##=     ${CYAN}|  _ \  __ _ _   _|  _ \  __ _ ___ ___${RESET}\n"
    printf "${W_LOGO}      =#*###:.##+     =*#-    ${CYAN}| | | |/ _\` | | | | |_) / _\` / __/ __|${RESET}\n"
    printf "${W_LOGO}      .  **#: ***:   .+#*.    ${CYAN}| |_| | (_| | |_| |  __/ (_| \__ \__ \\\\${RESET}\n"
    printf "${R_LOGO}        .**#: .+***++*+=.     ${CYAN}|____/ \__,_|\__, |_|   \__,_|___/___/${RESET}\n"
    printf "${R_LOGO}        .***:.+**+=-::::-:    ${CYAN}             |___/${RESET}\n"
    printf "${R_LOGO}        .***:=+=:      :--.   ${RESET}\n"
    printf "${R_LOGO}        .***::-:       :--.   ${WHITE}🐱 github.com/Chamroosh98${RESET}\n"
    printf "${R_LOGO}        .++*. :--:....:--:    ${WHITE}🏷️ Version     : %s${RESET}\n" "$VERSION"
    printf "${R_LOGO}        .+++:  .::::::--:     ${RESET}\n"
    printf "${R_LOGO}       =+++++=     .:::.      ${RESET}\n"
    printf "${R_LOGO}       .......  .::::.        ${RESET}\n"

    echo
    printf "  ${GRAY}───────────────────── 🕊️ Remembering the IRAN Massacre on Jan 8-9, 2026 ─────────────────────${RESET}\n"
}