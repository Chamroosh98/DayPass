#!/bin/sh

# Shared global state for resource checks
BEFORE_FREE_RAM=0
BEFORE_FREE_FLASH=0
TOTAL_REQUIRED_BYTES=0

# Converts bytes to human readable string (KB / MB)
human_readable_bytes()
{
    bytes="$1"
    [ -z "$bytes" ] && bytes=0

    if [ "$bytes" -ge 1048576 ]; then
        awk -v b="$bytes" 'BEGIN {printf "%.2f MB", b/1048576}' 2>/dev/null
    elif [ "$bytes" -ge 1024 ]; then
        awk -v b="$bytes" 'BEGIN {printf "%.1f KB", b/1024}' 2>/dev/null
    else
        echo "${bytes} Bytes"
    fi
}

# Queries available free RAM in Bytes from /proc/meminfo
get_free_ram_bytes()
{
    if [ -f /proc/meminfo ]; then
        # Try MemAvailable first (modern kernels), fallback to MemFree + Buffers + Cached
        mem_avail=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null)
        
        if [ -n "$mem_avail" ] && [ "$mem_avail" -gt 0 ]; then
            echo $((mem_avail * 1024))
        else
            mem_free=$(awk '/MemFree:/ {print $2}' /proc/meminfo 2>/dev/null)
            buffers=$(awk '/Buffers:/ {print $2}' /proc/meminfo 2>/dev/null)
            cached=$(awk '/^Cached:/ {print $2}' /proc/meminfo 2>/dev/null)
            
            [ -z "$mem_free" ] && mem_free=0
            [ -z "$buffers" ] && buffers=0
            [ -z "$cached" ] && cached=0
            
            total_avail=$((mem_free + buffers + cached))
            echo $((total_avail * 1024))
        fi
    else
        echo 0
    fi
}

# Queries available free Storage/Flash space in Bytes for target path
get_free_flash_bytes()
{
    target_path="${1:-/overlay}"
    
    # Fallback to root / if overlay is not a separate mount point
    if ! df "$target_path" >/dev/null 2>&1; then
        target_path="/"
    fi

    # Extract available space in 1K blocks from df output
    free_blocks=$(df -k "$target_path" 2>/dev/null | awk 'NR==2 {print $4}')
    [ -z "$free_blocks" ] && free_blocks=0

    echo $((free_blocks * 1024))
}

# Captures pre-installation hardware memory snapshot
resource_snapshot()
{
    BEFORE_FREE_RAM=$(get_free_ram_bytes)
    BEFORE_FREE_FLASH=$(get_free_flash_bytes "/overlay")

    ram_str=$(human_readable_bytes "$BEFORE_FREE_RAM")
    flash_str=$(human_readable_bytes "$BEFORE_FREE_FLASH")

    log_info "System Memory Snapshot:"
    log_info "  ├─ Available RAM    : [$ram_str]"
    log_info "  └─ Free Flash Space : [$flash_str]"
}

