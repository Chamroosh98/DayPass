#!/bin/sh
# ============================================================
# DayPass - In-App Help Viewer & Manual Index
# Renders the JSON manuals cached by ui/lib/help.sh.
# The viewer uses a compact header (no banner) so a full page
# of manual entries fits a standard 24-row SSH terminal.
# ============================================================

HELP_ITEM_INDENT="       "
HELP_LIST_FILE=""
HELP_TAB="$(printf '\t')"

# ------------------------------------------------------------
# Detected terminal height (falls back to 24 rows)
# ------------------------------------------------------------
help_rows() {
    HELP_ROWS=$(stty size 2>/dev/null | awk 'NR==1 {print $1+0}')
    [ -z "$HELP_ROWS" ] && HELP_ROWS=0
    [ "$HELP_ROWS" -le 0 ] && HELP_ROWS=24
    echo "$HELP_ROWS"
}

# ------------------------------------------------------------
# How many manual entries fit on one page
# ------------------------------------------------------------
help_item_page_size() {
    HELP_ROWS="$(help_rows)"
    if [ "$HELP_ROWS" -ge 44 ]; then
        echo 4
    elif [ "$HELP_ROWS" -ge 32 ]; then
        echo 3
    else
        echo 2
    fi
}

# ------------------------------------------------------------
# How many manuals fit in the global help index
# ------------------------------------------------------------
help_list_page_size() {
    HELP_ROWS="$(help_rows)"
    if [ "$HELP_ROWS" -ge 40 ]; then
        echo 8
    elif [ "$HELP_ROWS" -ge 30 ]; then
        echo 6
    else
        echo 4
    fi
}

# ------------------------------------------------------------
# Wrap text to terminal-friendly lines
# ------------------------------------------------------------
help_wrap() {
    HELP_TEXT="$1"
    HELP_PREFIX="$2"
    HELP_WIDTH="${3:-66}"

    printf '%s\n' "$HELP_TEXT" | awk -v pre="$HELP_PREFIX" -v w="$HELP_WIDTH" '
    {
        n = split($0, word, " ")
        line = pre
        for (i = 1; i <= n; i++) {
            if (word[i] == "") continue
            if (length(line) > length(pre) && length(line) + length(word[i]) + 1 > w) {
                print line
                line = pre word[i]
            } else if (length(line) > length(pre)) {
                line = line " " word[i]
            } else {
                line = line word[i]
            }
        }
        if (length(line) > length(pre)) print line
    }'
}

# ------------------------------------------------------------
# Friendly message when a manual cannot be loaded at all
# ------------------------------------------------------------
help_unavailable() {
    HELP_LABEL="${1:-Manual}"

    echo
    log_warn "Manual unavailable"
    echo "  ${GRAY}[${HELP_LABEL}] has no cached copy, and jq or the download failed.${RESET}"
    echo "  ${GRAY}Cache directory : [$(help_cache_dir)]${RESET}"
    echo
    printf "  ${GRAY}Press [Enter] to continue ...${RESET}"
    read -r _ </dev/tty
    return 0
}

