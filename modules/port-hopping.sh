#!/bin/bash
# 端口跳跃管理（iptables 规则）
#
# 依赖: common.sh, config.sh
# 导出函数: manage_port_hopping, enable_port_hopping, modify_port_hopping, disable_port_hopping, show_port_hopping_details, cleanup_port_hopping

# 安全读取 port-hopping 配置文件：只解析已知键值对，不 source 执行
_read_port_hopping_conf_local() {
    local config_file="${1:-/etc/hysteria/port-hopping.conf}"
    PORT_HOPPING_INTERFACE=""
    PORT_HOPPING_START_PORT=""
    PORT_HOPPING_END_PORT=""
    PORT_HOPPING_TARGET_PORT=""
    PORT_HOPPING_BACKEND=""

    [[ -f "$config_file" ]] || return 1

    local line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            INTERFACE=*)
                value="${line#INTERFACE=}"
                value="${value%\"}"
                value="${value#\"}"
                [[ "$value" =~ ^[a-zA-Z0-9_.-]+$ ]] && PORT_HOPPING_INTERFACE="$value"
                ;;
            START_PORT=*)
                value="${line#START_PORT=}"
                value="${value%\"}"
                value="${value#\"}"
                [[ "$value" =~ ^[0-9]+$ ]] && PORT_HOPPING_START_PORT="$value"
                ;;
            END_PORT=*)
                value="${line#END_PORT=}"
                value="${value%\"}"
                value="${value#\"}"
                [[ "$value" =~ ^[0-9]+$ ]] && PORT_HOPPING_END_PORT="$value"
                ;;
            TARGET_PORT=*)
                value="${line#TARGET_PORT=}"
                value="${value%\"}"
                value="${value#\"}"
                [[ "$value" =~ ^[0-9]+$ ]] && PORT_HOPPING_TARGET_PORT="$value"
                ;;
            FIREWALL_BACKEND=*)
                value="${line#FIREWALL_BACKEND=}"
                value="${value%\"}"
                value="${value#\"}"
                [[ "$value" =~ ^(iptables|nftables)$ ]] && PORT_HOPPING_BACKEND="$value"
                ;;
        esac
    done < "$config_file"

    return 0
}

manage_port_hopping() {
    while true; do
        clear
        echo -e "${CYAN}=== 端口跳跃配置管理 ===${NC}"
        echo ""
        
        # 显示当前端口跳跃状态
        echo -e "${YELLOW}当前端口跳跃状态:${NC}"
        if safe_source_script "$SCRIPTS_DIR/config.sh" "配置脚本"; then
            local current_port
            current_port=$(get_current_listen_port)
            echo -e "监听端口: ${GREEN}$current_port${NC}"
            
            if check_port_hopping_status; then
                local hopping_info
                hopping_info=$(get_port_hopping_info)
                echo -e "端口跳跃: ${GREEN}✅ 已启用${NC}"
                if [[ -n "$hopping_info" ]]; then
                    echo "   $hopping_info"
                fi
            else
                echo -e "端口跳跃: ${YELLOW}❌ 未启用${NC}"
            fi
        fi
        
        echo ""
        echo -e "${YELLOW}端口跳跃管理选项:${NC}"
        echo -e "${GREEN}1.${NC} 启用端口跳跃"
        echo -e "${GREEN}2.${NC} 修改端口跳跃配置"
        echo -e "${GREEN}3.${NC} 禁用端口跳跃"
        echo -e "${GREEN}4.${NC} 查看端口跳跃详情"
        echo -e "${RED}0.${NC} 返回上级菜单"
        echo ""
        echo -n -e "${BLUE}请选择操作 [0-4]: ${NC}"
        read -r choice
        
        case $choice in
            1) enable_port_hopping ;;
            2) modify_port_hopping ;;
            3) disable_port_hopping ;;
            4) show_port_hopping_details ;;
            0) break ;;
            *)
                log_error "无效选项"
                sleep 1
                ;;
        esac
    done
}

