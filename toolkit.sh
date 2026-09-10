#!/usr/bin/env bash
# ============================================================
# 开发工具集 - 交互式 Shell 工具箱
# 支持 macOS / Linux / Windows(Git Bash, WSL)
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载模块
source "$SCRIPT_DIR/lib/platform.sh"
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/tools/git.sh"
source "$SCRIPT_DIR/tools/easytier.sh"

main() {
    trap 'tput cnorm 2>/dev/null || true' EXIT

    while true; do
        show_menu "开发工具集" false \
            "Git 工具" \
            "EasyTier 工具"

        case $MENU_RESULT in
            0)   menu_git ;;
            1)   menu_easytier ;;
            255)
                clear
                printf "\n  ${C_CYAN}👋 再见！${C_RESET}\n\n"
                exit 0
                ;;
        esac
    done
}

main "$@"
