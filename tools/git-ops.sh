#!/usr/bin/env bash
# Git 常用操作 + 分支管理

# ── 仓库操作 ─────────────────────────────────────────────────

git_init_repo() {
    echo ""
    msg_info "初始化 Git 仓库"

    if [[ -d .git ]]; then
        msg_warn "当前目录已是 Git 仓库"
        press_any_key
        return
    fi

    local branch
    if branch=$(prompt_validated "默认分支名" "main" validate_git_branch "分支名无效"); then
        if git init -b "$branch" 2>/dev/null; then
            msg_success "已初始化 (默认分支: $branch)"
        else
            git init && git checkout -b "$branch" 2>/dev/null || true
            msg_success "已初始化 (默认分支: $branch)"
        fi
    else
        msg_warn "已取消"
    fi
    press_any_key
}

git_pull() {
    require_git_repo || return

    local branch remote
    branch=$(git branch --show-current 2>/dev/null || echo "")
    remote=$(git remote 2>/dev/null | head -1)

    local title="拉取"
    [[ -n "$branch" ]] && title+=" [$branch"
    [[ -n "$remote" ]] && title+=" ← $remote"
    [[ -n "$branch" ]] && title+="]"

    show_menu "$title" true \
        "pull (合并模式)" \
        "pull --rebase (变基模式)" \
        "pull --ff-only (仅快进)"
    [[ $MENU_RESULT -eq 255 ]] && return

    echo ""
    local ok=true
    case $MENU_RESULT in
        0) git pull              2>&1 || ok=false ;;
        1) git pull --rebase     2>&1 || ok=false ;;
        2) git pull --ff-only    2>&1 || ok=false ;;
    esac

    $ok && msg_success "拉取成功" || msg_error "拉取失败"
    press_any_key
}

git_push() {
    require_git_repo || return

    local branch tracking
    branch=$(git branch --show-current 2>/dev/null || echo "")
    tracking=$(git rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null || echo "")

    local title="推送"
    [[ -n "$branch" ]] && title+=" [$branch"
    [[ -n "$tracking" ]] && title+=" → $tracking"
    [[ -n "$branch" ]] && title+="]"

    show_menu "$title" true \
        "push" \
        "push -u origin $branch (设置上游)" \
        "push --force-with-lease (安全强推)" \
        "push --tags (推送所有标签)"
    [[ $MENU_RESULT -eq 255 ]] && return

    echo ""
    local ok=true
    case $MENU_RESULT in
        0) git push                     2>&1 || ok=false ;;
        1) git push -u origin "$branch" 2>&1 || ok=false ;;
        2) git push --force-with-lease  2>&1 || ok=false ;;
        3) git push --tags              2>&1 || ok=false ;;
    esac

    $ok && msg_success "推送成功" || msg_error "推送失败"
    press_any_key
}

git_reset_commit() {
    require_git_repo || return

    echo ""
    msg_info "最近提交"
    git --no-pager log --oneline --color=always -10 2>/dev/null
    echo ""

    show_menu "重置模式" true \
        "soft  (保留修改在暂存区)" \
        "mixed (保留修改在工作区)" \
        "hard  (丢弃所有修改 ⚠️)"
    [[ $MENU_RESULT -eq 255 ]] && return

    local mode
    case $MENU_RESULT in
        0) mode="--soft" ;;
        1) mode="--mixed" ;;
        2) mode="--hard" ;;
    esac

    echo ""
    local target
    target=$(prompt_input "重置目标 (hash 或 HEAD~N)" "HEAD~1")
    [[ -z "$target" ]] && return

    if ! git rev-parse --verify "$target" &>/dev/null; then
        msg_error "无效的提交引用: $target"
        press_any_key
        return
    fi

    if [[ "$mode" == "--hard" ]]; then
        echo ""
        printf "  ${C_RED}⚠ hard reset 将丢弃所有未提交的修改！${C_RESET}\n"
        printf "  ${C_YELLOW}输入 yes 确认: ${C_RESET}"
        local confirm
        read -r confirm
        if [[ "$confirm" != "yes" ]]; then
            msg_warn "已取消"
            press_any_key
            return
        fi
    fi

    if git reset $mode "$target" 2>&1; then
        msg_success "已重置到 $target ($mode)"
    else
        msg_error "重置失败"
    fi
    press_any_key
}

