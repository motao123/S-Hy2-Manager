#!/bin/bash
# 日志查看与管理模块
#
# 依赖: common.sh
# 导出函数: log_management, view_hysteria_log, tail_hysteria_log, clear_hysteria_log, setup_log_rotation

LOG_OUTPUT="${LOG_OUTPUT:-/var/log/hysteria/}"

# ========== 日志管理菜单 ==========
log_management() {
    while true; do
        clear
        echo -e "${CYAN}================================================${NC}"
        echo -e "${CYAN}           日志管理${NC}"
        echo -e "${CYAN}================================================${NC}"
        echo ""

        echo -e "${YELLOW}请选择操作:${NC}"
        echo ""
        echo -e "${GREEN} 1.${NC} 查看最近日志（最近 50 行）"
        echo -e "${GREEN} 2.${NC} 实时跟踪日志"
        echo -e "${GREEN} 3.${NC} 搜索日志"
        echo -e "${GREEN} 4.${NC} 清理日志"
        echo -e "${CYAN} 5.${NC} 设置日志轮转"
        echo -e "${RED} 0.${NC} 返回主菜单"
        echo ""
        echo -n -e "${BLUE}请输入选项 [0-5]: ${NC}"

        local choice
        read -r choice

        case $choice in
            1) view_hysteria_log ;;
            2) tail_hysteria_log ;;
            3) search_hysteria_log ;;
            4) clear_hysteria_log ;;
            5) setup_log_rotation ;;
            0) return 0 ;;
            *) echo -e "${RED}无效选项${NC}" ;;
        esac

        echo ""
        echo -n "按回车键继续..."
        read -r
    done
}

# ========== 查看最近日志 ==========
view_hysteria_log() {
    echo -e "${CYAN}=== Hysteria2 最近日志 ===${NC}"
    echo ""
    journalctl -u "$HYSTERIA_SERVICE" -n 50 --no-pager 2>/dev/null || \
        tail -50 "$LOG_OUTPUT"/*.log 2>/dev/null || \
        echo -e "${YELLOW}未找到日志${NC}"
}

# ========== 实时跟踪日志 ==========
tail_hysteria_log() {
    echo -e "${CYAN}=== 实时日志跟踪（Ctrl+C 退出）===${NC}"
    echo ""
    journalctl -u "$HYSTERIA_SERVICE" -f 2>/dev/null || \
        tail -f "$LOG_OUTPUT"/*.log 2>/dev/null || \
        echo -e "${YELLOW}未找到日志${NC}"
}

# ========== 搜索日志 ==========
search_hysteria_log() {
    echo -n "请输入搜索关键词: "
    local keyword
    read -r keyword

    if [[ -z "$keyword" ]]; then
        log_error "关键词不能为空"
        return 1
    fi

    echo -e "${CYAN}=== 搜索 '$keyword' ===${NC}"
    journalctl -u "$HYSTERIA_SERVICE" --no-pager | grep -i "$keyword" | tail -30 2>/dev/null || \
        grep -ri "$keyword" "$LOG_OUTPUT"/*.log 2>/dev/null | tail -30 || \
        echo -e "${YELLOW}未找到匹配${NC}"
}

# ========== 清理日志 ==========
clear_hysteria_log() {
    echo -e "${RED}⚠️  确认清理 Hysteria2 日志？${NC}"
    echo -n "确认？[y/N]: "
    local confirm
    read -r confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        return 0
    fi

    journalctl --vacuum-time=1d -u "$HYSTERIA_SERVICE" 2>/dev/null
    log_success "日志已清理"
}

# ========== 设置日志轮转 ==========
setup_log_rotation() {
    echo -e "${CYAN}=== 设置日志轮转 ===${NC}"
    echo ""
    echo -e "将创建 /etc/logrotate.d/hysteria 配置"
    echo -n "确认？[y/N]: "
    local confirm
    read -r confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        return 0
    fi

    cat > /etc/logrotate.d/hysteria << 'LOGROTATE'
/var/log/hysteria/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 hysteria hysteria
}
LOGROTATE

    log_success "日志轮转已配置（每天轮转，保留 7 天）"
}
