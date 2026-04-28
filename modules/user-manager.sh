#!/bin/bash
# 多用户管理模块
#
# 依赖: common.sh, config.sh
# 导出函数: user_management, add_user, delete_user, list_users, modify_user_password, toggle_auth_mode

# 转义字符串中 sed 替换表达式的特殊字符（用于替换部分）
_escape_sed_replace() {
    printf '%s' "$1" | sed 's/[\\&|]/\\&/g'
}

# 转义字符串中 sed 搜索/匹配部分的特殊字符
_escape_sed_pattern() {
    printf '%s' "$1" | sed 's/[[\.*^$(){}+?|\/]/\\&/g'
}

# ========== 用户管理菜单 ==========
user_management() {
    while true; do
        clear
        echo -e "${CYAN}================================================${NC}"
        echo -e "${CYAN}           Hysteria2 多用户管理${NC}"
        echo -e "${CYAN}================================================${NC}"
        echo ""

        # 显示当前认证模式
        local auth_mode
        auth_mode=$(get_auth_mode)
        if [[ "$auth_mode" == "userpass" ]]; then
            echo -e "${GREEN}当前认证模式: 多用户 (userpass)${NC}"
            local user_count
            user_count=$(count_users)
            echo -e "已配置用户数: ${CYAN}$user_count${NC}"
        else
            echo -e "${YELLOW}当前认证模式: 单密码 (password)${NC}"
            echo -e "${YELLOW}提示: 切换到多用户模式可管理多个用户${NC}"
        fi
        echo ""

        echo -e "${YELLOW}请选择操作:${NC}"
        echo ""
        echo -e "${GREEN} 1.${NC} 查看用户列表"
        echo -e "${GREEN} 2.${NC} 添加用户"
        echo -e "${GREEN} 3.${NC} 删除用户"
        echo -e "${GREEN} 4.${NC} 修改用户密码"
        echo -e "${GREEN} 5.${NC} 切换认证模式（单密码 ↔ 多用户）"
        echo -e "${CYAN} 6.${NC} 批量添加用户"
        echo -e "${RED} 0.${NC} 返回主菜单"
        echo ""
        echo -n -e "${BLUE}请输入选项 [0-6]: ${NC}"

        local choice
        read -r choice

        case $choice in
            1) list_users ;;
            2) add_user ;;
            3) delete_user ;;
            4) modify_user_password ;;
            5) toggle_auth_mode ;;
            6) batch_add_users ;;
            0) return 0 ;;
            *) echo -e "${RED}无效选项${NC}" ;;
        esac

        echo ""
        echo -n "按回车键继续..."
        read -r
    done
}

# ========== 获取当前认证模式 ==========
get_auth_mode() {
    if [[ ! -f "$HYSTERIA_CONFIG" ]]; then
        echo "none"
        return 1
    fi

    # 检查是否有 userpass 字段
    if grep -q "type: userpass" "$HYSTERIA_CONFIG" 2>/dev/null; then
        echo "userpass"
    elif grep -q "type: password" "$HYSTERIA_CONFIG" 2>/dev/null; then
        echo "password"
    else
        echo "unknown"
    fi
}

# ========== 统计用户数 ==========
count_users() {
    if [[ ! -f "$HYSTERIA_CONFIG" ]]; then
        echo "0"
        return
    fi

    local auth_mode
    auth_mode=$(get_auth_mode)

    if [[ "$auth_mode" == "userpass" ]]; then
        # 统计 userpass 下的用户数
        local in_userpass=false
        local count=0
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*userpass: ]]; then
                in_userpass=true
                continue
            fi
            if $in_userpass; then
                # userpass 段下的缩进行，形如 "    username: password"
                if [[ "$line" =~ ^[[:space:]]+[a-zA-Z0-9_-]+:.+ ]]; then
                    # 排除其他顶级字段
                    if [[ ! "$line" =~ ^[[:space:]]*(type|password): ]]; then
                        ((count++))
                    fi
                else
                    # 缩进结束，退出 userpass 段
                    if [[ "$line" =~ ^[a-zA-Z] ]]; then
                        break
                    fi
                fi
            fi
        done < "$HYSTERIA_CONFIG"
        echo "$count"
    else
        echo "1"
    fi
}

