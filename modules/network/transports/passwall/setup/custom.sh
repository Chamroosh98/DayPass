#!/bin/sh

show_custom_help()
{
    render_persistent_header
    echo "  📖 ${BOLD}Custom Selection Guide & Keyboard Shortcuts${RESET}"
    ui_divider
    echo "  🔹 ${YELLOW}Toggle Item (1-6):${RESET} Enter item number to Select [✔] or Deselect [ ]."
    echo "  🔹 Choose the engine, translation and Geo data after saving this list."
    echo "  🔹 ${YELLOW}[n] / [p]:${RESET} Next or previous page on the navigation bar."
    echo "  🔹 ${YELLOW}[d]:${RESET} Save the current selection and continue to Review."
    _nav_muted="${COLOR_MUTED:-$GRAY}"
    printf "  ${_nav_muted}0) Back / Skip${RESET}\n"
    printf "  ${_nav_muted}q) Quit DayPass${RESET}\n"
    ui_divider
    echo "  💡 ${CYAN}Pro-Tip:${RESET} Combining Sing-box and Xray together is supported,"
    echo "     but recommended mainly for powerful hardware (ARM64 / x86)."
    echo
    printf "  ${GRAY}Press [ENTER] to return to selection menu ...${RESET}"
    read -r _ </dev/tty || daypass_quit
}

toggle_custom_package()
{
    local pkg_to_toggle="$1" p new_selection="" translation_prefix=""
    local selected=no

    case " $SELECTED_PACKAGES " in
        *" $pkg_to_toggle "*) selected=yes ;;
    esac
    case "$pkg_to_toggle" in
        luci-i18n-passwall2-*) translation_prefix=luci-i18n-passwall2- ;;
        luci-i18n-passwall-*) translation_prefix=luci-i18n-passwall- ;;
    esac
    for p in $SELECTED_PACKAGES; do
        [ "$p" != "$pkg_to_toggle" ] || continue
        if [ "$selected" = no ] && [ -n "$translation_prefix" ]; then
            case "$p" in "$translation_prefix"*) continue ;; esac
        fi
        new_selection="${new_selection:+$new_selection }$p"
    done

    if [ "$selected" = yes ]; then
        SELECTED_PACKAGES="$new_selection"
        log_info "Removed package [$pkg_to_toggle]"
    else
        SELECTED_PACKAGES="${new_selection:+$new_selection }$pkg_to_toggle"
        log_success "Selected package: [$pkg_to_toggle]"

        if [ "$pkg_to_toggle" = "sing-box" ] || [ "$pkg_to_toggle" = "xray-core" ]; then
            case "${ARCH:-}" in
                *mips*|*ramips*|*aarch64_cortex-a53*)
                    echo
                    log_warn "⚠️ PERFORMANCE NOTICE : Engine [$pkg_to_toggle] on architecture [$ARCH]"
                    log_warn "Running heavy proxy engines alongside Passwall on low-resource hardware may cause high CPU/RAM usage!"
                    sleep 1
                    ;;
            esac
        fi
    fi

    export SELECTED_PACKAGES
}

# Same horizontal pager as the manuals, plus save and help.
custom_render_nav_bar() {
    if command -v render_pager_footer >/dev/null 2>&1; then
        render_pager_footer "${CURRENT_PAGE:-1}" "${TOTAL_PAGES:-1}" \
            "${GREEN}d) Save & Continue${RESET}" \
            "h) Help"
        return 0
    fi
    ui_divider
    echo "  n) Next   p) Previous   0) Back / Skip   q) Quit DayPass   d) Save & Continue   h) Help"
}

