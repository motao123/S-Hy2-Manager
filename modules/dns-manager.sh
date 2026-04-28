#!/bin/bash
# DNS 配置管理模块
#
# 依赖: common.sh
# 导出函数: dns_management, set_dns_config, show_dns_config, remove_dns_config

# ========== DNS 管理菜单 ==========
dns_management() {
    while true; do
        clear
        echo -e "${CYAN}================================================${NC}"
        echo -e "${CYAN}           DNS 配置管理${NC}"
        echo -e "${CYAN}================================================${NC}"
        echo ""

        show_dns_config
        echo ""

        echo -e "${YELLOW}请选择操作:${NC}"
        echo ""
        echo -e "${GREEN} 1.${NC} 设置 DNS 服务器"
        echo -e "${GREEN} 2.${NC} 使用推荐 DNS 配置"
        echo -e "${GREEN} 3.${NC} 移除 DNS 配置"
        echo -e "${RED} 0.${NC} 返回主菜单"
        echo ""
        echo -n -e "${BLUE}请输入选项 [0-3]: ${NC}"

        local choice
        read -r choice

        case $choice in
            1) set_dns_config ;;
            2) set_recommended_dns ;;
            3) remove_dns_config ;;
            0) return 0 ;;
            *) echo -e "${RED}无效选项${NC}" ;;
        esac

        echo ""
        echo -n "按回车键继续..."
        read -r
    done
}

# ========== 显示当前 DNS 配置 ==========
show_dns_config() {
    if [[ ! -f "$HYSTERIA_CONFIG" ]]; then
        echo -e "${YELLOW}配置文件不存在${NC}"
        return 1
    fi

    if grep -q "^dns:" "$HYSTERIA_CONFIG" 2>/dev/null; then
        echo -e "${GREEN}当前 DNS 配置:${NC}"
        sed -n '/^dns:/,/^[a-zA-Z]/{p}' "$HYSTERIA_CONFIG" | head -20
    else
        echo -e "${YELLOW}未配置自定义 DNS（使用系统默认）${NC}"
    fi
}

# ========== 设置 DNS 配置 ==========
set_dns_config() {
    echo -e "${CYAN}=== 设置 DNS 服务器 ===${NC}"
    echo ""

    echo -e "${YELLOW}常用 DNS 服务器:${NC}"
    echo -e "  Google:   8.8.8.8:53"
    echo -e "  Cloudflare: 1.1.1.1:53"
    echo -e "  OpenDNS:  208.67.222.222:53"
    echo -e "  阿里:     223.5.5.5:53"
    echo -e "  腾讯:     119.29.29.29:53"
    echo ""

    echo -n "请输入主 DNS 地址（如 8.8.8.8:53）: "
    local dns1
    read -r dns1

    if [[ -z "$dns1" ]]; then
        log_error "DNS 地址不能为空"
        return 1
    fi

    echo -n "请输入备用 DNS 地址（可选，回车跳过）: "
    local dns2
    read -r dns2

    # 备份
    cp "$HYSTERIA_CONFIG" "${HYSTERIA_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    chmod 600 "${HYSTERIA_CONFIG}.backup."* 2>/dev/null || true

    # 删除旧的 DNS 段
    local temp_file
    temp_file=$(create_temp_file)
    local in_dns=false
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*dns: ]]; then
            in_dns=true
            continue
        fi
        if $in_dns; then
            if [[ "$line" =~ ^[a-zA-Z] ]] || [[ "$line" =~ ^$ ]]; then
                in_dns=false
            else
                continue
            fi
        fi
        echo "$line" >> "$temp_file"
    done < "$HYSTERIA_CONFIG"

    # 添加新的 DNS 配置（使用 yaml_write_kv 安全写入）
    printf '\ndns:\n' >> "$temp_file"
    printf '  servers:\n' >> "$temp_file"
    printf '    - addr: %s\n' "$(yaml_quote_scalar "$dns1")" >> "$temp_file"
    printf '      timeout: 5s\n' >> "$temp_file"
    if [[ -n "$dns2" ]]; then
        printf '    - addr: %s\n' "$(yaml_quote_scalar "$dns2")" >> "$temp_file"
        printf '      timeout: 5s\n' >> "$temp_file"
    fi

    replace_config_file_securely "$temp_file" "$HYSTERIA_CONFIG"
    log_success "DNS 配置已设置"
    ask_restart_service
}

