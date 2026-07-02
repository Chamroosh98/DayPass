#!/usr/bin/env bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/ui/colors.sh"

OUTPUT_DIR="$ROOT_DIR/output"

generate_install_script() {
    log_info "Step 3: Generating Smart Modular One-Liner Install Script..."
    
    if [ ! -d "$OUTPUT_DIR" ]; then
        log_error "Output directory not found! Run signer module first."
        exit 1
    fi

    local client_script="$OUTPUT_DIR/install.sh"

    # ۱. شروع ساخت فایل کلاینت با هدر استاندارد
    cat << 'EOF' > "$client_script"
#!/bin/sh
# DayPass Client Auto Installer for OpenWrt 25 (APK Packaging)
# 🕊 Remembering the IRAN massacre on January 8 and 9, 2026 ...
EOF

    # ۲. تزریق ماژولار رنگ‌ها مستقیم از فایل ui/colors.sh پروژه
    if [ -f "$ROOT_DIR/ui/colors.sh" ]; then
        grep -v '^#!' "$ROOT_DIR/ui/colors.sh" >> "$client_script"
    fi

    # ۳. تزریق بدنه اصلی منطق روتر به صورت کاملاً اصلاح شده
    cat << 'EOF' >> "$client_script"

clear

# نمایش بنر داینامیک
if command -v show_banner >/dev/null 2>&1; then
    show_banner
else
    echo -e "${CYAN}🕊️ DayPass Project By Chamroosh98${NC}"
fi

# تضمین وجود ابزار curl با بوت‌استرپ wget
if ! command -v curl >/dev/null 2>&1; then
    echo -e "${CYAN}[INFO]${NC} Bootstrapping full curl client for secure downloads..."
    apk update >/dev/null 2>&1 && apk add curl >/dev/null 2>&1
fi

# استخراج معماری فید به صورت کاملاً نیتیو و دقیق
UNAME_M=$(uname -m)
case "$UNAME_M" in
    x86_64)       ARCH="x86_64" ;;
    armv7l)       ARCH="arm_cortex-a7_neon-vfpv4" ;;
    aarch64)      ARCH="aarch64_generic" ;;
    mips)         ARCH="mips_24kc" ;;
    mipsel)       ARCH="mipsel_24kc" ;;
    *)            ARCH="$UNAME_M" ;;
esac

# تلمتری سیستم کاربر
router_model=$(ubus call system board 2>/dev/null | grep '"model":' | awk -F'"' '{print $4}')
os_release=$(ubus call system board 2>/dev/null | grep '"release":' | awk -F'"' '{print $4}')
[ -z "$router_model" ] && router_model="Generic OpenWrt Device"
[ -z "$os_release" ] && os_release="25.x (Bleeding Edge)"

public_ip=$(curl -sA "Mozilla/5.0" --connect-timeout 3 icanhazip.com 2>/dev/null | tr -d '\n')
if [ -z "$public_ip" ]; then
    public_ip="${RED}No Internet / Blocked 🔒${NC}"
else
    public_ip="${GREEN}${public_ip}${NC}"
fi

total_mem=$(free -m | awk '/Mem:/ {print $2}')
used_mem=$(free -m | awk '/Mem:/ {print $3}')
free_mem=$(free -m | awk '/Mem:/ {print $4}')

echo -e "${CYAN}SYSTEM TELEMETRY & RESOURCES:${NC}"
echo -e "  💅 Router Model   : ${YELLOW}${router_model}${NC}"
echo -e "  🩻 Firmware OS    : ${YELLOW}OpenWrt ${os_release}${NC}"
echo -e "  🖥️ Core Arch      : ${PURPLE}${ARCH}${NC} (${UNAME_M})"
echo -e "  🌍 Public WAN IP  : ${public_ip}"
echo -e "  🧠 Memory (RAM)   : ${used_mem}MB Used / ${free_mem}MB Free (${total_mem}MB Total)"
echo -e "  📦 Package Engine : ${GREEN}APK (Next-Gen)${NC}"
echo -e "${PURPLE}─────────────────────────────────────────────────${NC}"

REPO_URL="https://chamroosh98.github.io/DayPass"

# تزریق کلید عمومی مخزن
echo -e "${CYAN}[INFO]${NC} Injecting DayPass cryptographic public key..."
mkdir -p /etc/apk/keys/
curl -sL "$REPO_URL/daypass.pub" -o /etc/apk/keys/daypass.pub

if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR] Failed to download DayPass public key!${NC}"
    exit 1
fi
echo -e "${GREEN}[SUCCESS]${NC} Public key deployed safely inside /etc/apk/keys/"

# ست کردن فیدهای سه گانه APK متناسب با درخت دایرکتوری گیت‌هاب پیجز
echo -e "${CYAN}[INFO]${NC} Configuring custom APK feed repositories..."
mkdir -p /etc/apk/repositories.d/

# منطق جدید: چون خود APK اسم معماری را به انتهای آدرس می‌چسباند، 
# ساختار زیر دقیقاً به دایرکتوری‌های داخلی حاوی packages.adb اشاره خواهد کرد.
cat << REPOS > /etc/apk/repositories.d/daypass.list
$REPO_URL/passwall_packages
$REPO_URL/passwall2
$REPO_URL/passwall_luci
REPOS

# آپدیت مخازن و نصب پایانی
echo -e "${CYAN}[INFO]${NC} Re-indexing APK repositories with DayPass integration..."
apk update

echo -e "${CYAN}[INFO]${NC} Deploying Passwall 2 components... This may take a moment."
apk add luci-app-passwall passwall2

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[SUCCESS] Passwall successfully installed on OpenWrt 25! Enjoy freedom.${NC}"
else
    echo -e "${RED}[ERROR] Installation failed during APK package deployment.${NC}"
fi
EOF

    chmod +x "$client_script"
    log_success "Clean modular installer script compiled successfully at: $client_script"
}