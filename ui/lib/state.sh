#!/bin/sh

SELECTED_PROFILE=""
SELECTED_ENGINE="auto"
SELECTED_LANGUAGE="none"
SELECTED_GEO="none"
SELECTED_PACKAGES=""
GEOIP_URL=""
GEOSITE_URL=""

add_selected_package()
{
    pkg="$1"
    [ -z "$pkg" ] && return

    case " $SELECTED_PACKAGES " in
        *" $pkg "*) ;;
        *) SELECTED_PACKAGES="$SELECTED_PACKAGES $pkg" ;;
    esac
}

reset_state()
{
    SELECTED_PROFILE=""
    SELECTED_ENGINE="auto"
    SELECTED_LANGUAGE="none"
    SELECTED_GEO="none"
    SELECTED_PACKAGES=""
    GEOIP_URL=""
    GEOSITE_URL=""
}