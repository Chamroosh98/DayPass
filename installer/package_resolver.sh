#!/bin/sh

# Resolves target packages and dependencies for opkg / apk engines
resolve_packages()
{
    log_info "Resolving targeted packages and dependencies for engine : [${PKG_MANAGER:-opkg}] ..."

    FINAL_PACKAGES=""

    # Helper function to append package uniquely to resolution queue
    add_final()
    {
        pkg="$1"
        [ -z "$pkg" ] && return

        case " $FINAL_PACKAGES " in
            *" $pkg "*) 
                # Package already resolved; skipping duplicate entry
                ;;
            *) 
                if [ -z "$FINAL_PACKAGES" ]; then
                    FINAL_PACKAGES="$pkg"
                else
                    FINAL_PACKAGES="$FINAL_PACKAGES $pkg"
                fi
                log_info "  ├─ Resolved target : [$pkg]"
                ;;
        esac
    }

    CURRENT_MGR="${PKG_MANAGER:-opkg}"

    # 1. Low-level utilities and pre-requisites
    add_final "tcping"
    add_final "geoview"

    # 2. GeoIP / GeoSite databases
    if [ "${SELECTED_GEO:-}" = "official" ]; then
        add_final "v2ray-geoip"
        add_final "v2ray-geosite"
    fi

    # 3. Core Routing Engines
    case "${SELECTED_ENGINE:-auto}" in
        xray)     
            add_final "xray-core" 
            ;;
        sing-box) 
            add_final "sing-box" 
            ;;
        auto|*)     
            add_final "xray-core" 
            ;;
    esac

    # 4. User-selected custom packages (excluding main application and translations)
    if [ -n "${SELECTED_PACKAGES:-}" ]; then
        for pkg in $SELECTED_PACKAGES; do
            case "$pkg" in
                luci-app-passwall|luci-app-passwall2|luci-i18n-*) 
                    # Skipped here to ensure strict sequence ordering below
                    ;; 
                *) 
                    add_final "$pkg" 
                    ;;
            esac
        done
    fi

    # 5. Main Application Interface (Must be installed BEFORE translation packages)
    MAIN_APP=""
    case "${SELECTED_PROFILE:-}" in
        passwall2) MAIN_APP="luci-app-passwall2" ;;
        passwall)  MAIN_APP="luci-app-passwall" ;;
    esac

    [ -n "$MAIN_APP" ] && add_final "$MAIN_APP"

    # 6. Localization & Translation Packages (Must be installed AFTER main app)
    if [ -n "${SELECTED_LANGUAGE:-}" ]; then
        LANG_CODE="${SELECTED_LANGUAGE:-}"
        APP_NAME="${SELECTED_PROFILE:-passwall2}"

        # Resolve package name (handles edge cases across apk / opkg naming schemas)
        I18N_PKG="luci-i18n-${APP_NAME}-${LANG_CODE}"

        case "$LANG_CODE" in
            fa|zh-cn|ru)
                add_final "$I18N_PKG"
                ;;
        esac
    fi

    # Validate non-empty final package list
    if [ -z "$FINAL_PACKAGES" ]; then
        log_error "Package resolution finished with an empty target package list :("
        return 1
    fi

    log_success "Package resolution completed successfully :)"
    log_info "Final deployment target list : [$FINAL_PACKAGES]"

    export FINAL_PACKAGES
}

# Standalone execution handler
case "$0" in
    *package_resolver.sh) resolve_packages ;;
esac