#!/bin/sh
# ============================================================
# DayPass - Traffic Routing / Shunt Rules
# Engine-neutral routing modes on top of the transport bridge
#   self   engines (Passwall, Passwall2) : mode applied through the driver
#   tproxy engines (sing-box, Xray)      : DayPass nft TPROXY chain + policy route
#   tunnel engines (WireGuard, OpenVPN)  : DayPass fwmark + policy route into tunnel
# ============================================================

# ------------------------------------------------------------
# Paths & constants
# ------------------------------------------------------------
PROXY_DIR="/etc/daypass/proxy"
ROUTING_DIR="$PROXY_DIR/routing"
mkdir -p "$ROUTING_DIR"

# Mark bits 16-23 are DayPass-owned (mwan3 uses 0x3f00, Passwall uses its own table)
RT_NFT_TABLE="daypass"
RT_NFT_FILE="$ROUTING_DIR/daypass.nft"
RT_MARK_MASK="0x00ff0000"
RT_MARK_KEEP="0xff00ffff"
RT_MARK_TPROXY="0x00010000"
RT_MARK_TUNNEL="0x00020000"
RT_TABLE_TPROXY="2585"
RT_TABLE_TUNNEL="2586"
RT_RULE_PRIORITY="900"

# ------------------------------------------------------------
# Options ($ROUTING_DIR/routing.conf, key=value)
#   ipv6=1                  intercept IPv6 as well
#   lan_devices=br-lan ...  ingress devices to steer
# ------------------------------------------------------------
_rt_opt() {
    local val=""
    [ -f "$ROUTING_DIR/routing.conf" ] && val=$(sed -n "s/^$1=//p" "$ROUTING_DIR/routing.conf" | tail -n 1)
    echo "${val:-${2:-}}"
}

_rt_lan_devices() {
    local devs dev out=""

    devs=$(_rt_opt lan_devices)
    [ -z "$devs" ] && devs=$(uci -q get network.lan.device 2>/dev/null)
    [ -z "$devs" ] && devs=$(uci -q get network.lan.ifname 2>/dev/null)
    [ -z "$devs" ] && devs="br-lan"

    for dev in $devs; do
        case "$dev" in
            *[!A-Za-z0-9._@-]*) continue ;;
        esac
        out="${out:+$out, }\"$dev\""
    done
    echo "$out"
}

_rt_mode_title() {
    case "$1" in
        iran_direct)  echo "Iran Direct + Foreign Proxy" ;;
        global_proxy) echo "Global Proxy" ;;
        direct_only)  echo "Direct Only" ;;
        *)            return 1 ;;
    esac
}

_rt_mode_label() {
    case "$1" in
        iran_direct)  echo "🦁☀️ IRAN Direct" ;;
        global_proxy) echo "🌏 Global Proxy" ;;
        direct_only)  echo "🎯 Direct Only" ;;
    esac
}

# Prints comma-joined CIDRs from a list file (comments / invalid lines skipped)
_rt_list_elements() {
    [ -f "$1" ] || return 0
    sed 's/#.*//; s/[[:space:]]//g' "$1" | grep -E "$2" | tr '\n' ',' | sed 's/,$//; s/,/, /g'
}

