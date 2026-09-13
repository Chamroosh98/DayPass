#!/bin/sh

# DNS Mode: System Default — WAN / ISP resolvers, no hijack

apply_dns_system() {
    log_info "Applying DNS mode: system default ..."

    dns_dnsmasq_reset
    dns_dnsmasq_commit
    dns_disable_passwall_hijack

    log_info "LAN clients use the router WAN/ISP DNS path."
    return 0
}
