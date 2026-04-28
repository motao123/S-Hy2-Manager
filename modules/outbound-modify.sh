#!/bin/bash
# 出站规则修改
#
# 依赖: common.sh, outbound-core.sh
# 导出函数: modify_outbound_rule, modify_rule_name, modify_server_address, modify_username, modify_password

outbound_name_matches_line() {
    local line="$1" rule_name="$2"
    local current_name

    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*(.*)$ ]]; then
        current_name=$(yaml_unquote_scalar "${BASH_REMATCH[1]}")
        [[ "$current_name" == "$rule_name" ]]
        return
    fi

    return 1
}

extract_outbound_field_value() {
    local rule_name="$1" field_pattern="$2"
    local line in_target_rule=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        if outbound_name_matches_line "$line" "$rule_name"; then
            in_target_rule=true
            continue
        elif [[ "$in_target_rule" == true ]]; then
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name: ]] || [[ "$line" =~ ^[[:space:]]*[a-zA-Z]+:[[:space:]]*$ ]] && [[ ! "$line" =~ ^[[:space:]]*(type|direct|socks5|http|addr|url|mode|username|password|insecure): ]]; then
                in_target_rule=false
            elif [[ "$line" =~ ^[[:space:]]*($field_pattern):[[:space:]]*(.*)$ ]]; then
                yaml_unquote_scalar "${BASH_REMATCH[2]}"
                return 0
            fi
        fi
    done < "$HYSTERIA_CONFIG"

    return 1
}

