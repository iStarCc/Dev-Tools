#!/usr/bin/env bash
# Git 配置管理

_git_set_user_field() {
    local field="$1"
    local field_label config_key validator err_msg

    if [[ "$field" == "name" ]]; then
        field_label="用户名"
        config_key="user.name"
        validator="validate_not_empty"
        err_msg="用户名不能为空"
    else
        field_label="邮箱"
        config_key="user.email"
        validator="validate_email"
        err_msg="邮箱格式不正确，如: user@example.com"
    fi

    select_scope
    [[ -z "$SCOPE_RESULT" ]] && return

    local scope="$SCOPE_RESULT"
    local flag
    flag=$(scope_flag "$scope")

    if [[ "$scope" == "local" ]]; then
        require_git_repo || return
    fi

    local current
    current=$(git config "$flag" "$config_key" 2>/dev/null || echo "")

    echo ""
    msg_info "设置$(scope_label "$scope")${field_label}"

    local value
    if value=$(prompt_validated "请输入${field_label}" "$current" "$validator" "$err_msg"); then
        git config "$flag" "$config_key" "$value"
        msg_success "$(scope_label "$scope")${field_label}已设置为: $value"
    else
        msg_warn "已取消"
    fi
    press_any_key
}

git_set_username() { _git_set_user_field "name"; }
git_set_email()    { _git_set_user_field "email"; }

git_ignore_filemode() {
    select_scope
    [[ -z "$SCOPE_RESULT" ]] && return

    local scope="$SCOPE_RESULT"
    local flag
    flag=$(scope_flag "$scope")

    if [[ "$scope" == "local" ]]; then
        require_git_repo || return
    fi

    local current
    current=$(git config "$flag" core.fileMode 2>/dev/null || echo "未设置")

    git config "$flag" core.fileMode false
    echo ""
    printf "  ${C_DIM}core.fileMode: %s → false${C_RESET}\n" "$current"
    msg_success "$(scope_label "$scope") 已忽略文件权限变更"
    press_any_key
}

git_set_default_branch() {
    local current
    current=$(git config --global init.defaultBranch 2>/dev/null || echo "")

    echo ""
    msg_info "设置全局默认分支名"

    local branch
    if branch=$(prompt_validated "默认分支名" "${current:-main}" validate_git_branch "分支名无效（不允许空格、..、特殊字符等）"); then
        git config --global init.defaultBranch "$branch"
        msg_success "全局默认分支名已设置为: $branch"
    else
        msg_warn "已取消"
    fi
    press_any_key
}

git_set_line_ending() {
    local current
    current=$(git config --global core.autocrlf 2>/dev/null || echo "未设置")

    local opts=() values=()
    if is_windows || is_wsl; then
        opts+=("true  (提交转LF, 检出转CRLF) [推荐]") ; values+=("true")
        opts+=("input (提交转LF, 检出不转)")            ; values+=("input")
    else
        opts+=("input (提交转LF, 检出不转) [推荐]")     ; values+=("input")
        opts+=("true  (提交转LF, 检出转CRLF)")          ; values+=("true")
    fi
    opts+=("false (不做转换)")                           ; values+=("false")

    show_menu "换行符 (当前: $current)" true "${opts[@]}"
    [[ $MENU_RESULT -eq 255 ]] && return

    git config --global core.autocrlf "${values[$MENU_RESULT]}"
    msg_success "core.autocrlf = ${values[$MENU_RESULT]}"
    press_any_key
}

git_set_proxy() {
    local current_http
    current_http=$(git config --global http.proxy 2>/dev/null || echo "")

    show_menu "Git 代理 (当前: ${current_http:-未设置})" true \
        "socks5://127.0.0.1:7890" \
        "http://127.0.0.1:7890" \
        "socks5://127.0.0.1:1080" \
        "http://127.0.0.1:8080" \
        "自定义地址"
    [[ $MENU_RESULT -eq 255 ]] && return

    local proxy=""
    case $MENU_RESULT in
        0) proxy="socks5://127.0.0.1:7890" ;;
        1) proxy="http://127.0.0.1:7890" ;;
        2) proxy="socks5://127.0.0.1:1080" ;;
        3) proxy="http://127.0.0.1:8080" ;;
        4)
            echo ""
            if ! proxy=$(prompt_validated "代理地址" "$current_http" validate_proxy_url "格式不正确，如: socks5://127.0.0.1:7890"); then
                msg_warn "已取消"
                press_any_key
                return
            fi
            ;;
    esac

    git config --global http.proxy "$proxy"
    git config --global https.proxy "$proxy"
    msg_success "代理已设置为: $proxy"
    press_any_key
}

