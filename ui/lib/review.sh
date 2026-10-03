#!/bin/sh

review_install()
{
    if ! resolve_packages; then
        log_error "Failed to resolve final package list!"
        sleep 2
        return 1
    fi

    render_persistent_header

    _rv_title="${SELECTED_PROFILE:-DayPass}"
    command -v mf_title_for >/dev/null 2>&1 && _rv_title="$(mf_title_for "${SELECTED_PROFILE:-proxy}")"

    echo "  📊 ${_rv_title} — Installation Plan"
    echo "  ─────────────────────────────────────────────────────────────"
    printf "  👤 %-18s : %s\n" "Module" "${SELECTED_PROFILE:-N/A}"
    command -v mf_category_for >/dev/null 2>&1 && \
        printf "  📂 %-18s : %s\n" "Category" "$(mf_category_for "${SELECTED_PROFILE:-proxy}")"
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
        if command -v ui_nav_footer >/dev/null 2>&1; then
            ui_nav_footer
        fi
        ui_read "Proceed with deployment? [Y/n]"
        confirm="$UI_CHOICE"

        case "$confirm" in
            y|Y|"")
                return 0
                ;;
            q|Q)
                daypass_quit
                ;;
            n|N|0)
                log_warn "Installation cancelled by user!"
                FINAL_PACKAGES=""
                export FINAL_PACKAGES
                sleep 1
                clear
                return 1
                ;;
            *)
                log_error "Invalid input! Please enter Y, N or 0."
                ;;
        esac
    done
}