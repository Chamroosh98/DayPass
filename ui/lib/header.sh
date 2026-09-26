#!/bin/sh

# Start every UI screen the same way: clear, then the DayPass banner.
render_persistent_header()
{
    clear
    if command -v show_banner >/dev/null 2>&1; then
        show_banner
    fi
    echo
}
