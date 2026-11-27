#!/bin/sh

# Applies ready-to-use profiles by calling real routing modes
# ============================================================


# Paths

PROXY_DIR="/etc/daypass/proxy"
PROFILE_DIR="$PROXY_DIR/profiles"
ROUTING_DIR="$PROXY_DIR/routing"
mkdir -p "$PROFILE_DIR"
mkdir -p "$ROUTING_DIR"


# Show current active profile

show_active_profile() {
    local active mode
    echo "  🎭 Saved Profile"
    ui_divider

    if [ -f "$PROFILE_DIR/active" ]; then
        active=$(cat "$PROFILE_DIR/active")
        echo "  🫀 Saved profile : ${GREEN}$active${RESET}"
    else
        echo "  🫀 Saved profile : ${GRAY}None${RESET}"
    fi

    if [ -f "$ROUTING_DIR/current_mode" ]; then
        mode=$(cat "$ROUTING_DIR/current_mode")
        echo "  🚦 Saved routing mode : ${CYAN}$mode${RESET}"
    else
        echo "  🚦 Saved routing mode : ${GRAY}Not set${RESET}"
    fi

    ui_divider
}


# List available profiles

list_profiles() {
    echo "  🎭 Available Routing Profiles"
    ui_divider
    echo "  ⚖️  1) Balanced       (Iran Direct + Foreign Proxy)"
    echo "  🕹️  2) Gaming         (Low latency focus)"
    echo "  📺  3) Streaming      (Better for video services)"
    echo "  🌎  4) Global Proxy   (All traffic through proxy)"
    echo "  🎯  5) Direct Only    (Disable proxy completely)"
    ui_divider
}


# Apply a profile (calls real routing functions when possible)

apply_profile() {
    local profile="$1" action tmp
    case "$profile" in
        balanced|gaming|streaming) action=apply_iran_direct ;;
        global) action=apply_global_proxy ;;
        direct) action=apply_direct_only ;;
        *) log_error "Unknown profile."; return 1 ;;
    esac
    command -v "$action" >/dev/null || { log_error "Routing module unavailable."; return 1; }
    [ ! -L "$PROFILE_DIR/active" ] && [ ! -d "$PROFILE_DIR/active" ] || return 1
    tmp=$(mktemp "$PROFILE_DIR/.active.XXXXXX") || return 1
    printf '%s\n' "$profile" > "$tmp" && "$action" ||
        { local rc=$?; rm -f "$tmp"; return "$rc"; }
    mv "$tmp" "$PROFILE_DIR/active" || { rm -f "$tmp"; return 1; }
    log_success "Profile [$profile] applied."

}


# Main Menu

profile_manager_menu() {
    local HELP_MODULE_ID="proxy_profiles"

    while true; do
        render_persistent_header

        echo "  🎭 Routing Profiles"
        ui_divider
        show_active_profile
        echo
        list_profiles
        echo
        ui_nav_footer

        ui_prompt 5
        choice="$UI_CHOICE"

        case "$choice" in
            1) apply_profile "balanced" ;;
            2) apply_profile "gaming" ;;
            3) apply_profile "streaming" ;;
            4) apply_profile "global" ;;
            5) apply_profile "direct" ;;
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

        printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
        read -r _ </dev/tty || daypass_quit
    done
}