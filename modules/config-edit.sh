#!/bin/bash
# 配置修改（认证密码/端口/混淆参数）
#
# 依赖: common.sh, config.sh
# 导出函数: config_management, view_current_config, modify_auth_password, modify_port_settings, modify_obfs_settings, edit_config_file

# 转义字符串中 sed 替换表达式的特殊字符（用于替换部分）
# 转义 \\、&、以及用作分隔符的 | 符号
_escape_sed_replace() {
    printf '%s' "$1" | sed 's/[\\&|]/\\&/g'
}

backup_config_securely() {
    local source_file="$1"
    local backup_file="${2:-${source_file}.bak}"

    if cp "$source_file" "$backup_file"; then
        chmod 600 "$backup_file" 2>/dev/null || true
        return 0
    fi

    return 1
}

run_safe_editor() {
    local target_file="$1"
    local preferred_editor="${2:-${EDITOR:-vi}}"
    local editor_name

    editor_name=$(basename -- "$preferred_editor")
    case "$editor_name" in
        nano|vim|vi)
            if command -v "$editor_name" >/dev/null 2>&1; then
                "$editor_name" "$target_file"
                return $?
            fi
            ;;
    esac

    if command -v vi >/dev/null 2>&1; then
        vi "$target_file"
        return $?
    fi

    log_error "未找到可用编辑器"
    return 1
}

read_port_hopping_config() {
    local config_file="/etc/hysteria/port-hopping.conf"
    local line key value

    START_PORT=""
    END_PORT=""

    [[ -f "$config_file" ]] || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            START_PORT=*)
                value="${line#START_PORT=}"
                value="${value%\"}"
                value="${value#\"}"
                [[ "$value" =~ ^[0-9]+$ ]] && START_PORT="$value"
                ;;
            END_PORT=*)
                value="${line#END_PORT=}"
                value="${value%\"}"
                value="${value#\"}"
                [[ "$value" =~ ^[0-9]+$ ]] && END_PORT="$value"
                ;;
        esac
    done < "$config_file"

    [[ -n "$START_PORT" && -n "$END_PORT" ]]
}

update_auth_password_line() {
    local new_password="$1"
    local temp_file line in_obfs=false updated=false

    temp_file=$(create_temp_file)

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*obfs:[[:space:]]*$ ]]; then
            in_obfs=true
        elif [[ "$in_obfs" == true && "$line" =~ ^[^[:space:]#][^:]*:[[:space:]]* ]]; then
            in_obfs=false
        fi

        if [[ "$in_obfs" != true && "$updated" == false && "$line" =~ ^([[:space:]]*)password:[[:space:]]* ]]; then
            yaml_write_kv "${BASH_REMATCH[1]}" "password" "$new_password" >> "$temp_file"
            updated=true
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$HYSTERIA_CONFIG"

    if [[ "$updated" == true ]]; then
        replace_config_file_securely "$temp_file" "$HYSTERIA_CONFIG"
    else
        rm -f "$temp_file"
        return 1
    fi
}

update_listen_port_line() {
    local new_port="$1"
    local temp_file line updated=false

    temp_file=$(create_temp_file)

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^([[:space:]]*listen:[[:space:]]*[^:]*:)[0-9]+([[:space:]]*)$ ]]; then
            printf '%s%s%s\n' "${BASH_REMATCH[1]}" "$new_port" "${BASH_REMATCH[2]}" >> "$temp_file"
            updated=true
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$HYSTERIA_CONFIG"

    if [[ "$updated" == true ]]; then
        replace_config_file_securely "$temp_file" "$HYSTERIA_CONFIG"
    else
        rm -f "$temp_file"
        return 1
    fi
}