git_stash() {
    require_git_repo || return

    local count
    count=$(git stash list 2>/dev/null | wc -l | tr -d ' ')

    show_menu "暂存 (当前: ${count} 条)" true \
        "保存当前修改" \
        "保存 (含未跟踪文件)" \
        "弹出最近暂存 (pop)" \
        "应用最近暂存 (apply)" \
        "查看暂存列表" \
        "删除指定暂存" \
        "清空所有暂存"
    [[ $MENU_RESULT -eq 255 ]] && return

    echo ""
    case $MENU_RESULT in
        0)
            local msg
            msg=$(prompt_input "暂存说明（可选）" "")
            if [[ -n "$msg" ]]; then
                git stash push -m "$msg" 2>&1 && msg_success "已暂存" || msg_error "暂存失败"
            else
                git stash 2>&1 && msg_success "已暂存" || msg_error "暂存失败"
            fi
            ;;
        1)
            git stash push --include-untracked 2>&1 && msg_success "已暂存" || msg_error "暂存失败"
            ;;
        2) git stash pop   2>&1 && msg_success "已弹出" || msg_error "弹出失败（可能有冲突）" ;;
        3) git stash apply 2>&1 && msg_success "已应用" || msg_error "应用失败（可能有冲突）" ;;
        4)
            if [[ "$count" -eq 0 ]]; then
                printf "  ${C_DIM}(空)${C_RESET}\n"
            else
                git --no-pager stash list --color=always 2>/dev/null
            fi
            ;;
        5)
            if [[ "$count" -eq 0 ]]; then
                msg_warn "暂存列表为空"
            else
                git --no-pager stash list 2>/dev/null
                echo ""
                local idx
                idx=$(prompt_input "要删除的序号 (如 0)" "0")
                git stash drop "stash@{${idx:-0}}" 2>&1 && msg_success "已删除" || msg_error "删除失败"
            fi
            ;;
        6)
            printf "  ${C_RED}⚠ 确定清空所有暂存？${C_RESET}\n"
            printf "  ${C_YELLOW}输入 yes 确认: ${C_RESET}"
            local confirm
            read -r confirm
            if [[ "$confirm" == "yes" ]]; then
                git stash clear 2>&1 && msg_success "已清空" || msg_error "操作失败"
            else
                msg_warn "已取消"
            fi
            ;;
    esac
    press_any_key
}

git_log_view() {
    require_git_repo || return

    show_menu "查看历史" true \
        "简洁模式 (最近 20 条)" \
        "图形模式 (最近 30 条)" \
        "详细模式 (最近 10 条)" \
        "文件历史"
    [[ $MENU_RESULT -eq 255 ]] && return

    tput cnorm >&2 2>/dev/null || true
    echo ""
    case $MENU_RESULT in
        0) git --no-pager log --oneline --color=always -20 ;;
        1) git --no-pager log --oneline --graph --all --color=always -30 ;;
        2) git --no-pager log --color=always --format="%C(yellow)%h%C(reset) %C(blue)%ad%C(reset) %C(green)%an%C(reset)%n  %s" --date=short -10 ;;
        3)
            local file
            file=$(prompt_input "文件路径" "")
            if [[ -z "$file" ]]; then
                press_any_key
                return
            fi
            if [[ ! -e "$file" ]] && ! git log --oneline -1 -- "$file" &>/dev/null; then
                msg_error "文件不存在且无历史记录: $file"
                press_any_key
                return
            fi
            git --no-pager log --oneline --color=always -- "$file"
            ;;
    esac
    press_any_key
}

# ── 分支管理 ─────────────────────────────────────────────────

# 获取本地分支列表（去除 * 和空格前缀）
_git_local_branches() {
    git branch 2>/dev/null | sed 's/^[* ]*//'
}

git_branch_list() {
    require_git_repo || return

    echo ""
    msg_info "本地分支"
    git --no-pager branch -v --color=always 2>/dev/null
    echo ""
    msg_info "远程分支"
    git --no-pager branch -rv --color=always 2>/dev/null || printf "  ${C_DIM}(无远程分支)${C_RESET}\n"
    press_any_key
}

git_branch_create() {
    require_git_repo || return

    echo ""
    local name
    if name=$(prompt_validated "新分支名" "" validate_git_branch "分支名无效"); then
        show_menu "创建后" true "切换到新分支" "留在当前分支"
        [[ $MENU_RESULT -eq 255 ]] && return

        if [[ $MENU_RESULT -eq 0 ]]; then
            git checkout -b "$name" 2>&1 && msg_success "已创建并切换到: $name" || msg_error "创建失败"
        else
            git branch "$name" 2>&1 && msg_success "已创建分支: $name" || msg_error "创建失败"
        fi
    else
        msg_warn "已取消"
    fi
    press_any_key
}

