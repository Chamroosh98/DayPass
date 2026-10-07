#!/bin/sh

# Same resolution the generated install.sh runs before this file.
# Skipped when the entrypoint already exported DAYPASS_HOME.
if [ -z "${DAYPASS_HOME:-}" ]; then
    _dp_invoked="$0"
    case "$_dp_invoked" in
        */*) ;;
        *)
            _dp_via=$(command -v "$_dp_invoked" 2>/dev/null || true)
            [ -n "$_dp_via" ] && _dp_invoked="$_dp_via"
            ;;
    esac
    REAL_SCRIPT=$(readlink -f "$_dp_invoked" 2>/dev/null || echo "$_dp_invoked")
    case "$REAL_SCRIPT" in
        /*) ;;
        *) REAL_SCRIPT="$(pwd)/$REAL_SCRIPT" ;;
    esac
    DAYPASS_HOME=$(CDPATH= cd -- "$(dirname "$REAL_SCRIPT")" >/dev/null 2>&1 && pwd) || DAYPASS_HOME=$(pwd)
    export REAL_SCRIPT DAYPASS_HOME
    unset _dp_invoked _dp_via
fi

export DAYPASS_DIR="/etc/daypass"
export INSTALL_LOG="$DAYPASS_DIR/install.log"
export DAYPASS_MANIFEST="$DAYPASS_DIR/installed_manifest.json"
export TRANSACTION_LOG="/tmp/daypass/transaction.log" 