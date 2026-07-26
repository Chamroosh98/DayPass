#!/bin/sh

if [ -t 1 ]; then

    NC='\033[0m'

    BLACK='\033[0;30m'
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    WHITE='\033[0;37m'
    GRAY='\033[90m'

else

    NC=''

    BLACK=''
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    PURPLE=''
    CYAN=''
    WHITE=''
    GRAY=''

fi

log_info() {

    printf "%b\n" "${GRAY}ℹ️${NC} $*"

}

log_success() {

    printf "%b\n" "${GREEN}✅${NC} $*"

}

log_warn() {

    printf "%b\n" "${YELLOW}⚠️${NC} $*"

}

log_error() {

    printf "%b\n" "${RED}❌${NC} $*"

}