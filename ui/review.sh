#!/bin/sh

review_install()
{
    resolve_packages

    clear
    
    [ -n "$(command -v render_persistent_header)" ] && render_persistent_header

    echo "  📊 Installation Plan Summary"
    echo "  ─────────────────────────────────────────────────────────────"
    printf "  👤 %-16s : %s\n" "Selected Profile" "${SELECTED_PROFILE:-N/A}"
    printf "  ⚙️ %-16s : %s\n" "Selected Engine"  "${SELECTED_ENGINE:-auto}"
    printf "  🗣️ %-16s : %s\n" "Language"         "${SELECTED_LANGUAGE:-none}"
    printf "  🌐 %-16s : %s\n" "Geo Database"     "${SELECTED_GEO:-none}"
    echo "  ─────────────────────────────────────────────────────────────"

    PKG_COUNT=$(echo $FINAL_PACKAGES | wc -w | tr -d ' ')
    echo "  📦 Targeted Packages (${PKG_COUNT:-0}) :"

    i=0
    for pkg in $FINAL_PACKAGES; do
        i=$((i + 1))
        if [ "$i" -eq "$PKG_COUNT" ]; then
            echo "     └─ 🔹 $pkg"
        else
            echo "     ├─ 🔹 $pkg"
        fi
    done
    echo "  ─────────────────────────────────────────────────────────────"
    echo

    while true; do
        printf "  ⁉️  Continue with installation? [y/N] : "
        read -r confirm </dev/tty

        case "$confirm" in
            y|Y)
                return 0
                ;;
            n|N|"")
                log_warn "Installation cancelled by user!"
                clear
                return 1
                ;;
            *)
                log_error "Invalid input! Please enter Y or N!"
                ;;
        esac
    done
}