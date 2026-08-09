#!/bin/sh

show_banner()
{
    W_LOGO="${BOLD}${WHITE}"
    R_LOGO="${BOLD}${RED}"
    VERSION="v2.1.0" 

    echo

    printf "${W_LOGO}          .=:   :-+++=-.${RESET}\n"
    printf "${W_LOGO}      .-+*##- :*##+==*##=${RESET}\n"
    printf "${W_LOGO}      =#*###:.##+     =*#-    ${RED} ____              ${GRAY}____${YELLOW} %s${RESET}\n" "$VERSION"
    printf "${W_LOGO}      .  **#: ***:   .+#*.    ${RED}|  _ \  __ _ _   _${GRAY}|  _ \  __ _ ___ ___${RESET}\n"
    printf "${R_LOGO}        .**#: .+***++*+=.     ${RED}| | | |/ _\` || | |${GRAY}| |_) / _\` / __/ __|${RESET}\n"
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