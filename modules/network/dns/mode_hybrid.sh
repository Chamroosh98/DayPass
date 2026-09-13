#!/bin/sh

# DNS Mode: Hybrid — Passwall/DoH first, public resolvers as ordered fallback

apply_dns_hybrid() {
    local port
    log_info "Applying DNS mode: hybrid ..."

    dns_dnsmasq_reset
    uci set dhcp.@dnsmasq[0].noresolv='1'
    uci set dhcp.@dnsmasq[0].strictorder='1'

    if dns_passwall_available; then
        dns_configure_passwall_hybrid
        port=$(dns_pw_listen_port)
        uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#${port}"
        log_info "Primary resolver: Passwall (DoH / tunnel). Fallback: Cloudflare + Google."
    elif port=$(dns_stubby_port); then
        uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#${port}"
        log_info "Primary resolver: Stubby DoT. Fallback: public DNS."
    elif port=$(dns_https_proxy_port); then
        uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#${port}"
        log_info "Primary resolver: https-dns-proxy. Fallback: public DNS."
    else
        log_warn "Passwall not found. Hybrid uses public resolvers only."
    fi

    uci add_list dhcp.@dnsmasq[0].server="$DNS_CF"
    uci add_list dhcp.@dnsmasq[0].server="$DNS_GOOGLE"
    dns_dnsmasq_commit
    return 0
}
