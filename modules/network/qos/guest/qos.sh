#!/bin/sh
# ============================================================
# DayPass - Guest QoS / Bandwidth Control
# Supports both Simple (tc) and Advanced (SQM) modes
# ============================================================

# ------------------------------------------------------------
# Simple Bandwidth Limit using tc (HTB)
# ------------------------------------------------------------
# Legacy qdiscs, the shared SQM service and the rc.local hook have no
# ownership receipts. Device/handle equality cannot authorize replacement.
setup_simple_qos() {
    log_error "The guest qdisc and startup hook have no verified owner. Simple shaping is unavailable."
    return 1
}

setup_sqm_qos() {
    log_error "Exclusive ownership of guest shaping cannot be established. SQM setup stopped."
    return 1
}

remove_guest_qos() {
    log_error "No verifiable ownership record for guest QoS. Existing rules and startup hooks were retained."
    return 1
}

guest_qos_menu() {
    local HELP_MODULE_ID="network_guest_qos"

    while true; do
        render_persistent_header

        echo "  🚦 Guest Bandwidth Control (QoS)"
        ui_divider
        echo "  1) Simple Limit (tc) - Lightweight"
        echo "  2) Advanced Limit (SQM + Cake) - Better quality"
        echo "  3) Remove all Guest QoS"
        ui_nav_footer
        ui_prompt 3
        choice="$UI_CHOICE"

        case "$choice" in
            1) setup_simple_qos ;;
            2) setup_sqm_qos ;;
            3) remove_guest_qos ;;
            q|Q) daypass_quit ;;
            h|H)
                if command -v show_help >/dev/null 2>&1; then
                    show_help "$HELP_MODULE_ID"
                else
                    log_warn "Help module not loaded!"
                    sleep 1
                fi
                continue
                ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press ENTER ...${RESET}"
        read -r _ </dev/tty || daypass_quit
    done
}