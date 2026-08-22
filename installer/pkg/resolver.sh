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

    # 1. Low-level utilities and pre-requisites
    add_final "tcping"
    add_final "geoview"

    # 2. GeoIP / GeoSite databases
    if [ "${SELECTED_GEO:-official}" = "official" ]; then
        add_final "v2ray-geoip"
        add_final "v2ray-geosite"
    fi

    # 3. Core Routing Engines (Fix handling for singbox name variations)
    case "${SELECTED_ENGINE:-xray}" in
        xray)     
            add_final "xray-core" 
            ;;
        singbox|sing-box) 
            add_final "sing-box" 
            ;;
        both)
            add_final "xray-core"
            add_final "sing-box"
            ;;
        *)     
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
    case "${SELECTED_PROFILE:-passwall2}" in
        passwall2) MAIN_APP="luci-app-passwall2" ;;
        passwall)  MAIN_APP="luci-app-passwall" ;;
    esac

    [ -n "$MAIN_APP" ] && add_final "$MAIN_APP"

    # 6. Localization & Translation Packages
    LANG_CODE="${SELECTED_LANGUAGE:-fa}"
    APP_NAME="${SELECTED_PROFILE:-passwall2}"

    if [ "$LANG_CODE" != "en" ]; then
        I18N_PKG="luci-i18n-${APP_NAME}-${LANG_CODE}"

        if [ -z "$MANIFEST_FILE" ] || [ ! -f "$MANIFEST_FILE" ]; then
            if [ -f "/tmp/manifest.json" ]; then
                MANIFEST_FILE="/tmp/manifest.json"
            elif [ -f "manifest.json" ]; then
                MANIFEST_FILE="manifest.json"
            fi
        fi

        if [ -n "$MANIFEST_FILE" ] && [ -f "$MANIFEST_FILE" ]; then
            EXISTS="$(jq -r --arg arch "${ARCH:-x86_64}" --arg pkg "$I18N_PKG" '
                .architectures[] | select(.name==$arch) | .feeds[]?[]? | select(.package==$pkg) | .package
            ' "$MANIFEST_FILE" 2>/dev/null)"

            if [ -n "$EXISTS" ]; then
                add_final "$I18N_PKG"
            else
                log_warn "Translation package [$I18N_PKG] is not available in feeds. Skipped."
            fi
        else
            [ "$APP_NAME" = "passwall2" ] && add_final "$I18N_PKG"
        fi
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