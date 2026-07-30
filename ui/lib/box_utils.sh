#!/bin/sh

draw_bar()
{
    PCT="$1"
    BW="${2:-20}"
    MODE="${3:-usage}"
    
    [ "$PCT" -gt 100 ] && PCT=100
    [ "$PCT" -lt 0 ] && PCT=0

    FILLED=$(( PCT * BW / 100 ))

    if [ "$MODE" = "score" ]; then
        if [ "$PCT" -ge 80 ]; then COLOR="$GREEN"
        elif [ "$PCT" -ge 50 ]; then COLOR="$YELLOW"
        else COLOR="$RED"
        fi
    else
        if [ "$PCT" -ge 85 ]; then COLOR="$RED"
        elif [ "$PCT" -ge 60 ]; then COLOR="$YELLOW"
        else COLOR="$GREEN"
        fi
    fi

    BAR=""
    i=0
    while [ "$i" -lt "$FILLED" ]; do 
        BAR="${BAR}█"
        i=$((i+1))
    done
    while [ "$i" -lt "$BW" ]; do 
        BAR="${BAR}░"
        i=$((i+1))
    done

    printf "${COLOR}%s${RESET}" "$BAR"
}

log_warn()    { printf "  ${YELLOW}⚠️  %s${RESET}\n" "$1" >&2; }
log_info()    { printf "  ${CYAN}ℹ️  %s${RESET}\n" "$1"; }
log_success() { printf "  ${GREEN}✅  %s${RESET}\n" "$1"; }
log_error()   { printf "  ${RED}❌  %s${RESET}\n" "$1" >&2; }