# ------------------------------------------------------------
# nftables ruleset (idempotent: loaded by fw4 include and directly)
# ------------------------------------------------------------
_rt_render_nft() {
    local intercept="$1"
    local port="$2"
    local mode="$3"
    local ipv6 lan d4="" d6="" mark

    ipv6=$(_rt_opt ipv6 0)
    lan=$(_rt_lan_devices)

    if [ "$mode" = "iran_direct" ]; then
        d4=$(_rt_list_elements "$ROUTING_DIR/direct_v4.list" '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$')
        d6=$(_rt_list_elements "$ROUTING_DIR/direct_v6.list" '^[0-9A-Fa-f:]+(/[0-9]+)?$')
    fi

    [ -n "$d4" ] && d4="        elements = { $d4 }"
    [ -n "$d6" ] && d6="        elements = { $d6 }"

    if [ "$intercept" = "tproxy" ]; then
        mark="$RT_MARK_TPROXY"
    else
        mark="$RT_MARK_TUNNEL"
    fi

    cat << EOF
# DayPass transport interception - generated, do not edit
table inet $RT_NFT_TABLE
delete table inet $RT_NFT_TABLE

table inet $RT_NFT_TABLE {
    set bypass_v4 {
        type ipv4_addr
        flags interval
        auto-merge
        elements = { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.168.0.0/16, 198.18.0.0/15, 224.0.0.0/4, 240.0.0.0/4 }
    }

    set bypass_v6 {
        type ipv6_addr
        flags interval
        auto-merge
        elements = { ::/128, ::1/128, 64:ff9b::/96, fc00::/7, fe80::/10, ff00::/8 }
    }

    set direct_v4 {
        type ipv4_addr
        flags interval
        auto-merge
$d4
    }

    set direct_v6 {
        type ipv6_addr
        flags interval
        auto-merge
$d6
    }

    chain prerouting {
        type filter hook prerouting priority mangle; policy accept;
        iifname != { $lan } return
        fib daddr type local return
        ip daddr @bypass_v4 return
        ip daddr @direct_v4 return
        ip6 daddr @bypass_v6 return
        ip6 daddr @direct_v6 return
EOF

    [ "$ipv6" = "1" ] || echo "        meta nfproto ipv6 return"

    if [ "$intercept" = "tproxy" ]; then
        echo "        meta nfproto ipv4 meta l4proto { tcp, udp } meta mark set meta mark & $RT_MARK_KEEP | $mark tproxy ip to 127.0.0.1:$port accept"
        [ "$ipv6" = "1" ] && \
        echo "        meta nfproto ipv6 meta l4proto { tcp, udp } meta mark set meta mark & $RT_MARK_KEEP | $mark tproxy ip6 to [::1]:$port accept"
    else
        echo "        meta mark set meta mark & $RT_MARK_KEEP | $mark"
    fi

    echo "    }"
    echo "}"
}

# ------------------------------------------------------------
# Managed rules (UCI network / firewall, persistent through fw4)
# ------------------------------------------------------------
_rt_managed_active() {
    uci -q get firewall.daypass_transport >/dev/null 2>&1 || \
    nft list table inet "$RT_NFT_TABLE" >/dev/null 2>&1
}

_rt_net_in_zone() {
    uci -q show firewall 2>/dev/null | grep -q "^firewall\.[^.]*\.network=.*'$1'"
}

_rt_clear_managed() {
    local sect net_changed=0 fw_changed=0

    for sect in daypass_rule4 daypass_rule6 daypass_route4 daypass_route6; do
        if uci -q get "network.$sect" >/dev/null 2>&1; then
            uci -q delete "network.$sect"
            net_changed=1
        fi
    done
    for sect in daypass_transport daypass_vpn daypass_vpn_fwd; do
        if uci -q get "firewall.$sect" >/dev/null 2>&1; then
            uci -q delete "firewall.$sect"
            fw_changed=1
        fi
    done

    [ "$net_changed" -eq 1 ] && uci commit network
    [ "$fw_changed" -eq 1 ] && uci commit firewall

    command -v nft >/dev/null 2>&1 && nft delete table inet "$RT_NFT_TABLE" >/dev/null 2>&1
    rm -f "$RT_NFT_FILE"

    [ "$net_changed" -eq 1 ] && { /etc/init.d/network reload >/dev/null 2>&1 || true; }
    [ "$fw_changed" -eq 1 ] && { /etc/init.d/firewall reload >/dev/null 2>&1 || true; }
    return 0
}

_rt_apply_managed() {
    local engine="$1"
    local intercept="$2"
    local mode="$3"
    local port="" net="" mark table ipv6

    if ! command -v nft >/dev/null 2>&1; then
        log_error "nftables (nft) not found. firewall4 is required for [$engine] routing!"
        return 1
    fi

    ipv6=$(_rt_opt ipv6 0)

    if [ "$intercept" = "tproxy" ]; then
        port=$(transport_call "$engine" tproxy_port 2>/dev/null)
        case "$port" in
            ''|*[!0-9]*)
                log_error "No TPROXY inbound found for [$engine]. Add a tproxy inbound to its config or set tproxy_port in $TRANSPORT_DIR/$engine.conf"
                return 1
                ;;
        esac
        mark="$RT_MARK_TPROXY"
        table="$RT_TABLE_TPROXY"
    else
        net=$(transport_tunnel_network "$engine")
        if [ -z "$net" ]; then
            log_error "Tunnel interface for [$engine] not found!"
            return 1
        fi
        mark="$RT_MARK_TUNNEL"
        table="$RT_TABLE_TUNNEL"
    fi

    if [ "$mode" = "iran_direct" ] && [ ! -s "$ROUTING_DIR/direct_v4.list" ]; then
        if [ "$intercept" = "tunnel" ]; then
            log_warn "No direct list [$ROUTING_DIR/direct_v4.list]: all LAN traffic will use the tunnel."
        else
            log_info "No direct list found; Iran-direct routing is left to the [$engine] core rules."
        fi
    fi

    if ! _rt_render_nft "$intercept" "$port" "$mode" > "$RT_NFT_FILE.tmp"; then
        rm -f "$RT_NFT_FILE.tmp"
        log_error "Could not write nftables rules!"
        return 1
    fi
    if ! nft -c -f "$RT_NFT_FILE.tmp" >/dev/null 2>&1; then
        rm -f "$RT_NFT_FILE.tmp"
        if [ "$intercept" = "tproxy" ]; then
            log_error "nftables rejected the TPROXY rules. Is kmod-nft-tproxy installed?"
        else
            log_error "nftables rejected the routing rules!"
        fi
        return 1
    fi
    mv "$RT_NFT_FILE.tmp" "$RT_NFT_FILE"

    # Policy routing
    uci -q delete network.daypass_rule4
    uci -q delete network.daypass_rule6
    uci -q delete network.daypass_route4
    uci -q delete network.daypass_route6

    uci set network.daypass_rule4=rule
    uci set network.daypass_rule4.mark="$mark/$RT_MARK_MASK"
    uci set network.daypass_rule4.lookup="$table"
    uci set network.daypass_rule4.priority="$RT_RULE_PRIORITY"

    uci set network.daypass_route4=route
    uci set network.daypass_route4.target='0.0.0.0/0'
    uci set network.daypass_route4.table="$table"

    if [ "$ipv6" = "1" ]; then
        uci set network.daypass_rule6=rule6
        uci set network.daypass_rule6.mark="$mark/$RT_MARK_MASK"
        uci set network.daypass_rule6.lookup="$table"
        uci set network.daypass_rule6.priority="$RT_RULE_PRIORITY"

        uci set network.daypass_route6=route6
        uci set network.daypass_route6.target='::/0'
        uci set network.daypass_route6.table="$table"
    fi

    if [ "$intercept" = "tproxy" ]; then
        uci set network.daypass_route4.type='local'
        uci set network.daypass_route4.interface='loopback'
        if [ "$ipv6" = "1" ]; then
            uci set network.daypass_route6.type='local'
            uci set network.daypass_route6.interface='loopback'
        fi
    else
        uci set network.daypass_route4.interface="$net"
        [ "$ipv6" = "1" ] && uci set network.daypass_route6.interface="$net"
    fi
    uci commit network

    # Firewall include + tunnel zone
    uci -q delete firewall.daypass_transport
    uci set firewall.daypass_transport=include
    uci set firewall.daypass_transport.type='nftables'
    uci set firewall.daypass_transport.path="$RT_NFT_FILE"
    uci set firewall.daypass_transport.position='ruleset-post'

    uci -q delete firewall.daypass_vpn
    uci -q delete firewall.daypass_vpn_fwd
    if [ "$intercept" = "tunnel" ] && ! _rt_net_in_zone "$net"; then
        uci set firewall.daypass_vpn=zone
        uci set firewall.daypass_vpn.name='dp_vpn'
        uci set firewall.daypass_vpn.input='REJECT'
        uci set firewall.daypass_vpn.output='ACCEPT'
        uci set firewall.daypass_vpn.forward='REJECT'
        uci set firewall.daypass_vpn.masq='1'
        uci set firewall.daypass_vpn.mtu_fix='1'
        uci add_list firewall.daypass_vpn.network="$net"

        uci set firewall.daypass_vpn_fwd=forwarding
        uci set firewall.daypass_vpn_fwd.src='lan'
        uci set firewall.daypass_vpn_fwd.dest='dp_vpn'
    fi
    uci commit firewall

    /etc/init.d/network reload >/dev/null 2>&1 || true
    /etc/init.d/firewall reload >/dev/null 2>&1 || true

    if ! nft list table inet "$RT_NFT_TABLE" >/dev/null 2>&1; then
        nft -f "$RT_NFT_FILE" >/dev/null 2>&1
    fi
    if ! nft list table inet "$RT_NFT_TABLE" >/dev/null 2>&1; then
        log_error "DayPass nftables table could not be loaded!"
        return 1
    fi
    return 0
}

# ------------------------------------------------------------
# Apply a routing mode to the active (or given) transport engine
# ------------------------------------------------------------
apply_routing_mode() {
    local mode="$1"
    local engine intercept title rc

    if ! title=$(_rt_mode_title "$mode"); then
        log_error "Unknown routing mode : [$mode]"
        return 1
    fi

    engine=$(_transport_target_engine "${2:-}") || return 1
    intercept=$(transport_call "$engine" interception)

    log_info "Applying mode : $title ..."

    case "$intercept" in
        self)
            _rt_managed_active && _rt_clear_managed
            transport_call "$engine" apply_route_mode "$mode"
            rc=$?
            if [ "$rc" -eq 3 ]; then
                log_error "Engine [$engine] does not support routing modes!"
                return 1
            fi
            [ "$rc" -eq 0 ] || return 1
            ;;
        tproxy|tunnel)
            transport_call "$engine" apply_route_mode "$mode"
            rc=$?
            if [ "$rc" -ne 0 ] && [ "$rc" -ne 3 ]; then
                return 1
            fi

            if [ "$mode" = "direct_only" ]; then
                _rt_clear_managed
            else
                _rt_apply_managed "$engine" "$intercept" "$mode" || return 1
            fi
            ;;
        *)
            log_error "Engine [$engine] reported unknown interception [$intercept]!"
            return 1
            ;;
    esac

    echo "$mode" > "$ROUTING_DIR/current_mode"
    echo "$engine" > "$ROUTING_DIR/current_engine"

    case "$mode" in
        iran_direct)
            cat > "$ROUTING_DIR/iran_direct.rules" << EOF
