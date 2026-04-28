#!/bin/bash
# Hysteria2 安装与卸载管理
#
# 依赖: common.sh
# 导出函数: install_hysteria, uninstall_hysteria, uninstall_all_dependencies, uninstall_everything, check_dependencies

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

install_hysteria() {
    log_info "准备安装 Hysteria2..."
    
    if safe_source_script "$SCRIPT_DIR/install.sh" "安装脚本"; then
        install_hysteria2
    fi
    wait_for_user
}

uninstall_hysteria() {
    clear
    echo -e "${CYAN}=== Hysteria2 卸载向导 ===${NC}"
    echo ""
    
    echo -e "${YELLOW}卸载选项:${NC}"
    echo -e "${GREEN}1.${NC} 卸载hy2及其相关配置文件"
    echo -e "${GREEN}2.${NC} 卸载删除所有脚本相关的程序和依赖和插件，但是保留脚本"
    echo -e "${GREEN}3.${NC} 完全卸载，删除所有程序，依赖插件和配置文件，包括脚本"
    echo -e "${RED}0.${NC} 取消"
    echo ""
    echo -e "${CYAN}说明:${NC}"
    echo "选项1: 卸载 Hysteria2 程序和配置文件"
    echo "选项2: 卸载所有相关依赖(包括订阅链接依赖)，保留管理脚本"
    echo "选项3: 完全清理所有内容，包括管理脚本本身"
    echo ""
    echo -n -e "${BLUE}请选择卸载方式 [0-3]: ${NC}"
    read -r uninstall_choice
    
    case $uninstall_choice in
        1) uninstall_hy2_and_config ;;
        2) uninstall_all_dependencies ;;
        3) uninstall_everything ;;
        0) 
            echo -e "${BLUE}取消卸载${NC}"
            ;;
        *)
            log_error "无效选择"
            ;;
    esac
    wait_for_user
}

uninstall_all_dependencies() {
    echo ""
    echo -e "${BLUE}卸载所有依赖和插件 (保留管理脚本)${NC}"
    echo ""
    
    echo -e "${YELLOW}此操作将删除:${NC}"
    echo "• Hysteria2 程序和配置"
    echo "• nginx (订阅链接依赖)"
    echo "• 订阅文件 (/var/www/html/sub/)"
    echo "• 端口跳跃规则"
    echo "• 系统用户账户"
    echo ""
    echo -e "${GREEN}保留内容:${NC}"
    echo "• 管理脚本 (s-hy2)"
    echo ""
    echo -n -e "${YELLOW}确定要卸载所有依赖吗? [y/N]: ${NC}"
    read -r confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}取消卸载${NC}"
        return
    fi
    
    log_info "开始卸载所有依赖..."
    
    # 1. 先执行基本的 hy2 卸载
    log_info "步骤 1/4: 卸载 Hysteria2..."
    # 清理端口跳跃规则
    cleanup_port_hopping
    
    # 停止并禁用服务
    if systemctl is-active --quiet hysteria-server.service; then
        systemctl stop hysteria-server.service
    fi
    if systemctl is-enabled --quiet hysteria-server.service 2>/dev/null; then
        systemctl disable hysteria-server.service 2>/dev/null
    fi
    
    # 卸载程序
    if check_hysteria_installed; then
        local tmp_rm
        tmp_rm=$(mktemp /tmp/s-hy2-remove.XXXXXX)
        chmod 600 "$tmp_rm"
        if curl -fsSL --proto "=https" --tlsv1.2 -o "$tmp_rm" "https://get.hy2.sh/" && bash -n "$tmp_rm"; then
            bash "$tmp_rm" --remove 2>/dev/null || log_warn "程序卸载失败"
        else
            log_warn "卸载脚本下载或语法检查失败，跳过自动卸载"
        fi
        rm -f "$tmp_rm"
    fi
    
    # 删除配置
    safe_remove_dir "/etc/hysteria" 2>/dev/null
    
    # 删除用户
    if id "hysteria" &>/dev/null; then
        userdel -r hysteria 2>/dev/null
    fi
    
    # 2. 卸载 nginx (订阅链接依赖)
    log_info "步骤 2/4: 卸载 nginx..."
    if command -v nginx &>/dev/null; then
        systemctl stop nginx 2>/dev/null
        systemctl disable nginx 2>/dev/null
        
        if command -v apt &>/dev/null; then
            apt remove -y nginx nginx-common nginx-core 2>/dev/null
            apt autoremove -y 2>/dev/null
        elif command -v yum &>/dev/null; then
            yum remove -y nginx 2>/dev/null
        elif command -v dnf &>/dev/null; then
            dnf remove -y nginx 2>/dev/null
        fi
        log_info "已卸载 nginx"
    else
        log_info "nginx 未安装，跳过"
    fi
    
    # 3. 删除订阅文件
    log_info "步骤 3/4: 删除订阅文件..."
    if safe_remove_dir "/var/www/html/sub"; then
        log_info "已删除订阅文件目录"
    fi
    
    # 清理可能的web根目录 (如果为空)
    if [[ -d "/var/www/html" && -z "$(ls -A /var/www/html 2>/dev/null)" ]]; then
        rmdir /var/www/html 2>/dev/null
    fi
    if [[ -d "/var/www" && -z "$(ls -A /var/www 2>/dev/null)" ]]; then
        rmdir /var/www 2>/dev/null
    fi
    
    # 4. 清理系统残留
    log_info "步骤 4/4: 清理系统残留..."
    rm -f /etc/systemd/system/multi-user.target.wants/hysteria-server.service 2>/dev/null
    rm -f /etc/systemd/system/multi-user.target.wants/hysteria-server@*.service 2>/dev/null
    systemctl daemon-reload
    
    echo ""
    log_success "所有依赖和插件卸载完成!"
    echo ""
    echo -e "${GREEN}管理脚本已保留，可以使用 's-hy2' 重新安装${NC}"
}