git_clear_proxy() {
    git config --global --unset http.proxy 2>/dev/null || true
    git config --global --unset https.proxy 2>/dev/null || true
    echo ""
    msg_success "已清除全局代理设置"
    press_any_key
}

git_set_credential() {
    local current
    current=$(git config --global credential.helper 2>/dev/null || echo "")

    local opts=()
    opts+=("cache  (内存缓存，默认15分钟)")
    opts+=("store  (明文存储到磁盘)")
    if is_macos; then
        opts+=("osxkeychain (macOS 钥匙串)")
    fi
    if is_windows; then
        opts+=("manager (Windows 凭据管理器)")
    fi
    opts+=("自定义超时的 cache")

    show_menu "凭据缓存 (当前: ${current:-未设置})" true "${opts[@]}"
    [[ $MENU_RESULT -eq 255 ]] && return

    local helper="${opts[$MENU_RESULT]}"

    case "$helper" in
        cache*)
            git config --global credential.helper cache
            msg_success "已设置为 cache"
            ;;
        store*)
            git config --global credential.helper store
            msg_success "已设置为 store"
            ;;
        *osxkeychain*)
            git config --global credential.helper osxkeychain
            msg_success "已设置为 osxkeychain"
            ;;
        *manager*)
            git config --global credential.helper manager
            msg_success "已设置为 manager"
            ;;
        *自定义*)
            echo ""
            local timeout
            if timeout=$(prompt_validated "缓存超时（秒）" "3600" validate_positive_int "请输入正整数"); then
                git config --global credential.helper "cache --timeout=$timeout"
                msg_success "已设置为 cache，超时 $timeout 秒"
            else
                msg_warn "已取消"
            fi
            ;;
    esac
    press_any_key
}

git_show_config() {
    select_scope
    [[ -z "$SCOPE_RESULT" ]] && return

    local scope="$SCOPE_RESULT"
    local flag
    flag=$(scope_flag "$scope")

    if [[ "$scope" == "local" ]]; then
        require_git_repo || return
    fi

    echo ""
    msg_info "$(scope_label "$scope") Git 配置"
    printf "  ${C_DIM}──────────────────────────────────────────${C_RESET}\n"

    local config_output
    config_output=$(git config "$flag" --list 2>/dev/null || echo "")

    if [[ -z "$config_output" ]]; then
        printf "  ${C_YELLOW}(空)${C_RESET}\n"
    else
        echo "$config_output" | while IFS='=' read -r key value; do
            printf "  ${C_CYAN}%-30s${C_RESET} = ${C_WHITE}%s${C_RESET}\n" "$key" "$value"
        done
    fi

    printf "  ${C_DIM}──────────────────────────────────────────${C_RESET}\n"
    press_any_key
}

menu_git_config() {
    while true; do
        show_menu "Git 配置管理" true \
            "设置用户名" \
            "设置邮箱" \
            "忽略文件权限" \
            "设置默认分支名" \
            "设置换行符处理" \
            "设置代理" \
            "清除代理" \
            "设置凭据缓存" \
            "查看 Git 配置"

        case $MENU_RESULT in
            0) git_set_username ;;
            1) git_set_email ;;
            2) git_ignore_filemode ;;
            3) git_set_default_branch ;;
            4) git_set_line_ending ;;
            5) git_set_proxy ;;
            6) git_clear_proxy ;;
            7) git_set_credential ;;
            8) git_show_config ;;
            255) return ;;
        esac
    done
}
