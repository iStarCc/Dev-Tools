#!/usr/bin/env bash
# EasyTier 工具集 - 安装 / 服务管理 / 网络配置

ET_VERSION="2.6.4"
ET_INSTALL_DIR="/usr/local/bin"
ET_CONFIG_PATH="/etc/easytier/easytier.toml"
ET_PLIST_PATH="/Library/LaunchDaemons/easytier.plist"
ET_SYSTEMD_PATH="/etc/systemd/system/easytier.service"

# ── 通用辅助 ─────────────────────────────────────────────────

_run_root() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

_et_detect_platform() {
    local os arch
    case "$(uname -s)" in
        Darwin) os="macos" ;;
        Linux)  os="linux" ;;
        *)      msg_error "不支持的系统: $(uname -s)"; return 1 ;;
    esac
    case "$(uname -m)" in
        arm64|aarch64) arch="aarch64" ;;
        x86_64)        arch="x86_64" ;;
        *)             msg_error "不支持的架构: $(uname -m)"; return 1 ;;
    esac
    echo "${os}-${arch}"
}

_et_is_installed() {
    command -v easytier-core &>/dev/null
}

# ── 安装 / 更新 ──────────────────────────────────────────────

et_install() {
    local platform
    platform=$(_et_detect_platform) || { press_any_key; return; }

    echo ""
    if _et_is_installed; then
        local current
        current=$(easytier-core --version 2>/dev/null || echo "未知")
        msg_info "当前版本: $current"
    fi

    local version
    version=$(prompt_input "安装版本" "$ET_VERSION")
    [[ -z "$version" ]] && return

    local filename="easytier-${platform}-v${version}.zip"
    local url="https://github.com/EasyTier/EasyTier/releases/download/v${version}/${filename}"
    local tmpdir
    tmpdir=$(mktemp -d)

    msg_info "下载 EasyTier v${version} (${platform})..."
    if ! curl -fL -o "${tmpdir}/${filename}" "$url"; then
        rm -rf "$tmpdir"
        msg_error "下载失败，请检查版本号和网络"
        press_any_key
        return
    fi

    msg_info "解压并安装到 ${ET_INSTALL_DIR}/..."
    unzip -o "${tmpdir}/${filename}" -d "${tmpdir}" > /dev/null

    local src="${tmpdir}/easytier-${platform}"
    if [[ ! -d "$src" ]]; then
        rm -rf "$tmpdir"
        msg_error "解压目录不存在: easytier-${platform}"
        press_any_key
        return
    fi

    _run_root mkdir -p "${ET_INSTALL_DIR}"
    _run_root cp -f "${src}/easytier-core" "${src}/easytier-cli" "${ET_INSTALL_DIR}/"
    _run_root chmod 755 "${ET_INSTALL_DIR}/easytier-core" "${ET_INSTALL_DIR}/easytier-cli"

    if is_macos; then
        _run_root xattr -cr "${ET_INSTALL_DIR}/easytier-core" "${ET_INSTALL_DIR}/easytier-cli" 2>/dev/null || true
    fi

    rm -rf "$tmpdir"
    msg_success "安装完成: $(${ET_INSTALL_DIR}/easytier-core --version 2>/dev/null || echo v${version})"
    press_any_key
}

# ── 配置管理 ─────────────────────────────────────────────────

et_config_view() {
    echo ""
    if [[ -f "$ET_CONFIG_PATH" ]]; then
        msg_info "配置文件: $ET_CONFIG_PATH"
        printf "  ${C_DIM}──────────────────────────────────────────${C_RESET}\n"
        cat "$ET_CONFIG_PATH"
        printf "  ${C_DIM}──────────────────────────────────────────${C_RESET}\n"
    else
        msg_warn "配置文件不存在: $ET_CONFIG_PATH"
    fi
    press_any_key
}

et_config_edit() {
    if [[ ! -f "$ET_CONFIG_PATH" ]]; then
        msg_warn "配置文件不存在，请先安装配置"
        press_any_key
        return
    fi
    local editor="${EDITOR:-nano}"
    _run_root "$editor" "$ET_CONFIG_PATH"
}

