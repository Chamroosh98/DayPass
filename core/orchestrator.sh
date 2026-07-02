#!/usr/bin/env bash
#!/bin/bash
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# بارگذاری تمام ماژول‌های پروژه به شکل کاملاً هماهنگ
source "$ROOT_DIR/ui/colors.sh"
source "$ROOT_DIR/ui/banner.sh"
source "$ROOT_DIR/core/signer.sh"
source "$ROOT_DIR/core/fetcher.sh"

main() {
    # نمایش هویت بصری پروژه
    show_banner
    log_info "Initiating DayPass core engine..."

    # فاز صفر: لود کردن و اعتبارسنجی جفت‌کلیدهای مخزن
    setup_keys
    echo -e "${GRAY}------------------------------------------------------------${NC}"

    # فاز اول: واکشی و آینه‌سازی (Mirroring) پکیج‌ها از سورس‌فورج
    log_info "Executing Phase 1: Upstream Package Syncing..."
    # پارامتر اول خالی است؛ در صورت نیاز به تست لوکال با تانل ssh -R، آدرس پروکسی را اینجا بگذارید
    # مانند: fetch_all_packages "http://127.0.0.1:8090"
    fetch_all_packages ""
    echo -e "${GRAY}------------------------------------------------------------${NC}"

    # فاز دوم: امضای دیجیتال مخازن با استاندارد OpenWrt 25 APK
    log_info "Executing Phase 2: Cryptographic Re-signing..."
    sign_repositories
    echo -e "${GRAY}------------------------------------------------------------${NC}"

    log_success "DayPass Pipeline Finished Execution Successfully! 🔥"
    log_info "Final artifacts are located at: ${GREEN}$ROOT_DIR/output/${NC}"
}

main "$@"