enable_port_hopping() {
    echo ""
    echo -e "${BLUE}启用端口跳跃${NC}"
    
    if safe_source_script "$SCRIPTS_DIR/config.sh" "配置脚本"; then
        if check_port_hopping_status; then
            log_warn "端口跳跃已启用"
            wait_for_user
            return
        fi
        
        echo ""
        echo -e "${BLUE}配置端口跳跃范围:${NC}"
        echo -n -e "${BLUE}起始端口 (默认 20000): ${NC}"
        read -r start_port
        start_port=${start_port:-20000}
        
        echo -n -e "${BLUE}结束端口 (默认 50000): ${NC}"
        read -r end_port
        end_port=${end_port:-50000}
        
        # 验证端口范围
        if [[ ! "$start_port" =~ ^[0-9]+$ ]] || [[ ! "$end_port" =~ ^[0-9]+$ ]] || 
           [[ "$start_port" -lt 1 ]] || [[ "$end_port" -gt 65535 ]] || 
           [[ "$start_port" -ge "$end_port" ]]; then
            log_error "端口范围无效"
            wait_for_user
            return
        fi
        
        local current_port
        current_port=$(get_current_listen_port)
        if add_port_hopping_rules "$start_port" "$end_port" "$current_port"; then
            log_success "端口跳跃启用成功"
            echo "配置: $start_port-$end_port -> $current_port"
        else
            log_error "端口跳跃启用失败"
        fi
    fi
    
    wait_for_user
}

modify_port_hopping() {
    echo ""
    echo -e "${BLUE}修改端口跳跃配置${NC}"
    
    if safe_source_script "$SCRIPTS_DIR/config.sh" "配置脚本"; then
        if ! check_port_hopping_status; then
            log_warn "端口跳跃未启用，请先启用"
            wait_for_user
            return
        fi
        
        # 获取当前配置
        local current_info=""
        if [[ -f "/etc/hysteria/port-hopping.conf" ]]; then
            _read_port_hopping_conf_local
            if [[ -n "$PORT_HOPPING_START_PORT" && -n "$PORT_HOPPING_END_PORT" && -n "$PORT_HOPPING_TARGET_PORT" ]]; then
                current_info="当前配置: $PORT_HOPPING_START_PORT-$PORT_HOPPING_END_PORT -> $PORT_HOPPING_TARGET_PORT"
            fi
        fi
        
        if [[ -n "$current_info" ]]; then
            echo "$current_info"
        fi
        
        echo ""
        echo -e "${BLUE}输入新的端口跳跃范围:${NC}"
        echo -n -e "${BLUE}起始端口 (当前 ${PORT_HOPPING_START_PORT:-20000}): ${NC}"
        read -r new_start_port
        new_start_port=${new_start_port:-${PORT_HOPPING_START_PORT:-20000}}
        
        echo -n -e "${BLUE}结束端口 (当前 ${PORT_HOPPING_END_PORT:-50000}): ${NC}"
        read -r new_end_port
        new_end_port=${new_end_port:-${PORT_HOPPING_END_PORT:-50000}}
        
        echo -n -e "${BLUE}目标端口 (当前 ${PORT_HOPPING_TARGET_PORT:-$(get_current_listen_port)}): ${NC}"
        read -r new_target_port
        new_target_port=${new_target_port:-${PORT_HOPPING_TARGET_PORT:-$(get_current_listen_port)}}
        
        # 验证端口范围
        if [[ ! "$new_start_port" =~ ^[0-9]+$ ]] || [[ ! "$new_end_port" =~ ^[0-9]+$ ]] || [[ ! "$new_target_port" =~ ^[0-9]+$ ]] || 
           [[ "$new_start_port" -lt 1 ]] || [[ "$new_end_port" -gt 65535 ]] || [[ "$new_target_port" -lt 1 ]] || [[ "$new_target_port" -gt 65535 ]] || 
           [[ "$new_start_port" -ge "$new_end_port" ]]; then
            log_error "端口范围无效"
            wait_for_user
            return
        fi
        
        # 清除旧规则并添加新规则
        echo -e "${BLUE}正在更新端口跳跃配置...${NC}"
        clear_port_hopping_rules
        
        if add_port_hopping_rules "$new_start_port" "$new_end_port" "$new_target_port"; then
            log_success "端口跳跃配置修改成功"
            echo "新配置: $new_start_port-$new_end_port -> $new_target_port"
        else
            log_error "端口跳跃配置修改失败"
        fi
    fi
    
    wait_for_user
}

