#!/bin/sh
# ============================================================
# Shared paths and proxy core detection
# ============================================================

PROXY_DIR="/etc/daypass/proxy"
CONFIG_DIR="$PROXY_DIR/configs"
CLEAN_IP_DIR="$PROXY_DIR/clean_ip"
CANDIDATE_FILE="$CLEAN_IP_DIR/candidates.txt"
RESULT_FILE="$CLEAN_IP_DIR/last_results.txt"

mkdir -p "$CLEAN_IP_DIR"
mkdir -p "$CONFIG_DIR"

# ------------------------------------------------------------
# Detect installed proxy core
# Returns: xray | sing-box | none
# ------------------------------------------------------------
detect_proxy_core() {
    if command -v xray >/dev/null 2>&1; then
        echo "xray"
        return
    fi

    if command -v sing-box >/dev/null 2>&1; then
        echo "sing-box"
        return
    fi

    echo "none"
}