write_obfs_config() {
    local action="$1"
    local obfs_password="${2:-}"
    local temp_file line in_obfs=false inserted=false

    temp_file=$(create_temp_file)

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*obfs:[[:space:]]*$ ]]; then
            in_obfs=true
            continue
        fi

        if [[ "$in_obfs" == true ]]; then
            if [[ "$line" =~ ^[^[:space:]#][^:]*:[[:space:]]* ]] || [[ -z "$line" ]]; then
                in_obfs=false
            else
                continue
            fi
        fi

        echo "$line" >> "$temp_file"

        if [[ "$action" == "enable" && "$inserted" == false && "$line" =~ ^[[:space:]]*listen:[[:space:]]* ]]; then
            printf 'obfs:\n' >> "$temp_file"
            printf '  type: salamander\n' >> "$temp_file"
            yaml_write_kv "  " "password" "$obfs_password" >> "$temp_file"
            inserted=true
        fi
    done < "$HYSTERIA_CONFIG"

    if [[ "$action" == "enable" && "$inserted" == false ]]; then
        printf '\nobfs:\n' >> "$temp_file"
        printf '  type: salamander\n' >> "$temp_file"
        yaml_write_kv "  " "password" "$obfs_password" >> "$temp_file"
    fi

    replace_config_file_securely "$temp_file" "$HYSTERIA_CONFIG"
}

config_management() {
    while true; do
        clear
        echo -e "${CYAN}=== 配置管理 ===${NC}"
        echo ""
        
        if [[ ! -f "$HYSTERIA_CONFIG" ]]; then
            echo -e "${YELLOW}未找到配置文件${NC}"
            echo ""
            echo -e "${GREEN}1.${NC} 返回主菜单"
            echo -n -e "${BLUE}请选择: ${NC}"
            read -r choice
            break
        fi
        
        echo -e "${YELLOW}配置管理选项:${NC}"
        echo -e "${GREEN}1.${NC} 查看当前配置"
        echo -e "${GREEN}2.${NC} 修改认证密码"
        echo -e "${GREEN}3.${NC} 修改端口设置"
        echo -e "${GREEN}4.${NC} 修改混淆设置"
        echo -e "${GREEN}5.${NC} 端口跳跃配置"
        echo -e "${GREEN}6.${NC} 打开配置文件编辑"
        echo -e "${RED}0.${NC} 返回主菜单"
        echo ""
        echo -n -e "${BLUE}请选择操作 [0-6]: ${NC}"
        read -r choice
        
        case $choice in
            1) view_current_config ;;
            2) modify_auth_password ;;
            3) modify_port_settings ;;
            4) modify_obfs_settings ;;
            5) manage_port_hopping ;;
            6) edit_config_file ;;
            0) break ;;
            *)
                log_error "无效选项"
                sleep 1
                ;;
        esac
    done
}

view_current_config() {
    echo ""
    echo -e "${BLUE}当前配置文件内容:${NC}"
    echo -e "${CYAN}================================${NC}"
    cat "$HYSTERIA_CONFIG"
    echo -e "${CYAN}================================${NC}"
    wait_for_user
}

modify_auth_password() {
    echo ""
    echo -e "${BLUE}修改认证密码${NC}"
    
    # 获取当前密码
    local current_password
    current_password=$(grep -E "^\s*password:" "$HYSTERIA_CONFIG" | awk '{print $2}' | tr -d '"' || echo "未设置")
    echo "当前密码: $current_password"
    echo ""
    
    echo -n -e "${YELLOW}输入新密码 (回车生成随机密码): ${NC}"
    read -r -s new_password
    echo  # 补换行，因为 -s 不回显
    
    if [[ -z "$new_password" ]]; then
        new_password=$(openssl rand -base64 12 | tr -d "=+/")
        echo "生成的随机密码: $new_password"
    fi
    
    # 备份配置文件
    backup_config_securely "$HYSTERIA_CONFIG" "$HYSTERIA_CONFIG.bak" || {
        log_error "配置文件备份失败"
        wait_for_user
        return
    }
    
    # 修改密码（逐行重写并使用 YAML 安全标量）
    if ! update_auth_password_line "$new_password"; then
        log_error "认证密码更新失败"
        wait_for_user
        return
    fi
    
    log_success "认证密码已更新"
    echo ""
    echo -n -e "${YELLOW}是否重启服务以应用更改? [Y/n]: ${NC}"
    read -r restart
    if [[ ! $restart =~ ^[Nn]$ ]]; then
        systemctl restart "$SERVICE_NAME"
        log_success "服务已重启"
    fi
    
    wait_for_user
}

