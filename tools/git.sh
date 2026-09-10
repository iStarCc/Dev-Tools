#!/usr/bin/env bash
# Git 工具集 - 主菜单入口

_GIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_GIT_DIR/git-config.sh"
source "$_GIT_DIR/git-ops.sh"

menu_git() {
    while true; do
        show_menu "Git 工具" true \
            "常用操作" \
            "分支管理" \
            "远程仓库" \
            "配置管理"

        case $MENU_RESULT in
            0) menu_git_ops ;;
            1) menu_git_branch ;;
            2) menu_git_remote ;;
            3) menu_git_config ;;
            255) return ;;
        esac
    done
}