uninstall_everything() {
    echo ""
    echo -e "${RED}完全卸载 - 删除所有内容${NC}"
    echo ""
    
    echo -e "${RED}警告: 此操作将删除:${NC}"
    echo "• Hysteria2 程序和配置"
    echo "• nginx 及订阅文件"
    echo "• 管理脚本 (s-hy2)"
    echo "• 所有相关目录和文件"
    echo "• 端口跳跃规则"
    echo "• 系统用户账户"
    echo ""
    echo -e "${YELLOW}此操作不可逆！请输入 'YES' 确认完全卸载: ${NC}"
    read -r confirm
    if [[ "$confirm" != "YES" ]]; then
        echo -e "${BLUE}取消卸载${NC}"
        return
    fi
    
    log_info "开始完全卸载..."
    
    # 1. 清理端口跳跃配置
    log_info "步骤 1/7: 清理端口跳跃配置..."
    cleanup_port_hopping
    
    # 2. 停止并禁用服务
    log_info "步骤 2/7: 停止并禁用服务..."
    if systemctl is-active --quiet hysteria-server.service; then
        systemctl stop hysteria-server.service
    fi
    if systemctl is-enabled --quiet hysteria-server.service 2>/dev/null; then
        systemctl disable hysteria-server.service 2>/dev/null
    fi
    
    # 3. 卸载 Hysteria2 程序
    log_info "步骤 3/7: 卸载 Hysteria2 程序..."
    if check_hysteria_installed; then
        local tmp_rm
        tmp_rm=$(mktemp /tmp/s-hy2-remove.XXXXXX)
        chmod 600 "$tmp_rm"
        if curl -fsSL --proto "=https" --tlsv1.2 -o "$tmp_rm" "https://get.hy2.sh/" && bash -n "$tmp_rm"; then
            bash "$tmp_rm" --remove 2>/dev/null || log_warn "程序卸载失败，继续清理"
        else
            log_warn "卸载脚本下载或语法检查失败，跳过自动卸载，继续清理"
        fi
        rm -f "$tmp_rm"
    fi
    
    # 4. 卸载 nginx 和清理订阅文件
    log_info "步骤 4/7: 卸载 nginx 和清理订阅文件..."
    if command -v nginx &>/dev/null; then
        systemctl stop nginx 2>/dev/null
        systemctl disable nginx 2>/dev/null
        
        if command -v apt &>/dev/null; then
            apt remove -y nginx nginx-common nginx-core 2>/dev/null
            apt autoremove -y 2>/dev/null
        elif command -v yum &>/dev/null; then
            yum remove -y nginx 2>/dev/null
        elif command -v dnf &>/dev/null; then
            dnf remove -y nginx 2>/dev/null
        fi
    fi
    
    # 删除web目录
    safe_remove_dir "/var/www" 2>/dev/null
    
    # 5. 删除配置文件和证书
    log_info "步骤 5/7: 删除配置文件和证书..."
    safe_remove_dir "/etc/hysteria" 2>/dev/null
    
    # 6. 清理系统残留
    log_info "步骤 6/7: 清理系统残留..."
    if id "hysteria" &>/dev/null; then
        userdel -r hysteria 2>/dev/null
    fi
    
    # 清理 iptables/nftables 规则残留
    if command -v nft >/dev/null 2>&1; then
        # nftables: 删除 nat prerouting 链中所有 redirect 规则
        nft -a list chain ip nat prerouting 2>/dev/null | grep "redirect to :443" | grep -o 'handle [0-9]*' | awk '{print $2}' | sort -rn | while read -r h; do
            nft delete rule ip nat prerouting handle "$h" 2>/dev/null
        done
    fi
    if command -v iptables >/dev/null 2>&1; then
        iptables -t nat -L PREROUTING --line-numbers 2>/dev/null | grep "REDIRECT.*443" | awk '{print $1}' | tac | while read -r line; do
            iptables -t nat -D PREROUTING "$line" 2>/dev/null
        done
    fi
    
    # 清理 systemd 残留
    rm -f /etc/systemd/system/multi-user.target.wants/hysteria-server.service 2>/dev/null
    rm -f /etc/systemd/system/multi-user.target.wants/hysteria-server@*.service 2>/dev/null
    systemctl daemon-reload
    
    # 7. 删除管理脚本
    log_info "步骤 7/7: 删除管理脚本..."
    rm -f /usr/local/bin/hy2-manager 2>/dev/null
    rm -f /usr/local/bin/s-hy2 2>/dev/null
    
    # 删除安装目录
    safe_remove_dir "/opt/s-hy2" 2>/dev/null
    
    # 删除桌面快捷方式
    if [[ -n "$SUDO_USER" ]]; then
        rm -f "/home/$SUDO_USER/Desktop/S-Hy2-Manager.desktop" 2>/dev/null
    fi
    
    echo ""
    log_success "完全卸载完成!"
    echo -e "${BLUE}系统已完全清理，感谢使用 S-Hy2 管理脚本${NC}"
    echo ""
    echo -e "${YELLOW}重新安装:${NC}"
    echo "curl -fsSL --proto \"=https\" --tlsv1.2 -o quick-install.sh https://raw.githubusercontent.com/motao123/S-Hy2-Manager/main/quick-install.sh"
    echo "bash -n quick-install.sh && sudo bash quick-install.sh"
    echo ""
    
    # 由于脚本本身已被删除，这里直接退出
    exit 0
}

check_dependencies() {
    local missing_deps=()
    local required_cmds=("curl" "systemctl")
    # iptables 或 nftables 至少需要一个（端口跳跃功能依赖）
    if ! command -v iptables &>/dev/null && ! command -v nft &>/dev/null; then
        required_cmds+=("iptables/nft")
    fi
    
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_warn "缺少必要的依赖:"
        printf ' • %s\n' "${missing_deps[@]}"
        echo ""
        echo "请安装缺少的依赖后重新运行脚本"
        exit 1
    fi
}

