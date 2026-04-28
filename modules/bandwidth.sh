#!/bin/bash
# 带宽限制管理模块
#
# 依赖: common.sh
# 导出函数: bandwidth_management, set_bandwidth, show_bandwidth, remove_bandwidth

# 校验带宽值格式：允许 "数字 单位" 格式（如 100 mbps、1 gbps、500 kbps）
_validate_bandwidth_value() {
    local value="$1"
    [[ "$value" =~ ^[0-9]+[[:space:]]*(kbps|mbps|gbps|Kbps|Mbps|Gbps|KBps|MBps|GBps|Bps|bps)$ ]]
}

# ========== 带宽管理菜单 ==========
bandwidth_management() {
    while true; do
        clear
        echo -e "${CYAN}================================================${NC}"
        echo -e "${CYAN}           带宽限制管理${NC}"
        echo -e "${CYAN}================================================${NC}"
        echo ""

        # 显示当前带宽设置
        show_bandwidth
        echo ""

        echo -e "${YELLOW}请选择操作:${NC}"
        echo ""
        echo -e "${GREEN} 1.${NC} 设置带宽限制"
        echo -e "${GREEN} 2.${NC} 修改带宽限制"
        echo -e "${GREEN} 3.${NC} 取消带宽限制"
        echo -e "${GREEN} 4.${NC} 设置忽略客户端带宽"
        echo -e "${RED} 0.${NC} 返回主菜单"
        echo ""
        echo -n -e "${BLUE}请输入选项 [0-4]: ${NC}"

        local choice
        read -r choice

        case $choice in
            1) set_bandwidth ;;
            2) set_bandwidth ;;  # 修改和设置用同一个函数
            3) remove_bandwidth ;;
            4) toggle_ignore_client_bandwidth ;;
            0) return 0 ;;
            *) echo -e "${RED}无效选项${NC}" ;;
        esac

        echo ""
        echo -n "按回车键继续..."
        read -r
    done
}

# ========== 显示当前带宽设置 ==========
show_bandwidth() {
    if [[ ! -f "$HYSTERIA_CONFIG" ]]; then
        echo -e "${YELLOW}配置文件不存在${NC}"
        return 1
    fi

    echo -e "${CYAN}当前带宽设置:${NC}"

    # 检查是否设置了带宽
    if grep -q "^bandwidth:" "$HYSTERIA_CONFIG" 2>/dev/null; then
        local up down
        up=$(grep "up:" "$HYSTERIA_CONFIG" | head -1 | awk '{print $2}')
        down=$(grep "down:" "$HYSTERIA_CONFIG" | head -1 | awk '{print $2}')
        echo -e "  上行: ${GREEN}${up:-未设置}${NC}"
        echo -e "  下行: ${GREEN}${down:-未设置}${NC}"
    else
        echo -e "  ${YELLOW}未设置带宽限制（无限制）${NC}"
    fi

    # 检查 ignoreClientBandwidth
    if grep -q "ignoreClientBandwidth: true" "$HYSTERIA_CONFIG" 2>/dev/null; then
        echo -e "  忽略客户端带宽: ${GREEN}已启用${NC}"
    elif grep -q "ignoreClientBandwidth:" "$HYSTERIA_CONFIG" 2>/dev/null; then
        echo -e "  忽略客户端带宽: ${YELLOW}已禁用${NC}"
    fi
}

