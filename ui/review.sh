#!/bin/sh

review_install()
{
    if ! resolve_packages; then
        log_error "Failed to resolve final package list!"
        sleep 2
        return 1
    fi

    clear
    [ -n "$(command -v render_persistent_header)" ] && render_persistent_header

    echo "  📊 Installation Plan Summary"
    echo "  ─────────────────────────────────────────────────────────────"
    printf "  👤 %-18s : %s\n" "Selected Profile" "${SELECTED_PROFILE:-N/A}"
    printf "  🛠️ %-18s : %s\n" "Installation Mode" "${SELECTED_MODE:-recommended}"
    printf "  ⚙️ %-18s : %s\n" "Proxy Engine"    "${SELECTED_ENGINE:-xray}"
    
    if [ "${SELECTED_MODE:-}" = "recommended" ]; then
        printf "  🗣️ %-18s : %s\n" "Language"        "${SELECTED_LANGUAGE:-fa}"
        printf "  🌐 %-18s : %s\n" "Geo Database"     "${SELECTED_GEO:-official}"
    fi
    echo "  ─────────────────────────────────────────────────────────────"

    PKG_COUNT=$(echo $FINAL_PACKAGES | wc -w | tr -d ' ')
    echo "  📦 Targeted Packages (${PKG_COUNT:-0}) :"

    i=0
    for pkg in $FINAL_PACKAGES; do
        i=$((i + 1))
        if [ "$i" -eq "$PKG_COUNT" ]; then
            echo "     └─ 🔹 ${CYAN}$pkg${RESET}"
        else
            echo "     ├─ 🔹 ${CYAN}$pkg${RESET}"
        fi
    done
    echo "  ─────────────────────────────────────────────────────────────"
    echo

    while true; do
        printf "  ⁉️  Proceed with deployment? [Y/n] : "
        read -r confirm </dev/tty

        case "$confirm" in
            y|Y|"")
                return 0
                ;;
            n|N)
                log_warn "Installation cancelled by user!"
                FINAL_PACKAGES=""
                export FINAL_PACKAGES
                sleep 1
                clear
                return 1
                ;;
            *)
                log_error "Invalid input! Please enter Y or N."
                ;;
        esac
    done
}