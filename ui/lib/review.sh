#!/bin/sh

review_install()
{
    local i pkg count confirm engine_packages geo_packages translations feed_label
    local title mode dataset label
    if ! resolve_packages proxy; then
        log_error "Failed to resolve the installation plan."
        ui_pause
        return 2
    fi

    title="$(mf_title_for "$SELECTED_PROFILE")"
    case "$SELECTED_MODE" in
        recommended) mode=Recommended ;;
        custom) mode=Custom ;;
    esac
    case "$SELECTED_GEO" in
        official) dataset="Standard GeoIP/GeoSite packages" ;;
        iran-full) dataset="Iran Full (staging only)" ;;
        iran-lite) dataset="Iran Lite (staging only)" ;;
        *) dataset="Skip adding targets through the Geo menu" ;;
    esac

    engine_packages=""
    geo_packages=""
    translations=""
    set -- $FINAL_PACKAGES
    count=$#
    for pkg do
        case "$pkg" in
            xray-core) label=Xray ;;
            sing-box) label=Sing-box ;;
            v2ray-core) label=V2Ray ;;
            *) label="" ;;
        esac
        [ -z "$label" ] || engine_packages="${engine_packages:+$engine_packages, }$label"

        case "$pkg" in
            v2ray-geoip|v2ray-geosite|geoip|geosite)
                geo_packages="${geo_packages:+$geo_packages, }$pkg"
                ;;
            luci-i18n-*)
                label="${pkg#luci-i18n-$SELECTED_PROFILE-}"
                case "$label" in
                    fa) label=Persian ;;
                    zh-cn) label="Simplified Chinese" ;;
                    zh-tw) label="Traditional Chinese" ;;
                    ru) label=Russian ;;
                    en) label=English ;;
                esac
                translations="${translations:+$translations, }$label"
                ;;
        esac
    done

    while true; do
        render_persistent_header
        ui_title "📊 $title — Installation Plan"
        printf '  🛠️  %-18s : %s\n' "Installation Mode" "$mode"
        printf '  ⚙️  %-18s : %s\n' "Proxy Engine" "${engine_packages:-None selected}"
        printf '  🗣️  %-18s : %s\n' "Translation" "${translations:-No additional pack}"
        printf '  🌐 %-18s : %s\n' "Geo Database" "$dataset"
        printf '  📦 %-18s : %s\n' "Geo Data Targets" "${geo_packages:-None selected}"
        printf '  🚦 %-18s : %s\n' "Routing" "Configure separately in Traffic Routing"
        ui_divider

        printf '  📦 Targeted Packages (%s)\n' "$count"
        i=0
        for pkg do
            i=$((i + 1))
            feed_label=""
            case " $REVIEW_FEED_PACKAGES " in
                *" $pkg "*) feed_label=" (router feed)" ;;
            esac
            if [ "$i" -eq "$count" ]; then
                printf '     └─ 🔹 %b%s%b%s\n' "$CYAN" "$pkg" "$RESET" "$feed_label"
            else
                printf '     ├─ 🔹 %b%s%b%s\n' "$CYAN" "$pkg" "$RESET" "$feed_label"
            fi
        done
        printf '  %s\n' "The package manager may also install dependencies."
        ui_nav_footer review
        ui_read "Proceed with deployment? [Y/n]"
        confirm="$UI_CHOICE"

        case "$confirm" in
            y|Y|"") return 0 ;;
            q|Q) daypass_quit ;;
            h|H) ui_show_help "packages" ;;
            n|N|0)
                log_info "Installation cancelled."
                return 1
                ;;
            *)
                log_error "Enter Y to deploy or N to cancel."
                sleep 1
                ;;
        esac
    done
}
