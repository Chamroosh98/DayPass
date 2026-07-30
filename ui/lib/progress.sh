#!/bin/sh

# -----------------------------------------------------------------------------
# 1. Timer + Animated Progress (For Async background tasks like opkg/apk update)
# -----------------------------------------------------------------------------
show_timer_progress()
{
    pid="$1"
    message="$2"
    
    start_time=$(date +%s)
    bar_width=30
    current_step=0

    # Hide Cursor
    printf "\033[?25l" 2>/dev/null

    echo "   🖐️ Please wait, $message ..."

    while kill -0 "$pid" 2>/dev/null; do
        now=$(date +%s)
        elapsed=$((now - start_time))
        
        # Simulate smooth progress loop up to 95% until task finishes
        current_step=$(( (current_step + 1) % (bar_width + 1) ))
        percent=$((current_step * 100 / bar_width))
        [ "$percent" -gt 95 ] && percent=95

        # Build [====>    ] ASCII Bar
        arrow_pos=$current_step
        bar=""
        i=0
        while [ "$i" -lt "$bar_width" ]; do
            if [ "$i" -lt "$arrow_pos" ]; then
                bar="${bar}="
            elif [ "$i" -eq "$arrow_pos" ]; then
                bar="${bar}>"
            else
                bar="${bar} "
            fi
            i=$((i + 1))
        done

        # Line 1: Timer line
        # Line 2: Progress bar line
        printf "    \033[K⏰ DayPass is working in the background, timer : ${BOLD}%d seconds${RESET}\n" "$elapsed"
        printf "    \033[K[${CYAN}%s${RESET}] ${BOLD}%3d%%${RESET}\033[1A\r" "$bar" "$percent"

        if command -v usleep >/dev/null 2>&1; then
            usleep 150000 2>/dev/null
        else
            sleep 1
        fi
    done

    # Finish Line on Complete (100%)
    now=$(date +%s)
    elapsed=$((now - start_time))
    
    # Render Full Bar [==============================] 100%
    full_bar=""
    i=0
    while [ "$i" -lt "$bar_width" ]; do
        full_bar="${full_bar}="
        i=$((i + 1))
    done

    printf "   \033[K✌️ Task finished! total time : ${GREEN}%d seconds${RESET}\n" "$elapsed"
    printf "   \033[K[${GREEN}%s${RESET}] ${BOLD}100%%${RESET}\n" "$full_bar"

    # Restore Cursor
    printf "\033[?25h" 2>/dev/null
}

# -----------------------------------------------------------------------------
# 2. Strict Real-Time Step Progress (For File downloads / Batch Package items)
# -----------------------------------------------------------------------------
show_ascii_progress()
{
    title="$1"
    current="$2"
    total="$3"
    bar_width="${4:-30}"

    [ "$total" -le 0 ] && return

    percent=$((current * 100 / total))
    [ "$percent" -gt 100 ] && percent=100

    filled=$((percent * bar_width / 100))

    bar=""
    i=0
    while [ "$i" -lt "$bar_width" ]; do
        if [ "$i" -lt "$filled" ]; then
            bar="${bar}="
        elif [ "$i" -eq "$filled" ] && [ "$percent" -lt 100 ]; then
            bar="${bar}>"
        else
            bar="${bar} "
        fi
        i=$((i + 1))
    done

    COLOR="${YELLOW}"
    [ "$percent" -ge 50 ] && COLOR="${CYAN}"
    [ "$percent" -eq 100 ] && COLOR="${GREEN}"

    printf "\r⏳ %-20s [${COLOR}%s${RESET}] ${BOLD}%3d%%${RESET} (%s/%s)" \
            "$title" "$bar" "$percent" "$current" "$total"

    [ "$current" -ge "$total" ] && echo
}

log_step()
{
    status="$1"
    message="$2"

    case "$status" in
        ok)   printf "   ${GREEN}✔ ${RESET} %s\n" "$message" ;;
        fail) printf "   ${RED}✖ ${RESET} %s\n" "$message" >&2 ;;
        warn) printf "   ${YELLOW}! ${RESET} %s\n" "$message" ;;
        *)    printf "   ${CYAN}ℹ ${RESET} %s\n" "$message" ;;
    esac
}