modify_port_settings() {
    echo ""
    echo -e "${BLUE}修改端口设置${NC}"
    
    # 获取当前端口
    local current_port
    current_port=$(grep -E "^\s*listen:" "$HYSTERIA_CONFIG" | awk -F':' '{print $3}' | tr -d ' ' || echo "443")
    echo "当前端口: $current_port"
    echo ""
    
    echo -n -e "${YELLOW}输入新端口 [1-65535]: ${NC}"
    read -r new_port
    
    if [[ ! "$new_port" =~ ^[0-9]+$ ]] || [[ "$new_port" -lt 1 ]] || [[ "$new_port" -gt 65535 ]]; then
        log_error "端口必须是 1-65535 之间的数字"
        wait_for_user
        return
    fi
    
    # 检查端口是否被占用
    if ss -tuln | grep -q ":$new_port "; then
        log_warn "端口 $new_port 似乎已被占用，请确认"
        echo -n -e "${YELLOW}是否继续? [y/N]: ${NC}"
        read -r continue
        if [[ ! $continue =~ ^[Yy]$ ]]; then
            return
        fi
    fi
    
    # 备份配置文件
    backup_config_securely "$HYSTERIA_CONFIG" "$HYSTERIA_CONFIG.bak" || {
        log_error "配置文件备份失败"
        wait_for_user
        return
    }
    
    # 修改 listen 端口，避免全文件替换误改其他 URL/注释/配置值
    if ! update_listen_port_line "$new_port"; then
        log_error "端口更新失败，未找到 listen 配置行"
        wait_for_user
        return
    fi
    
    log_success "端口已更新为: $new_port"
    
    # 检查端口跳跃配置并询问是否更新
    if safe_source_script "$SCRIPTS_DIR/config.sh" "配置脚本"; then
        if check_port_hopping_status; then
            echo ""
            echo -e "${YELLOW}检测到已配置端口跳跃${NC}"
            local hopping_info
            hopping_info=$(get_port_hopping_info)
            if [[ -n "$hopping_info" ]]; then
                echo "   $hopping_info"
            fi
            echo ""
            echo -n -e "${YELLOW}是否更新端口跳跃的目标端口为 $new_port? [Y/n]: ${NC}"
            read -r update_hopping
            if [[ ! $update_hopping =~ ^[Nn]$ ]]; then
                # 安全读取当前端口跳跃配置：只解析 START_PORT/END_PORT，不 source 配置文件
                if read_port_hopping_config; then
                    echo -e "${BLUE}正在更新端口跳跃配置...${NC}"
                    clear_port_hopping_rules
                    if add_port_hopping_rules "$START_PORT" "$END_PORT" "$new_port"; then
                        log_success "端口跳跃配置已更新为: $START_PORT-$END_PORT -> $new_port"
                    else
                        log_error "端口跳跃配置更新失败"
                    fi
                else
                    log_error "端口跳跃配置读取失败"
                fi
            fi
        fi
    fi
    
    echo ""
    echo -n -e "${YELLOW}是否重启服务以应用更改? [Y/n]: ${NC}"
    read -r restart
    if [[ ! $restart =~ ^[Nn]$ ]]; then
        systemctl restart "$SERVICE_NAME"
        log_success "服务已重启"
    fi
    
    wait_for_user
}