# ========== 获取所有用户 ==========
get_all_users() {
    if [[ ! -f "$HYSTERIA_CONFIG" ]]; then
        return 1
    fi

    local auth_mode
    auth_mode=$(get_auth_mode)

    if [[ "$auth_mode" == "userpass" ]]; then
        local in_userpass=false
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*userpass: ]]; then
                in_userpass=true
                continue
            fi
            if $in_userpass; then
                if [[ "$line" =~ ^[[:space:]]+([a-zA-Z0-9_-]+):(.+) ]]; then
                    local username="${BASH_REMATCH[1]}"
                    if [[ "$username" != "type" && "$username" != "password" ]]; then
                        echo "$username"
                    fi
                elif [[ "$line" =~ ^[a-zA-Z] ]]; then
                    break
                fi
            fi
        done < "$HYSTERIA_CONFIG"
    elif [[ "$auth_mode" == "password" ]]; then
        echo "default"
    fi
}

# ========== 查看用户列表 ==========
list_users() {
    echo -e "${CYAN}=== 用户列表 ===${NC}"
    echo ""

    local auth_mode
    auth_mode=$(get_auth_mode)

    if [[ "$auth_mode" == "password" ]]; then
        local password
        password=$(grep -A1 "type: password" "$HYSTERIA_CONFIG" 2>/dev/null | grep "password:" | awk '{print $2}')
        echo -e "认证模式: ${YELLOW}单密码${NC}"
        echo -e "密码: ${GREEN}${password:-未设置}${NC}"
        echo ""
        echo -e "${YELLOW}提示: 使用「切换认证模式」可开启多用户支持${NC}"
        return 0
    fi

    if [[ "$auth_mode" != "userpass" ]]; then
        echo -e "${RED}无法识别认证模式或配置文件不存在${NC}"
        return 1
    fi

    echo -e "认证模式: ${GREEN}多用户 (userpass)${NC}"
    echo ""
    echo -e "${YELLOW}用户名                密码${NC}"
    echo -e "${YELLOW}─────────────────────────────────${NC}"

    local in_userpass=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*userpass: ]]; then
            in_userpass=true
            continue
        fi
        if $in_userpass; then
            if [[ "$line" =~ ^[[:space:]]+([a-zA-Z0-9_-]+):[[:space:]]*(.+) ]]; then
                local username="${BASH_REMATCH[1]}"
                local password="${BASH_REMATCH[2]}"
                if [[ "$username" != "type" && "$username" != "password" ]]; then
                    echo -e "  ${GREEN}${username}${NC}          ${password}"
                fi
            elif [[ "$line" =~ ^[a-zA-Z] ]]; then
                break
            fi
        fi
    done < "$HYSTERIA_CONFIG"
}