rules_library_key_matches_line() {
    local line="$1" rule_name="$2"
    local current_key

    if [[ "$line" =~ ^[[:space:]]{2}([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*$ ]]; then
        current_key="${BASH_REMATCH[1]}"
        [[ "$current_key" == "$rule_name" ]]
        return
    fi

    return 1
}

rules_library_value_for_rule() {
    local rule_name="$1" field_name="$2"
    local line in_rule=false in_config=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        if rules_library_key_matches_line "$line" "$rule_name"; then
            in_rule=true
            in_config=false
            continue
        elif [[ "$in_rule" == true ]]; then
            if [[ "$line" =~ ^[[:space:]]{2}[a-zA-Z_][a-zA-Z0-9_]*:[[:space:]]*$ ]]; then
                return 1
            elif [[ "$line" =~ ^[[:space:]]*config:[[:space:]]*$ ]]; then
                in_config=true
                continue
            elif [[ "$field_name" == "type" && "$line" =~ ^[[:space:]]*type:[[:space:]]*(.*)$ ]]; then
                yaml_unquote_scalar "${BASH_REMATCH[1]}"
                return 0
            elif [[ "$in_config" == true && "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*(.*)$ ]]; then
                if [[ "${BASH_REMATCH[1]}" == "$field_name" ]]; then
                    yaml_unquote_scalar "${BASH_REMATCH[2]}"
                    return 0
                fi
            fi
        fi
    done < "$RULES_LIBRARY"

    return 1
}

modify_outbound_config() {
    log_info "修改现有出站配置"

    echo -e "${BLUE}=== 修改出站配置 ===${NC}"
    echo ""

    # 检查是否有出站配置
    if ! grep -q "^outbounds:" "$HYSTERIA_CONFIG"; then
        echo -e "${YELLOW}当前没有出站配置可修改${NC}"
        echo "请先添加出站规则"
        wait_for_user
        return
    fi

    # 列出现有的出站配置
    echo -e "${GREEN}当前出站规则：${NC}"
    local outbound_names=($(grep -A 1 "^[[:space:]]*-[[:space:]]*name:" "$HYSTERIA_CONFIG" | grep "name:" | sed 's/.*name:[[:space:]]*//' | tr -d '"'))

    if [[ ${#outbound_names[@]} -eq 0 ]]; then
        echo -e "${YELLOW}没有找到出站规则名称${NC}"
        wait_for_user
        return
    fi

    for i in "${!outbound_names[@]}"; do
        echo "$((i+1)). ${outbound_names[$i]}"
    done
    echo ""

    read -r -p "请选择要修改的出站规则 [1-${#outbound_names[@]}]: " choice

    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt ${#outbound_names[@]} ]]; then
        log_error "无效选择"
        return
    fi

    local selected_outbound
    selected_outbound="${outbound_names[$((choice-1))]}"

    echo -e "${BLUE}修改选项：${NC}"
    echo "1. 修改规则名称"
    echo "2. 修改服务器地址"
    echo "3. 修改用户名"
    echo "4. 修改密码"
    echo "5. 删除此出站规则"
    echo ""

    read -r -p "请选择操作 [1-5]: " modify_choice

    case $modify_choice in
        1) modify_rule_name "$selected_outbound" ;;
        2) modify_server_address "$selected_outbound" ;;
        3) modify_username "$selected_outbound" ;;
        4) modify_password "$selected_outbound" ;;
        5) delete_outbound_rule "$selected_outbound" ;;
        *)
            log_error "无效选择"
            ;;
    esac
}

modify_outbound_rule() {
    init_rules_library

    echo -e "${BLUE}=== 修改出站规则 ===${NC}"
    echo ""

    # 列出规则库中的规则 - 使用可靠的grep方法
    local rules=()
    local rule_count=0

    while IFS= read -r rule_name; do
        if [[ -n "$rule_name" ]]; then
            rules+=("$rule_name")
            ((rule_count++))
            echo "$rule_count. $rule_name"
        fi
    done < <(grep -o "^[[:space:]]\{2\}[a-zA-Z_][a-zA-Z0-9_]*:" "$RULES_LIBRARY" | sed 's/^[[:space:]]\{2\}\([^:]*\):.*/\1/')

    if [[ ${#rules[@]} -eq 0 ]]; then
        echo -e "${YELLOW}没有可修改的规则${NC}"
        wait_for_user
        return
    fi

    echo ""
    read -r -p "请选择要修改的规则 [1-$rule_count]: " choice

    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt $rule_count ]]; then
        log_error "无效选择"
        return 1
    fi

    local selected_rule
    selected_rule="${rules[$((choice-1))]}"

    echo ""
    echo "修改选项："
    echo "1. 修改描述"
    echo "2. 修改配置参数"
    echo ""

    read -r -p "请选择操作 [1-2]: " modify_choice

    case $modify_choice in
        1)
            # 获取当前描述
            local current_desc
            current_desc=$(awk -v rule="$selected_rule" '
            BEGIN { in_rule = 0 }
            $0 ~ "^[[:space:]]*" rule ":[[:space:]]*$" { in_rule = 1; next }
            in_rule && /^[[:space:]]*description:/ {
                gsub(/^[[:space:]]*description:[[:space:]]*"?/, "");
                gsub(/"?[[:space:]]*$/, "");
                print $0;
                exit
            }
            in_rule && /^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*:[[:space:]]*$/ { in_rule = 0 }
            ' "$RULES_LIBRARY")

            echo "当前描述: $current_desc"
            read -r -p "新的描述: " new_desc

            if [[ -n "$new_desc" ]]; then
                # 更新描述
                local quoted_desc
                quoted_desc=$(yaml_quote_scalar "$new_desc")
                awk -v rule="$selected_rule" -v desc="$quoted_desc" '
                BEGIN { in_rule = 0 }
                $0 ~ "^[[:space:]]*" rule ":[[:space:]]*$" { in_rule = 1; print; next }
                in_rule && /^[[:space:]]*description:/ {
                    indent = substr($0, 1, match($0, /[^ ]/) - 1)
                    print indent "description: " desc
                    next
                }
                in_rule && /^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*:[[:space:]]*$/ { in_rule = 0 }
                { print }
                ' "$RULES_LIBRARY" > "${RULES_LIBRARY}.tmp" && replace_config_file_securely "${RULES_LIBRARY}.tmp" "$RULES_LIBRARY"

                log_success "描述已更新"
            fi
            ;;
        2)
            # 修改配置参数
            modify_rule_parameters "$selected_rule"
            ;;
        *)
            log_error "无效选择"
            ;;
    esac

    wait_for_user
}

modify_rule_name() {
    local old_name="$1"

    echo -e "${BLUE}=== 修改规则名称 ===${NC}"
    echo "当前规则名称: ${CYAN}$old_name${NC}"
    echo ""

    read -r -p "请输入新的规则名称: " new_name

    if [[ -z "$new_name" ]]; then
        log_error "规则名称不能为空"
        return
    fi

    if [[ ! "$new_name" =~ ^[a-zA-Z0-9_]+$ ]]; then
        log_error "规则名称只能包含字母、数字和下划线"
        return
    fi

    # 检查新名称是否已存在
    local existing_name
    while IFS= read -r existing_name; do
        if [[ "$(yaml_unquote_scalar "$existing_name")" == "$new_name" ]]; then
            log_error "规则名称 '$new_name' 已存在"
            return
        fi
    done < <(grep -E "^[[:space:]]*-[[:space:]]*name:" "$HYSTERIA_CONFIG" 2>/dev/null | sed 's/.*name:[[:space:]]*//')

    # 逐行重写配置，避免规则名直接进入 sed 表达式
    local temp_config
    temp_config=$(mktemp /tmp/hysteria_rename_rule_XXXXXX.yaml)
    chmod 600 "$temp_config"

    local renamed=false
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^([[:space:]]*)-[[:space:]]*name:[[:space:]]*(.*)$ ]]; then
            local indent="${BASH_REMATCH[1]}"
            local current_name="${BASH_REMATCH[2]}"
            if [[ "$(yaml_unquote_scalar "$current_name")" == "$old_name" ]]; then
                printf '%s- name: %s\n' "$indent" "$(yaml_quote_scalar "$new_name")" >> "$temp_config"
                renamed=true
                continue
            fi
        elif [[ "$line" =~ ^([[:space:]]*)-[[:space:]]*(.*)$ ]]; then
            local indent="${BASH_REMATCH[1]}"
            local current_ref="${BASH_REMATCH[2]}"
            if [[ "$(yaml_unquote_scalar "$current_ref")" == "$old_name" ]]; then
                printf '%s- %s\n' "$indent" "$(yaml_quote_scalar "$new_name")" >> "$temp_config"
                renamed=true
                continue
            fi
        fi
        echo "$line" >> "$temp_config"
    done < "$HYSTERIA_CONFIG"

    if [[ "$renamed" == true ]] && replace_config_file_securely "$temp_config" "$HYSTERIA_CONFIG"; then
        log_success "规则名称已更新: $old_name → $new_name"
        ask_restart_service
    else
        log_error "修改失败"
        rm -f "$temp_config"
    fi
}

modify_server_address() {
    local rule_name="$1"

    echo -e "${BLUE}=== 修改服务器地址 ===${NC}"
    echo "规则名称: ${CYAN}$rule_name${NC}"
    echo ""

    # 获取当前地址
    local current_addr
    current_addr=$(extract_outbound_field_value "$rule_name" "addr|url" || true)
    if [[ -n "$current_addr" ]]; then
        echo "当前地址: ${YELLOW}$current_addr${NC}"
    fi

    read -r -p "请输入新的服务器地址: " new_addr

    if [[ -z "$new_addr" ]]; then
        log_error "服务器地址不能为空"
        return
    fi

    # 创建临时文件进行修改
    local temp_config
    temp_config=$(mktemp /tmp/hysteria_modify_addr_XXXXXX.yaml)
    chmod 600 "$temp_config"
    local in_target_rule=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        if outbound_name_matches_line "$line" "$rule_name"; then
            in_target_rule=true
            echo "$line" >> "$temp_config"
        elif [[ "$in_target_rule" == true ]]; then
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name: ]] || [[ "$line" =~ ^[[:space:]]*[a-zA-Z]+:[[:space:]]*$ ]] && [[ ! "$line" =~ ^[[:space:]]*(type|direct|socks5|http|addr|url|mode|username|password|insecure): ]]; then
                in_target_rule=false
                echo "$line" >> "$temp_config"
            elif [[ "$line" =~ ^[[:space:]]*(addr|url):[[:space:]]* ]]; then
                local indent
                indent=$(echo "$line" | sed 's/[a-zA-Z].*//')
                if [[ "$line" =~ addr: ]]; then
                    yaml_write_kv "$indent" "addr" "$new_addr" >> "$temp_config"
                else
                    yaml_write_kv "$indent" "url" "$new_addr" >> "$temp_config"
                fi
            else
                echo "$line" >> "$temp_config"
            fi
        else
            echo "$line" >> "$temp_config"
        fi
    done < "$HYSTERIA_CONFIG"

    if replace_config_file_securely "$temp_config" "$HYSTERIA_CONFIG"; then
        log_success "服务器地址已更新"
        ask_restart_service
    else
        log_error "修改失败"
    fi
}