# ========== 使用推荐 DNS 配置 ==========
set_recommended_dns() {
    echo -e "${CYAN}=== 推荐 DNS 配置 ===${NC}"
    echo ""

    echo -e "${YELLOW}推荐方案:${NC}"
    echo -e "  1. Google + Cloudflare（海外推荐）"
    echo -e "  2. 阿里 + 腾讯（国内推荐）"
    echo -e "  3. Google + 阿里（混合推荐）"
    echo ""
    echo -n "请选择 [1-3]: "
    local choice
    read -r choice

    case $choice in
        1)
            echo -n -e "8.8.8.8:53\n1.1.1.1:53" | set_dns_config_from_stdin
            ;;
        2)
            echo -n -e "223.5.5.5:53\n119.29.29.29:53" | set_dns_config_from_stdin
            ;;
        3)
            echo -n -e "8.8.8.8:53\n223.5.5.5:53" | set_dns_config_from_stdin
            ;;
        *)
            log_error "无效选择"
            return 1
            ;;
    esac
}

# ========== 从标准输入设置 DNS（内部使用）==========
set_dns_config_from_stdin() {
    # 从 stdin 读取两行：dns1 和 dns2
    local dns1 dns2
    read -r dns1
    read -r dns2

    if [[ -z "$dns1" ]]; then
        log_error "DNS 地址不能为空"
        return 1
    fi

    cp "$HYSTERIA_CONFIG" "${HYSTERIA_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    chmod 600 "${HYSTERIA_CONFIG}.backup."* 2>/dev/null || true

    local temp_file
    temp_file=$(create_temp_file)
    local in_dns=false
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*dns: ]]; then
            in_dns=true
            continue
        fi
        if $in_dns; then
            if [[ "$line" =~ ^[a-zA-Z] ]] || [[ "$line" =~ ^$ ]]; then
                in_dns=false
            else
                continue
            fi
        fi
        echo "$line" >> "$temp_file"
    done < "$HYSTERIA_CONFIG"

    # 添加新的 DNS 配置
    printf '\ndns:\n' >> "$temp_file"
    printf '  servers:\n' >> "$temp_file"
    printf '    - addr: %s\n' "$(yaml_quote_scalar "$dns1")" >> "$temp_file"
    printf '      timeout: 5s\n' >> "$temp_file"
    if [[ -n "$dns2" ]]; then
        printf '    - addr: %s\n' "$(yaml_quote_scalar "$dns2")" >> "$temp_file"
        printf '      timeout: 5s\n' >> "$temp_file"
    fi

    replace_config_file_securely "$temp_file" "$HYSTERIA_CONFIG"
    log_success "DNS 配置已设置"
    ask_restart_service
}

# ========== 移除 DNS 配置 ==========
remove_dns_config() {
    echo -e "${CYAN}=== 移除 DNS 配置 ===${NC}"

    if ! grep -q "^dns:" "$HYSTERIA_CONFIG" 2>/dev/null; then
        echo -e "${YELLOW}当前未配置自定义 DNS${NC}"
        return 0
    fi

    echo -n "确认移除 DNS 配置？[y/N]: "
    local confirm
    read -r confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        return 0
    fi

    cp "$HYSTERIA_CONFIG" "${HYSTERIA_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    chmod 600 "${HYSTERIA_CONFIG}.backup."* 2>/dev/null || true

    local temp_file
    temp_file=$(create_temp_file)
    local in_dns=false
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*dns: ]]; then
            in_dns=true
            continue
        fi
        if $in_dns; then
            if [[ "$line" =~ ^[a-zA-Z] ]] || [[ "$line" =~ ^$ ]]; then
                in_dns=false
            else
                continue
            fi
        fi
        echo "$line" >> "$temp_file"
    done < "$HYSTERIA_CONFIG"

    replace_config_file_securely "$temp_file" "$HYSTERIA_CONFIG"
    log_success "DNS 配置已移除"
    ask_restart_service
}
