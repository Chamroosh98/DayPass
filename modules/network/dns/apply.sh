#!/bin/sh

# DNS Apply Dispatcher — persist mode only after a successful apply

apply_dns_mode() {
    local mode="$1"
    local rc=0

    case "$mode" in
        system) apply_dns_system; rc=$? ;;
        secure) apply_dns_secure; rc=$? ;;
        tunnel) apply_dns_tunnel; rc=$? ;;
        hybrid) apply_dns_hybrid; rc=$? ;;
        *)
            log_error "Unknown DNS mode: $mode"
            return 1
            ;;
    esac

    [ "$rc" -eq 0 ] || return "$rc"

    set_dns_mode "$mode" || return 1
    log_success "DNS mode set to [${mode}]"
    return 0
}
