#!/bin/bash
# 出站规则删除
#
# 依赖: common.sh, outbound-core.sh
# 导出函数: delete_outbound_rule, delete_outbound_rule_new, delete_rule_from_library, remove_rule_from_config

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

acl_line_references_rule() {
    local line="$1" rule_name="$2"
    local acl_value

    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*(.*)$ ]]; then
        acl_value=$(yaml_unquote_scalar "${BASH_REMATCH[1]}")
        [[ "$acl_value" == "$rule_name" || "$acl_value" == "${rule_name}(all)" ]]
        return
    fi

    return 1
}

library_rule_key_matches_line() {
    local line="$1" rule_name="$2"
    local current_key

    if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*$ ]]; then
        current_key="${BASH_REMATCH[1]}"
        [[ "$current_key" == "$rule_name" ]]
        return
    fi

    return 1
}

delete_outbound_rule() {
    local rule_name="$1"

    echo -e "${RED}[WARNING]${NC} 即将删除出站规则: $rule_name"
    echo -e "${YELLOW}此操作不可逆，请确认操作${NC}"
    echo -n "确认删除？ [y/N]: "
    local confirm
    read -r -r confirm

    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}[INFO]${NC} 取消删除操作"
        return
    fi

    echo -e "${BLUE}[INFO]${NC} 开始删除出站规则: $rule_name"

    # 直接删除，不创建不必要的备份

    # 创建临时文件
    local temp_config
    temp_config=$(mktemp /tmp/hysteria_delete_temp_XXXXXX.yaml)
    chmod 600 "$temp_config"

    # 智能删除逻辑：完整删除outbound规则和相关ACL条目
    local in_outbound_rule=false
    local in_acl_section=false
    local acl_base_indent=""
    local delete_acl_inline=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        local should_keep=true

        # 1. 删除包含规则名的注释
        if [[ "$line" == *"$rule_name"* ]] && [[ "$line" =~ ^[[:space:]]*# ]]; then
            should_keep=false
        fi

        # 2. 检测outbound规则块
        if outbound_name_matches_line "$line" "$rule_name"; then
            in_outbound_rule=true
            should_keep=false
        elif [[ "$in_outbound_rule" == true ]]; then
            # 在outbound规则块中，检查是否结束
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name: ]] || [[ "$line" =~ ^[[:space:]]*[a-zA-Z]+:[[:space:]]*$ ]] && [[ ! "$line" =~ ^[[:space:]]*(type|direct|socks5|http|addr|url|mode|username|password|insecure): ]]; then
                in_outbound_rule=false
                should_keep=true
            else
                should_keep=false  # 删除outbound规则块内的所有行
            fi
        fi

        # 3. 检测ACL节点
        if [[ "$line" =~ ^[[:space:]]*acl:[[:space:]]*$ ]]; then
            in_acl_section=true
            acl_base_indent=$(echo "$line" | sed 's/acl:.*//')
            should_keep=true
        elif [[ "$line" =~ ^[[:space:]]*acl: ]]; then
            in_acl_section=true
            acl_base_indent=$(echo "$line" | sed 's/acl:.*//')
            should_keep=true
        elif [[ "$in_acl_section" == true ]]; then
            # 检查是否离开ACL节点
            if [[ "$line" =~ ^[[:space:]]*[a-zA-Z]+:[[:space:]]*$ ]] && [[ ! "$line" =~ ^[[:space:]]*(inline|file): ]]; then
                local line_indent
                line_indent=$(echo "$line" | sed 's/[a-zA-Z].*//')
                if [[ ${#line_indent} -le ${#acl_base_indent} ]]; then
                    in_acl_section=false
                    should_keep=true
                fi
            fi

            # 在ACL节点中处理
            if [[ "$in_acl_section" == true ]]; then
                # 检测inline节点开始
                if [[ "$line" =~ ^[[:space:]]*inline:[[:space:]]*$ ]]; then
                    delete_acl_inline=false
                    should_keep=true
                elif acl_line_references_rule "$line" "$rule_name"; then
                    should_keep=false  # 删除ACL中引用目标规则的条目
                else
                    should_keep=true
                fi
            fi
        fi

        # 写入保留的行
        if [[ "$should_keep" == true ]]; then
            echo "$line" >> "$temp_config"
        fi
    done < "$HYSTERIA_CONFIG"

    # 检查删除是否成功
    while IFS= read -r line || [[ -n "$line" ]]; do
        if outbound_name_matches_line "$line" "$rule_name"; then
            echo -e "${RED}[ERROR]${NC} 删除失败，规则仍存在"
            rm -f "$temp_config"
            return 1
        fi
    done < "$temp_config"

    # 应用修改
    if mv "$temp_config" "$HYSTERIA_CONFIG" 2>/dev/null; then
        echo -e "${GREEN}[SUCCESS]${NC} 出站规则 '$rule_name' 已删除"

        # 询问是否重启服务
        echo ""
        read -r -p "是否重启 Hysteria2 服务以应用配置？ [y/N]: " restart_service

        if [[ $restart_service =~ ^[Yy]$ ]]; then
            if systemctl restart hysteria-server 2>/dev/null; then
                echo -e "${GREEN}[SUCCESS]${NC} 服务已重启"
            else
                echo -e "${YELLOW}[WARN]${NC} 服务重启失败，请手动重启"
            fi
        fi
    else
        echo -e "${RED}[ERROR]${NC} 配置应用失败"
        return 1
    fi

    echo ""
    wait_for_user
}

delete_outbound_rule_new() {
    init_rules_library

    echo -e "${BLUE}=== 删除出站规则 ===${NC}"
    echo ""

    # 收集规则库中的规则
    local library_rules=()
    while IFS= read -r rule_name; do
        if [[ -n "$rule_name" ]]; then
            library_rules+=("$rule_name")
        fi
    done < <(grep -o "^[[:space:]]\{2\}[a-zA-Z_][a-zA-Z0-9_]*:" "$RULES_LIBRARY" | sed 's/^[[:space:]]\{2\}\([^:]*\):.*/\1/')

    # 收集配置文件中的规则
    local config_rules=()
    while IFS= read -r rule_name; do
        if [[ -n "$rule_name" ]]; then
            config_rules+=("$rule_name")
        fi
    done < <(get_config_outbound_rules)

    # 合并规则并确定来源
    local all_rules=()
    local rule_sources=()
    local rule_count=0

    # 构建规则来源映射
    declare -A rule_in_library
    declare -A rule_in_config

    # 标记规则库中的规则
    for rule in "${library_rules[@]}"; do
        rule_in_library["$rule"]=1
    done

    # 标记配置文件中的规则
    for rule in "${config_rules[@]}"; do
        rule_in_config["$rule"]=1
    done

    # 合并所有规则（去重）
    local all_rule_names=()
    
    # 先添加规则库中的规则
    for rule in "${library_rules[@]}"; do
        all_rule_names+=("$rule")
    done
    
    # 添加配置文件中独有的规则
    for rule in "${config_rules[@]}"; do
        local found=false
        for existing in "${all_rule_names[@]}"; do
            if [[ "$rule" == "$existing" ]]; then
                found=true
                break
            fi
        done
        if [[ "$found" == false ]]; then
            all_rule_names+=("$rule")
        fi
    done


    # === 调试信息 (可通过 export DEBUG_OUTBOUND=1 启用) ===
    if [[ -n "${DEBUG_OUTBOUND:-}" ]]; then
        echo -e "${CYAN}[调试] 规则库规则数: ${#library_rules[@]}${NC}"
        echo -e "${CYAN}[调试] 规则库规则: ${library_rules[*]}${NC}"
        echo -e "${CYAN}[调试] 配置文件规则数: ${#config_rules[@]}${NC}"
        echo -e "${CYAN}[调试] 配置文件规则: ${config_rules[*]}${NC}"
        echo ""
        echo -e "${CYAN}[调试] 关联数组状态:${NC}"
        for rule in "${all_rule_names[@]}"; do
            local in_lib=${rule_in_library[$rule]:-0}
            local in_conf=${rule_in_config[$rule]:-0}
            echo "  $rule: lib=$in_lib, conf=$in_conf"
        done
        echo ""
    fi
    # === 调试信息结束 ===
    # 为每个规则确定来源
    for rule in "${all_rule_names[@]}"; do
        all_rules+=("$rule")
        ((rule_count++))
        
        local in_lib=${rule_in_library[$rule]:-0}
        local in_conf=${rule_in_config[$rule]:-0}
        
        if [[ $in_lib -eq 1 ]] && [[ $in_conf -eq 1 ]]; then
            rule_sources+=("both")
        elif [[ $in_lib -eq 1 ]]; then
            rule_sources+=("library")
        else
            rule_sources+=("config")
        fi
    done

    if [[ ${#all_rules[@]} -eq 0 ]]; then
        echo -e "${YELLOW}没有找到任何规则${NC}"
        wait_for_user
        return
        return
    fi

    echo -e "${CYAN}找到以下规则:${NC}"
    echo ""
    printf "%-5s %-25s %-12s %s\n" "编号" "规则名称" "位置" "状态"
    echo "---------------------------------------------------"

    for i in "${!all_rules[@]}"; do
        local rule_name="${all_rules[i]}"
        local source="${rule_sources[i]}"
        local status=""

        # 确定位置显示
        local location_display
        case "$source" in
            "library") location_display="${GREEN}规则库${NC}" ;;
            "config") location_display="${YELLOW}配置文件${NC}" ;;
            "both") location_display="${BLUE}规则库+配置${NC}" ;;
        esac

        # 检查应用状态
        local status
        status=$(get_rule_status_text "$rule_name")

        printf "%-5d %-25s %-12s %s\n" "$((i+1))" "$rule_name" "$location_display" "$status"
    done

    echo ""
    echo -e "${YELLOW}说明:${NC}"
    echo "• 规则库: 规则模板，可重复应用"
    echo "• 配置文件: 当前活动的规则"
    echo "• 规则库+配置: 存在于两个位置"
    echo ""

    read -r -p "请选择要删除的规则编号 [1-$rule_count]: " choice

    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt $rule_count ]]; then
        log_error "无效选择"
        return 1
    fi

    local selected_rule
    selected_rule="${all_rules[$((choice-1))]}"
    local selected_source
    selected_source="${rule_sources[$((choice-1))]}"

    echo ""
    echo -e "${RED}⚠️  警告: 即将删除规则 '$selected_rule'${NC}"

    # 根据规则位置给出不同的提示
    case "$selected_source" in
        "library")
            echo -e "${YELLOW}此规则仅存在于规则库中${NC}"
            ;;
        "config")
            echo -e "${YELLOW}此规则仅存在于配置文件中，删除后将立即生效${NC}"
            ;;
        "both")
            echo -e "${YELLOW}此规则同时存在于规则库和配置文件中${NC}"
            echo "选择删除范围:"
            echo "1. 仅从规则库中删除"
            echo "2. 仅从配置文件中删除"
            echo "3. 同时从两个位置删除"
            echo ""
            read -r -p "请选择 [1-3]: " delete_scope
            ;;
    esac

    echo ""
    read -r -p "确认删除？ [y/N]: " confirm

    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}已取消删除操作${NC}"
        return 0
    fi

    local delete_success=false

    # 执行删除操作
    case "$selected_source" in
        "library")
            if delete_rule_from_library "$selected_rule"; then
                delete_success=true
            fi
            ;;
        "config")
            if remove_rule_from_config "$selected_rule"; then
                delete_success=true
                # 从状态文件中移除
                remove_rule_from_state "$selected_rule"
            fi
            ;;
        "both")
            case "$delete_scope" in
                1)
                    if delete_rule_from_library "$selected_rule"; then
                        delete_success=true
                    fi
                    ;;
                2)
                    if remove_rule_from_config "$selected_rule"; then
                        remove_rule_from_state "$selected_rule"
                        delete_success=true
                    fi
                    ;;
                3)
                    local lib_success=false
                    local config_success=false

                    if delete_rule_from_library "$selected_rule"; then
                        lib_success=true
                    fi

                    if remove_rule_from_config "$selected_rule"; then
                        remove_rule_from_state "$selected_rule"
                        config_success=true
                    fi

                    if [[ "$lib_success" == true ]] || [[ "$config_success" == true ]]; then
                        delete_success=true
                    fi
                    ;;
                *)
                    log_error "无效的删除范围选择"
                    return 1
                    ;;
            esac
            ;;
    esac

    if [[ "$delete_success" == true ]]; then
        log_success "规则 '$selected_rule' 删除操作完成"

        # 如果删除了配置文件中的规则，询问是否重启服务
        if [[ "$selected_source" == "config" ]] || [[ "$selected_source" == "both" && ("$delete_scope" == "2" || "$delete_scope" == "3") ]]; then
            echo ""
            read -r -p "是否重启 Hysteria2 服务以应用更改？ [y/N]: " restart_service
            if [[ $restart_service =~ ^[Yy]$ ]]; then
                if systemctl restart hysteria-server 2>/dev/null; then
                    log_success "服务已重启"
                else
                    log_warn "服务重启失败，请手动重启"
                fi
            fi
        fi
    else
        log_error "规则删除失败"
        return 1
    fi

    wait_for_user
}