et_config_install() {
    echo ""
    local src
    src=$(prompt_input "配置文件路径" "")
    [[ -z "$src" ]] && return

    if [[ ! -f "$src" ]]; then
        msg_error "文件不存在: $src"
        press_any_key
        return
    fi

    _run_root mkdir -p "$(dirname "$ET_CONFIG_PATH")"
    _run_root cp -f "$src" "$ET_CONFIG_PATH"
    _run_root chmod 644 "$ET_CONFIG_PATH"
    msg_success "配置已安装: $ET_CONFIG_PATH"
    press_any_key
}

et_config_generate() {
    echo ""
    msg_info "交互式生成 EasyTier 配置"
    echo ""

    local name ip net_name net_secret peer proxy

    name=$(prompt_input "节点名称" "$(hostname)")
    [[ -z "$name" ]] && return

    ip=$(prompt_input "虚拟 IP (如 10.10.10.2)" "")
    [[ -z "$ip" ]] && return

    net_name=$(prompt_input "网络名称" "")
    [[ -z "$net_name" ]] && return

    net_secret=$(prompt_input "网络密钥" "")
    [[ -z "$net_secret" ]] && return

    peer=$(prompt_input "对端地址 (如 tcp://1.2.3.4:11010)" "")

    proxy=$(prompt_input "代理网段 (如 192.168.1.0/24，留空跳过)" "")

    local config="instance_name = \"${name}\"
ipv4 = \"${ip}\"
dhcp = false
listeners = [
    \"tcp://0.0.0.0:11010\",
    \"udp://0.0.0.0:11010\",
    \"wg://0.0.0.0:11011\",
    \"ws://0.0.0.0:11011/\",
    \"wss://0.0.0.0:11012/\",
]

[network_identity]
network_name = \"${net_name}\"
network_secret = \"${net_secret}\""

    if [[ -n "$proxy" ]]; then
        config+="

[[proxy_network]]
cidr = \"${proxy}\""
    fi

    if [[ -n "$peer" ]]; then
        config+="

[[peer]]
uri = \"${peer}\""
    fi

    config+="

[flags]
enable_encryption = true
enable_ipv6 = true
mtu = 1380"

    echo ""
    msg_info "生成的配置:"
    printf "  ${C_DIM}──────────────────────────────────────────${C_RESET}\n"
    echo "$config"
    printf "  ${C_DIM}──────────────────────────────────────────${C_RESET}\n"

    show_menu "安装到 $ET_CONFIG_PATH ?" true "确认安装" "仅显示不安装"
    if [[ $MENU_RESULT -eq 0 ]]; then
        _run_root mkdir -p "$(dirname "$ET_CONFIG_PATH")"
        echo "$config" | _run_root tee "$ET_CONFIG_PATH" > /dev/null
        _run_root chmod 644 "$ET_CONFIG_PATH"
        msg_success "配置已写入 $ET_CONFIG_PATH"
    fi
    press_any_key
}

menu_et_config() {
    while true; do
        show_menu "EasyTier 配置" true \
            "查看配置" \
            "编辑配置" \
            "从文件安装配置" \
            "交互式生成配置"

        case $MENU_RESULT in
            0) et_config_view ;;
            1) et_config_edit ;;
            2) et_config_install ;;
            3) et_config_generate ;;
            255) return ;;
        esac
    done
}

# ── 服务管理 ─────────────────────────────────────────────────

_et_create_service_macos() {
    _run_root tee "$ET_PLIST_PATH" > /dev/null << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>easytier</string>
    <key>ProgramArguments</key>
    <array>
        <string>${ET_INSTALL_DIR}/easytier-core</string>
        <string>-c</string>
        <string>${ET_CONFIG_PATH}</string>
    </array>
    <key>WorkingDirectory</key><string>/var/log/easytier</string>
    <key>UserName</key><string>root</string>
    <key>GroupName</key><string>wheel</string>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>/var/log/easytier.log</string>
    <key>StandardErrorPath</key><string>/var/log/easytier.err</string>
</dict>
</plist>
EOF
    _run_root mkdir -p /var/log/easytier
}

