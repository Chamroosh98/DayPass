#!/bin/sh
# ============================================================
# DayPass - Routing Profiles Manager
# ============================================================

# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------
PROXY_DIR="/etc/daypass/proxy"
PROFILE_DIR="$PROXY_DIR/profiles"
mkdir -p "$PROFILE_DIR"

# ------------------------------------------------------------
# List available profiles
# ------------------------------------------------------------
list_profiles() {
    echo "  🎭 Available Routing Profiles"
    echo "  ───────────────────────────────────────────────────────────"
    echo "  ⚖️ 1) Balanced          (Default - Iran Direct + Proxy)"
    echo "  🕹️ 2) Gaming            (Low latency, prefer stable nodes)"
    echo "  🛗 3) Streaming         (Better for YouTube / Netflix)"
    echo "  🌎 4) Global Proxy      (All traffic through proxy)"
    echo "  🎯 5) Direct Only       (No proxy)"
    echo "  ───────────────────────────────────────────────────────────"
}

# ------------------------------------------------------------
# Apply a profile
# ------------------------------------------------------------
apply_profile() {
    local profile="$1"

    case "$profile" in
        balanced)
            echo "balanced" > "$PROFILE_DIR/active"
            echo "iran_direct" > "$PROXY_DIR/routing/current_mode" 2>/dev/null
            log_success "Profile [⚖️ Balanced] applied!"
            log_info "Iranian sites → Direct | Foreign sites → Proxy!"
            ;;
        gaming)
            echo "gaming" > "$PROFILE_DIR/active"
            log_success "Profile [🕹️ Gaming] applied!"
            log_info "Optimized for low latency and stable connection!"
            ;;
        streaming)
            echo "streaming" > "$PROFILE_DIR/active"
            log_success "Profile [🛗 Streaming] applied!"
            log_info "Optimized for video streaming services!"
            ;;
        global)
            echo "global" > "$PROFILE_DIR/active"
            echo "global_proxy" > "$PROXY_DIR/routing/current_mode" 2>/dev/null
            log_success "Profile [🌎 Global Proxy] applied!"
            log_info "All traffic will go through proxy!"
            ;;
        direct)
            echo "direct" > "$PROFILE_DIR/active"
            echo "direct_only" > "$PROXY_DIR/routing/current_mode" 2>/dev/null
            log_success "Profile [🎯 Direct Only] applied!"
            log_info "Proxy is disabled. All traffic is direct!"
            ;;
        *)
            log_error "Unknown profile!"
            return 1
            ;;
    esac
}

# ------------------------------------------------------------
# Show current active profile
# ------------------------------------------------------------
show_active_profile() {
    echo "  🎭 Current Active Profile"
    if [ -f "$PROFILE_DIR/active" ]; then
        active=$(cat "$PROFILE_DIR/active")
        echo "    🫀 Active Profile : ${GREEN}$active${RESET}"
    else
        echo "    🫀 Active Profile : ${GRAY}None${RESET}"
    fi
    echo ""
}

# ------------------------------------------------------------
# Main Menu
# ------------------------------------------------------------
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

        printf "\n  ${GRAY}Press [Enter] to continue ... ${RESET}"
        read -r _ </dev/tty
    done
}