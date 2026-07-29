#!/bin/sh

# Get free RAM in Megabytes
get_free_ram_mb()
{
    FREE_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    [ -z "$FREE_KB" ] && FREE_KB=$(grep MemFree /proc/meminfo | awk '{print $2}')
    echo $((FREE_KB / 1024))
}

# Get total RAM in Megabytes
get_total_ram_mb()
{
    TOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    echo $((TOTAL_KB / 1024))
}

# Get free disk storage in Megabytes
get_free_storage_mb()
{
    TARGET="/"
    [ -d /overlay ] && TARGET="/overlay"
    df -k "$TARGET" | awk 'END {printf "%.0f\n", $4 / 1024}'
}

# Get total disk storage in Megabytes
get_total_storage_mb()
{
    TARGET="/"
    [ -d /overlay ] && TARGET="/overlay"
    df -k "$TARGET" | awk 'END {printf "%.0f\n", $2 / 1024}'
}

# Capture snapshot of current resource states
resource_snapshot()
{
    SNAPSHOT_RAM_FREE="$(get_free_ram_mb)"
    SNAPSHOT_STORAGE_FREE="$(get_free_storage_mb)"

    export SNAPSHOT_RAM_FREE
    export SNAPSHOT_STORAGE_FREE
}

# Compare resource usage between snapshot and current state
resource_compare()
{
    CURRENT_RAM_FREE="$(get_free_ram_mb)"
    CURRENT_STORAGE_FREE="$(get_free_storage_mb)"

    if [ "${SNAPSHOT_RAM_FREE:-0}" -gt "$CURRENT_RAM_FREE" ]; then
        RAM_USED=$((SNAPSHOT_RAM_FREE - CURRENT_RAM_FREE))
    else
        RAM_USED=0
    fi

    if [ "${SNAPSHOT_STORAGE_FREE:-0}" -gt "$CURRENT_STORAGE_FREE" ]; then
        STORAGE_USED=$((SNAPSHOT_STORAGE_FREE - CURRENT_STORAGE_FREE))
    else
        STORAGE_USED=0
    fi

    RAM_STR="${RAM_USED} MB"
    STORAGE_STR="${STORAGE_USED} MB"

    echo
    echo "   📊 System Resource Impact                                 "
    echo "  ───────────────────────────────────────────────────────────"
    printf "   🧠 RAM Consumed     : %-35s \n" "$RAM_STR"
    printf "   💾 Storage Consumed : %-35s \n" "$STORAGE_STR"
    echo "  ───────────────────────────────────────────────────────────"
    echo
}

# Estimate total package download size based on package manager engine (opkg / apk)
estimate_install_size()
{
    TOTAL_SIZE=0

    # Determine size field identifier depending on package manager
    SIZE_KEY="Size"
    if [ "${PKG_MANAGER:-opkg}" = "apk" ]; then
        SIZE_KEY="size"
    fi

    for pkg in $FINAL_PACKAGES; do
        # Fetch package size from local manifest index
        size="$(manifest_lookup "$SIZE_KEY" "$pkg")"

        # Fallback check if size was stored under lowercase key
        if [ -z "$size" ] || [ "$size" = "null" ]; then
            size="$(manifest_lookup "Size" "$pkg")"
        fi

        [ -z "$size" ] || [ "$size" = "null" ] && continue
        TOTAL_SIZE=$((TOTAL_SIZE + size))
    done

    # Format output display (KB vs MB)
    if [ "$TOTAL_SIZE" -lt 1048576 ]; then
        SIZE_DISPLAY="$((TOTAL_SIZE / 1024)) KB"
    else
        SIZE_DISPLAY="$(( (TOTAL_SIZE + 1048575) / 1048576 )) MB"
    fi

    PKG_COUNT=$(echo "$FINAL_PACKAGES" | wc -w | tr -d ' ')

    echo
    echo "   📥 Download & Deployment Estimate                         "
    echo "  ───────────────────────────────────────────────────────────"
    printf "   📦 Packages Count   : %-35s \n" "${PKG_COUNT:-0}"
    printf "   💾 Total Download   : %-35s \n" "$SIZE_DISPLAY"
    echo "  ───────────────────────────────────────────────────────────"
    echo
}