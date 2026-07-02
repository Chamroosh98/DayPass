#!/usr/bin/env bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/ui/colors.sh"
source "$ROOT_DIR/ui/banner.sh"
source "$ROOT_DIR/core/signer.sh"
source "$ROOT_DIR/core/fetcher.sh"
source "$ROOT_DIR/core/template_gen.sh"

main() {
    show_banner
    log_info "Initiating DayPass core engine..."

    # فاز صفر: لود کردن و اعتبارسنجی جفت‌کلیدهای مخزن
    setup_keys
    echo -e "${GRAY}------------------------------------------------------------${NC}"

    # فاز اول: واکشی و آینه‌سازی (Mirroring) پکیج‌ها از سورس‌فورج
    log_info "Executing Phase 1: Upstream Package Syncing..."
    fetch_all_packages ""
    echo -e "${GRAY}------------------------------------------------------------${NC}"

    # فاز دوم: امضای دیجیتال مخازن با استاندارد OpenWrt 25 APK
    log_info "Executing Phase 2: Cryptographic Re-signing..."
    sign_repositories
    echo -e "${GRAY}------------------------------------------------------------${NC}"

    # فاز سوم: ساخت اسکریپت نصب نهایی برای کاربران
    log_info "Executing Phase 3: Client Installer Compilation..."
    generate_install_script
    echo -e "${GRAY}------------------------------------------------------------${NC}"

    log_success "DayPass Pipeline Finished Execution Successfully! 🔥"
    log_info "Final artifacts are located at: ${GREEN}$ROOT_DIR/output/${NC}"
}

main "$@"