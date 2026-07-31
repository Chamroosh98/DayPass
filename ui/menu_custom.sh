#!/bin/sh

handle_custom_profile()
{
    # Dynamic manifest determination for opkg (24) vs apk (25)
    if [ -z "$MANIFEST_FILE" ]; then
        if [ "${PKG_MANAGER:-opkg}" = "apk" ]; then
            MANIFEST_FILE="config/architectures_25.json"
        else
            MANIFEST_FILE="config/architectures_24.json"
        fi
    fi

    ALL_AVAILABLE_PKGS="$(jq -r --arg arch "$ARCH" '.architectures[] | select(.name==$arch) | .packages[].package' "$MANIFEST_FILE" 2>/dev/null)"

    if [ -z "$ALL_AVAILABLE_PKGS" ]; then
        log_error "No packages found in manifest [$MANIFEST_FILE] for architecture: $ARCH"
        return 1
    fi

    PAGE_SIZE=5
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

        echo "  🛠️  ${BOLD}Custom Package Selection${RESET} ${GRAY}(Page ${YELLOW}$CURRENT_PAGE${RESET}${GRAY}/$TOTAL_PAGES | Selected: ${GREEN}$SEL_COUNT${RESET}${GRAY})${RESET}"
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
        echo "   ${GRAY}[${CYAN}n${RESET}${GRAY}] Next Page  |  [${CYAN}p${RESET}${GRAY}] Prev Page  |  [${GREEN}d${RESET}${GRAY}] Done Selection${RESET}"
        echo

        printf "   ⁉️  ${YELLOW}Toggle Item${RESET} ${GRAY}(1-$((item_no - 1))) or Action (${CYAN}n${RESET}${GRAY}/${CYAN}p${RESET}${GRAY}/${GREEN}d${RESET}${GRAY}) :${RESET} "
        read -r cmd </dev/tty

        case "$cmd" in
            n|N)
                [ "$CURRENT_PAGE" -lt "$TOTAL_PAGES" ] && CURRENT_PAGE=$((CURRENT_PAGE + 1))
                ;;
            p|P)
                [ "$CURRENT_PAGE" -gt 1 ] && CURRENT_PAGE=$((CURRENT_PAGE - 1))
                ;;
            d|D)
                log_info "Custom package selection saved."
                break
                ;;
            [1-9])
                if [ "$cmd" -ge 1 ] && [ "$cmd" -lt "$item_no" ]; then
                    TARGET_INDEX=$(( START_IDX + cmd - 1 ))
                    idx=1
                    for pkg in "$@"; do
                        if [ "$idx" -eq "$TARGET_INDEX" ]; then
                            add_selected_package "$pkg"
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