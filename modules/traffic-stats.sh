#!/bin/bash
# 流量统计模块
#
# 依赖: common.sh
# 导出函数: traffic_stats, show_traffic_summary, show_connection_stats, reset_traffic_stats

# ========== 流量统计菜单 ==========
traffic_stats() {
    while true; do
        clear
        echo -e "${CYAN}================================================${NC}"
        echo -e "${CYAN}           流量统计${NC}"
        echo -e "${CYAN}================================================${NC}"
        echo ""

        echo -e "${YELLOW}请选择操作:${NC}"
        echo ""
        echo -e "${GREEN} 1.${NC} 查看流量概览"
        echo -e "${GREEN} 2.${NC} 查看连接统计"
        echo -e "${GREEN} 3.${NC} 查看实时连接"
        echo -e "${GREEN} 4.${NC} 按用户查看流量（多用户模式）"
        echo -e "${RED} 0.${NC} 返回主菜单"
        echo ""
        echo -n -e "${BLUE}请输入选项 [0-4]: ${NC}"

        local choice
        read -r choice

        case $choice in
            1) show_traffic_summary ;;
            2) show_connection_stats ;;
            3) show_live_connections ;;
            4) show_user_traffic ;;
            0) return 0 ;;
            *) echo -e "${RED}无效选项${NC}" ;;
        esac

        echo ""
        echo -n "按回车键继续..."
        read -r
    done
}

# ========== 流量概览 ==========
show_traffic_summary() {
    echo -e "${CYAN}=== 流量概览 ===${NC}"
    echo ""

    if ! systemctl is-active --quiet "$HYSTERIA_SERVICE" 2>/dev/null; then
        log_error "Hysteria2 服务未运行"
        return 1
    fi

    # 从 hysteria API 获取统计信息（如果支持）
    local api_available=false
    if [[ -f "$HYSTERIA_CONFIG" ]]; then
        local api_addr
        api_addr=$(grep -A5 "^http:" "$HYSTERIA_CONFIG" 2>/dev/null | grep "listen:" | awk '{print $2}')
        if [[ -n "$api_addr" ]]; then
            api_available=true
        fi
    fi

    if $api_available; then
        echo -e "${GREEN}通过 API 获取统计信息:${NC}"
        curl -s "http://${api_addr}/traffic" 2>/dev/null | head -20 || \
            echo -e "${YELLOW}API 请求失败${NC}"
    else
        echo -e "${YELLOW}HTTP API 未启用，使用系统工具估算${NC}"
        echo ""

        # 从 systemd 获取服务运行时间
        local uptime
        uptime=$(systemctl show "$HYSTERIA_SERVICE" --property=ActiveEnterTimestamp --value 2>/dev/null)
        if [[ -n "$uptime" ]]; then
            echo -e "服务启动时间: ${GREEN}$uptime${NC}"
        fi

        # 从 journalctl 统计连接日志
        local total_conns
        total_conns=$(journalctl -u "$HYSTERIA_SERVICE" --no-pager -q --since today 2>/dev/null | grep -c "new connection" || echo 0)
        echo -e "今日连接数: ${GREEN}$total_conns${NC}"

        # 网络流量统计
        echo ""
        echo -e "${CYAN}网络接口流量:${NC}"
        local main_if
        main_if=$(ip route | grep default | awk '{print $5}' | head -1)
        if [[ -n "$main_if" ]]; then
            local rx_bytes tx_bytes
            rx_bytes=$(cat "/sys/class/net/$main_if/statistics/rx_bytes" 2>/dev/null || echo 0)
            tx_bytes=$(cat "/sys/class/net/$main_if/statistics/tx_bytes" 2>/dev/null || echo 0)
            echo -e "  接口: ${GREEN}$main_if${NC}"
            echo -e "  总接收: ${CYAN}$(human_readable_bytes "$rx_bytes")${NC}"
            echo -e "  总发送: ${CYAN}$(human_readable_bytes "$tx_bytes")${NC}"
        fi

        echo ""
        echo -e "${YELLOW}提示: 在配置中启用 HTTP API 可获取更详细的统计${NC}"
        echo -e "${YELLOW}添加以下配置即可:${NC}"
        echo -e "  ${CYAN}http:${NC}"
        echo -e "  ${CYAN}  listen: 127.0.0.1:8080${NC}"
    fi
}

# ========== 连接统计 ==========
show_connection_stats() {
    echo -e "${CYAN}=== 连接统计 ===${NC}"
    echo ""

    local listen_port
    listen_port=$(get_listen_port 2>/dev/null || echo "443")

    echo -e "${YELLOW}Hysteria2 端口: $listen_port${NC}"
    echo ""

    # UDP 连接（Hysteria2 基于 QUIC/UDP）
    echo -e "${GREEN}UDP 连接:${NC}"
    ss -lnup | grep ":${listen_port}" 2>/dev/null | head -10 || echo -e "  ${YELLOW}无 UDP 连接${NC}"

    echo ""
    echo -e "${GREEN}连接数统计:${NC}"
    local udp_count
    udp_count=$(ss -nup state established 2>/dev/null | grep ":${listen_port}" | wc -l)
    echo -e "  活跃 UDP 连接: ${CYAN}$udp_count${NC}"
}

# ========== 实时连接 ==========
show_live_connections() {
    echo -e "${CYAN}=== 实时连接（5秒快照）===${NC}"
    echo ""

    local listen_port
    listen_port=$(get_listen_port 2>/dev/null || echo "443")

    echo -e "${YELLOW}最近连接日志:${NC}"
    journalctl -u "$HYSTERIA_SERVICE" --no-pager -n 30 2>/dev/null | grep -i "connect" | tail -10 || \
        echo -e "  ${YELLOW}无连接日志${NC}"
}

# ========== 按用户查看流量 ==========
show_user_traffic() {
    echo -e "${Cyan}=== 按用户查看流量 ===${NC}"
    echo ""

    local auth_mode
    auth_mode=$(get_auth_mode 2>/dev/null || echo "password")

    if [[ "$auth_mode" != "userpass" ]]; then
        echo -e "${YELLOW}当前为单密码模式，无多用户流量数据${NC}"
        return 0
    fi

    echo -e "${YELLOW}提示: Hysteria2 内置 API 可按用户统计流量${NC}"
    echo -e "需要在配置中启用 HTTP API，并配置用户流量统计"
    echo ""

    # 尝试从日志中按用户统计连接
    echo -e "${CYAN}从日志中统计用户连接:${NC}"
    while IFS= read -r username; do
        local count
        count=$(journalctl -u "$HYSTERIA_SERVICE" --no-pager -q --since today 2>/dev/null | grep -c "$username" || echo 0)
        echo -e "  ${GREEN}$username${NC}: $count 条日志"
    done < <(get_all_users 2>/dev/null)
}

# ========== 字节可读化 ==========
human_readable_bytes() {
    local bytes="${1:-0}"
    if [[ $bytes -ge 1073741824 ]]; then
        echo "$(echo "scale=2; $bytes / 1073741824" | bc) GB"
    elif [[ $bytes -ge 1048576 ]]; then
        echo "$(echo "scale=2; $bytes / 1048576" | bc) MB"
    elif [[ $bytes -ge 1024 ]]; then
        echo "$(echo "scale=2; $bytes / 1024" | bc) KB"
    else
        echo "$bytes B"
    fi
}