# ========== 添加用户 ==========
add_user() {
    echo -e "${CYAN}=== 添加用户 ===${NC}"
    echo ""

    local auth_mode
    auth_mode=$(get_auth_mode)

    if [[ "$auth_mode" == "password" ]]; then
        echo -e "${YELLOW}当前为单密码模式，需要先切换到多用户模式${NC}"
        echo -n "是否现在切换？[y/N]: "
        local confirm
        read -r confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            switch_to_userpass
        else
            return 1
        fi
    fi

    # 输入用户名
    echo -n "请输入用户名（字母/数字/下划线/连字符）: "
    local username
    read -r username

    # 验证用户名
    if [[ -z "$username" ]]; then
        log_error "用户名不能为空"
        return 1
    fi

    if [[ ! "$username" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "用户名只能包含字母、数字、下划线和连字符"
        return 1
    fi

    # 检查用户是否已存在
    if get_all_users | grep -q "^${username}$"; then
        log_error "用户 '$username' 已存在"
        return 1
    fi

    # 输入密码
    echo -n "请输入密码（留空自动生成）: "
    local password
    read -r -s password
    echo  # 补换行

    if [[ -z "$password" ]]; then
        password=$(generate_password 16)
        echo -e "${GREEN}已自动生成密码: $password${NC}"
    fi

    # 确认添加
    echo ""
    echo -e "用户名: ${CYAN}$username${NC}"
    echo -e "密码:   ${CYAN}$password${NC}"
    echo -n "确认添加？[y/N]: "
    local confirm
    read -r confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "已取消"
        return 0
    fi

    # 添加用户到配置文件
    add_user_to_config "$username" "$password"

    if [[ $? -eq 0 ]]; then
        log_success "用户 '$username' 添加成功"
        ask_restart_service
    else
        log_error "添加用户失败"
    fi
}

# ========== 批量添加用户 ==========
batch_add_users() {
    echo -e "${CYAN}=== 批量添加用户 ===${NC}"
    echo ""

    local auth_mode
    auth_mode=$(get_auth_mode)

    if [[ "$auth_mode" == "password" ]]; then
        echo -e "${YELLOW}当前为单密码模式，需要先切换到多用户模式${NC}"
        echo -n "是否现在切换？[y/N]: "
        local confirm
        read -r confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            switch_to_userpass
        else
            return 1
        fi
    fi

    echo -n "请输入要添加的用户数量: "
    local count
    read -r count

    if [[ ! "$count" =~ ^[0-9]+$ ]] || [[ "$count" -lt 1 ]] || [[ "$count" -gt 100 ]]; then
        log_error "数量无效（1-100）"
        return 1
    fi

    echo -n "用户名前缀（留空使用 user）: "
    local prefix
    read -r prefix
    prefix="${prefix:-user}"

    if [[ ! "$prefix" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "前缀只能包含字母、数字、下划线和连字符"
        return
    fi

    echo ""
    log_info "将添加 $count 个用户，前缀: $prefix"
    echo -n "确认？[y/N]: "
    local confirm
    read -r confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "已取消"
        return 0
    fi

    # 确定起始编号
    local start_num=1
    while get_all_users | grep -q "^${prefix}${start_num}$"; do
        ((start_num++))
    done

    local added=0
    for ((i=0; i<count; i++)); do
        local num
        num=$((start_num + i))
        local username="${prefix}${num}"
        local password
        password=$(generate_password 16)

        if add_user_to_config "$username" "$password"; then
            ((added++))
            echo -e "  ${GREEN}$username${NC}: $password"
        fi
    done

    log_success "成功添加 $added 个用户"
    echo ""
    echo -e "${YELLOW}请妥善保存以上用户信息！${NC}"

    if [[ $added -gt 0 ]]; then
        ask_restart_service
    fi
}

# ========== 删除用户 ==========
delete_user() {
    echo -e "${CYAN}=== 删除用户 ===${NC}"
    echo ""

    local auth_mode
    auth_mode=$(get_auth_mode)

    if [[ "$auth_mode" != "userpass" ]]; then
        log_error "当前不是多用户模式"
        return 1
    fi

    local user_count
    user_count=$(count_users)

    if [[ "$user_count" -le 1 ]]; then
        log_error "至少需要保留一个用户，无法删除"
        return 1
    fi

    # 显示用户列表
    list_users
    echo ""
    echo -n "请输入要删除的用户名: "
    local username
    read -r username

    if [[ -z "$username" ]]; then
        log_error "用户名不能为空"
        return 1
    fi

    # 检查用户是否存在
    if ! get_all_users | grep -q "^${username}$"; then
        log_error "用户 '$username' 不存在"
        return 1
    fi

    echo -e "${RED}⚠️  确认删除用户 '$username'？此操作不可恢复！${NC}"
    echo -n "确认？[y/N]: "
    local confirm
    read -r confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "已取消"
        return 0
    fi

    # 从配置文件中删除用户
    remove_user_from_config "$username"

    if [[ $? -eq 0 ]]; then
        log_success "用户 '$username' 已删除"
        ask_restart_service
    else
        log_error "删除用户失败"
    fi
}

# ========== 修改用户密码 ==========
modify_user_password() {
    echo -e "${CYAN}=== 修改用户密码 ===${NC}"
    echo ""

    local auth_mode
    auth_mode=$(get_auth_mode)

    if [[ "$auth_mode" == "password" ]]; then
        # 单密码模式，直接修改密码
        echo -e "${YELLOW}当前为单密码模式${NC}"
        echo -n "请输入新密码（留空自动生成）: "
        local new_password
        read -r -s new_password
        echo  # 补换行

        if [[ -z "$new_password" ]]; then
            new_password=$(generate_password 16)
            echo -e "${GREEN}已自动生成密码: $new_password${NC}"
        fi

        # 备份配置
        cp "$HYSTERIA_CONFIG" "${HYSTERIA_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"

        # 逐行重写密码，避免密码进入 sed 表达式或裸 YAML 标量
        local temp_file
        temp_file=$(create_temp_file)
        local password_updated=false
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ ^([[:space:]]*)password:[[:space:]]* ]]; then
                yaml_write_kv "${BASH_REMATCH[1]}" "password" "$new_password" >> "$temp_file"
                password_updated=true
            else
                echo "$line" >> "$temp_file"
            fi
        done < "$HYSTERIA_CONFIG"

        if [[ "$password_updated" == true ]] && replace_config_file_securely "$temp_file" "$HYSTERIA_CONFIG"; then
            log_success "密码已修改"
            ask_restart_service
            return 0
        fi

        rm -f "$temp_file"
        log_error "密码修改失败"
        return 1
    fi

    # 多用户模式
    list_users
    echo ""
    echo -n "请输入要修改密码的用户名: "
    local username
    read -r username

    if ! get_all_users | grep -q "^${username}$"; then
        log_error "用户 '$username' 不存在"
        return 1
    fi

    echo -n "请输入新密码（留空自动生成）: "
    local new_password
    read -r -s new_password
    echo  # 补换行

    if [[ -z "$new_password" ]]; then
        new_password=$(generate_password 16)
        echo -e "${GREEN}已自动生成密码: $new_password${NC}"
    fi

    # 备份配置
    cp "$HYSTERIA_CONFIG" "${HYSTERIA_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"

    # 逐行重写用户密码，避免用户名/密码进入 sed 表达式
    local temp_file
    temp_file=$(create_temp_file)
    local password_updated=false
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^([[:space:]]*)([a-zA-Z0-9_-]+):[[:space:]]* ]]; then
            local current_user="${BASH_REMATCH[2]}"
            if [[ "$current_user" == "$username" ]]; then
                yaml_write_kv "${BASH_REMATCH[1]}" "$username" "$new_password" >> "$temp_file"
                password_updated=true
                continue
            fi
        fi
        echo "$line" >> "$temp_file"
    done < "$HYSTERIA_CONFIG"

    if [[ "$password_updated" == true ]] && replace_config_file_securely "$temp_file" "$HYSTERIA_CONFIG"; then
        log_success "用户 '$username' 密码已修改"
        ask_restart_service
        return 0
    fi

    rm -f "$temp_file"
    log_error "用户密码修改失败"
    return 1
}