disable_port_hopping() {
    echo ""
    echo -e "${BLUE}禁用端口跳跃${NC}"
    echo ""
    
    if safe_source_script "$SCRIPTS_DIR/config.sh" "配置脚本"; then
        # 首先显示系统中所有的端口跳跃规则
        echo -e "${YELLOW}系统中的端口跳跃规则:${NC}"
        local all_redirect_rules
        all_redirect_rules=$(iptables-save -t nat 2>/dev/null | grep "^-A PREROUTING.*REDIRECT")
        
        if [[ -n "$all_redirect_rules" ]]; then
            echo "$all_redirect_rules"
            echo ""
            
            local redirect_count
            redirect_count=$(echo "$all_redirect_rules" | wc -l)
            echo -e "${GREEN}发现 $redirect_count 条端口重定向规则${NC}"
            
            # 解析所有规则的详细信息
            echo ""
            echo -e "${CYAN}规则详细信息:${NC}"
            local rule_number=1
            while IFS= read -r rule_line; do
                if [[ -n "$rule_line" ]]; then
                    local target_port
                    target_port=$(echo "$rule_line" | grep -o -- '--to-ports [0-9]\+' | awk '{print $2}')
                    
                    # 提取源端口信息，基于iptables-save格式
                    local port_info=""
                    # 匹配--dport端口范围格式：--dport 20000:50000
                    if [[ "$rule_line" =~ --dport[[:space:]]+([0-9]+):([0-9]+) ]]; then
                        port_info="源端口范围 ${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"
                    # 匹配--dport单端口格式：--dport 8080
                    elif [[ "$rule_line" =~ --dport[[:space:]]+([0-9]+) ]]; then
                        port_info="源单端口 ${BASH_REMATCH[1]}"
                    else
                        port_info="未知端口配置"
                    fi
                    
                    echo "$rule_number. $port_info → 目标端口$target_port"
                    ((rule_number++))
                fi
            done <<< "$all_redirect_rules"
        else
            echo "未找到任何端口重定向规则"
            echo -e "${YELLOW}系统中没有端口跳跃配置${NC}"
            wait_for_user
            return
        fi
        
        echo ""
        echo -e "${YELLOW}禁用选项:${NC}"
        echo -e "${GREEN}1.${NC} 禁用当前监听端口的端口跳跃"
        echo -e "${GREEN}2.${NC} 禁用指定目标端口的端口跳跃"  
        echo -e "${GREEN}3.${NC} 按行号禁用特定规则"
        echo -e "${GREEN}4.${NC} 禁用所有端口跳跃规则"
        echo -e "${RED}0.${NC} 取消操作"
        echo ""
        echo -n -e "${BLUE}请选择操作 [0-4]: ${NC}"
        read -r choice
        
        case $choice in
            1)
                # 禁用当前监听端口的端口跳跃
                local current_port
                current_port=$(get_current_listen_port)
                echo ""
                echo -e "${BLUE}当前监听端口: $current_port${NC}"
                
                local current_port_rules
                current_port_rules=$(iptables -t nat -L PREROUTING -n --line-numbers 2>/dev/null | grep "REDIRECT.*--to-ports $current_port")
                if [[ -n "$current_port_rules" ]]; then
                    echo -e "${YELLOW}将要删除的规则:${NC}"
                    echo "$current_port_rules"
                    echo ""
                    echo -n -e "${YELLOW}确定要禁用当前监听端口的端口跳跃吗? [y/N]: ${NC}"
                    read -r confirm
                    if [[ $confirm =~ ^[Yy]$ ]]; then
                        clear_port_hopping_rules
                        log_success "当前监听端口的端口跳跃已禁用"
                    else
                        echo -e "${BLUE}取消操作${NC}"
                    fi
                else
                    echo -e "${YELLOW}当前监听端口没有端口跳跃配置${NC}"
                fi
                ;;
            2)
                # 禁用指定端口的端口跳跃
                echo ""
                echo -e "${BLUE}禁用指定端口的端口跳跃${NC}"
                
                # 重新获取所有规则，确保数据是最新的
                local current_rules
                current_rules=$(iptables-save -t nat 2>/dev/null | grep "^-A PREROUTING.*REDIRECT")
                if [[ -z "$current_rules" ]]; then
                    echo -e "${YELLOW}系统中没有端口跳跃规则${NC}"
                    break
                fi
                
                # 显示所有目标端口及其规则信息
                echo -e "${YELLOW}可禁用的目标端口:${NC}"
                local target_ports=($(echo "$current_rules" | grep -o -- '--to-ports [0-9]\+' | awk '{print $2}' | sort -u))
                
                if [[ ${#target_ports[@]} -eq 0 ]]; then
                    echo "未找到任何目标端口"
                    echo ""
                    echo -e "${YELLOW}您可以直接输入要检查的端口号，或输入 0 取消操作${NC}"
                else
                    local i=1
                    for port in "${target_ports[@]}"; do
                        local port_rules_count
                        port_rules_count=$(echo "$current_rules" | grep -- "--to-ports $port" | wc -l)
                        echo "$i. 端口 $port ($port_rules_count 条规则)"
                        
                        # 显示此端口的详细规则信息
                        echo "$current_rules" | grep -- "--to-ports $port" | while IFS= read -r rule_line; do
                            local port_info=""
                            # 基于iptables-save格式解析
                            # 匹配--dport端口范围格式：--dport 20000:50000
                            if [[ "$rule_line" =~ --dport[[:space:]]+([0-9]+):([0-9]+) ]]; then
                                port_info="源端口范围 ${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"
                            # 匹配--dport单端口格式：--dport 8080
                            elif [[ "$rule_line" =~ --dport[[:space:]]+([0-9]+) ]]; then
                                port_info="源单端口 ${BASH_REMATCH[1]}"
                            else
                                port_info="未知端口配置"
                            fi
                            echo "   - $port_info → 目标端口$port"
                        done
                        echo ""
                        ((i++))
                    done
                fi
                
                echo -n -e "${BLUE}请输入要禁用的目标端口号 (0=取消): ${NC}"
                read -r target_port
                
                # 检查是否取消操作
                if [[ "$target_port" == "0" ]]; then
                    echo -e "${BLUE}取消操作${NC}"
                elif [[ "$target_port" =~ ^[0-9]+$ ]] && [[ "$target_port" -ge 1 ]] && [[ "$target_port" -le 65535 ]]; then
                    # 重新获取最新规则并检查指定端口
                    local specific_rules
                    specific_rules=$(iptables-save -t nat 2>/dev/null | grep "^-A PREROUTING.*REDIRECT.*--to-ports $target_port")
                    if [[ -n "$specific_rules" ]]; then
                        echo ""
                        echo -e "${YELLOW}将要删除目标端口 $target_port 的以下规则:${NC}"
                        echo "$specific_rules"
                        echo ""
                        echo -n -e "${YELLOW}确定要禁用目标端口 $target_port 的所有端口跳跃规则吗? [y/N]: ${NC}"
                        read -r confirm
                        if [[ $confirm =~ ^[Yy]$ ]]; then
                            clear_specific_port_rules "$target_port"
                            log_success "目标端口 $target_port 的端口跳跃已禁用"
                        else
                            echo -e "${BLUE}取消操作${NC}"
                        fi
                    else
                        echo -e "${YELLOW}目标端口 $target_port 没有端口跳跃配置${NC}"
                    fi
                elif [[ -n "$target_port" ]]; then
                    echo -e "${RED}无效的端口号: $target_port${NC}"
                else
                    echo -e "${BLUE}未输入端口号，取消操作${NC}"
                fi
                ;;
            3)
                # 按规则选择禁用特定规则
                echo ""
                echo -e "${BLUE}选择特定规则禁用${NC}"
                
                # 重新获取最新规则
                local save_rules
                save_rules=$(iptables-save -t nat 2>/dev/null | grep "^-A PREROUTING.*REDIRECT")
                if [[ -z "$save_rules" ]]; then
                    echo -e "${YELLOW}系统中没有端口跳跃规则${NC}"
                    break
                fi
                
                echo -e "${YELLOW}当前所有规则:${NC}"
                local rule_num=1
                local -a rule_array
                while IFS= read -r rule_line; do
                    if [[ -n "$rule_line" ]]; then
                        rule_array[$rule_num]="$rule_line"
                        
                        # 解析规则信息
                        local target_port
                        target_port=$(echo "$rule_line" | grep -o -- '--to-ports [0-9]\+' | awk '{print $2}')
                        local port_info=""
                        if [[ "$rule_line" =~ --dport[[:space:]]+([0-9]+):([0-9]+) ]]; then
                            port_info="源端口范围 ${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"
                        elif [[ "$rule_line" =~ --dport[[:space:]]+([0-9]+) ]]; then
                            port_info="源单端口 ${BASH_REMATCH[1]}"
                        else
                            port_info="未知端口配置"
                        fi
                        
                        echo "$rule_num. $port_info → 目标端口$target_port"
                        ((rule_num++))
                    fi
                done <<< "$save_rules"
                
                echo ""
                echo -n -e "${BLUE}请输入要删除的规则编号 (0=取消): ${NC}"
                read -r rule_choice
                
                if [[ "$rule_choice" == "0" ]]; then
                    echo -e "${BLUE}取消操作${NC}"
                elif [[ "$rule_choice" =~ ^[0-9]+$ ]] && [[ "$rule_choice" -ge 1 ]] && [[ "$rule_choice" -lt "$rule_num" ]]; then
                    local selected_rule="${rule_array[$rule_choice]}"
                    echo ""
                    echo -e "${YELLOW}将要删除的规则:${NC}"
                    echo "$selected_rule"
                    echo ""
                    echo -n -e "${YELLOW}确定要删除此规则吗? [y/N]: ${NC}"
                    read -r confirm
                    if [[ $confirm =~ ^[Yy]$ ]]; then
                        # 将-A改为-D来删除规则
                        local delete_rule="${selected_rule/-A/-D}"
                        if iptables -t nat $delete_rule 2>/dev/null; then
                            log_success "规则已删除"
                        else
                            log_error "删除规则失败"
                        fi
                    else
                        echo -e "${BLUE}取消操作${NC}"
                    fi
                else
                    echo -e "${RED}无效的规则编号${NC}"
                fi
                ;;
            4)
                # 禁用所有端口跳跃规则
                echo ""
                echo -e "${BLUE}禁用所有端口跳跃规则${NC}"
                echo -e "${RED}警告: 这将删除系统中所有的端口重定向规则!${NC}"
                echo ""
                echo -n -e "${YELLOW}确定要禁用所有端口跳跃规则吗? [y/N]: ${NC}"
                read -r confirm
                if [[ $confirm =~ ^[Yy]$ ]]; then
                    echo -n -e "${RED}再次确认: 这是危险操作，确定继续吗? [y/N]: ${NC}"
                    read -r final_confirm
                    if [[ $final_confirm =~ ^[Yy]$ ]]; then
                        clear_all_port_hopping_rules
                        log_success "所有端口跳跃规则已禁用"
                    else
                        echo -e "${BLUE}取消操作${NC}"
                    fi
                else
                    echo -e "${BLUE}取消操作${NC}"
                fi
                ;;
            0)
                echo -e "${BLUE}取消操作${NC}"
                ;;
            *)
                echo -e "${RED}无效选项${NC}"
                ;;
        esac
    fi
    
    wait_for_user
}