_et_create_service_linux() {
    _run_root tee "$ET_SYSTEMD_PATH" > /dev/null << EOF
[Unit]
Description=EasyTier VPN Service
After=network.target

[Service]
Type=simple
ExecStart=${ET_INSTALL_DIR}/easytier-core -c ${ET_CONFIG_PATH}
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
}

et_service_status() {
    echo ""
    if is_macos; then
        if _run_root launchctl list 2>/dev/null | grep -q "easytier"; then
            msg_success "服务运行中"
            _run_root launchctl list 2>/dev/null | grep "easytier"
        else
            msg_warn "服务未运行"
        fi
    else
        _run_root systemctl status easytier 2>/dev/null || msg_warn "服务未安装或未运行"
    fi
    press_any_key
}

et_service_start() {
    echo ""
    if [[ ! -f "$ET_CONFIG_PATH" ]]; then
        msg_error "配置文件不存在，请先安装配置"
        press_any_key
        return
    fi

    if is_macos; then
        [[ ! -f "$ET_PLIST_PATH" ]] && _et_create_service_macos
        _run_root launchctl stop easytier 2>/dev/null || true
        _run_root launchctl unload -w "$ET_PLIST_PATH" 2>/dev/null || true
        _run_root launchctl load -w "$ET_PLIST_PATH"
        _run_root launchctl start easytier
        sleep 2
        if _run_root launchctl list 2>/dev/null | grep -q "easytier"; then
            msg_success "服务已启动"
        else
            msg_error "启动失败，查看: /var/log/easytier.err"
        fi
    else
        [[ ! -f "$ET_SYSTEMD_PATH" ]] && _et_create_service_linux
        _run_root systemctl daemon-reload
        _run_root systemctl start easytier
        sleep 2
        if _run_root systemctl is-active --quiet easytier; then
            msg_success "服务已启动"
        else
            msg_error "启动失败，查看: journalctl -u easytier -f"
        fi
    fi
    press_any_key
}

et_service_stop() {
    echo ""
    if is_macos; then
        _run_root launchctl stop easytier 2>/dev/null || true
        _run_root launchctl unload -w "$ET_PLIST_PATH" 2>/dev/null || true
    else
        _run_root systemctl stop easytier 2>/dev/null || true
    fi
    msg_success "服务已停止"
    press_any_key
}

et_service_restart() {
    echo ""
    if is_macos; then
        _run_root launchctl stop easytier 2>/dev/null || true
        sleep 1
        _run_root launchctl start easytier 2>/dev/null || true
    else
        _run_root systemctl restart easytier 2>/dev/null || true
    fi
    sleep 2
    msg_success "服务已重启"
    press_any_key
}

et_service_enable() {
    echo ""
    if is_macos; then
        [[ ! -f "$ET_PLIST_PATH" ]] && _et_create_service_macos
        _run_root launchctl load -w "$ET_PLIST_PATH" 2>/dev/null || true
        msg_success "已设置开机自启 (launchd)"
    else
        [[ ! -f "$ET_SYSTEMD_PATH" ]] && _et_create_service_linux
        _run_root systemctl daemon-reload
        _run_root systemctl enable easytier 2>/dev/null || true
        msg_success "已设置开机自启 (systemd)"
    fi
    press_any_key
}

et_service_logs() {
    echo ""
    msg_info "最近日志 (最后 30 行)"
    printf "  ${C_DIM}──────────────────────────────────────────${C_RESET}\n"
    if is_macos; then
        _run_root tail -30 /var/log/easytier.log 2>/dev/null || msg_warn "无日志"
    else
        _run_root journalctl -u easytier --no-pager -n 30 2>/dev/null || msg_warn "无日志"
    fi
    printf "  ${C_DIM}──────────────────────────────────────────${C_RESET}\n"
    press_any_key
}

menu_et_service() {
    while true; do
        show_menu "EasyTier 服务管理" true \
            "查看状态" \
            "启动服务" \
            "停止服务" \
            "重启服务" \
            "开机自启" \
            "查看日志"

        case $MENU_RESULT in
            0) et_service_status ;;
            1) et_service_start ;;
            2) et_service_stop ;;
            3) et_service_restart ;;
            4) et_service_enable ;;
            5) et_service_logs ;;
            255) return ;;
        esac
    done
}

