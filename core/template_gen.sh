#!/usr/bin/env bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/ui/colors.sh"

OUTPUT_DIR="$ROOT_DIR/output"

generate_install_script() {
    log_info "Step 3: Generating One-Liner Install Script for users..."
    
    if [ ! -d "$OUTPUT_DIR" ]; then
        log_error "Output directory not found! Run signer module first."
        exit 1
    fi

    # ایجاد فایل install.sh درون پوشه output
    local client_script="$OUTPUT_DIR/install.sh"

    # نوشتن کدهایی که قراره روی روتر OpenWrt 25 کاربر اجرا بشن
    cat << 'EOF' > "$client_script"
#!/bin/sh
# DayPass Client Auto Installer for OpenWrt 25 (APK Packaging)
# 🕊 Remembering the IRAN massacre on January 8 and 9, 2026 ...

export CYAN="\033[1;38;5;51m"
export PURPLE="\033[38;5;141m"
export GREEN="\033[32m"
export RED="\033[31m"
export NC="\033[0m"

echo -e "${PURPLE}============================================================${NC}"
echo -e "${CYAN}🕊 Initializing DayPass Packages for OpenWrt 25...${NC}"
echo -e "${PURPLE}============================================================${NC}"

# ۱. تشخیص خودکار معماری روتر (بدون هاردکد کردن)
ARCH=$(apk architecture 2>/dev/null)
if [ -z "$ARCH" ]; then
    # اگر دستور apk architecture نبود از روش سنتی اوپن‌ورت استفاده می‌کنیم
    ARCH=$(opkg info base-files | grep "Architecture:" | awk '{print $2}')
fi

if [ -z "$ARCH" ]; then
    echo -e "${RED}[ERROR] Could not detect router architecture!${NC}"
    exit 1
fi

echo -e "${CYAN}[INFO]${NC} Detected Architecture: ${PURPLE}$ARCH${NC}"

# آدرس گیت‌هاب پیج تو (این بخش موقع ریلیز واقعی آدرس مستقیم ریپوی تو می‌شه)
# فعلاً برچسب داینامیک می‌ذاریم که اسکریپت آدرس خودش رو پیدا کنه یا هاردکد می‌کنیم:
REPO_URL="https://chamroosh98.github.io/DayPass"

# ۲. دانلود و ست کردن کلید عمومی مخزن تو روی روتر (حل قطعی مشکل لایسنس ردیت)
echo -e "${CYAN}[INFO]${NC} Injecting DayPass cryptographic public key..."
mkdir -p /etc/apk/keys/
curl -sL "$REPO_URL/daypass.pub" -o /etc/apk/keys/daypass.pub

if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR] Failed to download DayPass repository public key!${NC}"
    exit 1
fi
echo -e "${GREEN}[SUCCESS]${NC} Public key deployed safely inside /etc/apk/keys/"

# ۳. اضافه کردن مخازن ماژولار پاس‌وال به پکیج‌منیجر APK روتر
echo -e "${CYAN}[INFO]${NC} Configuring custom APK feed repositories..."
mkdir -p /etc/apk/repositories.d/

# اضافه کردن هر ۳ فید دانلود شده
cat << REPOS > /etc/apk/repositories.d/daypass.list
$REPO_URL/$ARCH/passwall_packages
$REPO_URL/$ARCH/passwall2
$REPO_URL/$ARCH/passwall_luci
REPOS

# ۴. آپدیت ایندکس‌ها و نصب پاس‌وال
echo -e "${CYAN}[INFO]${NC} Updating APK indexes on router..."
apk update

echo -e "${CYAN}[INFO]${NC} Installing Passwall 2 and all its packages seamlessly..."
apk add luci-app-passwall passwall2

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[SUCCESS] Passwall successfully installed on OpenWrt 25! Enjoy freedom.${NC}"
else
    echo -e "${RED}[ERROR] Installation failed. Check network or repository configurations.${NC}"
fi
EOF

    chmod +x "$client_script"
    log_success "One-Liner Install script successfully generated at: $client_script"
}