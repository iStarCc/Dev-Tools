#!/usr/bin/env bash
# 平台检测模块

detect_platform() {
    case "$(uname -s)" in
        Darwin*)  PLATFORM="macos" ;;
        Linux*)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                PLATFORM="wsl"
            else
                PLATFORM="linux"
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ;;
        *)                     PLATFORM="unknown" ;;
    esac
    export PLATFORM
}

is_macos()   { [[ "$PLATFORM" == "macos" ]]; }
is_linux()   { [[ "$PLATFORM" == "linux" ]]; }
is_wsl()     { [[ "$PLATFORM" == "wsl" ]]; }
is_windows() { [[ "$PLATFORM" == "windows" ]]; }

detect_platform