modify_username() {
    local rule_name="$1"

    echo -e "${BLUE}=== 修改用户名 ===${NC}"
    echo "规则名称: ${CYAN}$rule_name${NC}"
    echo ""

    # 获取当前用户名
    local current_username
    current_username=$(extract_outbound_field_value "$rule_name" "username" || true)
    if [[ -n "$current_username" ]]; then
        echo "当前用户名: ${YELLOW}$current_username${NC}"
    fi

    read -r -p "请输入新的用户名 (留空则删除): " new_username

    if [[ -n "$new_username" && ! "$new_username" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "用户名只能包含字母、数字、下划线和连字符"
        return
    fi

    # 修改用户名
    modify_config_field "$rule_name" "username" "$new_username"
}

modify_password() {
    local rule_name="$1"

    echo -e "${BLUE}=== 修改密码 ===${NC}"
    echo "规则名称: ${CYAN}$rule_name${NC}"
    echo ""

    read -r -s -p "请输入新密码 (留空则删除): " new_password
    echo ""

    # 修改密码
    modify_config_field "$rule_name" "password" "$new_password"
}

modify_config_field() {
    local rule_name="$1"
    local field_name="$2"
    local new_value="$3"

    local temp_config
    temp_config=$(mktemp "/tmp/hysteria_modify_${field_name}_XXXXXX.yaml")
    chmod 600 "$temp_config"
    local in_target_rule=false
    local field_found=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        if outbound_name_matches_line "$line" "$rule_name"; then
            in_target_rule=true
            echo "$line" >> "$temp_config"
        elif [[ "$in_target_rule" == true ]]; then
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name: ]] || [[ "$line" =~ ^[[:space:]]*[a-zA-Z]+:[[:space:]]*$ ]] && [[ ! "$line" =~ ^[[:space:]]*(type|direct|socks5|http|addr|url|mode|username|password|insecure): ]]; then
                # 如果没找到字段且有新值，在规则结束前插入
                if [[ "$field_found" == false && -n "$new_value" ]]; then
                    local base_indent="      " # 假设基础缩进
                    yaml_write_kv "$base_indent" "$field_name" "$new_value" >> "$temp_config"
                fi
                in_target_rule=false
                echo "$line" >> "$temp_config"
            elif [[ "$line" =~ ^[[:space:]]*${field_name}:[[:space:]]* ]]; then
                field_found=true
                if [[ -n "$new_value" ]]; then
                    local indent
                    indent=$(echo "$line" | sed 's/[a-zA-Z].*//')
                    yaml_write_kv "$indent" "$field_name" "$new_value" >> "$temp_config"
                fi
                # 如果新值为空，则跳过此行（删除字段）
            else
                echo "$line" >> "$temp_config"
            fi
        else
            echo "$line" >> "$temp_config"
        fi
    done < "$HYSTERIA_CONFIG"

    if replace_config_file_securely "$temp_config" "$HYSTERIA_CONFIG"; then
        if [[ -n "$new_value" ]]; then
            log_success "${field_name} 已更新"
        else
            log_success "${field_name} 已删除"
        fi
        ask_restart_service
    else
        log_error "修改失败"
    fi
}