# ========== 设置带宽限制 ==========
set_bandwidth() {
    echo -e "${CYAN}=== 设置带宽限制 ===${NC}"
    echo ""

    echo -e "${YELLOW}常见带宽参考:${NC}"
    echo -e "  家庭宽带 100M:  up: 20 mbps / down: 100 mbps"
    echo -e "  家庭宽带 200M:  up: 30 mbps / down: 200 mbps"
    echo -e "  家庭宽带 500M:  up: 50 mbps / down: 500 mbps"
    echo -e "  家庭宽带 1000M: up: 100 mbps / down: 1000 mbps"
    echo -e "  VPS 小鸡:       up: 100 mbps / down: 100 mbps"
    echo ""

    echo -n "请输入上行带宽（如 100 mbps / 1 gbps）: "
    local up_bw
    read -r up_bw

    if [[ -z "$up_bw" ]]; then
        log_error "上行带宽不能为空"
        return 1
    fi

    if ! _validate_bandwidth_value "$up_bw"; then
        log_error "上行带宽格式无效，请使用如 '100 mbps' 或 '1 gbps' 的格式"
        return 1
    fi

    echo -n "请输入下行带宽（如 200 mbps / 1 gbps）: "
    local down_bw
    read -r down_bw

    if [[ -z "$down_bw" ]]; then
        log_error "下行带宽不能为空"
        return 1
    fi

    if ! _validate_bandwidth_value "$down_bw"; then
        log_error "下行带宽格式无效，请使用如 '100 mbps' 或 '1 gbps' 的格式"
        return 1
    fi

    echo ""
    echo -e "上行: ${CYAN}$up_bw${NC}"
    echo -e "下行: ${CYAN}$down_bw${NC}"
    echo -n "确认设置？[y/N]: "
    local confirm
    read -r confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "已取消"
        return 0
    fi

    # 备份配置
    cp "$HYSTERIA_CONFIG" "${HYSTERIA_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    chmod 600 "${HYSTERIA_CONFIG}.backup."* 2>/dev/null || true

    # 删除旧的 bandwidth 段并在正确位置插入新的
    local temp_file
    temp_file=$(create_temp_file)
    local in_bw=false bw_inserted=false
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*bandwidth: ]]; then
            in_bw=true
            continue
        fi
        if $in_bw; then
            if [[ "$line" =~ ^[a-zA-Z] ]] || [[ "$line" =~ ^$ ]]; then
                in_bw=false
            else
                continue
            fi
        fi

        echo "$line" >> "$temp_file"

        # 在 masquerade 块结束后插入 bandwidth
        if [[ "$bw_inserted" == false && "$line" =~ ^masquerade:[[:space:]]*$ ]]; then
            # 标记：等 masquerade 块结束后再插入
            :
        fi
    done < "$HYSTERIA_CONFIG"

    # 删除旧的 bandwidth 段并在正确位置插入新的
    local temp_file
    temp_file=$(create_temp_file)
    local in_bw=false bw_inserted=false in_masq=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        # 跳过旧 bandwidth 块
        if [[ "$line" =~ ^[[:space:]]*bandwidth: ]]; then
            in_bw=true
            continue
        fi
        if $in_bw; then
            if [[ "$line" =~ ^[a-zA-Z] ]] || [[ "$line" =~ ^$ ]]; then
                in_bw=false
            else
                continue
            fi
        fi

        # 检测 masquerade 块边界
        if [[ "$bw_inserted" == false ]]; then
            if [[ "$line" =~ ^masquerade:[[:space:]]*$ ]]; then
                in_masq=true
                echo "$line" >> "$temp_file"
                continue
            elif [[ "$in_masq" == true && "$line" =~ ^[[:space:]]+(type|url|proxy|disable): ]]; then
                echo "$line" >> "$temp_file"
                continue
            elif [[ "$in_masq" == true ]]; then
                # masquerade 子块结束，在此插入 bandwidth
                printf 'bandwidth:\n' >> "$temp_file"
                yaml_write_kv "  " "up" "$up_bw" >> "$temp_file"
                yaml_write_kv "  " "down" "$down_bw" >> "$temp_file"
                bw_inserted=true
                in_masq=false
                # 继续处理当前行
            fi
        fi

        echo "$line" >> "$temp_file"
    done < "$HYSTERIA_CONFIG"

    # 如果没找到 masquerade 块，在文件末尾追加
    if [[ "$bw_inserted" == false ]]; then
        printf '\nbandwidth:\n' >> "$temp_file"
        yaml_write_kv "  " "up" "$up_bw" >> "$temp_file"
        yaml_write_kv "  " "down" "$down_bw" >> "$temp_file"
    fi

    replace_config_file_securely "$temp_file" "$HYSTERIA_CONFIG"

    log_success "带宽限制已设置"
    ask_restart_service
}