# DayPass Routing Rule - Iran Direct
# Engine : $engine ($intercept)
# 1. Iranian domains & IPs → Direct
# 2. Everything else → Proxy
EOF
            ;;
        global_proxy)
            cat > "$ROUTING_DIR/global_proxy.rules" << EOF
# DayPass Routing Rule - Global Proxy
# Engine : $engine ($intercept)
# All traffic → Proxy
EOF
            ;;
        direct_only)
            cat > "$ROUTING_DIR/direct_only.rules" << EOF
# DayPass Routing Rule - Direct Only
# Engine : $engine ($intercept)
# All traffic → Direct (Proxy disabled)
EOF
            ;;
    esac

    if [ "$mode" = "direct_only" ]; then
        log_success "Mode [$(_rt_mode_label "$mode")] applied. Proxy disabled!"
    else
        log_success "Mode [$(_rt_mode_label "$mode")] applied to $engine!"
    fi
}

apply_iran_direct()  { apply_routing_mode iran_direct "$@"; }
apply_global_proxy() { apply_routing_mode global_proxy "$@"; }
apply_direct_only()  { apply_routing_mode direct_only "$@"; }

# Re-applies the saved mode (after engine switch / reload). No saved mode: nothing to do.
routing_reapply() {
    local mode
    mode=$(cat "$ROUTING_DIR/current_mode" 2>/dev/null)
    _rt_mode_title "$mode" >/dev/null || return 0
    apply_routing_mode "$mode" "${1:-}"
}

