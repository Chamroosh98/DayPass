#!/bin/sh

# DNS Mode: all DNS through the active transport engine (proxy DNS or VPN tunnel)

apply_dns_tunnel() {
    local endpoint label
    log_info "Applying DNS mode: through tunnel ..."

    if ! dns_engine_available; then
        log_error "No transport engine found. Cannot force tunnel DNS."
        return 1
    fi
    label=$(dns_engine_label)

    if ! dns_engine_configure tunnel; then
        log_error "Engine [$label] cannot route DNS through its tunnel."
        return 1
    fi

    endpoint=$(dns_engine_endpoint)
    if [ -z "$endpoint" ]; then
        log_error "Engine [$label] has no DNS endpoint (add a dns-in inbound or set dns_port)."
        return 1
    fi

    dns_dnsmasq_forward_only "$endpoint"
    dns_dnsmasq_commit

    log_info "dnsmasq forwards to $label ($endpoint); LAN DNS goes through the tunnel."
    return 0
}
