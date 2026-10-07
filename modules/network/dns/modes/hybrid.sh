#!/bin/sh

# DNS Mode: Hybrid — transport engine / DoH first, public resolvers as ordered fallback

apply_dns_hybrid() {
    local port primary=""
    log_info "Applying DNS mode: hybrid ..."

    dns_dnsmasq_reset
    uci set dhcp.@dnsmasq[0].noresolv='1'
    uci set dhcp.@dnsmasq[0].strictorder='1'

    if dns_engine_configure hybrid && primary=$(dns_engine_endpoint) && [ -n "$primary" ]; then
        uci add_list dhcp.@dnsmasq[0].server="$primary"
        log_info "Primary resolver: $(dns_engine_label) (DoH / tunnel). Fallback: Cloudflare + Google."
    elif port=$(dns_stubby_port); then
        primary=""
        dns_engine_release
        uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#${port}"
        log_info "Primary resolver: Stubby DoT. Fallback: public DNS."
    elif port=$(dns_https_proxy_port); then
        primary=""
        dns_engine_release
        uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#${port}"
        log_info "Primary resolver: https-dns-proxy. Fallback: public DNS."
    else
        primary=""
        dns_engine_release
        log_warn "No transport engine DNS found. Hybrid uses public resolvers only."
    fi

    [ "$primary" = "$DNS_CF" ] || uci add_list dhcp.@dnsmasq[0].server="$DNS_CF"
    uci add_list dhcp.@dnsmasq[0].server="$DNS_GOOGLE"
    dns_dnsmasq_commit
    return 0
}
