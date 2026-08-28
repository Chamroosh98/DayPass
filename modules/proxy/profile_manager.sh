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
    echo "  🎭 Current Active Profile"
    echo "  ───────────────────────────────────────────────────────────"

    if [ -f "$PROFILE_DIR/active" ]; then
        active=$(cat "$PROFILE_DIR/active")
        echo "  🫀 Active Profile : ${GREEN}$active${RESET}"
    else
        echo "  🫀 Active Profile : ${GRAY}None${RESET}"
    fi

    if [ -f "$ROUTING_DIR/current_mode" ]; then
        mode=$(cat "$ROUTING_DIR/current_mode")
        echo "  🚦 Routing Mode   : ${CYAN}$mode${RESET}"
    else
        echo "  🚦 Routing Mode   : ${GRAY}Not set${RESET}"
    fi

    echo "  ───────────────────────────────────────────────────────────"
}


# List available profiles

list_profiles() {
    echo "  🎭 Available Routing Profiles"
    echo "  ───────────────────────────────────────────────────────────"
    echo "  ⚖️  1) Balanced       (Iran Direct + Foreign Proxy)"
    echo "  🕹️  2) Gaming         (Low latency focus)"
    echo "  📺  3) Streaming      (Better for video services)"
    echo "  🌎  4) Global Proxy   (All traffic through proxy)"
    echo "  🎯  5) Direct Only    (Disable proxy completely)"
    echo "  ───────────────────────────────────────────────────────────"
}


# Apply a profile (calls real routing functions when possible)

apply_profile() {
    local profile="$1"

    case "$profile" in
        balanced)
            echo "balanced" > "$PROFILE_DIR/active"

            if command -v apply_iran_direct >/dev/null 2>&1; then
                apply_iran_direct
            else
                echo "iran_direct" > "$ROUTING_DIR/current_mode"
                log_warn "Routing module not fully loaded. Mode saved locally."
            fi

            log_success "Profile [⚖️ Balanced] applied!"
            log_info "Iranian sites → Direct | Foreign sites → Proxy"
            ;;

        gaming)
            echo "gaming" > "$PROFILE_DIR/active"

            # Gaming currently uses Iran Direct as base
            if command -v apply_iran_direct >/dev/null 2>&1; then
                apply_iran_direct
            else
                echo "iran_direct" > "$ROUTING_DIR/current_mode"
                log_warn "Routing module not fully loaded. Mode saved locally."
            fi

            log_success "Profile [🕹️ Gaming] applied!"
            log_info "Optimized for lower latency and stability."
            ;;

        streaming)
            echo "streaming" > "$PROFILE_DIR/active"

            if command -v apply_iran_direct >/dev/null 2>&1; then
                apply_iran_direct
            else
                echo "iran_direct" > "$ROUTING_DIR/current_mode"
                log_warn "Routing module not fully loaded. Mode saved locally."
            fi

            log_success "Profile [📺 Streaming] applied!"
            log_info "Optimized for YouTube / Netflix style traffic."
            ;;

        global)
            echo "global" > "$PROFILE_DIR/active"

            if command -v apply_global_proxy >/dev/null 2>&1; then
                apply_global_proxy
            else
                echo "global_proxy" > "$ROUTING_DIR/current_mode"
                log_warn "Routing module not fully loaded. Mode saved locally."
            fi

            log_success "Profile [🌎 Global Proxy] applied!"
            log_info "All traffic will go through proxy."
            ;;

        direct)
            echo "direct" > "$PROFILE_DIR/active"

            if command -v apply_direct_only >/dev/null 2>&1; then
                apply_direct_only
            else
                echo "direct_only" > "$ROUTING_DIR/current_mode"
                log_warn "Routing module not fully loaded. Mode saved locally."
            fi

            log_success "Profile [🎯 Direct Only] applied!"
            log_info "Proxy disabled. All traffic is direct."
            ;;

        *)
            log_error "Unknown profile!"
            return 1
            ;;
    esac
}


# Main Menu

profile_manager_menu() {
    while true; do
        render_persistent_header 2>/dev/null || clear

        echo "  🎭 Routing Profiles"
        echo "  ───────────────────────────────────────────────────────────"
        show_active_profile
        echo
        list_profiles
        echo
        echo "  🚪 0) Back"
        echo "  ───────────────────────────────────────────────────────────"
        echo

        printf "  ⁉️ Select profile [1-5] or 0 to back : "
        read -r choice </dev/tty

        case "$choice" in
            1) apply_profile "balanced" ;;
            2) apply_profile "gaming" ;;
            3) apply_profile "streaming" ;;
            4) apply_profile "global" ;;
            5) apply_profile "direct" ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
        read -r _ </dev/tty
    done
}