# ========== 切换认证模式 ==========
toggle_auth_mode() {
    echo -e "${CYAN}=== 切换认证模式 ===${NC}"
    echo ""

    local auth_mode
    auth_mode=$(get_auth_mode)

    if [[ "$auth_mode" == "password" ]]; then
        echo -e "${YELLOW}当前模式: 单密码 → 切换到多用户${NC}"
        echo ""
        echo -e "切换后配置将变为:"
        echo -e "  ${RED}auth:${NC}"
        echo -e "  ${RED}  type: password${NC}     →  ${GREEN}type: userpass${NC}"
        echo -e "  ${RED}  password: xxx${NC}      →  ${GREEN}userpass:${NC}"
        echo -e "                            ${GREEN}  user1: pass1${NC}"
        echo -e "                            ${GREEN}  user2: pass2${NC}"
        echo ""
        echo -e "${RED}⚠️  切换后所有客户端需要重新配置！${NC}"
        echo -n "确认切换？[y/N]: "
        local confirm
        read -r confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            switch_to_userpass
        fi
    elif [[ "$auth_mode" == "userpass" ]]; then
        echo -e "${YELLOW}当前模式: 多用户 → 切换到单密码${NC}"
        echo ""
        echo -e "${RED}⚠️  切换后所有用户信息将丢失！${NC}"
        echo -e "${RED}⚠️  所有客户端需要重新配置！${NC}"
        echo -n "确认切换？[y/N]: "
        local confirm
        read -r confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            switch_to_password
        fi
    else
        log_error "无法识别当前认证模式"
    fi
}

# ========== 切换到多用户模式 ==========
switch_to_userpass() {
    if [[ ! -f "$HYSTERIA_CONFIG" ]]; then
        log_error "配置文件不存在"
        return 1
    fi

    # 备份
    cp "$HYSTERIA_CONFIG" "${HYSTERIA_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    chmod 600 "${HYSTERIA_CONFIG}.backup."* 2>/dev/null || true

    # 获取当前密码
    local current_password
    current_password=$(grep "password:" "$HYSTERIA_CONFIG" | grep -v "type:" | head -1 | awk '{print $2}')

    # 使用逐行重写进行 YAML 转换
    # 将 auth 段从 password 改为 userpass
    local temp_file
    temp_file=$(create_temp_file)

    local in_auth=false
    local auth_indent=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^([[:space:]]*)auth: ]]; then
            in_auth=true
            auth_indent="${BASH_REMATCH[1]}"
            echo "${auth_indent}auth:" >> "$temp_file"
            echo "${auth_indent}  type: userpass" >> "$temp_file"
            echo "${auth_indent}  userpass:" >> "$temp_file"
            yaml_write_kv "${auth_indent}    " "user1" "${current_password:-changeme}" >> "$temp_file"
            continue
        fi

        if $in_auth; then
            # 跳过旧的 auth 内容
            if [[ "$line" =~ ^[a-zA-Z] ]] || [[ "$line" =~ ^$ ]]; then
                in_auth=false
                echo "$line" >> "$temp_file"
            fi
            # 跳过 auth 段内的旧行
            continue
        fi

        echo "$line" >> "$temp_file"
    done < "$HYSTERIA_CONFIG"

    replace_config_file_securely "$temp_file" "$HYSTERIA_CONFIG"

    log_success "已切换到多用户模式"
    echo -e "默认用户: ${GREEN}user1${NC}，密码: ${GREEN}${current_password:-changeme}${NC}"
    ask_restart_service
}