# Calculates estimated deployment size and verifies capacity limits
estimate_install_size()
{
    [ -z "${FINAL_PACKAGES:-}" ] && return 0
    [ -z "${MANIFEST_FILE:-}" ] || [ ! -f "$MANIFEST_FILE" ] && return 0

    TOTAL_REQUIRED_BYTES=0

    for pkg in $FINAL_PACKAGES; do
        pkg_bytes=0
        
        if command -v manifest_lookup >/dev/null 2>&1; then
            pkg_bytes=$(manifest_lookup "size" "$pkg")
        fi

        # Fallback direct jq query if manifest_lookup fails
        if [ -z "$pkg_bytes" ] || [ "$pkg_bytes" = "null" ]; then
            pkg_bytes=$(jq -r --arg pkg "$pkg" --arg arch "${ARCH:-}" '
                .architectures[]? | select(.name == $arch) | .packages[]? | select(.package == $pkg) | .size // .Size // 0
            ' "$MANIFEST_FILE" 2>/dev/null | head -n1)
        fi

        [ -z "$pkg_bytes" ] || [ "$pkg_bytes" = "null" ] && pkg_bytes=0
        TOTAL_REQUIRED_BYTES=$((TOTAL_REQUIRED_BYTES + pkg_bytes))
    done

    # Add 2.5x buffer estimation for uncompressed binary extraction & package DB overhead
    ESTIMATED_EXTRACTED_BYTES=$((TOTAL_REQUIRED_BYTES * 5 / 2))

    download_str=$(human_readable_bytes "$TOTAL_REQUIRED_BYTES")
    install_str=$(human_readable_bytes "$ESTIMATED_EXTRACTED_BYTES")

    log_info "Estimated Resource Allocation Requirements:"
    log_info "  ├─ Download Payload Size : [$download_str]"
    log_info "  └─ Estimated Storage Req : [$install_str] (with safety buffer)"

    # Check 1: Verify RAM space in /tmp for storing download artifacts
    CURRENT_RAM=$(get_free_ram_bytes)
    
    # Require payload size + 4MB safety margin for RAM execution
    RAM_MARGIN=$((4 * 1024 * 1024))
    MIN_RAM_NEEDED=$((TOTAL_REQUIRED_BYTES + RAM_MARGIN))

    if [ "$CURRENT_RAM" -lt "$MIN_RAM_NEEDED" ]; then
        log_error "Insufficient RAM in /tmp for package download workspace!"
        log_warn "Available RAM: $(human_readable_bytes "$CURRENT_RAM") | Required: $(human_readable_bytes "$MIN_RAM_NEEDED")"
        return 1
    fi

    # Check 2: Verify Flash storage space for package extraction & system installation
    CURRENT_FLASH=$(get_free_flash_bytes "/overlay")
    
    # Require estimated extracted size + 2MB safety margin for package DB/UCI state
    FLASH_MARGIN=$((2 * 1024 * 1024))
    MIN_FLASH_NEEDED=$((ESTIMATED_EXTRACTED_BYTES + FLASH_MARGIN))

    if [ "$CURRENT_FLASH" -lt "$MIN_FLASH_NEEDED" ]; then
        log_error "Insufficient Flash storage space on system!"
        log_warn "Available Storage: $(human_readable_bytes "$CURRENT_FLASH") | Required: $(human_readable_bytes "$MIN_FLASH_NEEDED")"
        return 1
    fi

    log_success "System resource check PASSED! Adequate RAM and Flash available."
    return 0
}

# Compares pre/post installation memory states for post-deployment telemetry
resource_compare()
{
    AFTER_FREE_RAM=$(get_free_ram_bytes)
    AFTER_FREE_FLASH=$(get_free_flash_bytes "/overlay")

    # RAM Delta
    if [ "$BEFORE_FREE_RAM" -gt "$AFTER_FREE_RAM" ]; then
        USED_RAM=$((BEFORE_FREE_RAM - AFTER_FREE_RAM))
        RAM_DELTA_STR="-$(human_readable_bytes "$USED_RAM")"
    else
        FREED_RAM=$((AFTER_FREE_RAM - BEFORE_FREE_RAM))
        RAM_DELTA_STR="+$(human_readable_bytes "$FREED_RAM")"
    fi

    # Storage Delta
    if [ "$BEFORE_FREE_FLASH" -gt "$AFTER_FREE_FLASH" ]; then
        USED_FLASH=$((BEFORE_FREE_FLASH - AFTER_FREE_FLASH))
        FLASH_DELTA_STR="-$(human_readable_bytes "$USED_FLASH")"
    else
        FREED_FLASH=$((AFTER_FREE_FLASH - BEFORE_FREE_FLASH))
        FLASH_DELTA_STR="+$(human_readable_bytes "$FREED_FLASH")"
    fi

    log_info "Resource Usage Impact Summary:"
    log_info "  ├─ Memory Delta  : $RAM_DELTA_STR (Remaining RAM: $(human_readable_bytes "$AFTER_FREE_RAM"))"
    log_info "  └─ Storage Delta : $FLASH_DELTA_STR (Remaining Storage: $(human_readable_bytes "$AFTER_FREE_FLASH"))"
}

# Standalone execution handler for testing
case "$0" in
    *resource_checker.sh)
        resource_snapshot
        estimate_install_size
        ;;
esac