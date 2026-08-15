#!/bin/sh

# Shared global state for resource checks
BEFORE_FREE_RAM=0
BEFORE_FREE_FLASH=0
TOTAL_REQUIRED_BYTES=0
TOTAL_SAVED_BYTES=0

human_readable_bytes()
{
    bytes="${1:-0}"
    if [ "$bytes" -ge 1048576 ]; then
        awk -v b="$bytes" 'BEGIN {printf "%.2f MB", b/1048576}' 2>/dev/null
    elif [ "$bytes" -ge 1024 ]; then
        awk -v b="$bytes" 'BEGIN {printf "%.1f KB", b/1024}' 2>/dev/null
    else
        echo "${bytes} Bytes"
    fi
}

get_free_ram_bytes()
{
    if [ -f /proc/meminfo ]; then
        mem_avail=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null)
        if [ -n "$mem_avail" ] && [ "$mem_avail" -gt 0 ]; then
            echo $((mem_avail * 1024))
        else
            mem_free=$(awk '/MemFree:/ {print $2}' /proc/meminfo 2>/dev/null)
            buffers=$(awk '/Buffers:/ {print $2}' /proc/meminfo 2>/dev/null)
            cached=$(awk '/^Cached:/ {print $2}' /proc/meminfo 2>/dev/null)
            echo $(( (${mem_free:-0} + ${buffers:-0} + ${cached:-0}) * 1024 ))
        fi
    else
        echo 0
    fi
}

get_free_flash_bytes()
{
    target_path="${1:-/overlay}"
    if ! df "$target_path" >/dev/null 2>&1; then
        target_path="/"
    fi
    free_blocks=$(df -k "$target_path" 2>/dev/null | awk 'NR==2 {print $4}')
    echo $(( ${free_blocks:-0} * 1024 ))
}

resource_snapshot()
{
    BEFORE_FREE_RAM=$(get_free_ram_bytes)
    BEFORE_FREE_FLASH=$(get_free_flash_bytes "/overlay")

    log_info "System Memory Snapshot :"
    log_info "  ├─ Available RAM          : [$(human_readable_bytes "$BEFORE_FREE_RAM")]"
    log_info "  └─ Free Flash Space       : [$(human_readable_bytes "$BEFORE_FREE_FLASH")]"
}

# Smart estimation: Calculates REAL net storage expansion
estimate_install_size()
{
    [ -z "${FINAL_PACKAGES:-}" ] && return 0
    [ -z "${MANIFEST_FILE:-}" ] || [ ! -f "$MANIFEST_FILE" ] && return 0

    TOTAL_REQUIRED_BYTES=0
    TOTAL_SAVED_BYTES=0
    RECLAIMABLE_BYTES=0

    for pkg in $FINAL_PACKAGES; do
        pkg_bytes=$(manifest_lookup "size" "$pkg")
        [ -z "$pkg_bytes" ] || [ "$pkg_bytes" = "null" ] && pkg_bytes=0

        inst_ver=$(pkg_get_installed_version "$pkg")
        manif_ver=$(manifest_lookup "version" "$pkg")

        # Skip logic if version is identical and not generic "Latest"
        if [ -n "$inst_ver" ] && [ "$inst_ver" = "$manif_ver" ] && [ "$manif_ver" != "Latest" ]; then
            TOTAL_SAVED_BYTES=$((TOTAL_SAVED_BYTES + pkg_bytes))
        else
            TOTAL_REQUIRED_BYTES=$((TOTAL_REQUIRED_BYTES + pkg_bytes))

            # If replacing an existing package, account for reclaimed space
            if [ -n "$inst_ver" ] && [ "$inst_ver" != "None" ]; then
                RECLAIMABLE_BYTES=$((RECLAIMABLE_BYTES + pkg_bytes))
            fi
        fi
    done

    # Buffer: Only 10% safety margin for extract/temp operational overhead
    TEMP_OVERHEAD=$((TOTAL_REQUIRED_BYTES / 10))
    PEAK_STORAGE_REQ=$((TOTAL_REQUIRED_BYTES + TEMP_OVERHEAD))

    log_info "Smart Resource Allocation Requirements :"
    log_info "  ├─ Payload Download Req   : [$(human_readable_bytes "$TOTAL_REQUIRED_BYTES")]"
    log_info "  ├─ Reclaimable Storage    : [$(human_readable_bytes "$RECLAIMABLE_BYTES")]"
    log_info "  ├─ Saved Traffic (Skip)   : [$(human_readable_bytes "$TOTAL_SAVED_BYTES")]"
    log_info "  └─ Peak Temp Storage Req  : [$(human_readable_bytes "$PEAK_STORAGE_REQ")]"

    CURRENT_RAM=$(get_free_ram_bytes)
    RAM_MARGIN=$((2 * 1024 * 1024)) # 2MB margin
    MIN_RAM_NEEDED=$((TOTAL_REQUIRED_BYTES + RAM_MARGIN))

    if [ "$CURRENT_RAM" -lt "$MIN_RAM_NEEDED" ]; then
        log_error "Insufficient RAM workspace for package downloads :( "
        log_warn "Available RAM : $(human_readable_bytes "$CURRENT_RAM") | Required : $(human_readable_bytes "$MIN_RAM_NEEDED")"
        return 1
    fi

    CURRENT_FLASH=$(get_free_flash_bytes "/overlay")

    # Soft check: If space is tight, warn but DON'T abort if old packages can be purged first
    if [ "$CURRENT_FLASH" -lt "$PEAK_STORAGE_REQ" ]; then
        if [ "$((CURRENT_FLASH + RECLAIMABLE_BYTES))" -ge "$PEAK_STORAGE_REQ" ]; then
            log_warn "Flash storage is tight, but replacing old packages will yield enough space :("
        else
            log_error "Insufficient Flash storage space on system!"
            log_warn "Available Storage : $(human_readable_bytes "$CURRENT_FLASH") | Peak Required : $(human_readable_bytes "$PEAK_STORAGE_REQ")"
            return 1
        fi
    fi

    log_success "System resource check PASSED!"
    return 0
}