modify_obfs_settings() {
    echo ""
    echo -e "${BLUE}修改混淆设置${NC}"
    
    # 检查当前混淆配置
    local current_obfs
    current_obfs=$(grep -E "^\s*type: salamander" "$HYSTERIA_CONFIG" && echo "启用" || echo "禁用")
    echo "当前混淆状态: $current_obfs"
    
    if [[ "$current_obfs" == "启用" ]]; then
        local current_obfs_password
        current_obfs_password=$(grep -A1 "type: salamander" "$HYSTERIA_CONFIG" | grep "password:" | awk '{print $2}' | tr -d '"')
        echo "当前混淆密码: $current_obfs_password"
    fi
    
    echo ""
    echo -e "${YELLOW}混淆选项:${NC}"
    echo "1. 启用混淆"
    echo "2. 禁用混淆"
    echo "3. 修改混淆密码"
    echo "0. 返回"
    echo ""
    echo -n -e "${BLUE}请选择: ${NC}"
    read -r obfs_choice
    
    case $obfs_choice in
        1|2|3)
            # 备份配置文件
            backup_config_securely "$HYSTERIA_CONFIG" "$HYSTERIA_CONFIG.bak" || {
                log_error "配置文件备份失败"
                wait_for_user
                return
            }
            
            case $obfs_choice in
                1)
                    echo -n -e "${YELLOW}输入混淆密码 (回车生成随机密码): ${NC}"
                    read -r -s obfs_password
                    echo  # 补换行，因为 -s 不回显
                    if [[ -z "$obfs_password" ]]; then
                        obfs_password=$(openssl rand -base64 12 | tr -d "=+/")
                        echo "生成的随机密码: $obfs_password"
                    fi
                    
                    # 添加混淆配置
                    if write_obfs_config "enable" "$obfs_password"; then
                        log_success "混淆已启用"
                    else
                        log_error "混淆启用失败"
                        wait_for_user
                        return
                    fi
                    ;;
                2)
                    # 删除混淆配置
                    if write_obfs_config "disable"; then
                        log_success "混淆已禁用"
                    else
                        log_error "混淆禁用失败"
                        wait_for_user
                        return
                    fi
                    ;;
                3)
                    if [[ "$current_obfs" == "禁用" ]]; then
                        log_error "当前未启用混淆"
                        wait_for_user
                        return
                    fi
                    
                    echo -n -e "${YELLOW}输入新的混淆密码: ${NC}"
                    read -r -s new_obfs_password
                    echo  # 补换行，因为 -s 不回显
                    
                    if [[ -z "$new_obfs_password" ]]; then
                        log_error "混淆密码不能为空"
                        wait_for_user
                        return
                    fi
                    
                    # 修改混淆密码
                    if write_obfs_config "enable" "$new_obfs_password"; then
                        log_success "混淆密码已更新"
                    else
                        log_error "混淆密码更新失败"
                        wait_for_user
                        return
                    fi
                    ;;
            esac
            
            echo ""
            echo -n -e "${YELLOW}是否重启服务以应用更改? [Y/n]: ${NC}"
            read -r restart
            if [[ ! $restart =~ ^[Nn]$ ]]; then
                systemctl restart "$SERVICE_NAME"
                log_success "服务已重启"
            fi
            ;;
        0)
            return
            ;;
        *)
            log_error "无效选择"
            ;;
    esac
    
    wait_for_user
}

edit_config_file() {
    echo ""
    echo -e "${BLUE}打开配置文件编辑${NC}"
    echo "配置文件路径: $HYSTERIA_CONFIG"
    echo ""
    echo -e "${YELLOW}编辑器选项:${NC}"
    echo "1. 使用 nano (推荐新手)"
    echo "2. 使用 vim"
    echo "3. 使用系统默认编辑器"
    echo "0. 返回"
    echo ""
    echo -n -e "${BLUE}请选择编辑器: ${NC}"
    read -r editor_choice
    
    # 备份配置文件
    backup_config_securely "$HYSTERIA_CONFIG" "$HYSTERIA_CONFIG.bak" || {
        log_error "配置文件备份失败"
        wait_for_user
        return
    }
    log_info "已备份配置文件"
    
    case $editor_choice in
        1)
            if command -v nano &> /dev/null; then
                run_safe_editor "$HYSTERIA_CONFIG" "nano"
            else
                log_error "nano 未安装，使用安全默认编辑器"
                run_safe_editor "$HYSTERIA_CONFIG" "vi"
            fi
            ;;
        2)
            if command -v vim &> /dev/null; then
                run_safe_editor "$HYSTERIA_CONFIG" "vim"
            else
                log_error "vim 未安装，使用安全默认编辑器"
                run_safe_editor "$HYSTERIA_CONFIG" "vi"
            fi
            ;;
        3)
            run_safe_editor "$HYSTERIA_CONFIG" "${EDITOR:-vi}"
            ;;
        0)
            return
            ;;
        *)
            log_error "无效选择，使用安全默认编辑器"
            run_safe_editor "$HYSTERIA_CONFIG" "vi"
            ;;
    esac
    
    echo ""
    echo -n -e "${YELLOW}配置已修改，是否重启服务以应用更改? [Y/n]: ${NC}"
    read -r restart
    if [[ ! $restart =~ ^[Nn]$ ]]; then
        if systemctl restart "$SERVICE_NAME"; then
            log_success "服务已重启"
        else
            log_error "服务重启失败，请检查配置文件语法"
            echo -n -e "${YELLOW}是否恢复备份配置? [Y/n]: ${NC}"
            read -r restore
            if [[ ! $restore =~ ^[Nn]$ ]]; then
                cp "$HYSTERIA_CONFIG.bak" "$HYSTERIA_CONFIG"
                chmod 600 "$HYSTERIA_CONFIG" 2>/dev/null || true
                systemctl restart "$SERVICE_NAME"
                log_info "已恢复备份配置"
            fi
        fi
    fi
    
    wait_for_user
}