modify_rule_parameters() {
    local rule_name="$1"

    echo ""
    echo -e "${BLUE}=== 修改规则配置参数: ${CYAN}$rule_name${NC} ===${NC}"

    # 获取规则类型
    local rule_type
    rule_type=$(rules_library_value_for_rule "$rule_name" "type" || true)

    if [[ -z "$rule_type" ]]; then
        log_error "无法获取规则类型"
        return 1
    fi

    echo -e "${BLUE}规则类型: ${CYAN}$rule_type${NC}"
    echo ""

    case "$rule_type" in
        "direct")
            modify_direct_parameters "$rule_name"
            ;;
        "socks5")
            modify_socks5_parameters "$rule_name"
            ;;
        "http")
            modify_http_parameters "$rule_name"
            ;;
        *)
            log_error "不支持的规则类型: $rule_type"
            return 1
            ;;
    esac
}

modify_direct_parameters() {
    local rule_name="$1"

    echo "Direct 类型参数修改："
    echo "1. mode (auto|64|46|6|4)"
    echo "2. bindIPv4"
    echo "3. bindIPv6"
    echo "4. bindDevice"
    echo "5. fastOpen (true|false)"
    echo ""

    read -r -p "请选择要修改的参数 [1-5]: " param_choice

    local param_name param_value current_value

    case $param_choice in
        1)
            param_name="mode"
            current_value=$(get_rule_config_value "$rule_name" "$param_name")
            echo "当前值: ${current_value:-"未设置"}"
            echo "可选值: auto, 64, 46, 6, 4"
            read -r -p "请输入新的mode值: " param_value
            ;;
        2)
            param_name="bindIPv4"
            current_value=$(get_rule_config_value "$rule_name" "$param_name")
            echo "当前值: ${current_value:-"未设置"}"
            read -r -p "请输入新的bindIPv4值: " param_value
            ;;
        3)
            param_name="bindIPv6"
            current_value=$(get_rule_config_value "$rule_name" "$param_name")
            echo "当前值: ${current_value:-"未设置"}"
            read -r -p "请输入新的bindIPv6值: " param_value
            ;;
        4)
            param_name="bindDevice"
            current_value=$(get_rule_config_value "$rule_name" "$param_name")
            echo "当前值: ${current_value:-"未设置"}"
            read -r -p "请输入新的bindDevice值: " param_value
            ;;
        5)
            param_name="fastOpen"
            current_value=$(get_rule_config_value "$rule_name" "$param_name")
            echo "当前值: ${current_value:-"未设置"}"
            echo "可选值: true, false"
            read -r -p "请输入新的fastOpen值: " param_value
            ;;
        *)
            log_error "无效选择"
            return 1
            ;;
    esac

    if [[ -n "$param_value" ]]; then
        update_rule_config_value "$rule_name" "$param_name" "$param_value"

        # 检查是否需要同步到配置文件
        prompt_config_sync "$rule_name"
    fi
}