delete_existing_rule_silent() {
    local rule_name="$1"

    echo -e "${BLUE}[INFO]${NC} 正在删除现有规则: $rule_name"

    # 创建临时文件
    local temp_config
    temp_config=$(mktemp /tmp/hysteria_delete_temp_XXXXXX.yaml)
    chmod 600 "$temp_config"

    # 智能删除逻辑：完整删除outbound规则和相关ACL条目
    local in_outbound_rule=false
    local in_acl_section=false
    local acl_base_indent=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        local should_keep=true

        # 1. 删除包含规则名的注释
        if [[ "$line" == *"$rule_name"* ]] && [[ "$line" =~ ^[[:space:]]*# ]]; then
            should_keep=false
        fi

        # 2. 检测outbound规则块
        if outbound_name_matches_line "$line" "$rule_name"; then
            in_outbound_rule=true
            should_keep=false
        elif [[ "$in_outbound_rule" == true ]]; then
            # 在outbound规则块中，检查是否结束
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name: ]] || [[ "$line" =~ ^[[:space:]]*[a-zA-Z]+:[[:space:]]*$ ]] && [[ ! "$line" =~ ^[[:space:]]*(type|direct|socks5|http|addr|url|mode|username|password|insecure): ]]; then
                in_outbound_rule=false
                should_keep=true
            else
                should_keep=false  # 删除outbound规则块内的所有行
            fi
        fi

        # 3. 检测ACL节点
        if [[ "$line" =~ ^[[:space:]]*acl: ]]; then
            in_acl_section=true
            acl_base_indent=$(echo "$line" | sed 's/acl:.*//')
            should_keep=true
        elif [[ "$in_acl_section" == true ]]; then
            # 检查是否离开ACL节点
            if [[ "$line" =~ ^[[:space:]]*[a-zA-Z]+:[[:space:]]*$ ]] && [[ ! "$line" =~ ^[[:space:]]*(inline|file): ]]; then
                local line_indent
                line_indent=$(echo "$line" | sed 's/[a-zA-Z].*//')
                if [[ ${#line_indent} -le ${#acl_base_indent} ]]; then
                    in_acl_section=false
                    should_keep=true
                fi
            fi

            # 在ACL节点中处理 - 删除引用目标规则的条目
            if [[ "$in_acl_section" == true ]] && acl_line_references_rule "$line" "$rule_name"; then
                should_keep=false
            fi
        fi

        # 写入保留的行
        if [[ "$should_keep" == true ]]; then
            echo "$line" >> "$temp_config"
        fi
    done < "$HYSTERIA_CONFIG"

    # 检查删除是否成功
    while IFS= read -r line || [[ -n "$line" ]]; do
        if outbound_name_matches_line "$line" "$rule_name"; then
            echo -e "${RED}[ERROR]${NC} 删除失败，规则仍存在"
            rm -f "$temp_config"
            return 1
        fi
    done < "$temp_config"

    # 应用修改
    if safe_move_config "$temp_config" "$HYSTERIA_CONFIG"; then
        echo -e "${GREEN}[SUCCESS]${NC} 现有规则 '$rule_name' 已删除"
        return 0
    else
        echo -e "${RED}[ERROR]${NC} 删除失败，文件操作错误"
        rm -f "$temp_config"
        return 1
    fi
}

delete_existing_outbound_from_config() {
    local rule_name="$1"
    local config_file="${2:-$HYSTERIA_CONFIG}"

    if [[ -z "$rule_name" ]]; then
        log_error "规则名称不能为空"
        return 1
    fi

    if [[ ! -f "$config_file" ]]; then
        log_warn "配置文件不存在: $config_file"
        return 0  # 文件不存在视为成功删除
    fi

    # 检查文件是否可写
    if [[ ! -w "$config_file" ]]; then
        log_warn "配置文件无写权限: $config_file"
        return 1
    fi

    echo -e "${BLUE}[INFO]${NC} 从配置文件中删除规则: $rule_name"

    # 创建临时文件
    local temp_config
    temp_config=$(create_delete_temp_file)

    # 删除指定的outbound规则
    local in_outbound_rule=false
    local in_outbounds_section=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        local should_keep=true

        # 检测outbounds节点
        if [[ "$line" =~ ^[[:space:]]*outbounds:[[:space:]]*$ ]]; then
            in_outbounds_section=true
            should_keep=true
        elif [[ "$in_outbounds_section" == true ]]; then
            # 在outbounds节点中

            # 检测目标规则开始
            if outbound_name_matches_line "$line" "$rule_name"; then
                in_outbound_rule=true
                should_keep=false
            elif [[ "$in_outbound_rule" == true ]]; then
                # 在目标规则块中，检查是否结束
                if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name: ]] || [[ "$line" =~ ^[[:space:]]*[a-zA-Z]+:[[:space:]]*$ ]] && [[ ! "$line" =~ ^[[:space:]]*(type|direct|socks5|http): ]]; then
                    # 遇到下一个规则或顶级节点，结束当前规则删除
                    in_outbound_rule=false
                    # 检查是否离开outbounds节点
                    if [[ "$line" =~ ^[a-zA-Z]+:[[:space:]]*$ ]]; then
                        in_outbounds_section=false
                    fi
                    should_keep=true
                else
                    # 仍在目标规则块中，继续删除
                    should_keep=false
                fi
            else
                # 不在目标规则块中，检查是否离开outbounds节点
                if [[ "$line" =~ ^[a-zA-Z]+:[[:space:]]*$ ]]; then
                    in_outbounds_section=false
                fi
                should_keep=true
            fi
        fi

        # 保留需要的行
        if [[ "$should_keep" == true ]]; then
            echo "$line" >> "$temp_config"
        fi
    done < "$config_file"

    # 替换原文件 - 增强错误处理
    if mv "$temp_config" "$config_file" 2>/dev/null; then
        echo -e "${GREEN}[SUCCESS]${NC} 规则 '$rule_name' 已从配置文件中删除"
        return 0
    elif cp "$temp_config" "$config_file" 2>/dev/null; then
        # mv失败时尝试cp
        rm -f "$temp_config"
        echo -e "${GREEN}[SUCCESS]${NC} 规则 '$rule_name' 已从配置文件中删除"
        return 0
    else
        log_error "删除规则失败: 文件操作错误，可能是权限问题"
        log_info "临时文件保存在: $temp_config"
        return 1
    fi
}

delete_rule_from_library() {
    local rule_name="$1"
    local temp_library
    temp_library=$(mktemp /tmp/rules_delete_library_XXXXXX.yaml)
    chmod 600 "$temp_library"
    local in_target_rule=false
    local rule_indent=""
    local rule_found=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        if library_rule_key_matches_line "$line" "$rule_name"; then
            in_target_rule=true
            rule_found=true
            rule_indent=$(echo "$line" | sed 's/[a-zA-Z].*//')
            continue
        elif [[ "$in_target_rule" == true ]]; then
            # 检查是否离开规则
            if [[ "$line" =~ ^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*:[[:space:]]*$ ]]; then
                local line_indent
                line_indent=$(echo "$line" | sed 's/[a-zA-Z].*//')
                if [[ ${#line_indent} -le ${#rule_indent} ]]; then
                    in_target_rule=false
                    echo "$line" >> "$temp_library"
                fi
            elif [[ "$line" =~ ^[[:space:]]*[a-zA-Z]+:[[:space:]]*$ ]] && [[ ! "$line" =~ ^[[:space:]]*(type|description|config|created_at|updated_at): ]]; then
                in_target_rule=false
                echo "$line" >> "$temp_library"
            fi
            # 在规则中的行都跳过
        else
            echo "$line" >> "$temp_library"
        fi
    done < "$RULES_LIBRARY"

    if [[ "$rule_found" == true ]]; then
        if mv "$temp_library" "$RULES_LIBRARY"; then
            log_success "已从规则库中删除规则 '$rule_name'"
            return 0
        else
            log_error "规则库更新失败"
            rm -f "$temp_library"
            return 1
        fi
    else
        log_warn "在规则库中未找到规则 '$rule_name'"
        rm -f "$temp_library"
        return 1
    fi
}

remove_rule_from_config() {
    local rule_name="$1"

    if [[ ! -f "$HYSTERIA_CONFIG" ]]; then
        log_error "配置文件不存在"
        return 1
    fi

    local temp_config
    temp_config=$(mktemp /tmp/hysteria_delete_config_XXXXXX.yaml)
    chmod 600 "$temp_config"
    local in_target_rule=false
    local rule_found=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        # 解析 name 字段，避免规则名作为正则参与匹配
        if outbound_name_matches_line "$line" "$rule_name"; then
            in_target_rule=true
            rule_found=true
            continue
        elif [[ "$in_target_rule" == true ]]; then
            # 检查是否到达下一个规则或段落
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name: ]] || [[ "$line" =~ ^[[:space:]]*[a-zA-Z]+:[[:space:]]*$ ]] && [[ ! "$line" =~ ^[[:space:]]*(type|direct|socks5|http|addr|url|mode|username|password|insecure): ]]; then
                in_target_rule=false
                echo "$line" >> "$temp_config"
            fi
            # 在目标规则中的行都跳过
        else
            echo "$line" >> "$temp_config"
        fi
    done < "$HYSTERIA_CONFIG"

    if [[ "$rule_found" == true ]]; then
        if safe_move_config "$temp_config" "$HYSTERIA_CONFIG"; then
            log_success "已从配置文件中删除规则 '$rule_name'"
            return 0
        else
            log_error "配置文件更新失败"
            rm -f "$temp_config"
            return 1
        fi
    else
        log_warn "在配置文件中未找到规则 '$rule_name'"
        rm -f "$temp_config"
        return 1
    fi
}

remove_rule_from_state() {
    local rule_name="$1"
    local temp_state line state_value

    if [[ -f "$RULES_STATE" ]]; then
        temp_state=$(create_temp_file)
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*(.*)$ ]]; then
                state_value=$(yaml_unquote_scalar "${BASH_REMATCH[1]}")
                if [[ "$state_value" == "$rule_name" ]]; then
                    continue
                fi
            fi
            echo "$line" >> "$temp_state"
        done < "$RULES_STATE"

        if [[ -s "$temp_state" ]]; then
            replace_config_file_securely "$temp_state" "$RULES_STATE" || rm -f "$temp_state"
        else
            rm -f "$temp_state"
        fi
    fi
}

