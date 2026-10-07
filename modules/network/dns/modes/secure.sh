#!/bin/sh

# DNS Mode: encrypted resolvers (DoT/DoH stub, transport engine DoH, or public DNS)

apply_dns_secure() {
    local stub encrypted=0
    log_info "Applying DNS mode: secure (DoT/DoH) ..."

    if stub=$(dns_stubby_port); then
        log_info "Using Stubby DoT stub on 127.0.0.1#${stub}"
        dns_dnsmasq_forward_only "127.0.0.1#${stub}"
        dns_engine_release
        encrypted=1
    elif stub=$(dns_https_proxy_port); then
        log_info "Using https-dns-proxy DoH stub on 127.0.0.1#${stub}"
        dns_dnsmasq_forward_only "127.0.0.1#${stub}"
        dns_engine_release
        encrypted=1
    elif dns_engine_configure doh && stub=$(dns_engine_endpoint) && [ -n "$stub" ]; then
        log_info "Using $(dns_engine_label) DoH (Cloudflare) as encrypted resolver ..."
        dns_dnsmasq_forward_only "$stub"
        encrypted=1
    else
        log_warn "No DoT/DoH stub or DoH-capable transport engine found. Falling back to public DNS (plaintext)."
        dns_dnsmasq_forward_only "$DNS_CF" "$DNS_CF2" "$DNS_GOOGLE"
        dns_engine_release
    fi

    dns_dnsmasq_commit

    if [ "$encrypted" -eq 1 ]; then
        log_info "Queries are forwarded to an encrypted resolver, not ISP DNS."
    fi
    return 0
}