resource_compare()
{
    AFTER_FREE_RAM=$(get_free_ram_bytes)
    AFTER_FREE_FLASH=$(get_free_flash_bytes "/overlay")

    [ "$BEFORE_FREE_RAM" -gt "$AFTER_FREE_RAM" ] && USED_RAM=$((BEFORE_FREE_RAM - AFTER_FREE_RAM)) || USED_RAM=0
    [ "$BEFORE_FREE_FLASH" -gt "$AFTER_FREE_FLASH" ] && USED_FLASH=$((BEFORE_FREE_FLASH - AFTER_FREE_FLASH)) || USED_FLASH=0

    echo
    echo "  📊 DayPass Deployment Efficiency Summary"
    echo "  ────────────────────────────────────────────────────────── "
    echo "    ├─ Total Downloaded Payload     : $(human_readable_bytes "$TOTAL_REQUIRED_BYTES")"
    echo "    ├─ Total Network Traffic Saved  : $(human_readable_bytes "$TOTAL_SAVED_BYTES") "
    echo "    ├─ Net Storage Consumed         : $(human_readable_bytes "$USED_FLASH")"
    echo "    └─ Free Storage Remaining       : $(human_readable_bytes "$AFTER_FREE_FLASH")"
    echo "  ────────────────────────────────────────────────────────── "
    echo
}

get_total_ram_bytes()
{
    if [ -f /proc/meminfo ]; then
        mem_total=$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null)
        echo $(( ${mem_total:-0} * 1024 ))
    else
        echo 0
    fi
}

get_total_flash_bytes()
{
    target_path="${1:-/overlay}"
    if ! df "$target_path" >/dev/null 2>&1; then
        target_path="/"
    fi
    total_blocks=$(df -k "$target_path" 2>/dev/null | awk 'NR==2 {print $2}')
    echo $(( ${total_blocks:-0} * 1024 ))
}

show_system_resources_menu()
{
    render_persistent_header

    # Fetch Architecture
    [ -z "$ARCH" ] && command -v detect_arch >/dev/null 2>&1 && detect_arch

    # Fetch OpenWrt Release & Date Details
    OW_VER="Unknown"
    OW_DATE=""
    if [ -f /etc/openwrt_release ]; then
        . /etc/openwrt_release
        OW_VER="${DISTRIB_RELEASE:-Unknown}"
        
        if [ -n "$DISTRIB_REVISION" ]; then
            OW_DATE=" ($DISTRIB_REVISION)"
        fi
    fi

    # Fetch Memory Data
    tot_ram_b=$(get_total_ram_bytes)
    free_ram_b=$(get_free_ram_bytes)
    used_ram_b=$((tot_ram_b - free_ram_b))

    # Fetch Storage Data
    tot_flash_b=$(get_total_flash_bytes "/overlay")
    free_flash_b=$(get_free_flash_bytes "/overlay")
    used_flash_b=$((tot_flash_b - free_flash_b))

    echo "  🖥️ System Hardware & Resource Status"
    echo "  ──────────────────────────────────────────────────────────"
    printf "  🩻 Architecture      : ${CYAN}%s${RESET}\n" "${ARCH:-N/A}"
    printf "  💡 OpenWrt System    : ${CYAN}%s [%s]${RESET}\n" "$OW_VER" "${PKG_MANAGER:-opkg}"
    echo "  ──────────────────────────────────────────────────────────"
    printf "  🧠 Total RAM         : %s\n" "$(human_readable_bytes "$tot_ram_b")"
    printf "    🟠 Used RAM          : ${YELLOW}%s${RESET}\n" "$(human_readable_bytes "$used_ram_b")"
    printf "    🟢 Free RAM          : ${GREEN}%s${RESET}\n" "$(human_readable_bytes "$free_ram_b")"
    echo "  ──────────────────────────────────────────────────────────"
    printf "  💾 Total Storage     : %s\n" "$(human_readable_bytes "$tot_flash_b")"
    printf "    🟠 Used Storage      : ${YELLOW}%s${RESET}\n" "$(human_readable_bytes "$used_flash_b")"
    printf "    🟢 Free Storage      : ${GREEN}%s${RESET}\n" "$(human_readable_bytes "$free_flash_b")"
    echo "  ──────────────────────────────────────────────────────────"
    echo

    printf "  ${GRAY}Press [ENTER] to return to main menu ...${RESET}"
    read -r _ </dev/tty
}