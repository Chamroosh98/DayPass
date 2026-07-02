#!/usr/bin/env bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/ui/colors.sh"

# پوشه موقت برای دانلودها
DOWNLOAD_DIR="$ROOT_DIR/download_temp"
mkdir -p "$DOWNLOAD_DIR"

# تابع دانلود امن با پشتیبانی از پروکسی آپشنال
download_file() {
    local url=$1
    local output=$2
    local proxy_env=$3 # اگر پروکسی ست شده باشه (برای تست محلی شما)

    if [ -n "$proxy_env" ]; then
        curl -sS --connect-timeout 15 --retry 3 -x "$proxy_env" -L "$url" -o "$output"
    else
        curl -sS --connect-timeout 15 --retry 3 -L "$url" -o "$output"
    fi
}

fetch_all_packages() {
    local config_file="$ROOT_DIR/config/architectures.json"
    local proxy=$1

    if [ ! -f "$config_file" ]; then
        log_error "Config file not found at $config_file"
        exit 1
    fi

    # خواندن تعداد معماری‌ها از فایل کانفیگ با jq
    local arch_count=$(jq '.architectures | length' "$config_file")

    for ((i=0; i<arch_count; i++)); do
        local arch_name=$(jq -r ".architectures[$i].name" "$config_file")
        local base_url=$(jq -r ".architectures[$i].base_url" "$config_file")
        
        log_info "Processing architecture: ${PURPLE}$arch_name${NC}"

        # خواندن فیدهای تعریف شده برای این معماری
        local feed_count=$(jq ".architectures[$i].feeds | length" "$config_file")
        
        for ((j=0; j<feed_count; j++)); do
            local feed_name=$(jq -r ".architectures[$i].feeds[$j]" "$config_file")
            local feed_url="$base_url/$feed_name"
            local target_dir="$DOWNLOAD_DIR/$arch_name/$feed_name"
            mkdir -p "$target_dir"

            log_info "Fetching index for feed: ${YELLOW}$feed_name${NC}"
            
            # ۱. دانلود فایل index.json کشف شده توسط شما
            local index_json_path="$target_dir/index.json"
            download_file "$feed_url/index.json" "$index_json_path" "$proxy"

            if [ ! -s "$index_json_path" ]; then
                log_error "Failed to download index.json for $feed_name. Skipping..."
                continue
            fi

            # ۲. دانلود فایل اصلی ایندکس apk یعنی packages.adb
            log_info "Downloading packages.adb..."
            download_file "$feed_url/packages.adb" "$target_dir/packages.adb" "$proxy"

            # ۳. استخراج نام پکیج‌ها از روی index.json و دانلود دانه دانه آن‌ها
            # فرض بر این است که ساختار جِیسون شامل آرایه یا آبجکتی از فایل‌هاست. 
            # با فرض ساختار استاندارد فایل‌لیست سورس‌فورج، نام فایل‌ها را استخراج می‌کنیم:
            local pkgs=$(jq -r '.files[].name // .[] | select(strings | endswith(".apk"))' "$index_json_path" 2>/dev/null)
            
            # اگر فرمت جیسون سورس‌فورج ساختار متفاوتی داشت، نام کلید را جنریک‌تر می‌خوانیم:
            if [ -z "$pkgs" ]; then
                pkgs=$(jq -r '.. | .name? // empty | select(endswith(".apk"))' "$index_json_path")
            fi

            for pkg in $pkgs; do
                log_info "Downloading package: $pkg"
                download_file "$feed_url/$pkg" "$target_dir/$pkg" "$proxy"
            done
            log_success "Feed $feed_name completely mirrored."
        done
    done
}