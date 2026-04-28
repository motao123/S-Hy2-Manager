#!/bin/bash
# 速度测试模块
#
# 依赖: common.sh
# 导出函数: speed_test, test_download_speed, test_latency, test_hysteria_speed

# ========== 速度测试菜单 ==========
speed_test() {
    echo -e "${CYAN}================================================${NC}"
    echo -e "${CYAN}           速度测试${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo ""

    echo -e "${YELLOW}请选择测试类型:${NC}"
    echo ""
    echo -e "${GREEN} 1.${NC} 服务器下载速度测试"
    echo -e "${GREEN} 2.${NC} 服务器延迟测试"
    echo -e "${GREEN} 3.${NC} Hysteria2 连接测试"
    echo -e "${RED} 0.${NC} 返回"
    echo ""
    echo -n -e "${BLUE}请输入选项 [0-3]: ${NC}"

    local choice
    read -r choice

    case $choice in
        1) test_download_speed ;;
        2) test_latency ;;
        3) test_hysteria_speed ;;
        *) return 0 ;;
    esac
}

# ========== 下载速度测试 ==========
test_download_speed() {
    echo -e "${CYAN}=== 下载速度测试 ===${NC}"
    echo ""

    # 使用常见的测速文件（优先使用 HTTPS 防止劫持，保留 HTTP 备用节点并注明风险）
    local test_urls=(
        "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
        "https://releases.ubuntu.com/22.04/ubuntu-22.04.3-live-server-amd64.iso"
        "http://cachefly.cachefly.net/10mb.test"  # 备用：HTTP，可能被劫持
    )

    echo -e "${YELLOW}正在测试下载速度...${NC}"
    for url in "${test_urls[@]}"; do
        echo -e "\n测试地址: ${CYAN}$url${NC}"
        curl -o /dev/null -w "  下载速度: %{speed_download} bytes/s (%{time_total}s)\n" -s "$url" 2>/dev/null || \
            echo -e "  ${RED}测试失败${NC}"
    done
}

# ========== 延迟测试 ==========
test_latency() {
    echo -e "${CYAN}=== 延迟测试 ===${NC}"
    echo ""

    local targets=(
        "8.8.8.8:Google DNS"
        "1.1.1.1:Cloudflare DNS"
        "208.67.222.222:OpenDNS"
    )

    for target in "${targets[@]}"; do
        local ip="${target%%:*}"
        local name="${target##*:}"
        echo -ne "  $name ($ip): "
        ping -c 3 -W 2 "$ip" 2>/dev/null | tail -1 | awk -F '/' '{printf "%.1f ms\n", $5}' || echo -e "${RED}超时${NC}"
    done
}

# ========== Hysteria2 连接测试 ==========
test_hysteria_speed() {
    echo -e "${CYAN}=== Hysteria2 连接测试 ===${NC}"
    echo ""

    if ! systemctl is-active --quiet "$HYSTERIA_SERVICE" 2>/dev/null; then
        log_error "Hysteria2 服务未运行"
        return 1
    fi

    # 获取本地 SOCKS5 端口（如果有）
    local local_port
    local_port=$(grep "socks5:" "$HYSTERIA_CONFIG" 2>/dev/null | grep -oP ':\K\d+' || echo "1080")

    echo -e "${YELLOW}检查服务状态...${NC}"
    systemctl status "$HYSTERIA_SERVICE" --no-pager -l | head -20

    echo ""
    echo -e "${YELLOW}检查端口监听...${NC}"
    local listen_port
    listen_port=$(get_listen_port)
    ss -tlnp | grep ":${listen_port}" || echo -e "${YELLOW}端口 $listen_port 未监听${NC}"
}