git_branch_switch() {
    require_git_repo || return

    local branches=()
    while IFS= read -r b; do
        [[ -n "$b" ]] && branches+=("$b")
    done < <(_git_local_branches)

    if [[ ${#branches[@]} -eq 0 ]]; then
        msg_warn "没有可切换的分支"
        press_any_key
        return
    fi

    local current
    current=$(git branch --show-current 2>/dev/null || echo "")

    show_menu "切换分支 (当前: $current)" true "${branches[@]}"
    [[ $MENU_RESULT -eq 255 ]] && return

    local target="${branches[$MENU_RESULT]}"
    if [[ "$target" == "$current" ]]; then
        msg_warn "已在该分支"
    elif git checkout "$target" 2>&1; then
        msg_success "已切换到: $target"
    else
        msg_error "切换失败"
    fi
    press_any_key
}

git_branch_delete() {
    require_git_repo || return

    local current
    current=$(git branch --show-current 2>/dev/null || echo "")

    local branches=()
    while IFS= read -r b; do
        [[ -n "$b" && "$b" != "$current" ]] && branches+=("$b")
    done < <(_git_local_branches)

    if [[ ${#branches[@]} -eq 0 ]]; then
        msg_warn "没有可删除的分支（不能删除当前分支）"
        press_any_key
        return
    fi

    show_menu "删除分支" true "${branches[@]}"
    [[ $MENU_RESULT -eq 255 ]] && return

    local target="${branches[$MENU_RESULT]}"

    show_menu "删除方式" true \
        "-d (安全删除，已合并才允许)" \
        "-D (强制删除 ⚠️)"
    [[ $MENU_RESULT -eq 255 ]] && return

    local flag="-d"
    [[ $MENU_RESULT -eq 1 ]] && flag="-D"

    if git branch "$flag" "$target" 2>&1; then
        msg_success "已删除分支: $target"
    else
        msg_error "删除失败（分支可能未合并，使用 -D 强制删除）"
    fi
    press_any_key
}

git_branch_merge() {
    require_git_repo || return

    local current
    current=$(git branch --show-current 2>/dev/null || echo "")

    local branches=()
    while IFS= read -r b; do
        [[ -n "$b" && "$b" != "$current" ]] && branches+=("$b")
    done < <(_git_local_branches)

    if [[ ${#branches[@]} -eq 0 ]]; then
        msg_warn "没有可合并的分支"
        press_any_key
        return
    fi

    show_menu "合并到 $current ←" true "${branches[@]}"
    [[ $MENU_RESULT -eq 255 ]] && return

    local source="${branches[$MENU_RESULT]}"
    if git merge "$source" 2>&1; then
        msg_success "已将 $source 合并到 $current"
    else
        msg_error "合并失败（可能有冲突，请手动解决）"
    fi
    press_any_key
}

menu_git_branch() {
    while true; do
        show_menu "分支管理" true \
            "查看分支" \
            "创建分支" \
            "切换分支" \
            "删除分支" \
            "合并分支"

        case $MENU_RESULT in
            0) git_branch_list ;;
            1) git_branch_create ;;
            2) git_branch_switch ;;
            3) git_branch_delete ;;
            4) git_branch_merge ;;
            255) return ;;
        esac
    done
}

# ── 远程仓库 ─────────────────────────────────────────────────

git_remote_list() {
    require_git_repo || return

    echo ""
    msg_info "远程仓库"
    local output
    output=$(git remote -v 2>/dev/null || echo "")
    if [[ -z "$output" ]]; then
        printf "  ${C_DIM}(无)${C_RESET}\n"
    else
        echo "$output" | while IFS= read -r line; do
            printf "  ${C_CYAN}%s${C_RESET}\n" "$line"
        done
    fi
    press_any_key
}

git_remote_add() {
    require_git_repo || return

    echo ""
    local name
    name=$(prompt_input "远程名称" "origin")
    [[ -z "$name" ]] && return

    local url
    url=$(prompt_input "远程 URL" "")
    [[ -z "$url" ]] && return

    if git remote add "$name" "$url" 2>&1; then
        msg_success "已添加远程: $name → $url"
    else
        msg_error "添加失败（名称可能已存在）"
    fi
    press_any_key
}

git_remote_remove() {
    require_git_repo || return

    local remotes=()
    while IFS= read -r r; do
        [[ -n "$r" ]] && remotes+=("$r")
    done < <(git remote 2>/dev/null)

    if [[ ${#remotes[@]} -eq 0 ]]; then
        msg_warn "没有远程仓库"
        press_any_key
        return
    fi

    show_menu "移除远程" true "${remotes[@]}"
    [[ $MENU_RESULT -eq 255 ]] && return

    local target="${remotes[$MENU_RESULT]}"
    if git remote remove "$target" 2>&1; then
        msg_success "已移除: $target"
    else
        msg_error "移除失败"
    fi
    press_any_key
}

menu_git_remote() {
    while true; do
        show_menu "远程仓库" true \
            "查看远程" \
            "添加远程" \
            "移除远程"

        case $MENU_RESULT in
            0) git_remote_list ;;
            1) git_remote_add ;;
            2) git_remote_remove ;;
            255) return ;;
        esac
    done
}

# ── 常用操作菜单 ─────────────────────────────────────────────

menu_git_ops() {
    while true; do
        show_menu "Git 常用操作" true \
            "初始化仓库" \
            "拉取 (Pull)" \
            "推送 (Push)" \
            "暂存 (Stash)" \
            "重置 (Reset)" \
            "查看历史 (Log)"

        case $MENU_RESULT in
            0) git_init_repo ;;
            1) git_pull ;;
            2) git_push ;;
            3) git_stash ;;
            4) git_reset_commit ;;
            5) git_log_view ;;
            255) return ;;
        esac
    done
}
