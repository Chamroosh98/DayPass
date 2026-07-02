#!/usr/bin/env bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/ui/colors.sh"

KEY_DIR="$ROOT_DIR/keys"
DOWNLOAD_DIR="$ROOT_DIR/download_temp"
OUTPUT_DIR="$ROOT_DIR/output"

setup_keys() {
    mkdir -p "$KEY_DIR"

    # مدیریت کلیدها: اگر کلید نبود، کاملاً خودکار ساخته میشه
    if [ ! -f "$KEY_DIR/daypass.key" ]; then
        log_info "Generating secure usign key pair for DayPass..."
        usign -G -p "$KEY_DIR/daypass.pub" -s "$KEY_DIR/daypass.key" -c "DayPass OpenWrt 25 Repository Key"
        log_success "New cryptographic keys deployed at: $KEY_DIR"
    else
        log_info "DayPass cryptographic keys verified and loaded."
    fi
}

sign_repositories() {
    log_info "Step 2: Starting Repository Signing Process..."
    
    if [ ! -d "$DOWNLOAD_DIR" ]; then
        log_error "Download directory not found! Run fetcher first."
        exit 1
    fi

    # پاک‌سازی و آماده‌سازی دایرکتوری خروجی نهایی
    rm -rf "$OUTPUT_DIR" && mkdir -p "$OUTPUT_DIR"

    # کپی کردن کلید عمومی مخزن به دایرکتوری خروجی تا کاربران بتونن دانلودش کنن
    cp "$KEY_DIR/daypass.pub" "$OUTPUT_DIR/daypass.pub"

    # اسکن ساختار دایرکتوری‌ها بر اساس معماری و فید
    # ساختار: download_temp/architecture/feed/packages.adb
    for arch_path in "$DOWNLOAD_DIR"/*; do
        [ -d "$arch_path" ] || continue
        local arch_name=$(basename "$arch_path")

        for feed_path in "$arch_path"/*; do
            [ -d "$feed_path" ] || continue
            local feed_name=$(basename "$feed_path")
            local adb_file="$feed_path/packages.adb"

            if [ -f "$adb_file" ]; then
                log_info "Signing database for [${PURPLE}$arch_name${NC} -> ${YELLOW}$feed_name${NC}]"

                # ایجاد مسیر متناظر در پوشه نهایی output
                local final_feed_dir="$OUTPUT_DIR/$arch_name/$feed_name"
                mkdir -p "$final_feed_dir"

                # ۱. انتقال تمامی پکیج‌های apk و فایل ایندکس به دایرکتوری نهایی
                cp "$feed_path"/*.apk "$final_feed_dir/" 2>/dev/null || true
                cp "$adb_file" "$final_feed_dir/packages.adb"

                # ۲. استفاده از usign برای ساخت امضای دیجیتالِ معتبر روی فایل adb
                # دستور -S یعنی Sign، فایل خروجی امضا با پسوند .sig ساخته میشه
                usign -S -m "$final_feed_dir/packages.adb" -s "$KEY_DIR/daypass.key" -x "$final_feed_dir/packages.adb.sig"
                
                if [ -f "$final_feed_dir/packages.adb.sig" ]; then
                    log_success "Successfully signed and structured: $feed_name"
                else
                    log_error "Failed to generate signature for $feed_name"
                fi
            else
                log_warn "No packages.adb found in $arch_name/$feed_name. Skipping signing..."
            fi
        done
    done

    # تمیزکاری فایل‌های موقت پس از اتمام فرآیند موفق
    rm -rf "$DOWNLOAD_DIR"
    log_success "All repositories signed successfully! Ready for distribution."
}