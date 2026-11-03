#!/bin/sh
# ============================================================
# DayPass - Passwall Recommended Mode Profile
# ============================================================

handle_recommended_profile()
{
    # Clear manually selected packages so resolver handles strict ordering
    SELECTED_PACKAGES=""

    # Default pre-configured parameters for Recommended mode
    SELECTED_ENGINE="xray"
    SELECTED_LANGUAGE="fa"
    SELECTED_GEO="official"

    export SELECTED_PACKAGES SELECTED_ENGINE SELECTED_LANGUAGE SELECTED_GEO
    return 0
}