# ── 网络设置 (IP 转发 + iptables) ────────────────────────────

et_enable_ip_forward() {
    echo ""
    if is_macos; then
        _run_root sysctl -w net.inet.ip.forwarding=1 > /dev/null
        local sysctl_conf="/etc/sysctl.conf"
        if ! grep -q "net.inet.ip.forwarding=1" "$sysctl_conf" 2>/dev/null; then
            echo "net.inet.ip.forwarding=1" | _run_root tee -a "$sysctl_conf" > /dev/null
        fi

        # 创建开机自启 plist
        local fw_plist="/Library/LaunchDaemons/net.inet.ip.forwarding.plist"
        _run_root tee "$fw_plist" > /dev/null << 'FWEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>net.inet.ip.forwarding</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/sbin/sysctl</string>
        <string>-w</string>
        <string>net.inet.ip.forwarding=1</string>
    </array>
    <key>RunAtLoad</key><true/>
</dict>
</plist>
FWEOF
        _run_root launchctl load -w "$fw_plist" 2>/dev/null || true
        msg_success "macOS IP 转发已启用（已设置开机自启）"
    else
        _run_root sysctl -w net.ipv4.ip_forward=1 > /dev/null
        echo "net.ipv4.ip_forward=1" | _run_root tee /etc/sysctl.d/99-easytier.conf > /dev/null
        _run_root sysctl --system > /dev/null 2>&1
        msg_success "Linux IP 转发已启用（已持久化）"
    fi
    press_any_key
}

# 获取默认出口网卡
_detect_default_iface() {
    if is_macos; then
        route -n get default 2>/dev/null | awk '/interface:/{print $2}'
    else
        ip route show default 2>/dev/null | awk '{print $5; exit}'
    fi
}

et_iptables_setup() {
    if is_macos; then
        msg_warn "iptables 仅适用于 Linux，macOS 请使用 pfctl"
        press_any_key
        return
    fi

    if ! command -v iptables &>/dev/null; then
        msg_error "iptables 未安装"
        press_any_key
        return
    fi

    local default_iface
    default_iface=$(_detect_default_iface)

    echo ""
    msg_info "配置 iptables 转发规则（使对端可访问本机局域网）"
    echo ""

    local vpn_subnet lan_subnet iface

    vpn_subnet=$(prompt_input "EasyTier VPN 网段" "10.10.10.0/24")
    [[ -z "$vpn_subnet" ]] && return

    lan_subnet=$(prompt_input "本机局域网网段" "")
    [[ -z "$lan_subnet" ]] && return

    iface=$(prompt_input "出口网卡" "$default_iface")
    [[ -z "$iface" ]] && return

    echo ""
    msg_info "将添加以下规则:"
    printf "  ${C_CYAN}iptables -t nat -A POSTROUTING -s %s -d %s -j MASQUERADE${C_RESET}\n" "$vpn_subnet" "$lan_subnet"
    printf "  ${C_CYAN}iptables -A FORWARD -s %s -d %s -j ACCEPT${C_RESET}\n" "$vpn_subnet" "$lan_subnet"
    printf "  ${C_CYAN}iptables -A FORWARD -s %s -d %s -m state --state RELATED,ESTABLISHED -j ACCEPT${C_RESET}\n" "$lan_subnet" "$vpn_subnet"
    echo ""

    show_menu "确认应用?" true "应用规则" "应用并持久化" "取消"
    [[ $MENU_RESULT -eq 255 || $MENU_RESULT -eq 2 ]] && return

    _run_root iptables -t nat -A POSTROUTING -s "$vpn_subnet" -d "$lan_subnet" -j MASQUERADE
    _run_root iptables -A FORWARD -s "$vpn_subnet" -d "$lan_subnet" -j ACCEPT
    _run_root iptables -A FORWARD -s "$lan_subnet" -d "$vpn_subnet" -m state --state RELATED,ESTABLISHED -j ACCEPT
    msg_success "iptables 规则已应用"

    if [[ $MENU_RESULT -eq 1 ]]; then
        if command -v netfilter-persistent &>/dev/null; then
            _run_root netfilter-persistent save 2>/dev/null
            msg_success "规则已持久化 (netfilter-persistent)"
        elif command -v iptables-save &>/dev/null; then
            _run_root sh -c 'iptables-save > /etc/iptables/rules.v4' 2>/dev/null || \
            _run_root sh -c 'iptables-save > /etc/iptables.rules' 2>/dev/null
            msg_success "规则已保存"
        else
            msg_warn "未找到持久化工具，建议安装 iptables-persistent"
        fi
    fi
    press_any_key
}

