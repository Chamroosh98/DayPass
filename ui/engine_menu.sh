#!/bin/sh

engine_menu()
{
    render_persistent_header

    echo "    🕵️‍♀️  Select Proxy Engine                                  "
    echo "  ───────────────────────────────────────────────────────────"
    echo "    1) ⚡ Auto      (Recommended)                            "
    echo "    2) ✖️ Xray      (Xray-core proxy engine)                 "
    echo "    3) 📦 Sing-box  (Sing-box proxy engine)                  "
    echo "  ───────────────────────────────────────────────────────────"
    echo

    printf "  ⁉️ Select option [1-3] (Default: 1) : "
    read -r choice </dev/tty

    case "$choice" in
        1|"")
            SELECTED_ENGINE="auto"
            ;;
        2)
            SELECTED_ENGINE="xray"
            add_selected_package "xray-core"
            ;;
        3)
            SELECTED_ENGINE="sing-box"
            echo
            log_warn "Sing-box may consume higher RAM on low-end hardware!"
            echo
            printf "  ⁉️  Are you sure you want to proceed with Sing-box? [y/N] : "
            read -r confirm </dev/tty

            case "$confirm" in
                y|Y)
                    add_selected_package "sing-box"
                    ;;
                *)
                    log_info "Reverting Proxy Engine selection to Auto."
                    SELECTED_ENGINE="auto"
                    ;;
            esac
            ;;
        *)
            log_warn "Invalid choice! Defaulting to Auto engine."
            SELECTED_ENGINE="auto"
            ;;
    esac

    export SELECTED_ENGINE
}