handle_custom_profile()
{
    local TARGET_PROFILE ALL_AVAILABLE_PKGS APP_FEED candidate
    local PAGE_SIZE CURRENT_PAGE TOTAL_PKGS TOTAL_PAGES
    local FIRST_RENDER SEL_COUNT _p START_IDX END_IDX item_no curr_idx pkg is_selected
    local _last cmd TARGET_INDEX idx saved_packages

    if ! load_package_profiles || ! _pr_detect_environment; then
        log_error "Could not determine the package profile or router release."
        ui_pause
        return 2
    fi
    if ! _pr_locate_manifest; then
        for candidate in \
            "${DAYPASS_HOME:-.}/manifest.json" \
            "${DAYPASS_HOME:-.}/build-artifacts/v$PROFILE_RELEASE/manifest.json" \
            "build-artifacts/v$PROFILE_RELEASE/manifest.json"; do
            if [ -s "$candidate" ] && _pr_valid_manifest "$candidate"; then
                _PR_MANIFEST="$candidate"
                break
            fi
        done
    fi

    if [ -z "$_PR_MANIFEST" ]; then
        log_error "No valid package manifest for $_PR_ARCH on OpenWrt $PROFILE_RELEASE."
        ui_pause
        return 2
    fi
    MANIFEST_FILE="$_PR_MANIFEST"
    TARGET_PROFILE="${SELECTED_PROFILE:-passwall2}"
    case "$TARGET_PROFILE" in passwall) APP_FEED=passwall_luci ;; *) APP_FEED=passwall2 ;; esac

    if ! ALL_AVAILABLE_PKGS="$(jq -r --arg arch "$_PR_ARCH" --arg app_feed "$APP_FEED" '
        [
            .architectures[] | select(.name == $arch) | .feeds as $feeds
            | ($feeds[$app_feed][]?, $feeds.passwall_packages[]?,
                (if $app_feed == "passwall_luci" then $feeds.passwall[]? else empty end))
            | .package | strings
            | select(test("^luci-app-passwall2?$|^luci-i18n-") | not)
        ] | unique[]
    ' "$MANIFEST_FILE" 2>/dev/null)"; then
        log_error "Could not read package choices from [$MANIFEST_FILE]."
        ui_pause
        return 2
    fi

    PAGE_SIZE=6
    CURRENT_PAGE=1
    
    set -- $ALL_AVAILABLE_PKGS
    TOTAL_PKGS=$#
    TOTAL_PAGES=$(( (TOTAL_PKGS + PAGE_SIZE - 1) / PAGE_SIZE ))
    [ "$TOTAL_PAGES" -gt 0 ] || TOTAL_PAGES=1
    
    FIRST_RENDER=1

    while true; do
        render_persistent_header

        SEL_COUNT=0
        for _p in $SELECTED_PACKAGES; do
            SEL_COUNT=$((SEL_COUNT + 1))
        done

        echo "  🛠️ ${BOLD}Custom Package Selection${RESET} ${GRAY}(Selected: ${GREEN}$SEL_COUNT${RESET}${GRAY})${RESET}"
        ui_divider "$GRAY"
        printf '  %s\n' "The profile includes the selected Passwall app and its base tools."

        START_IDX=$(( (CURRENT_PAGE - 1) * PAGE_SIZE + 1 ))
        END_IDX=$(( CURRENT_PAGE * PAGE_SIZE ))

        item_no=1
        curr_idx=1
        
        for pkg in "$@"; do
            if [ "$curr_idx" -ge "$START_IDX" ] && [ "$curr_idx" -le "$END_IDX" ]; then
                
                is_selected="${GRAY}[ ]${RESET}"
                case " $SELECTED_PACKAGES " in
                    *" $pkg "*) is_selected="${GREEN}[✔]${RESET}" ;;
                esac
                
                printf "   ${CYAN}%d${RESET}) %b %s\n" "$item_no" "$is_selected" "$pkg"
                
                if [ "$FIRST_RENDER" -eq 1 ]; then
                    command -v usleep >/dev/null 2>&1 && usleep 12000
                fi

                item_no=$((item_no + 1))
            fi
            curr_idx=$((curr_idx + 1))
        done

        FIRST_RENDER=0

        custom_render_nav_bar

        _last=$((${item_no:-1} - 1))
        if [ "$_last" -gt 0 ]; then
            printf "  ⁉️ Select option or toggle [1-%s] : " "$_last"
        else
            printf "  ⁉️ Select option : "
        fi
        read -r cmd </dev/tty || daypass_quit

        case "$cmd" in
            n|N)
                [ "$CURRENT_PAGE" -lt "$TOTAL_PAGES" ] && CURRENT_PAGE=$((CURRENT_PAGE + 1))
                ;;
            p|P)
                [ "$CURRENT_PAGE" -gt 1 ] && CURRENT_PAGE=$((CURRENT_PAGE - 1))
                ;;
            h|H)
                show_custom_help
                ;;
            q|Q)
                daypass_quit
                ;;
            0)
                log_warn "Custom selection cancelled."
                SELECTED_PACKAGES=""
                return 1
                ;;
            d|D)
                saved_packages="$SELECTED_PACKAGES"
                if engine_menu && language_menu && geo_menu; then
                    log_info "Custom package selection and preferences saved."
                    break
                fi
                SELECTED_PACKAGES="$saved_packages"
                ;;
            [1-9])
                if [ "$cmd" -ge 1 ] && [ "$cmd" -lt "$item_no" ]; then
                    TARGET_INDEX=$(( START_IDX + cmd - 1 ))
                    idx=1
                    for pkg in "$@"; do
                        if [ "$idx" -eq "$TARGET_INDEX" ]; then
                            toggle_custom_package "$pkg"
                            break
                        fi
                        idx=$((idx + 1))
                    done
                else
                    log_warn "Invalid selection range!"
                    sleep 1
                fi
                ;;
            *)
                log_warn "Invalid command!"
                sleep 1
                ;;
        esac
    done
}
