#!/bin/sh

show_banner()
{
    # Ensure system metadata variables are resolved
    [ -z "$ARCH" ] && detect_arch
    
    OW_VER="Unknown"
    if [ -f /etc/openwrt_release ]; then
        . /etc/openwrt_release
        OW_VER="${DISTRIB_RELEASE:-Unknown}"
    fi

    PKG_MGR="${PKG_MANAGER:-opkg}"

    TOTAL_RAM_MB=$(get_total_ram_mb)
    FREE_RAM_MB=$(get_free_ram_mb)
    USED_RAM_MB=$((TOTAL_RAM_MB - FREE_RAM_MB))

    TOTAL_STO_MB=$(get_total_storage_mb)
    FREE_STO_MB=$(get_free_storage_mb)
    USED_STO_MB=$((TOTAL_STO_MB - FREE_STO_MB))

    W_LOGO="${BOLD}${WHITE}"
    R_LOGO="${BOLD}${RED}"

    echo

    printf "${W_LOGO}          .=:   :-+++=-.      ${CYAN}____              ____${RESET}\n"
    printf "${W_LOGO}      .-+*##- :*##+==*##=     ${CYAN}|  _ \  __ _ _   _|  _ \  __ _ ___ ___${RESET}\n"
    printf "${W_LOGO}      =#*###:.##+     =*#-    ${CYAN}| | | |/ _\` | | | | |_) / _\` / __/ __|${RESET}\n"
    printf "${W_LOGO}      .  **#: ***:   .+#*.    ${CYAN}| |_| | (_| | |_| |  __/ (_| \__ \__ \\\\${RESET}\n"
    printf "${R_LOGO}        .**#: .+***++*+=.     ${CYAN}|____/ \__,_|\__, |_|   \__,_|___/___/${RESET}\n"
    printf "${R_LOGO}        .***:.+**+=-::::-:    ${CYAN}             |___/${RESET}\n"
    printf "${R_LOGO}        .***:=+=:      :--.   ${RESET}\n"
    printf "${R_LOGO}        .***::-:       :--.   ${WHITE}🐱github.com/Chamroosh98${RESET}\n"
    printf "${R_LOGO}        .++*. :--:....:--:    ${WHITE}🩻 Architecture : %s${RESET}\n" "$ARCH"
    printf "${R_LOGO}        .+++:  .::::::--:     ${WHITE}💡 OpenWrt      : %s (%s)${RESET}\n" "$OW_VER" "$PKG_MGR"
    printf "${R_LOGO}       =+++++=     .:::.      ${WHITE}🧠 Memory       : %s/%s MB${RESET}\n" "$USED_RAM_MB" "$TOTAL_RAM_MB"
    printf "${R_LOGO}       .......  .::::.        ${WHITE}💾 Storage      : %s/%s MB${RESET}\n" "$USED_STO_MB" "$TOTAL_STO_MB"

    echo
    printf "  ${GRAY}───────────────────── 🕊️ Remembering the IRAN Massacre on Jan 8-9, 2026 ─────────────────────${RESET}\n"
}