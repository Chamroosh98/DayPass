#!/bin/sh

# ------------------------------------------------------------
# Extract address from share link
# ------------------------------------------------------------
extract_address_from_link() {
    local link="$1"
    local host=""

    host=$(echo "$link" | sed -n 's/.*@\([^:/]*\).*/\1/p' | head -1)

    if [ -z "$host" ]; then
        host=$(echo "$link" | sed -n 's/.*\/\/\([^:/]*\).*/\1/p' | head -1)
    fi

    echo "$host"
}

# ------------------------------------------------------------
# Extract port from share link
# ------------------------------------------------------------
extract_port_from_link() {
    local link="$1"
    local port=""

    port=$(echo "$link" | sed -n 's/.*@[^:]*:\([0-9]*\).*/\1/p' | head -1)

    if [ -z "$port" ]; then
        port=$(echo "$link" | sed -n 's/.*\/\/[^:]*:\([0-9]*\).*/\1/p' | head -1)
    fi

    if [ -z "$port" ]; then
        port=$(echo "$link" | grep -oE ':[0-9]{2,5}' | head -1 | tr -d ':')
    fi

    [ -z "$port" ] && port="443"
    echo "$port"
}

# ------------------------------------------------------------
# Replace only the address part of a share link
# ------------------------------------------------------------
replace_address_in_link() {
    local link="$1"
    local new_ip="$2"
    local old_host

    old_host=$(extract_address_from_link "$link")
    if [ -z "$old_host" ]; then
        echo "$link"
        return 1
    fi

    echo "$link" | sed "s/@${old_host}/@${new_ip}/" | sed "s/\/\/${old_host}/\/\/${new_ip}/"
}