#!/usr/bin/env bash
# 交互式菜单框架 + UI 组件

# ── 颜色 ─────────────────────────────────────────────────────
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_BLUE='\033[34m'
C_CYAN='\033[36m'
C_RED='\033[31m'
C_WHITE='\033[97m'

# ── 全局变量 ─────────────────────────────────────────────────
MENU_RESULT=0

# ── 按键读取（兼容 macOS bash 3.2，使用整数超时）──────────
read_key() {
    local key
    IFS= read -rsn1 key 2>/dev/null || return

    if [[ "$key" == $'\e' ]]; then
        # bash 3.2 不支持小数 -t，必须用整数；一次读 2 字符捕获 [A / [B
        local rest=""
        IFS= read -rsn2 -t 1 rest 2>/dev/null || true
        case "$rest" in
            '[A') echo "up"; return ;;
            '[B') echo "down"; return ;;
            '[C') echo "right"; return ;;
            '[D') echo "left"; return ;;
        esac
        echo "esc"
        return
    fi

    case "$key" in
        "")    echo "enter" ;;
        [0-9]) echo "num_$key" ;;
        k|K)   echo "up" ;;
        j|J)   echo "down" ;;
        q|Q)   echo "quit" ;;
    esac
}

# ── 交互式菜单 ───────────────────────────────────────────────
# 用法: show_menu "标题" has_back "选项1" "选项2" ...
# 结果: MENU_RESULT = 0~N-1 选项索引 | 255 返回/退出
show_menu() {
    local title="$1"
    local has_back="$2"
    shift 2
    local options=("$@")
    local selected=0
    local total=${#options[@]}

    tput civis 2>/dev/null || true

    while true; do
        clear
        echo ""
        printf "  ${C_BOLD}${C_CYAN}┌──────────────────────────────────────────┐${C_RESET}\n"
        printf "  ${C_BOLD}${C_CYAN}│${C_RESET}  ${C_BOLD}${C_WHITE}🛠  %-36s${C_RESET} ${C_BOLD}${C_CYAN}│${C_RESET}\n" "$title"
        printf "  ${C_BOLD}${C_CYAN}└──────────────────────────────────────────┘${C_RESET}\n"
        echo ""

        local i
        for i in "${!options[@]}"; do
            if [[ $i -eq $selected ]]; then
                printf "    ${C_BOLD}${C_GREEN}▶ %d. %s${C_RESET}\n" "$((i + 1))" "${options[$i]}"
            else
                printf "      ${C_DIM}%d. %s${C_RESET}\n" "$((i + 1))" "${options[$i]}"
            fi
        done

        echo ""
        if [[ "$has_back" == "true" ]]; then
            if [[ $selected -eq $total ]]; then
                printf "    ${C_BOLD}${C_YELLOW}▶ 0. ← 返回上级${C_RESET}\n"
            else
                printf "      ${C_DIM}0. ← 返回上级${C_RESET}\n"
            fi
        else
            if [[ $selected -eq $total ]]; then
                printf "    ${C_BOLD}${C_RED}▶ 0. 退出${C_RESET}\n"
            else
                printf "      ${C_DIM}0. 退出${C_RESET}\n"
            fi
        fi

        echo ""
        printf "  ${C_DIM}──────────────────────────────────────────────${C_RESET}\n"
        local hint="↑↓/jk 选择  Enter 确认"
        if [[ "$has_back" == "true" ]]; then
            hint+="  ESC/0 返回"
        else
            hint+="  q/0 退出"
        fi
        printf "  ${C_DIM}%s${C_RESET}\n" "$hint"

        local key
        key=$(read_key)

        case "$key" in
            up)
                if ((selected > 0)); then
                    ((selected--))
                else
                    selected=$total
                fi
                ;;
            down)
                if ((selected < total)); then
                    ((selected++))
                else
                    selected=0
                fi
                ;;
            enter)
                tput cnorm 2>/dev/null || true
                if [[ $selected -eq $total ]]; then
                    MENU_RESULT=255
                else
                    MENU_RESULT=$selected
                fi
                return
                ;;
            esc)
                if [[ "$has_back" == "true" ]]; then
                    tput cnorm 2>/dev/null || true
                    MENU_RESULT=255
                    return
                fi
                ;;
            quit)
                if [[ "$has_back" != "true" ]]; then
                    tput cnorm 2>/dev/null || true
                    MENU_RESULT=255
                    return
                fi
                ;;
            num_0)
                tput cnorm 2>/dev/null || true
                MENU_RESULT=255
                return
                ;;
            num_*)
                local num=${key#num_}
                if ((num >= 1 && num <= total)); then
                    tput cnorm 2>/dev/null || true
                    MENU_RESULT=$((num - 1))
                    return
                fi
                ;;
        esac
    done
}

