#!/bin/sh

handle_recommended_profile()
{
    # Clear manually selected packages so resolver handles strict ordering
    SELECTED_PACKAGES=""
    export SELECTED_PACKAGES
}