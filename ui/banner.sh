#!/bin/sh

# Single source of truth for the version shown in the UI, the system
# login banner (/etc/banner) and the help metadata.
DAYPASS_VERSION="v2.1.1"

# The logo carries backslashes and a backtick, and the colors come from
# variables. printf with a literal format keeps every row byte for byte:
# nothing in the art or in a color variable is ever read as an escape
# sequence or as a format specifier.
# $1 left half (red), $2 right half (white), $3 optional trailing text
_banner_row()
{
    printf '%s%s%s%s%s%s%s\n' "$RED" "$1" "$RESET" "$WHITE" "$2" "$RESET" "$3"
}

show_banner()
{
    VERSION="${DAYPASS_VERSION}"

    printf '\n'

    _banner_row '   ____              ' ' ____               '
    _banner_row '  |  _ \  __ _ _   _ ' '|  _ \  __ _ ___ ___' "${GRAY} ${VERSION}${RESET}"
    _banner_row '  | | | |/ _` | | | |' '| |_) / _` / __/ __|'
    _banner_row '  | |_| | (_| | |_| |' '|  __/ (_| \__ \__ \'
    _banner_row '  |____/ \__,_|\__, |' '|_|   \__,_|___/___/'
    _banner_row '               |___/ ' ''

    printf '%s%s%s\n' "$GRAY" \
        '  ───────────────────── 🕊️ Remembering the IRAN Massacre on Jan 8-9, 2026 ─────────────────────' \
        "$RESET"
    printf '\n'
}