# ── 作用域选择子菜单（全局 / 当前仓库）───────────────────────
# 结果: SCOPE_RESULT = "global" | "local" | ""(取消)
SCOPE_RESULT=""

select_scope() {
    local label="${1:-作用域}"
    show_menu "选择${label}" true "全局" "当前仓库"
    case $MENU_RESULT in
        0) SCOPE_RESULT="global" ;;
        1) SCOPE_RESULT="local" ;;
        *) SCOPE_RESULT="" ;;
    esac
}

scope_flag()  { [[ "$1" == "global" ]] && echo "--global" || echo "--local"; }
scope_label() { [[ "$1" == "global" ]] && echo "全局" || echo "当前仓库"; }

# ── 输入 / 消息 / 确认 ──────────────────────────────────────

prompt_input() {
    local label="$1"
    local default="${2:-}"
    local result

    # 所有显示输出走 stderr，避免被 $() 捕获
    tput cnorm >&2 2>/dev/null || true
    if [[ -n "$default" ]]; then
        printf "  ${C_CYAN}%s${C_RESET} ${C_DIM}(当前: %s)${C_RESET}: " "$label" "$default" >&2
    else
        printf "  ${C_CYAN}%s${C_RESET}: " "$label" >&2
    fi
    read -r result
    echo "${result:-$default}"
}

# 带验证的输入提示（循环直到合法或用户输入空值取消）
# 用法: prompt_validated "标签" "默认值" validator_func "错误提示"
# 返回: 0=成功(值通过 stdout), 1=取消(空输入)
prompt_validated() {
    local label="$1"
    local default="$2"
    local validator="$3"
    local err_msg="$4"

    while true; do
        local value
        value=$(prompt_input "$label" "$default")
        [[ -z "$value" ]] && return 1
        if $validator "$value"; then
            echo "$value"
            return 0
        fi
        # 错误提示写到 stderr，避免被外层 $() 捕获
        printf "\n  ${C_RED}✘ %s${C_RESET}\n" "$err_msg" >&2
    done
}

# ── 验证器（正则存入变量，兼容 bash 3.2）────────────────────

validate_email() {
    local re='^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    [[ "$1" =~ $re ]]
}

validate_git_branch() {
    local bad='\.\.|~|\^|:|\\|\?|\*|\[|@\{'
    local bad_start='^[./-]'
    local bad_end='\.lock$|\.$|/$'
    [[ -n "$1" ]] \
        && [[ ! "$1" =~ [[:space:][:cntrl:]] ]] \
        && [[ ! "$1" =~ $bad ]] \
        && [[ ! "$1" =~ $bad_start ]] \
        && [[ ! "$1" =~ $bad_end ]]
}

validate_proxy_url() {
    local re='^(https?|socks5?)://[a-zA-Z0-9._-]+(:[0-9]+)?/?$'
    [[ "$1" =~ $re ]]
}

validate_positive_int() {
    local re='^[1-9][0-9]*$'
    [[ "$1" =~ $re ]]
}

validate_not_empty() {
    [[ -n "$1" ]]
}

msg_success() { printf "\n  ${C_GREEN}✔ %s${C_RESET}\n" "$1"; }
msg_error()   { printf "\n  ${C_RED}✘ %s${C_RESET}\n" "$1"; }
msg_info()    { printf "\n  ${C_BLUE}ℹ %s${C_RESET}\n" "$1"; }
msg_warn()    { printf "\n  ${C_YELLOW}⚠ %s${C_RESET}\n" "$1"; }

press_any_key() {
    echo ""
    printf "  ${C_DIM}按任意键继续...${C_RESET}"
    read -rsn1
}

# 检查是否在 Git 仓库内
require_git_repo() {
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        msg_error "当前目录不是 Git 仓库"
        press_any_key
        return 1
    fi
}
