#!/bin/sh
# pkg-switch.sh - Universal package feed switcher for OpenWrt 24 (opkg) & 25 (apk)
# Usage: pkg-switch.sh [http|https|test|auto|rollback|status|help]

# ============ Auto-detect package manager ============

if command -v apk > /dev/null 2>&1; then
    PM="apk"
    CONF="/etc/apk/repositories.d/distfeeds.list"
    BACKUP_EXT="list"
elif command -v opkg > /dev/null 2>&1; then
    PM="opkg"
    CONF="/etc/opkg/distfeeds.conf"
    BACKUP_EXT="conf"
else
    echo "[!] Neither apk nor opkg found. Unsupported system."
    exit 1
fi

BACKUP_DIR="/root/pkg-backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p "$BACKUP_DIR"

# ============ Functions ============

backup_conf() {
    if [ -f "$CONF" ]; then
        cp "$CONF" "$BACKUP_DIR/distfeeds-$TIMESTAMP.$BACKUP_EXT"
        echo -e "${BLUE}[+] Backup saved: $BACKUP_DIR/distfeeds-$TIMESTAMP.$BACKUP_EXT${NC}"
    else
        echo -e "${RED}[!] Config file not found: $CONF${NC}"
        exit 1
    fi
}

set_protocol() {
    PROTO="$1"
    if [ "$PROTO" != "http" ] && [ "$PROTO" != "https" ]; then
        echo -e "${RED}[!] Invalid protocol: $PROTO${NC}"
        exit 1
    fi

    backup_conf

    if [ "$PROTO" = "http" ]; then
        sed -i 's|https://downloads.openwrt.org|http://downloads.openwrt.org|g' "$CONF"
        echo -e "${GREEN}[+] Switched to HTTP (using $PM)${NC}"
    else
        sed -i 's|http://downloads.openwrt.org|https://downloads.openwrt.org|g' "$CONF"
        echo -e "${GREEN}[+] Switched to HTTPS (using $PM)${NC}"
    fi

    echo -e "${BLUE}[i] Current content:${NC}"
    cat "$CONF"
}

test_pm() {
    echo -e "${YELLOW}[*] Testing $PM update...${NC}"
    echo ""

    rm -rf /var/opkg-lists/* 2>/dev/null
    rm -rf /var/cache/apk/* 2>/dev/null

    if timeout 30 $PM update > /tmp/pm-test.log 2>&1; then
        echo -e "${GREEN}[+] $PM update succeeded!${NC}"
        echo ""
        echo "[i] Summary:"
        grep -iE "updated|downloading|ok" /tmp/pm-test.log | head -20
        return 0
    else
        echo -e "${RED}[!] $PM update failed${NC}"
        echo ""
        echo "[i] Errors:"
        grep -iE "failed|error|unable|signature" /tmp/pm-test.log | head -10
        return 1
    fi
}

auto_test() {
    echo -e "${BLUE}[*] Package manager detected: ${YELLOW}$PM${BLUE}${NC}"
    echo -e "${BLUE}[*] Config file: ${YELLOW}$CONF${BLUE}${NC}"
    echo ""

    CURRENT=$(grep -o 'http[s]*://downloads' "$CONF" | head -1 | cut -d: -f1)
    echo -e "Current state: ${YELLOW}$CURRENT${NC}"
    echo ""

    echo -e "${BLUE}=== Test 1: HTTPS ===${NC}"
    set_protocol https
    if test_pm; then
        echo ""
        echo -e "${GREEN}[+] HTTPS works! Keep it.${NC}"
        exit 0
    fi

    echo ""
    echo -e "${YELLOW}[!] HTTPS failed, trying HTTP...${NC}"
    echo ""

    echo -e "${BLUE}=== Test 2: HTTP ===${NC}"
    set_protocol http
    if test_pm; then
        echo ""
        echo -e "${GREEN}[+] HTTP works! Keep it.${NC}"
        exit 0
    fi

    echo ""
    echo -e "${RED}[!] Neither worked! You need a tunnel/proxy.${NC}"
    echo ""
    echo -e "${YELLOW}[i] Solution: SSH tunnel from your PC:${NC}"
    echo "   ssh -R 10900:127.0.0.1:10810 root@192.168.1.1 -N"
    echo ""
    echo -e "${YELLOW}Then on the router:${NC}"
    echo "   export http_proxy=http://127.0.0.1:10900"
    echo "   export https_proxy=http://127.0.0.1:10900"
    echo "   $PM update"
    exit 1
}

rollback() {
    echo -e "${YELLOW}[*] Rolling back...${NC}"

    LATEST=$(ls -t "$BACKUP_DIR"/distfeeds-*.$BACKUP_EXT 2>/dev/null | head -1)

    if [ -z "$LATEST" ]; then
        echo -e "${RED}[!] No backup found!${NC}"
        echo -e "Backup dir: $BACKUP_DIR"
        ls -la "$BACKUP_DIR" 2>/dev/null
        exit 1
    fi

    echo -e "Latest backup: ${BLUE}$LATEST${NC}"
    cp "$LATEST" "$CONF"
    echo -e "${GREEN}[+] Rollback complete${NC}"
    echo ""
    cat "$CONF"
}

show_status() {
    echo -e "${BLUE}[i] System status:${NC}"
    echo ""
    echo -e "${YELLOW}Package manager:${NC} $PM"
    echo -e "${YELLOW}Config file:${NC} $CONF"
    echo ""
    echo -e "${YELLOW}Current content:${NC}"
    cat "$CONF" 2>/dev/null
    echo ""
    echo -e "${YELLOW}Current protocol:${NC}"
    grep -o 'http[s]*://downloads' "$CONF" | head -1
    echo ""
    echo -e "${YELLOW}Proxy variables:${NC}"
    echo "http_proxy=$http_proxy"
    echo "https_proxy=$https_proxy"
    echo ""
    echo -e "${YELLOW}Available backups:${NC}"
    ls -lt "$BACKUP_DIR"/distfeeds-*.$BACKUP_EXT 2>/dev/null | head -5
}

show_help() {
    echo "pkg-switch.sh - Universal OpenWrt package feed switcher"
    echo "Supports: OpenWrt 24 (opkg) & OpenWrt 25 (apk)"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  http       - Switch to HTTP"
    echo "  https      - Switch to HTTPS"
    echo "  test       - Test update with current protocol"
    echo "  auto       - Auto-test both protocols"
    echo "  rollback   - Restore latest backup"
    echo "  status     - Show current status"
    echo "  help       - Show this help"
    echo ""
}

# ============ Main ============

case "$1" in
    http)
        set_protocol http
        ;;
    https)
        set_protocol https
        ;;
    test)
        test_pm
        ;;
    auto)
        auto_test
        ;;
    rollback)
        rollback
        ;;
    status)
        show_status
        ;;
    help|--help|-h|"")
        show_help
        ;;
    *)
        echo -e "${RED}[!] Invalid command: $1${NC}"
        show_help
        exit 1
        ;;
esac