et_iptables_show() {
    echo ""
    if is_macos; then
        msg_info "macOS pfctl 规则"
        _run_root pfctl -sr 2>/dev/null || msg_warn "无规则或无权限"
    else
        msg_info "iptables FILTER 规则"
        _run_root iptables -L -n -v 2>/dev/null || msg_warn "无权限"
        echo ""
        msg_info "iptables NAT 规则"
        _run_root iptables -t nat -L -n -v 2>/dev/null || msg_warn "无权限"
    fi
    press_any_key
}

et_iptables_clear() {
    if is_macos; then
        msg_warn "macOS 请手动管理 pfctl 规则"
        press_any_key
        return
    fi

    echo ""
    printf "  ${C_RED}⚠ 将清除所有 iptables FORWARD 和 NAT 规则！${C_RESET}\n"
    printf "  ${C_YELLOW}输入 yes 确认: ${C_RESET}"
    local confirm
    read -r confirm
    if [[ "$confirm" == "yes" ]]; then
        _run_root iptables -F FORWARD 2>/dev/null || true
        _run_root iptables -t nat -F POSTROUTING 2>/dev/null || true
        msg_success "已清除 FORWARD 和 NAT 规则"
    else
        msg_warn "已取消"
    fi
    press_any_key
}

menu_et_network() {
    while true; do
        show_menu "网络设置" true \
            "启用 IP 转发" \
            "配置 iptables 转发规则" \
            "查看防火墙规则" \
            "清除转发规则"

        case $MENU_RESULT in
            0) et_enable_ip_forward ;;
            1) et_iptables_setup ;;
            2) et_iptables_show ;;
            3) et_iptables_clear ;;
            255) return ;;
        esac
    done
}

# ── 节点信息 ─────────────────────────────────────────────────

et_node_info() {
    if ! _et_is_installed; then
        msg_error "EasyTier 未安装"
        press_any_key
        return
    fi

    show_menu "节点信息" true \
        "查看节点 (node)" \
        "查看对端 (peer)" \
        "查看路由 (route)" \
        "Ping 测试"
    [[ $MENU_RESULT -eq 255 ]] && return

    echo ""
    case $MENU_RESULT in
        0) _run_root easytier-cli node 2>&1 || msg_error "查询失败" ;;
        1) _run_root easytier-cli peer 2>&1 || msg_error "查询失败" ;;
        2) _run_root easytier-cli route 2>&1 || msg_error "查询失败" ;;
        3)
            local target
            target=$(prompt_input "目标 IP" "10.10.10.1")
            [[ -z "$target" ]] && { press_any_key; return; }
            ping -c 4 "$target" 2>&1
            ;;
    esac
    press_any_key
}

# ── EasyTier 主菜单 ──────────────────────────────────────────

menu_easytier() {
    while true; do
        local status=""
        if _et_is_installed; then
            status=" [已安装]"
        else
            status=" [未安装]"
        fi

        show_menu "EasyTier${status}" true \
            "安装/更新" \
            "配置管理" \
            "服务管理" \
            "网络设置 (IP转发/iptables)" \
            "节点信息"

        case $MENU_RESULT in
            0) et_install ;;
            1) menu_et_config ;;
            2) menu_et_service ;;
            3) menu_et_network ;;
            4) et_node_info ;;
            255) return ;;
        esac
    done
}