# ------------------------------------------------------------
# Show current routing status
# ------------------------------------------------------------
show_routing_status() {
    local mode engine intercept managed

    echo "  🚦 Current Routing Status"
    ui_divider

    if [ -f "$ROUTING_DIR/current_mode" ]; then
        mode=$(cat "$ROUTING_DIR/current_mode")
        echo "  🫀 Active Mode : ${GREEN}$mode${RESET}"
    else
        echo "  🫀 Active Mode : ${GRAY}Not configured${RESET}"
    fi

    engine=$(get_active_engine)
    if [ "$engine" = "none" ]; then
        echo "  🛡️ Engine      : ${GRAY}none${RESET}"
    else
        intercept=$(transport_call "$engine" interception)
        echo "  🛡️ Engine      : ${CYAN}$(transport_engine_label "$engine")${RESET}  ${GRAY}[$intercept]${RESET}"
        if [ "$intercept" != "self" ]; then
            if nft list table inet "$RT_NFT_TABLE" >/dev/null 2>&1; then
                managed="${GREEN}loaded${RESET}"
            else
                managed="${GRAY}not loaded${RESET}"
            fi
            echo "  🧱 DayPass Rules : $managed  ${GRAY}(IPv6 : $(_rt_opt ipv6 0))${RESET}"
        fi
    fi
    ui_divider
}