show_port_hopping_details() {
    echo ""
    echo -e "${BLUE}端口跳跃详细信息${NC}"
    echo ""
    
    if safe_source_script "$SCRIPTS_DIR/config.sh" "配置脚本"; then
        local current_port
        current_port=$(get_current_listen_port)
        echo -e "${YELLOW}当前监听端口:${NC} $current_port"
        echo ""
        
        # 显示系统中所有的端口跳跃配置
        echo -e "${CYAN}=== 系统端口跳跃配置概览 ===${NC}"
        
        # 显示所有 REDIRECT 到端口的 iptables 规则
        echo -e "${YELLOW}所有 iptables REDIRECT 规则:${NC}"
        local all_redirect_rules
        all_redirect_rules=$(iptables-save -t nat 2>/dev/null | grep "^-A PREROUTING.*REDIRECT")
        if [[ -n "$all_redirect_rules" ]]; then
            echo "$all_redirect_rules"
            echo ""
            
            # 统计端口跳跃规则数量
            local redirect_count
            redirect_count=$(echo "$all_redirect_rules" | wc -l)
            echo -e "${GREEN}共发现 $redirect_count 条端口重定向规则${NC}"
            
            # 解析并显示详细的规则信息
            echo ""
            echo -e "${CYAN}详细规则解析:${NC}"
            local rule_number=1
            while IFS= read -r rule_line; do
                if [[ -n "$rule_line" ]]; then
                    local target_port
                    target_port=$(echo "$rule_line" | grep -o -- '--to-ports [0-9]\+' | awk '{print $2}')
                    
                    # 提取源端口信息，基于iptables-save格式
                    local port_info=""
                    # 匹配--dport端口范围格式：--dport 20000:50000
                    if [[ "$rule_line" =~ --dport[[:space:]]+([0-9]+):([0-9]+) ]]; then
                        port_info="源端口范围 ${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"
                    # 匹配--dport单端口格式：--dport 8080
                    elif [[ "$rule_line" =~ --dport[[:space:]]+([0-9]+) ]]; then
                        port_info="源单端口 ${BASH_REMATCH[1]}"
                    else
                        port_info="未知端口配置"
                    fi
                    
                    echo "$rule_number. $port_info → 目标端口$target_port"
                    ((rule_number++))
                fi
            done <<< "$all_redirect_rules"
        else
            echo "未找到任何端口重定向规则"
        fi
        
        echo ""
        echo -e "${CYAN}=== 当前监听端口配置状态 ===${NC}"
        
        if check_port_hopping_status; then
            echo -e "${YELLOW}端口跳跃状态:${NC} ${GREEN}已启用${NC}"
            
            # 显示配置文件信息
            if [[ -f "/etc/hysteria/port-hopping.conf" ]]; then
                echo -e "${YELLOW}配置文件:${NC} /etc/hysteria/port-hopping.conf"
                echo ""
                echo -e "${CYAN}配置内容:${NC}"
                cat /etc/hysteria/port-hopping.conf
                echo ""
            fi
            
            # 显示当前监听端口相关的iptables规则
            echo -e "${YELLOW}当前监听端口 ($current_port) 的相关规则:${NC}"
            local current_port_rules
            current_port_rules=$(iptables -t nat -L PREROUTING -n --line-numbers 2>/dev/null | grep "REDIRECT.*--to-ports $current_port")
            if [[ -n "$current_port_rules" ]]; then
                echo "$current_port_rules"
            else
                echo "未找到针对当前监听端口的规则"
            fi
        else
            echo -e "${YELLOW}端口跳跃状态:${NC} ${YELLOW}未启用${NC}"
            
            # 检查是否有其他端口的跳跃规则
            local other_rules
            other_rules=$(iptables -t nat -L PREROUTING -n --line-numbers 2>/dev/null | grep "REDIRECT" | grep -v "to-ports $current_port")
            if [[ -n "$other_rules" ]]; then
                echo ""
                echo -e "${YELLOW}发现其他端口的跳跃配置:${NC}"
                echo "$other_rules"
                echo ""
                echo -e "${RED}警告: 发现非当前监听端口的端口跳跃规则，可能存在端口冲突${NC}"
            fi
        fi
        
        echo ""
        echo -e "${CYAN}=== 完整 iptables-save 输出 ===${NC}"
        echo -e "${YELLOW}完整的 NAT 表规则 (类似 sudo iptables-save):${NC}"
        iptables-save -t nat 2>/dev/null | grep -E "(PREROUTING|REDIRECT)" || echo "无法获取完整规则信息"
        
        echo ""
        echo -e "${GREEN}提示: 可以使用 'sudo iptables-save' 命令查看完整的防火墙规则${NC}"
    fi
    
    wait_for_user
}

