#!/bin/bash

# Hysteria2 配置管理脚本
# 版本: 2.0.0
# 作者: Hysteria2 Manager

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# 错误处理函数
# 日志和错误处理函数由 common.sh 提供
# 此处仅保留 common.sh 不可用时的简易回退
if ! declare -f log_info >/dev/null 2>&1; then
    log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
    log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
    log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
    log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
fi
if ! declare -f error_exit >/dev/null 2>&1; then
    error_exit() { echo -e "${RED}错误: $1${NC}" >&2; exit "${2:-1}"; }
fi

safe_remove_dir() {
    local target="${1:-}"
    case "$target" in
        /etc/hysteria|/opt/s-hy2|/var/www/html/sub|/var/www)
            if [[ -d "$target" ]]; then
                rm -rf -- "$target"
            fi
            ;;
        *)
            log_error "拒绝删除非白名单目录: $target"
            return 1
            ;;
    esac
}

# 脚本目录处理 - 改进符号链接检测
get_script_dir() {
    local source="${BASH_SOURCE[0]}"
    local dir
    
    # 处理符号链接
    while [[ -L "$source" ]]; do
        dir="$(cd -P "$(dirname "$source")" && pwd)"
        source="$(readlink "$source")"
        [[ $source != /* ]] && source="$dir/$source"
    done
    
    dir="$(cd -P "$(dirname "$source")" && pwd)"
    
    # 如果脚本在 /usr/local/bin 中运行，假设安装在 /opt/s-hy2
    if [[ "$dir" == "/usr/local/bin" ]]; then
        dir="/opt/s-hy2"
    fi
    
    echo "$dir"
}

load_new_modules() {
    # 加载公共库
    if [[ -f "$SCRIPTS_DIR/common.sh" ]]; then
        source "$SCRIPTS_DIR/common.sh"
    fi

    # 加载出站规则管理模块
    if [[ -f "$SCRIPTS_DIR/outbound-manager.sh" ]]; then
        source "$SCRIPTS_DIR/outbound-manager.sh"
    else
        log_warn "出站规则管理模块未找到"
    fi

    # 加载防火墙管理模块
    if [[ -f "$SCRIPTS_DIR/firewall-manager.sh" ]]; then
        source "$SCRIPTS_DIR/firewall-manager.sh"
    else
        log_warn "防火墙管理模块未找到"
    fi

    # 加载部署后检查模块
    if [[ -f "$SCRIPTS_DIR/post-deploy-check.sh" ]]; then
        source "$SCRIPTS_DIR/post-deploy-check.sh"
    else
        log_warn "部署后检查模块未找到"
    fi

    # 加载拆分模块
    local modules_dir="$SCRIPT_DIR/modules"
    for module in install domain certificate port-hopping config-edit \
                  user-manager client-export backup bandwidth \
                  acl-manager log-manager auto-update speed-test dns-manager \
                  traffic-stats \
                  outbound-core outbound-add outbound-modify outbound-delete outbound-apply outbound-view; do
        if [[ -f "$modules_dir/$module.sh" ]]; then
            source "$modules_dir/$module.sh"
        else
            log_warn "模块 $module.sh 未找到"
        fi
    done
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "此脚本需要 root 权限运行，请使用 sudo 运行此脚本"
    fi
}

check_script_integrity() {
    local missing_scripts=()
    
    # 检查必需的脚本文件
    local required_scripts=(
        # "install.sh" (在根目录)
        "config.sh"
        "service.sh"
        "domain-test.sh"
        "node-info.sh"
    )
    
    for script in "${required_scripts[@]}"; do
        if [[ ! -f "$SCRIPTS_DIR/$script" ]]; then
            missing_scripts+=("$script")
        fi
    done
    
    if [[ ${#missing_scripts[@]} -gt 0 ]]; then
        log_warn "检测到缺失的脚本文件:"
        for script in "${missing_scripts[@]}"; do
            echo "  - $script"
        done
        echo ""
        echo "这可能影响某些功能的正常使用"
        echo ""
    fi
}

print_header() {
    clear
    echo -e "${CYAN}================================================${NC}"
    echo -e "${CYAN}           Hysteria2 配置管理脚本 v2.0.0${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo ""
}

print_menu() {
    echo -e "${YELLOW}请选择操作:${NC}"
    echo ""
    echo -e "${PURPLE}── 基础操作 ──${NC}"
    echo -e "${GREEN} 1.${NC} 安装 Hysteria2"
    echo -e "${GREEN} 2.${NC} 快速配置"
    echo -e "${GREEN} 3.${NC} 手动配置"
    echo -e "${GREEN} 4.${NC} 修改配置"
    echo -e "${GREEN} 5.${NC} 域名管理"
    echo -e "${GREEN} 6.${NC} 证书管理"
    echo -e "${GREEN} 7.${NC} 服务管理"
    echo -e "${GREEN} 8.${NC} 订阅链接 / 客户端导出"
    echo ""
    echo -e "${PURPLE}── 高级功能 ──${NC}"
    echo -e "${CYAN} 9.${NC} 出站规则"
    echo -e "${CYAN}10.${NC} 防火墙管理"
    echo -e "${CYAN}11.${NC} 多用户管理"
    echo -e "${CYAN}12.${NC} ACL 规则管理"
    echo -e "${CYAN}13.${NC} 带宽限制管理"
    echo -e "${CYAN}14.${NC} DNS 配置管理"
    echo ""
    echo -e "${PURPLE}── 运维工具 ──${NC}"
    echo -e "${BLUE}15.${NC} 配置备份与恢复"
    echo -e "${BLUE}16.${NC} 日志管理"
    echo -e "${BLUE}17.${NC} 速度测试"
    echo -e "${BLUE}18.${NC} 流量统计"
    echo -e "${BLUE}19.${NC} 检查更新"
    echo ""
    echo -e "${GREEN}20.${NC} 卸载服务"
    echo -e "${GREEN}21.${NC} 关于脚本"
    echo -e "${RED} 0.${NC} 退出"
    echo ""
    echo -n -e "${BLUE}请输入选项 [0-21]: ${NC}"
}

check_hysteria_installed() {
    command -v hysteria &> /dev/null
}

check_service_status() {
    if systemctl is-active --quiet "${HYSTERIA_SERVICE:-hysteria-server.service}"; then
        echo -e "${GREEN}✅ 运行中${NC}"
        return 0
    elif systemctl is-enabled --quiet "${HYSTERIA_SERVICE:-hysteria-server.service}"; then
        echo -e "${YELLOW}⏸️  已启用但未运行${NC}"
        return 1
    else
        echo -e "${RED}❌ 未启用${NC}"
        return 2
    fi
}

show_system_info() {
    local server_ip
    server_ip=$(get_server_ip)
    local server_domain
    server_domain=$(get_server_domain)
    
    echo -e "${CYAN}系统信息:${NC}"
    echo "服务器IP: ${server_ip:-未知}"
    if [[ -n "$server_domain" ]]; then
        echo "服务器域名: $server_domain"
    fi
    echo "系统: $(get_system_info)"
    echo ""
}

get_system_info() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "${PRETTY_NAME:-$NAME $VERSION_ID}"
    else
        echo "未知系统"
    fi
}

show_status() {
    show_system_info
    
    echo -e "${CYAN}Hysteria2 状态:${NC}"
    if check_hysteria_installed; then
        echo -e "程序状态: ${GREEN}✅ 已安装${NC}"
        echo -n "服务状态: "
        check_service_status
        if [[ -f "$CONFIG_PATH" ]]; then
            echo -e "配置文件: ${GREEN}✅ 存在${NC}"
        else
            echo -e "配置文件: ${RED}❌ 不存在${NC}"
        fi
    else
        echo -e "程序状态: ${RED}❌ 未安装${NC}"
    fi
    echo ""
}

safe_source_script() {
    local script_path="$1"
    local script_name="$2"
    
    if [[ -f "$script_path" ]]; then
        log_info "加载 $script_name..."
        # shellcheck source=/dev/null
        source "$script_path" || {
            log_error "$script_name 加载失败"
            return 1
        }
        return 0
    else
        log_error "$script_name 不存在: $script_path"
        echo ""
        echo "可能的解决方案:"
        echo "1. 重新运行安装脚本"
        echo "2. 检查脚本文件是否完整"
        echo ""
        return 1
    fi
}

quick_config() {
    log_info "准备执行一键快速配置..."
    
    if ! check_hysteria_installed; then
        log_error "Hysteria2 未安装，请先安装"
        wait_for_user
        return
    fi
    
    if safe_source_script "$SCRIPTS_DIR/config.sh" "配置脚本"; then
        quick_setup_hysteria
    fi
}

manual_config() {
    log_info "准备执行手动配置..."
    
    if ! check_hysteria_installed; then
        log_error "Hysteria2 未安装，请先安装"
        wait_for_user
        return
    fi
    
    if safe_source_script "$SCRIPTS_DIR/config.sh" "配置脚本"; then
        generate_hysteria_config
    fi
}

manage_service() {
    log_info "准备进入服务管理..."
    
    if ! check_hysteria_installed; then
        log_error "Hysteria2 未安装，请先安装"
        wait_for_user
        return
    fi
    
    if safe_source_script "$SCRIPTS_DIR/service.sh" "服务管理脚本"; then
        manage_hysteria_service
    fi
}

show_node_info() {
    log_info "准备显示订阅链接..."
    
    if ! check_hysteria_installed; then
        log_error "Hysteria2 未安装，请先安装"
        wait_for_user
        return
    fi
    
    if safe_source_script "$SCRIPTS_DIR/node-info.sh" "节点信息脚本"; then
        display_node_info
    fi
}

uninstall_hy2_and_config() {
    echo ""
    echo -e "${BLUE}卸载 Hysteria2 程序和配置文件${NC}"
    echo ""
    
    echo -e "${YELLOW}此操作将删除:${NC}"
    echo "• Hysteria2 程序文件"
    echo "• 系统服务"
    echo "• 配置文件和证书"
    echo "• 用户账户"
    echo "• 端口跳跃规则"
    echo ""
    echo -n -e "${YELLOW}确定要卸载吗? [y/N]: ${NC}"
    read -r confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}取消卸载${NC}"
        return
    fi
    
    log_info "开始卸载 Hysteria2..."
    
    # 1. 清理端口跳跃规则
    log_info "步骤 1/5: 清理端口跳跃规则..."
    cleanup_port_hopping
    
    # 2. 停止并禁用服务
    log_info "步骤 2/5: 停止并禁用服务..."
    if systemctl is-active --quiet hysteria-server.service; then
        systemctl stop hysteria-server.service
        log_info "已停止服务"
    fi
    if systemctl is-enabled --quiet hysteria-server.service 2>/dev/null; then
        systemctl disable hysteria-server.service 2>/dev/null
        log_info "已禁用服务"
    fi
    
    # 3. 卸载 Hysteria2 程序
    log_info "步骤 3/5: 卸载 Hysteria2 程序..."
    if check_hysteria_installed; then
        local tmp_uninstall
        tmp_uninstall=$(mktemp /tmp/s-hy2-uninstall.XXXXXX)
        chmod 600 "$tmp_uninstall"

        if curl -fsSL --proto "=https" --tlsv1.2 -o "$tmp_uninstall" "https://get.hy2.sh/" && bash -n "$tmp_uninstall"; then
            if bash "$tmp_uninstall" --remove 2>/dev/null; then
                log_info "Hysteria2 程序卸载成功"
            else
                log_warn "程序卸载失败，继续清理"
            fi
        else
            log_warn "卸载脚本下载或语法检查失败，跳过程序卸载"
        fi
        rm -f "$tmp_uninstall"
    else
        log_info "Hysteria2 未安装，跳过程序卸载"
    fi
    
    # 4. 删除配置文件和证书
    log_info "步骤 4/5: 删除配置文件和证书..."
    if safe_remove_dir "/etc/hysteria"; then
        log_info "已删除 /etc/hysteria 目录"
    fi
    
    # 5. 清理用户账户和系统残留
    log_info "步骤 5/5: 清理用户账户和系统残留..."
    if id "hysteria" &>/dev/null; then
        userdel -r hysteria 2>/dev/null && log_info "已删除 hysteria 用户"
    fi
    
    # 清理 systemd 残留文件
    rm -f /etc/systemd/system/multi-user.target.wants/hysteria-server.service 2>/dev/null
    rm -f /etc/systemd/system/multi-user.target.wants/hysteria-server@*.service 2>/dev/null
    systemctl daemon-reload
    
    echo ""
    log_success "Hysteria2 程序和配置文件卸载完成!"
}

about_script() {
    clear
    echo -e "${CYAN}=== 关于 Hysteria2 配置管理脚本 ===${NC}"
    echo ""
    echo -e "${YELLOW}基本信息:${NC}"
    echo "脚本名称: S-Hy2 Manager"
    echo "版本: 2.0.0"
    echo "功能: Hysteria2 代理服务器部署和管理工具"
    echo ""
    echo -e "${YELLOW}主要功能:${NC}"
    echo "✓ 一键安装/卸载 Hysteria2"
    echo "✓ 智能配置生成 (ACME/自签名证书)"
    echo "✓ 配置管理 (密码、端口、混淆等)"
    echo "✓ 域名管理 (ACME域名和伪装域名)"
    echo "✓ 证书管理 (生成、上传、查看)"
    echo "✓ 端口跳跃配置"
    echo "✓ 出站规则管理 (Direct、SOCKS5、HTTP)"
    echo "✓ 防火墙管理 (自动检测配置)"
    echo "✓ 服务管理和监控"
    echo "✓ 订阅链接和节点信息生成"
    echo ""
    echo -e "${YELLOW}系统兼容性:${NC}"
    echo "• Ubuntu 18.04+ / Debian 9+"
    echo "• CentOS 7+ / RHEL 7+ / Fedora"
    echo "• 支持 systemd 的 Linux 发行版"
    echo ""
    echo -e "${YELLOW}脚本信息:${NC}"
    echo "安装位置: $SCRIPT_DIR"
    echo "配置目录: /etc/hysteria/"
    echo "日志查看: journalctl -u hysteria-server"
    echo ""
    echo -e "${YELLOW}获取支持:${NC}"
    echo "• GitHub: https://github.com/sindricn/s-hy2"
    echo "• Issues: 在 GitHub 仓库提交问题"
    echo ""
    wait_for_user
}

validate_input() {
    local input="$1"
    local min="$2"
    local max="$3"
    
    if [[ "$input" =~ ^[0-9]+$ ]] && [[ "$input" -ge "$min" ]] && [[ "$input" -le "$max" ]]; then
        return 0
    else
        return 1
    fi
}

main() {
    # 检查基本要求
    check_root
    check_script_integrity
    
    # 设置错误处理
    trap 'echo -e "\n${RED}脚本被中断${NC}"; exit 130' INT
    trap 'echo -e "\n${RED}脚本执行错误${NC}"; exit 1' ERR
    
    while true; do
        print_header
        show_status
        print_menu
        
        read -r choice
        
        # 输入验证
        if ! validate_input "$choice" 0 21; then
            log_error "请输入 0-21 之间的数字"
            sleep 2
            continue
        fi
        
        case $choice in
            # 基础操作
            1) install_hysteria ;;
            2) quick_config ;;
            3) manual_config ;;
            4) config_management ;;
            5) domain_management ;;
            6) certificate_management ;;
            7) manage_service ;;
            8) client_export ;;
            # 高级功能
            9) manage_outbound ;;
            10) manage_firewall ;;
            11) user_management ;;
            12) acl_management ;;
            13) bandwidth_management ;;
            14) dns_management ;;
            # 运维工具
            15) backup_management ;;
            16) log_management ;;
            17) speed_test ;;
            18) traffic_stats ;;
            19) check_for_updates ;;
            # 其他
            20) uninstall_hysteria ;;
            21) about_script ;;
            0)
                echo -e "${GREEN}感谢使用 Hysteria2 配置管理脚本!${NC}"
                exit 0
                ;;
        esac
    done
}

init_script() {
    # 设置严格模式（但允许某些命令失败）
    set -o pipefail

    # 检查依赖
    check_dependencies

    # 检查脚本目录权限
    if [[ ! -r "$SCRIPT_DIR" ]]; then
        error_exit "无法访问脚本目录: $SCRIPT_DIR"
    fi

    # 加载新功能模块
    load_new_modules
}

# ========== CLI 参数处理 ==========
show_cli_help() {
    cat << 'HELP'
S-Hy2 v2.0.0 — Hysteria2 管理脚本

用法: hy2-manager.sh [选项]

交互模式（默认）:
  hy2-manager.sh

非交互模式:
  hy2-manager.sh --install          安装 Hysteria2
  hy2-manager.sh --uninstall        卸载 Hysteria2
  hy2-manager.sh --status           查看服务状态
  hy2-manager.sh --restart          重启服务
  hy2-manager.sh --stop             停止服务
  hy2-manager.sh --start            启动服务
  hy2-manager.sh --backup           创建配置备份
  hy2-manager.sh --restore          恢复最新备份
  hy2-manager.sh --list-users       列出所有用户
  hy2-manager.sh --add-user USER    添加用户
  hy2-manager.sh --del-user USER    删除用户
  hy2-manager.sh --export           导出客户端配置
  hy2-manager.sh --export-uri       导出 URI 链接
  hy2-manager.sh --export-sub       导出订阅链接
  hy2-manager.sh --speed-test       运行速度测试
  hy2-manager.sh --update           检查更新
  hy2-manager.sh --auto-backup      自动备份（cron 用）
  hy2-manager.sh --validate         验证配置文件

其他:
  -h, --help        显示此帮助
  -v, --version     显示版本号
HELP
}

handle_cli_args() {
    case "${1:-}" in
        --install)       install_hysteria ;;
        --uninstall)     uninstall_hysteria ;;
        --status)        check_service_status ;;
        --restart)       systemctl restart "$HYSTERIA_SERVICE" && log_success "服务已重启" ;;
        --stop)          systemctl stop "$HYSTERIA_SERVICE" && log_success "服务已停止" ;;
        --start)         systemctl start "$HYSTERIA_SERVICE" && log_success "服务已启动" ;;
        --backup)        create_backup ;;
        --restore)       restore_backup ;;
        --list-users)    list_users ;;
        --add-user)      shift; add_user_cli "$@" ;;
        --del-user)      shift; delete_user_cli "$@" ;;
        --export)        generate_client_yaml ;;
        --export-uri)    generate_client_uri ;;
        --export-sub)    generate_subscription_link ;;
        --speed-test)    speed_test ;;
        --update)        check_for_updates ;;
        --auto-backup)   auto_backup ;;
        --validate)      validate_config ;;
        -h|--help)       show_cli_help ;;
        -v|--version)    echo "s-hy2 v2.0.0" ;;
        "")              return 1 ;;  # 无参数，进入交互模式
        *)               log_error "未知选项: $1"; show_cli_help; exit 1 ;;
    esac
    exit $?
}

# CLI 快捷添加用户（非交互）
add_user_cli() {
    local username="${1:-}"
    local password
    if [[ -z "$username" ]]; then
        log_error "用法: --add-user USERNAME"
        exit 1
    fi
    if [[ -n "${2:-}" ]]; then
        log_error "为避免密码进入 shell 历史，--add-user 不再接受密码参数"
        log_error "请使用自动生成的密码，或进入交互式用户管理修改密码"
        exit 1
    fi

    password=$(generate_password 16)
    echo -e "${GREEN}自动生成密码: $password${NC}"
    add_user_to_config "$username" "$password" && \
        log_success "用户 '$username' 已添加" && \
        echo -e "重启服务以生效: ${CYAN}hy2-manager.sh --restart${NC}"
}

# CLI 快捷删除用户（非交互）
delete_user_cli() {
    local username="${1:-}"
    if [[ -z "$username" ]]; then
        log_error "用法: --del-user USERNAME"
        exit 1
    fi
    remove_user_from_config "$username" && \
        log_success "用户 '$username' 已删除" && \
        echo -e "重启服务以生效: ${CYAN}hy2-manager.sh --restart${NC}"
}

# ========== 配置验证 ==========
validate_config() {
    echo -e "${CYAN}=== 配置文件验证 ===${NC}"
    echo ""

    if [[ ! -f "$HYSTERIA_CONFIG" ]]; then
        log_error "配置文件不存在: $HYSTERIA_CONFIG"
        return 1
    fi

    # 使用 hysteria 内置检查
    if command -v hysteria &>/dev/null; then
        echo -e "${YELLOW}使用 hysteria check 验证...${NC}"
        hysteria check "$HYSTERIA_CONFIG" 2>&1
        if [[ $? -eq 0 ]]; then
            log_success "hysteria check: 配置有效"
        else
            log_error "hysteria check: 配置有误"
        fi
    else
        echo -e "${YELLOW}hysteria 命令不可用，使用基础检查...${NC}"
    fi

    # 基础检查
    local errors=0

    # 检查 listen 字段
    if ! grep -q "listen:" "$HYSTERIA_CONFIG"; then
        log_error "缺少 listen 字段"
        ((errors++))
    fi

    # 检查 auth 字段
    if ! grep -q "type:" "$HYSTERIA_CONFIG" 2>/dev/null; then
        log_error "缺少 auth.type 字段"
        ((errors++))
    fi

    # 检查 TLS 配置
    if ! grep -q "acme:" "$HYSTERIA_CONFIG" && ! grep -q "cert:" "$HYSTERIA_CONFIG" && ! grep -q "tls:" "$HYSTERIA_CONFIG"; then
        log_warn "未找到 TLS/ACME 证书配置"
        ((errors++))
    fi

    # 检查 YAML 语法（基本）
    if command -v python3 &>/dev/null; then
        if ! python3 -c "import yaml; yaml.safe_load(open('$HYSTERIA_CONFIG'))" 2>/dev/null; then
            log_error "YAML 语法错误"
            ((errors++))
        else
            log_success "YAML 语法正确"
        fi
    fi

    if [[ $errors -eq 0 ]]; then
        log_success "配置验证通过 ✓"
    else
        log_error "配置验证发现 $errors 个问题"
        return 1
    fi
}

# ========== 入口 ==========
# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"

# 初始化
init_script

# 处理 CLI 参数或进入交互模式
handle_cli_args "$@" || main
