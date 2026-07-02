#!/usr/bin/env bash

export CYAN="\033[1;38;5;51m"
export PURPLE="\033[38;5;141m"
export GREEN="\033[32m"
export YELLOW="\033[33m"
export GRAY="\033[90m"
export RED="\033[31m"
export NC="\033[0m"

show_banner() {
    clear
    echo -e "${CYAN}____              ____                 ${NC}"
    echo -e "${CYAN}|  _ \  __ _ _   _|  _ \  __ _ ___ ___  ${NC}"
    echo -e "${CYAN}| | | |/ _\` | | | | |_) / _\` / __/ __| ${NC}"
    echo -e "${CYAN}| |_| | (_| | |_| |  __/ (_| \__ \__ \ ${NC}"
    echo -e "${CYAN}|____/ \__,_|\__, |_|   \__,_|___/___/ ${NC}"
    echo -e "${CYAN}             |___/                     ${NC}"
    echo -e "${PURPLE}🕊 Remembering the IRAN massacre on January 8 and 9, 2026 ...${NC}"
    echo -e "${GRAY}🐱 github.com/Chamroosh98${NC}"
    echo -e "${GRAY}============================================================${NC}"
}

log_info() {
    echo -e "[${CYAN}INFO${NC}] $1"
}

log_success() {
    echo -e "[${GREEN}SUCCESS${NC}] $1"
}

log_warning() {
    echo -e "[${YELLOW}WARNING${NC}] $1"
}

log_error() {
    echo -e "[${RED}ERROR${NC}] $1"
}