cleanup_port_hopping() {
    if [[ -f "/etc/hysteria/port-hopping.conf" ]]; then
        _read_port_hopping_conf_local
        if [[ -n "$PORT_HOPPING_INTERFACE" && -n "$PORT_HOPPING_START_PORT" && -n "$PORT_HOPPING_END_PORT" && -n "$PORT_HOPPING_TARGET_PORT" ]]; then
            # 根据记录的后端选择清理方式，未知时自动探测
            local backend="$PORT_HOPPING_BACKEND"
            if [[ -z "$backend" ]]; then
                if command -v nft >/dev/null 2>&1 && nft list table ip nat &>/dev/null; then
                    backend="nftables"
                elif command -v iptables >/dev/null 2>&1; then
                    backend="iptables"
                fi
            fi

            if [[ "$backend" == "nftables" ]]; then
                # nftables: 删除匹配的 redirect 规则
                local handle
                handle=$(nft -a list chain ip nat prerouting 2>/dev/null | \
                    grep "iifname \"${PORT_HOPPING_INTERFACE}\" udp dport ${PORT_HOPPING_START_PORT}-${PORT_HOPPING_END_PORT} redirect to :${PORT_HOPPING_TARGET_PORT}" | \
                    grep -o 'handle [0-9]*' | awk '{print $2}')
                if [[ -n "$handle" ]]; then
                    nft delete rule ip nat prerouting handle "$handle" 2>/dev/null
                    log_info "已清理端口跳跃规则 (nftables, handle $handle)"
                else
                    # 模糊匹配：按接口和目标端口删除
                    nft -a list chain ip nat prerouting 2>/dev/null | \
                        grep "iifname \"${PORT_HOPPING_INTERFACE}\".*redirect to :${PORT_HOPPING_TARGET_PORT}" | \
                        grep -o 'handle [0-9]*' | awk '{print $2}' | while read -r h; do
                        nft delete rule ip nat prerouting handle "$h" 2>/dev/null
                    done
                    log_info "已清理端口跳跃规则 (nftables)"
                fi
            else
                # iptables 回退
                iptables -t nat -D PREROUTING -i "$PORT_HOPPING_INTERFACE" -p udp --dport "$PORT_HOPPING_START_PORT:$PORT_HOPPING_END_PORT" -j REDIRECT --to-ports "$PORT_HOPPING_TARGET_PORT" 2>/dev/null
                log_info "已清理端口跳跃规则 (iptables)"
            fi
        fi
    fi

    # 清理其他可能的端口跳跃规则（双后端扫描）
    local rules_cleared=0

    # nftables: 清理所有 redirect 规则
    if command -v nft >/dev/null 2>&1; then
        while IFS= read -r handle_num; do
            if [[ -n "$handle_num" ]]; then
                if nft delete rule ip nat prerouting handle "$handle_num" 2>/dev/null; then
                    ((rules_cleared++))
                fi
            fi
        done < <(nft -a list chain ip nat prerouting 2>/dev/null | grep "redirect to :" | grep -o 'handle [0-9]*' | awk '{print $2}' | sort -rn)
    fi

    # iptables: 清理所有 REDIRECT 规则
    if command -v iptables >/dev/null 2>&1; then
        while IFS= read -r line_num; do
            if [[ -n "$line_num" ]]; then
                if iptables -t nat -D PREROUTING "$line_num" 2>/dev/null; then
                    ((rules_cleared++))
                fi
            fi
        done < <(iptables -t nat -L PREROUTING --line-numbers 2>/dev/null | grep "REDIRECT.*--to-ports" | awk '{print $1}' | tac)
    fi

    if [[ $rules_cleared -gt 0 ]]; then
        log_info "清理了 $rules_cleared 条端口跳跃规则"
    fi

    # 删除配置文件
    rm -f "/etc/hysteria/port-hopping.conf" 2>/dev/null
}