# ------------------------------------------------------------
# Contextual help screen for one module manual
# ------------------------------------------------------------
show_help() {
    HELP_ID="$1"

    if [ -z "$HELP_ID" ] || ! command -v jq >/dev/null 2>&1; then
        help_unavailable "${HELP_ID:-Help}"
        return 0
    fi

    if ! help_ensure_manual "$HELP_ID"; then
        help_unavailable "$HELP_ID"
        return 0
    fi

    HELP_FILE="$(help_manual_path "$HELP_ID")"

    HELP_TOTAL=$(jq '.items | length' "$HELP_FILE" 2>/dev/null)
    case "$HELP_TOTAL" in
        ''|*[!0-9]*) HELP_TOTAL=0 ;;
    esac

    HELP_PAGE_SIZE="$(help_item_page_size)"
    HELP_PAGES=$(( (HELP_TOTAL + HELP_PAGE_SIZE - 1) / HELP_PAGE_SIZE ))
    [ "$HELP_PAGES" -lt 1 ] && HELP_PAGES=1
    HELP_PAGE=1

    while true; do
        clear

        HELP_TITLE=$(jq -r '.title // "Help"' "$HELP_FILE" 2>/dev/null)
        HELP_SUMMARY=$(jq -r '.summary // ""' "$HELP_FILE" 2>/dev/null)

        echo "  📖 ${BOLD}${HELP_TITLE}${RESET}"
        echo "  ───────────────────────────────────────────────────────────"
        if [ -n "$HELP_SUMMARY" ]; then
            help_wrap "$HELP_SUMMARY" "  " 66
        fi
        echo "  ───────────────────────────────────────────────────────────"

        jq -r \
            --argjson s "$(( (HELP_PAGE - 1) * HELP_PAGE_SIZE ))" \
            --argjson e "$(( HELP_PAGE * HELP_PAGE_SIZE ))" '
            .items[$s:$e][]? |
            "K\u0009\(.key)\u0009\(.title)",
            "D\u0009\(.description // "")",
            "T\u0009\(.usage_tip // "")"
        ' "$HELP_FILE" 2>/dev/null | while IFS="$HELP_TAB" read -r HELP_TAG HELP_F1 HELP_F2; do
            case "$HELP_TAG" in
                K)
                    echo
                    printf "  ${CYAN}${BOLD}%s)${RESET} ${BOLD}%s${RESET}\n" "$HELP_F1" "$HELP_F2"
                    ;;
                D)
                    if [ -n "$HELP_F1" ]; then
                        help_wrap "$HELP_F1" "$HELP_ITEM_INDENT" 66
                    fi
                    ;;
                T)
                    if [ -n "$HELP_F1" ]; then
                        help_wrap "$HELP_F1" "${HELP_ITEM_INDENT}💡 " 66
                    fi
                    ;;
            esac
        done

        echo "  ───────────────────────────────────────────────────────────"
        printf "  ${GRAY}Page ${YELLOW}%s${GRAY}/${YELLOW}%s${GRAY} | [n] Next | [p] Prev | [Enter] Return${RESET}\n" \
            "$HELP_PAGE" "$HELP_PAGES"
        printf "  ⁉️ ${YELLOW}Option${RESET} ${GRAY}(n/p/Enter) :${RESET} "
        read -r HELP_CMD </dev/tty

        case "$HELP_CMD" in
            n|N)
                [ "$HELP_PAGE" -lt "$HELP_PAGES" ] && HELP_PAGE=$((HELP_PAGE + 1))
                ;;
            p|P)
                [ "$HELP_PAGE" -gt 1 ] && HELP_PAGE=$((HELP_PAGE - 1))
                ;;
            ''|q|Q)
                return 0
                ;;
            *)
                log_warn "Use [n] Next, [p] Prev or [Enter] to return."
                sleep 1
                ;;
        esac
    done
}

