#!/bin/sh

# DNS Mode: all DNS through the Passwall proxy path

apply_dns_tunnel() {
    log_info "Applying DNS mode: through tunnel ..."

    if ! dns_passwall_available; then
        log_error "Passwall not found. Cannot force tunnel DNS."
        return 1
    fi

    dns_configure_passwall_tunnel
    dns_dnsmasq_forward_only "127.0.0.1#$(dns_pw_listen_port)"
    dns_dnsmasq_commit

    log_info "dnsmasq forwards to Passwall; LAN DNS is redirected through the proxy."
    return 0
}