# ========== 切换到单密码模式 ==========
switch_to_password() {
    if [[ ! -f "$HYSTERIA_CONFIG" ]]; then
        log_error "配置文件不存在"
        return 1
    fi

    # 备份
    cp "$HYSTERIA_CONFIG" "${HYSTERIA_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    chmod 600 "${HYSTERIA_CONFIG}.backup."* 2>/dev/null || true

    # 使用第一个用户的密码作为单密码
    local first_password
    first_password=$(get_all_users | head -1 | xargs -I{} grep "^\s*{}:" "$HYSTERIA_CONFIG" | awk '{print $2}')

    local temp_file
    temp_file=$(create_temp_file)

    local in_auth=false
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^([[:space:]]*)auth: ]]; then
            in_auth=true
            local auth_indent="${BASH_REMATCH[1]}"
            echo "${auth_indent}auth:" >> "$temp_file"
            echo "${auth_indent}  type: password" >> "$temp_file"
            yaml_write_kv "${auth_indent}  " "password" "${first_password:-changeme}" >> "$temp_file"
            continue
        fi

        if $in_auth; then
            if [[ "$line" =~ ^[a-zA-Z] ]] || [[ "$line" =~ ^$ ]]; then
                in_auth=false
                echo "$line" >> "$temp_file"
            fi
            continue
        fi

        echo "$line" >> "$temp_file"
    done < "$HYSTERIA_CONFIG"

    replace_config_file_securely "$temp_file" "$HYSTERIA_CONFIG"

    log_success "已切换到单密码模式"
    echo -e "密码: ${GREEN}${first_password:-changeme}${NC}"
    ask_restart_service
}

# ========== 添加用户到配置文件 ==========
add_user_to_config() {
    local username="$1"
    local password="$2"

    if [[ ! -f "$HYSTERIA_CONFIG" ]]; then
        log_error "配置文件不存在"
        return 1
    fi

    # 备份
    cp "$HYSTERIA_CONFIG" "${HYSTERIA_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"

    local temp_file
    temp_file=$(create_temp_file)

    local in_userpass=false
    local added=false
    while IFS= read -r line; do
        echo "$line" >> "$temp_file"

        if [[ "$line" =~ ^[[:space:]]*userpass: ]]; then
            in_userpass=true
            # 在 userpass: 后面添加新用户
            local indent=""
            indent=$(echo "$line" | sed 's/userpass:.*/  /')
            yaml_write_kv "$indent" "$username" "$password" >> "$temp_file"
            added=true
        fi
    done < "$HYSTERIA_CONFIG"

    if $added; then
        replace_config_file_securely "$temp_file" "$HYSTERIA_CONFIG"
        return 0
    else
        rm -f "$temp_file"
        log_error "未找到 userpass 段"
        return 1
    fi
}

# ========== 从配置文件删除用户 ==========
remove_user_from_config() {
    local username="$1"

    if [[ ! -f "$HYSTERIA_CONFIG" ]]; then
        return 1
    fi

    # 备份
    cp "$HYSTERIA_CONFIG" "${HYSTERIA_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"

    # 删除匹配的用户行，避免用户名直接进入 grep 正则
    local temp_file
    temp_file=$(create_temp_file)
    local removed=false
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9_-]+): ]]; then
            if [[ "${BASH_REMATCH[1]}" == "$username" ]]; then
                removed=true
                continue
            fi
        fi
        echo "$line" >> "$temp_file"
    done < "$HYSTERIA_CONFIG"

    if [[ "$removed" == true ]] && replace_config_file_securely "$temp_file" "$HYSTERIA_CONFIG"; then
        return 0
    fi

    rm -f "$temp_file"
    return 1
}
