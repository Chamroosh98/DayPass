#!/usr/bin/env bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/ui/colors.sh"

OUTPUT_DIR="$ROOT_DIR/output"

generate_install_script() {
    log_info "Step 3: Generating Smart One-Liner Install Script for users..."
    
    if [ ! -d "$OUTPUT_DIR" ]; then
        log_error "Output directory not found! Run signer module first."
        exit 1
    fi

    local client_script="$OUTPUT_DIR/install.sh"

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

# ۱. تضمین نصب بودن curl در گام اول با استفاده از wget پیش‌فرض سیستم
if ! command -v curl >/dev/null 2>&1; then
    echo -e "${CYAN}[INFO]${NC} curl not found. Installing native curl via apk bootstrap..."
    apk update && apk add curl
    if [ $? -ne 0 ]; then
        echo -e "${RED}[ERROR] Failed to bootstrap curl using apk!${NC}"
        exit 1
    fi
fi

# ۲. تشخیص هوشمندانه معماری از فایل مرجع APK روتر
if [ -f /etc/apk/arch.list ]; then
    # خواندن اولین خط غیرخالی و غیرکامنت از فایل معماری‌های مجاز روتر
    ARCH=$(grep -v '^#' /etc/apk/arch.list | grep -v '^$' | head -n 1)
fi

if [ -z "$ARCH" ]; then
    echo -e "${RED}[ERROR] Could not extract router architecture from APK config!${NC}"
    exit 1
fi

echo -e "${CYAN}[INFO]${NC} Target Router Architecture Confirmed: ${PURPLE}$ARCH${NC}"

REPO_URL="https://chamroosh98.github.io/DayPass"

# ۳. دانلود و تزریق کلید عمومی مخزن با curl مدرن
echo -e "${CYAN}[INFO]${NC} Injecting DayPass cryptographic public key..."
mkdir -p /etc/apk/keys/
curl -sL "$REPO_URL/daypass.pub" -o /etc/apk/keys/daypass.pub

if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR] Failed to download DayPass repository public key!${NC}"
    exit 1
fi
echo -e "${GREEN}[SUCCESS]${NC} Public key deployed safely inside /etc/apk/keys/"

# ۴. پیکربندی ریپوزیتوری‌های ماژولار پاس‌وال
echo -e "${CYAN}[INFO]${NC} Configuring custom APK feed repositories..."
mkdir -p /etc/apk/repositories.d/

cat << REPOS > /etc/apk/repositories.d/daypass.list
$REPO_URL/$ARCH/passwall_packages
$REPO_URL/$ARCH/passwall2
$REPO_URL/$ARCH/passwall_luci
REPOS

# ۵. آپدیت مخازن و نصب نهایی
echo -e "${CYAN}[INFO]${NC} Re-indexing APK repositories with DayPass integration..."
apk update

echo -e "${CYAN}[INFO]${NC} Installing Passwall 2 core components..."
apk add luci-app-passwall passwall2

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[SUCCESS] Passwall successfully installed on OpenWrt 25! Enjoy freedom.${NC}"
else
    echo -e "${RED}[ERROR] Installation failed during APK package deployment.${NC}"
fi
EOF

    chmod +x "$client_script"
    log_success "One-Liner Install script successfully generated at: $client_script"
}