# ------------------------------------------------------------
# Global help index (driven by help/index.json)
# ------------------------------------------------------------
help_menu() {
    HELP_LIST_FILE="/tmp/.daypass_help_index.$$"
    HELP_PAGE=1

    while true; do
        clear

        echo "  📖 ${BOLD}Help & Manuals${RESET}"
        echo "  ───────────────────────────────────────────────────────────"

        if ! command -v jq >/dev/null 2>&1; then
            rm -f "$HELP_LIST_FILE" 2>/dev/null
            help_unavailable "index"
            return 0
        fi

        if ! help_ensure_manual "index"; then
            rm -f "$HELP_LIST_FILE" 2>/dev/null
            help_unavailable "index"
            return 0
        fi

        jq -r '
            .manuals[]? |
            "\(.module_id)\u0009\(.title)\u0009\(.item_count // 0)\u0009\(.reachable_from // "")"
        ' "$(help_manual_path index)" > "$HELP_LIST_FILE" 2>/dev/null

        HELP_TOTAL=$(wc -l < "$HELP_LIST_FILE" 2>/dev/null | tr -d ' ')
        case "$HELP_TOTAL" in
            ''|*[!0-9]*) HELP_TOTAL=0 ;;
        esac

        if [ "$HELP_TOTAL" -eq 0 ]; then
            log_warn "No manuals available!"
            rm -f "$HELP_LIST_FILE" 2>/dev/null
            sleep 1
            return 1
        fi

        HELP_LIST_SIZE="$(help_list_page_size)"
        HELP_PAGES=$(( (HELP_TOTAL + HELP_LIST_SIZE - 1) / HELP_LIST_SIZE ))
        HELP_PAGE_START=$(( (HELP_PAGE - 1) * HELP_LIST_SIZE + 1 ))
        HELP_PAGE_END=$(( HELP_PAGE * HELP_LIST_SIZE ))
        [ "$HELP_PAGE_END" -gt "$HELP_TOTAL" ] && HELP_PAGE_END=$HELP_TOTAL

        HELP_IDX=$(( HELP_PAGE_START - 1 ))
        sed -n "${HELP_PAGE_START},${HELP_PAGE_END}p" "$HELP_LIST_FILE" | \
        while IFS="$HELP_TAB" read -r HELP_MID HELP_MTITLE HELP_MCOUNT HELP_MFROM; do
            HELP_IDX=$((HELP_IDX + 1))
            HELP_NO=$(( HELP_IDX - HELP_PAGE_START + 1 ))
            printf "  ${CYAN}%s${RESET}) %s ${GRAY}(%s entries)${RESET}\n" \
                "$HELP_NO" "$HELP_MTITLE" "$HELP_MCOUNT"
            if [ -n "$HELP_MFROM" ]; then
                printf "      ${GRAY}↳ %s${RESET}\n" "$HELP_MFROM"
            fi
        done

        echo "  ───────────────────────────────────────────────────────────"
        printf "  ${GRAY}Page ${YELLOW}%s${GRAY}/${YELLOW}%s${GRAY} | [n] Next | [p] Prev | [r] Refresh | [Enter] Back${RESET}\n" \
            "$HELP_PAGE" "$HELP_PAGES"
        printf "  ⁉️ ${YELLOW}Manual number${RESET} ${GRAY}or action :${RESET} "
        read -r HELP_CMD </dev/tty

        case "$HELP_CMD" in
            n|N)
                [ "$HELP_PAGE" -lt "$HELP_PAGES" ] && HELP_PAGE=$((HELP_PAGE + 1))
                continue
                ;;
            p|P)
                [ "$HELP_PAGE" -gt 1 ] && HELP_PAGE=$((HELP_PAGE - 1))
                continue
                ;;
            r|R)
                help_cache_reset
                log_info "Manual cache cleared, re-downloading ..."
                sleep 1
                continue
                ;;
            ''|q|Q)
                rm -f "$HELP_LIST_FILE" 2>/dev/null
                return 0
                ;;
            *[!0-9]*)
                log_warn "Invalid choice!"
                sleep 1
                continue
                ;;
        esac

        if [ "$HELP_CMD" -ge 1 ] && [ "$HELP_CMD" -le $(( HELP_PAGE_END - HELP_PAGE_START + 1 )) ]; then
            HELP_LINE=$(( HELP_PAGE_START + HELP_CMD - 1 ))
            HELP_MID=$(sed -n "${HELP_LINE}p" "$HELP_LIST_FILE" | cut -f1)
            if [ -n "$HELP_MID" ]; then
                HELP_SAVED_PAGE=$HELP_PAGE
                show_help "$HELP_MID"
                HELP_PAGE=$HELP_SAVED_PAGE
            fi
        else
            log_warn "Invalid manual number!"
            sleep 1
        fi
    done
}


