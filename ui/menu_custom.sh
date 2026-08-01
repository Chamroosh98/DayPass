#!/bin/sh

show_custom_help()
{
    render_persistent_header
    echo "  📖 ${BOLD}Custom Selection Guide & Keyboard Shortcuts${RESET}"
    echo "  ──────────────────────────────────────────────────────────"
    echo "  🔹 ${YELLOW}Toggle Item (1-6):${RESET} Enter item number to Select [✔] or Deselect [ ]."
    echo "  🔹 ${YELLOW}Language Notice:${RESET} Selecting a new language (e.g. -fa) automatically"
    echo "     replaces previously selected translations for clean config."
    echo "  🔹 ${YELLOW}[n] / [p]:${RESET} Navigate to Next or Previous page."
    echo "  🔹 ${YELLOW}[d]:${RESET} Save your current selection and proceed to Review."
    echo "  ──────────────────────────────────────────────────────────"
    echo "  💡 ${CYAN}Pro-Tip:${RESET} Combining Sing-box and Xray together is supported,"
    echo "     but recommended mainly for powerful hardware (ARM64 / x86)."
    echo "  ──────────────────────────────────────────────────────────"
    echo
    printf "  ${GRAY}Press [ENTER] to return to selection menu ...${RESET}"
    read -r _ </dev/tty
}

toggle_custom_package()
{
    pkg_to_toggle="$1"

    case "$pkg_to_toggle" in
        luci-i18n-passwall*-*)
            base_prefix=$(echo "$pkg_to_toggle" | sed -E 's/-(fa|ru|zh-cn|zh-tw|en)$//')
            NEW_SEL=""
            for p in $SELECTED_PACKAGES; do
                case "$p" in
                    ${base_prefix}-*) ;;
                    *) NEW_SEL="$NEW_SEL $p" ;;
                esac
            done
            SELECTED_PACKAGES="$NEW_SEL"
            ;;
    esac

    if echo " $SELECTED_PACKAGES " | grep -q " $pkg_to_toggle "; then
        NEW_SEL=""
        for p in $SELECTED_PACKAGES; do
            [ "$p" != "$pkg_to_toggle" ] && NEW_SEL="$NEW_SEL $p"
        done
        SELECTED_PACKAGES="$NEW_SEL"
        log_info "Removed package : [$pkg_to_toggle]"
    else
        SELECTED_PACKAGES="$SELECTED_PACKAGES $pkg_to_toggle"
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

    SELECTED_PACKAGES=$(echo "$SELECTED_PACKAGES" | xargs)
    export SELECTED_PACKAGES
}

handle_custom_profile()
{
    if [ -z "$MANIFEST_FILE" ] || [ ! -f "$MANIFEST_FILE" ]; then
        if [ -f "/tmp/manifest.json" ]; then
            MANIFEST_FILE="/tmp/manifest.json"
        elif [ -f "manifest.json" ]; then
            MANIFEST_FILE="manifest.json"
        else
            OW_VER="25"
            [ "${PKG_MANAGER:-opkg}" = "opkg" ] && OW_VER="24"
            MANIFEST_FILE="build-artifacts/v${OW_VER}/manifest.json"
        fi
    fi

    FEED_NAME="${SELECTED_PROFILE:-passwall2}"

    ALL_AVAILABLE_PKGS="$(jq -r --arg arch "$ARCH" --arg feed "$FEED_NAME" \
        '.architectures[] | select(.name==$arch) | .feeds | to_entries[] | select(.key | contains($feed) or contains("packages") or contains("luci")) | .value[].package' \
        "$MANIFEST_FILE" 2>/dev/null | sort -u)"

    if [ -z "$ALL_AVAILABLE_PKGS" ]; then
        log_error "No packages found in manifest [$MANIFEST_FILE] for architecture : [$ARCH]"
        return 1
    fi

    PAGE_SIZE=6
    CURRENT_PAGE=1
    
    set -- $ALL_AVAILABLE_PKGS
    TOTAL_PKGS=$#
    TOTAL_PAGES=$(( (TOTAL_PKGS + PAGE_SIZE - 1) / PAGE_SIZE ))
    
    FIRST_RENDER=1

    while true; do
        render_persistent_header

        SEL_COUNT=0
        for _p in $SELECTED_PACKAGES; do
            SEL_COUNT=$((SEL_COUNT + 1))
        done

        echo "  🛠️ ${BOLD}Custom Package Selection${RESET} ${GRAY}(Page ${YELLOW}$CURRENT_PAGE${RESET}${GRAY}/$TOTAL_PAGES | Selected : ${GREEN}$SEL_COUNT${RESET}${GRAY})${RESET}"
        echo "  ${GRAY}──────────────────────────────────────────────────────────${RESET}"

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

        echo "  ${GRAY}──────────────────────────────────────────────────────────${RESET}"
        echo "  ${GRAY}[${CYAN}n${RESET}${GRAY}] Next Page | [${CYAN}p${RESET}${GRAY}] Prev Page | [${YELLOW}h${RESET}${GRAY}] Help | [${GREEN}d${RESET}${GRAY}] Done${RESET}"
        echo

        printf "  ⁉️ ${YELLOW}Toggle Item${RESET} ${GRAY}(1-$((item_no - 1))) or Action (${CYAN}n${RESET}${GRAY}/${CYAN}p${RESET}${GRAY}/${YELLOW}h${RESET}${GRAY}/${GREEN}d${RESET}${GRAY}) :${RESET} "
        read -r cmd </dev/tty

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
            d|D)
                if [ -z "$SELECTED_PACKAGES" ]; then
                    log_warn "No packages selected! Please select at least one package!"
                    sleep 1
                else
                    log_info "Custom package selection saved!"
                    break
                fi
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