modify_http_parameters() {
    local rule_name="$1"

    echo "HTTP 类型参数修改："
    echo "1. url"
    echo "2. insecure (true|false)"
    echo ""

    read -r -p "请选择要修改的参数 [1-2]: " param_choice

    local param_name param_value current_value

    case $param_choice in
        1)
            param_name="url"
            current_value=$(get_rule_config_value "$rule_name" "$param_name")
            echo "当前值: ${current_value:-"未设置"}"
            read -r -p "请输入新的URL: " param_value
            ;;
        2)
            param_name="insecure"
            current_value=$(get_rule_config_value "$rule_name" "$param_name")
            echo "当前值: ${current_value:-"未设置"}"
            echo "可选值: true, false"
            read -r -p "请输入新的insecure值: " param_value
            ;;
        *)
            log_error "无效选择"
            return 1
            ;;
    esac

    if [[ -n "$param_value" ]]; then
        update_rule_config_value "$rule_name" "$param_name" "$param_value"

        # 检查是否需要同步到配置文件
        prompt_config_sync "$rule_name"
    fi
}

get_rule_config_value() {
    local rule_name="$1"
    local param_name="$2"

    rules_library_value_for_rule "$rule_name" "$param_name"
}

update_rule_config_value() {
    local rule_name="$1"
    local param_name="$2"
    local param_value="$3"

    # 使用临时文件安全更新
    local temp_file
    temp_file=$(create_temp_file)

    local line in_rule=false in_config=false updated=false inserted=false
    while IFS= read -r line || [[ -n "$line" ]]; do
        if rules_library_key_matches_line "$line" "$rule_name"; then
            in_rule=true
            in_config=false
            updated=false
            echo "$line" >> "$temp_file"
            continue
        fi

        if [[ "$in_rule" == true ]]; then
            if [[ "$line" =~ ^[[:space:]]{2}[a-zA-Z_][a-zA-Z0-9_]*:[[:space:]]*$ ]]; then
                if [[ "$in_config" == true && "$updated" == false ]]; then
                    yaml_write_kv "      " "$param_name" "$param_value" >> "$temp_file"
                    inserted=true
                fi
                in_rule=false
                in_config=false
                echo "$line" >> "$temp_file"
                continue
            elif [[ "$line" =~ ^([[:space:]]*)config:[[:space:]]*$ ]]; then
                in_config=true
                echo "$line" >> "$temp_file"
                continue
            elif [[ "$in_config" == true && "$line" =~ ^([[:space:]]*)([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]* ]]; then
                if [[ "${BASH_REMATCH[2]}" == "$param_name" ]]; then
                    yaml_write_kv "${BASH_REMATCH[1]}" "$param_name" "$param_value" >> "$temp_file"
                    updated=true
                    inserted=true
                    continue
                fi
            fi
        fi

        echo "$line" >> "$temp_file"
    done < "$RULES_LIBRARY"

    if [[ "$in_rule" == true && "$in_config" == true && "$updated" == false ]]; then
        yaml_write_kv "      " "$param_name" "$param_value" >> "$temp_file"
        inserted=true
    fi

    if [[ -s "$temp_file" && "$inserted" == true ]]; then
        replace_config_file_securely "$temp_file" "$RULES_LIBRARY"
        log_success "参数 $param_name 已更新为: $param_value"
    else
        log_error "参数更新失败"
        rm -f "$temp_file"
        return 1
    fi
}

modify_socks5_parameters() {
    local rule_name="$1"

    echo "SOCKS5 类型参数修改："
    echo "1. addr"
    echo "2. username"
    echo "3. password"
    echo ""

    read -r -p "请选择要修改的参数 [1-3]: " param_choice

    local param_name param_value current_value

    case $param_choice in
        1)
            param_name="addr"
            current_value=$(get_rule_config_value "$rule_name" "$param_name")
            echo "当前值: ${current_value:-"未设置"}"
            read -r -p "请输入新的地址 (host:port): " param_value
            ;;
        2)
            param_name="username"
            current_value=$(get_rule_config_value "$rule_name" "$param_name")
            echo "当前值: ${current_value:-"未设置"}"
            read -r -p "请输入新的用户名: " param_value
            ;;
        3)
            param_name="password"
            current_value=$(get_rule_config_value "$rule_name" "$param_name")
            echo "当前值: ${current_value:-"未设置"}"
            read -r -p "请输入新的密码: " param_value
            ;;
        *)
            log_error "无效选择"
            return 1
            ;;
    esac

    if [[ -n "$param_value" ]]; then
        update_rule_config_value "$rule_name" "$param_name" "$param_value"

        # 检查是否需要同步到配置文件
        prompt_config_sync "$rule_name"
    fi
}

