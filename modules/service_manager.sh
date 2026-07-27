#!/bin/sh

# Service Manager module for managing init.d / procd services in OpenWrt
# Compatible with both OpenWrt 24 (opkg) and OpenWrt 25 (apk) setups

# Checks if a given service init script exists in /etc/init.d/
service_exists()
{
    service_name="$1"
    [ -n "$service_name" ] && [ -x "/etc/init.d/$service_name" ]
}

# Enables a service to automatically start on boot
service_enable()
{
    service_name="$1"
    if service_exists "$service_name"; then
        log_info "Enabling service to start on boot : [$service_name]"
        /etc/init.d/"$service_name" enable >/dev/null 2>&1
        return $?
    else
        log_warn "Cannot enable service [$service_name] : init script not found!"
        return 1
    fi
}

# Starts or restarts a target service via init.d
service_start()
{
    service_name="$1"
    if service_exists "$service_name"; then
        log_info "Starting service : [$service_name] ..."
        /etc/init.d/"$service_name" restart >/dev/null 2>&1 || /etc/init.d/"$service_name" start >/dev/null 2>&1
        
        # Brief pause for procd process spawning
        sleep 1
        
        if service_is_running "$service_name"; then
            log_success "Service [$service_name] is running smoothly!"
            return 0
        else
            log_warn "Service [$service_name] was triggered but is not reporting as active."
            return 1
        fi
    else
        log_error "Failed to start service [$service_name] : Service script missing!"
        return 1
    fi
}

# Stops an active service
service_stop()
{
    service_name="$1"
    if service_exists "$service_name"; then
        log_info "Stopping service : [$service_name] ..."
        /etc/init.d/"$service_name" stop >/dev/null 2>&1
        return 0
    fi
    return 1
}

# Checks if a target service process is currently active/running
service_is_running()
{
    service_name="$1"
    [ -z "$service_name" ] && return 1

    # Check via init.d status if supported by script
    if service_exists "$service_name"; then
        if /etc/init.d/"$service_name" status >/dev/null 2>&1; then
            return 0
        fi
    fi

    # Fallback process detection via pgrep or ps
    if command -v pgrep >/dev/null 2>&1; then
        pgrep -f "$service_name" >/dev/null 2>&1
        return $?
    else
        ps | grep -v grep | grep -q "$service_name"
        return $?
    fi
}

# Post-deployment orchestration for core network services
post_install_services_init()
{
    echo
    log_info "=================================================="
    log_info "Initiating Post-Install Service Operations"
    log_info "=================================================="
    echo

    # 1. Start core proxy profiles if selected
    case "${SELECTED_PROFILE:-passwall2}" in
        passwall2)
            service_enable "passwall2"
            service_start "passwall2"
            ;;
        passwall)
            service_enable "passwall"
            service_start "passwall"
            ;;
    esac

    # 2. Reload DNS resolution stack (dnsmasq) to apply new rules
    if service_exists "dnsmasq"; then
        log_info "Reloading dnsmasq configuration ..."
        /etc/init.d/dnsmasq reload >/dev/null 2>&1 || /etc/init.d/dnsmasq restart >/dev/null 2>&1
        log_success "DNS subsystem reloaded."
    fi

    # 3. Reload firewall rules
    if service_exists "firewall"; then
        log_info "Reloading system firewall rules ..."
        /etc/init.d/firewall reload >/dev/null 2>&1
        log_success "Firewall rules updated."
    fi

    echo
    log_success "All post-install service configurations applied!"
}

# Standalone test runner
case "$0" in
    *service_manager.sh)
        post_install_services_init
        ;;
esac