# ------------------------------------------------------------
# Main Routing Menu
# ------------------------------------------------------------
routing_menu() {
    local HELP_MODULE_ID="proxy_routing"

    while true; do
        render_persistent_header

        echo "  🚦 Traffic Routing / Shunt Rules"
        ui_divider
        show_routing_status
        echo
        echo "  👑 1) Iran Direct + Foreign Proxy   (Recommended)"
        echo "  🌏 2) Global Proxy                  (All traffic via proxy)"
        echo "  🎯 3) Direct Only                   (Disable proxy)"
        echo "  👀 4) Show current rules"
        echo "  🚀 5) Transport Engine              (Select / start / stop)"
        ui_nav_footer

        ui_prompt 5
        choice="$UI_CHOICE"

        case "$choice" in
            1) apply_iran_direct ;;
            2) apply_global_proxy ;;
            3) apply_direct_only ;;
            4)
                echo
                if [ -f "$ROUTING_DIR/current_mode" ]; then
                    mode=$(cat "$ROUTING_DIR/current_mode")
                    echo "  ⬆️  Current mode : $mode"
                    echo
                    cat "$ROUTING_DIR/${mode}.rules" 2>/dev/null || echo "  ${GRAY}No detailed rules file.${RESET}"
                    if [ -f "$RT_NFT_FILE" ]; then
                        echo
                        echo "  ${GRAY}nftables : $RT_NFT_FILE${RESET}"
                    fi
                else
                    echo "  💅🏻 No routing mode configured yet!"
                fi
                ;;
            5)
                proxy_engine_menu
                continue
                ;;
            q|Q) daypass_quit ;;
            h|H)
                if command -v show_help >/dev/null 2>&1; then
                    show_help "$HELP_MODULE_ID"
                else
                    log_warn "Help module not loaded!"
                    sleep 1
                fi
                continue
                ;;
            0) return 0 ;;
            *) log_warn "Invalid option!" ;;
        esac

        printf "\n  ${GRAY}Press [Enter] to continue ...${RESET}"
        read -r _ </dev/tty || daypass_quit
    done
}