# ========== 取消带宽限制 ==========
remove_bandwidth() {
    echo -e "${CYAN}=== 取消带宽限制 ===${NC}"

    if ! grep -q "^bandwidth:" "$HYSTERIA_CONFIG" 2>/dev/null; then
        echo -e "${YELLOW}当前未设置带宽限制${NC}"
        return 0
    fi

    echo -n "确认取消带宽限制？[y/N]: "
    local confirm
    read -r confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        return 0
    fi

    # 备份
    cp "$HYSTERIA_CONFIG" "${HYSTERIA_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    chmod 600 "${HYSTERIA_CONFIG}.backup."* 2>/dev/null || true

    # 删除 bandwidth 段
    local temp_file
    temp_file=$(create_temp_file)
    local in_bw=false
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*bandwidth: ]]; then
            in_bw=true
            continue
        fi
        if $in_bw; then
            if [[ "$line" =~ ^[a-zA-Z] ]] || [[ "$line" =~ ^$ ]]; then
                in_bw=false
            else
                continue
            fi
        fi
        echo "$line" >> "$temp_file"
    done < "$HYSTERIA_CONFIG"

    replace_config_file_securely "$temp_file" "$HYSTERIA_CONFIG"
    log_success "带宽限制已取消"
    ask_restart_service
}

# ========== 切换忽略客户端带宽 ==========
toggle_ignore_client_bandwidth() {
    echo -e "${CYAN}=== 忽略客户端带宽设置 ===${NC}"
    echo ""

    echo -e "${YELLOW}启用后，服务端将忽略客户端声明的带宽，强制使用服务端配置的带宽限制${NC}"
    echo ""

    local current_value=false
    if grep -q "ignoreClientBandwidth: true" "$HYSTERIA_CONFIG" 2>/dev/null; then
        current_value=true
    fi

    if [[ "$current_value" == true ]]; then
        echo -e "当前状态: ${GREEN}已启用${NC}"
        echo -n "是否禁用？[y/N]: "
        local confirm
        read -r confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            _update_ignore_client_bandwidth "false"
            log_success "已禁用忽略客户端带宽"
        fi
    else
        echo -e "当前状态: ${YELLOW}已禁用${NC}"
        echo -n "是否启用？[y/N]: "
        local confirm
        read -r confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            _update_ignore_client_bandwidth "true"
            log_success "已启用忽略客户端带宽"
        fi
    fi

    ask_restart_service
}

# 安全更新 ignoreClientBandwidth 字段
_update_ignore_client_bandwidth() {
    local new_value="$1"
    local temp_file line in_bw=false field_found=false

    temp_file=$(create_temp_file)

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*bandwidth: ]]; then
            in_bw=true
            echo "$line" >> "$temp_file"
            continue
        fi

        if [[ "$in_bw" == true ]]; then
            if [[ "$line" =~ ^[a-zA-Z] ]] || [[ "$line" =~ ^$ ]]; then
                # bandwidth 块结束，如果没找到字段就追加
                if [[ "$field_found" == false ]]; then
                    yaml_write_kv "  " "ignoreClientBandwidth" "$new_value" >> "$temp_file"
                    field_found=true
                fi
                in_bw=false
            elif [[ "$line" =~ ^([[:space:]]*)ignoreClientBandwidth:[[:space:]]* ]]; then
                yaml_write_kv "${BASH_REMATCH[1]}" "ignoreClientBandwidth" "$new_value" >> "$temp_file"
                field_found=true
                continue
            fi
        fi

        echo "$line" >> "$temp_file"
    done < "$HYSTERIA_CONFIG"

    # 不在 bandwidth 块内，追加到 bandwidth 后或文件末尾
    if [[ "$field_found" == false ]]; then
        if [[ "$in_bw" == true ]]; then
            yaml_write_kv "  " "ignoreClientBandwidth" "$new_value" >> "$temp_file"
        fi
    fi

    replace_config_file_securely "$temp_file" "$HYSTERIA_CONFIG"
}
