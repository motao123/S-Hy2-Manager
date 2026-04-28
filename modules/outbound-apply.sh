#!/bin/bash
# 出站规则应用（配置合并/写入）
#
# 依赖: common.sh, outbound-core.sh
# 导出函数: apply_outbound_config, apply_outbound_simple, apply_outbound_to_config, safe_move_config

write_outbound_entry() {
    local output_file="$1" name="$2" type="$3"
    local indent="${4:-  }"
    local child_indent="${indent}  "
    local field_indent="${child_indent}  "

    printf '%s# 新增出站规则 - %s (%s)\n' "$indent" "$name" "$type" >> "$output_file"
    printf '%s- name: %s\n' "$indent" "$(yaml_quote_scalar "$name")" >> "$output_file"
    printf '%stype: %s\n' "$child_indent" "$type" >> "$output_file"

    case "$type" in
        "direct")
            printf '%sdirect:\n' "$child_indent" >> "$output_file"
            yaml_write_kv "$field_indent" "mode" "auto" >> "$output_file"
            [[ -n "${DIRECT_INTERFACE:-}" ]] && yaml_write_kv "$field_indent" "bindDevice" "$DIRECT_INTERFACE" >> "$output_file"
            [[ -n "${DIRECT_IPV4:-}" ]] && yaml_write_kv "$field_indent" "bindIPv4" "$DIRECT_IPV4" >> "$output_file"
            [[ -n "${DIRECT_IPV6:-}" ]] && yaml_write_kv "$field_indent" "bindIPv6" "$DIRECT_IPV6" >> "$output_file"
            ;;
        "socks5")
            printf '%ssocks5:\n' "$child_indent" >> "$output_file"
            yaml_write_kv "$field_indent" "addr" "${SOCKS5_ADDR:-127.0.0.1:1080}" >> "$output_file"
            [[ -n "${SOCKS5_USERNAME:-}" ]] && yaml_write_kv "$field_indent" "username" "$SOCKS5_USERNAME" >> "$output_file"
            [[ -n "${SOCKS5_PASSWORD:-}" ]] && yaml_write_kv "$field_indent" "password" "$SOCKS5_PASSWORD" >> "$output_file"
            ;;
        "http")
            printf '%shttp:\n' "$child_indent" >> "$output_file"
            yaml_write_kv "$field_indent" "url" "${HTTP_URL:-http://127.0.0.1:8080}" >> "$output_file"
            [[ -n "${HTTP_INSECURE:-}" ]] && yaml_write_kv "$field_indent" "insecure" "$HTTP_INSECURE" >> "$output_file"
            ;;
    esac
}

apply_outbound_config() {
    local name="$1" type="$2" existing_rule="${3:-}"

    read -r -p "是否将此配置应用到 Hysteria2？ [y/N]: " apply_config

    if [[ $apply_config =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}[INFO]${NC} 开始应用出站配置: $name ($type)"

        # 使用极简稳定的方法
        if apply_outbound_simple "$name" "$type" "$existing_rule"; then
            echo -e "${GREEN}[SUCCESS]${NC} 出站配置已添加：$name ($type)"

            # 询问是否重启服务
            read -r -p "是否重启 Hysteria2 服务以应用配置？ [y/N]: " restart_service

            if [[ $restart_service =~ ^[Yy]$ ]]; then
                if systemctl restart hysteria-server 2>/dev/null; then
                    echo -e "${GREEN}[SUCCESS]${NC} 服务已重启"
                else
                    echo -e "${RED}[ERROR]${NC} 服务重启失败"
                fi
            fi
        else
            echo -e "${RED}[ERROR]${NC} 配置应用失败"
        fi
    else
        echo -e "${BLUE}[INFO]${NC} 操作已取消"
    fi
}

apply_outbound_simple() {
    local name="$1" type="$2" existing_rule="${3:-}"

    echo -e "${BLUE}[INFO]${NC} 检查配置文件: $HYSTERIA_CONFIG"

    # 检查配置文件
    if [[ ! -f "$HYSTERIA_CONFIG" ]]; then
        echo -e "${RED}[ERROR]${NC} 配置文件不存在: $HYSTERIA_CONFIG"
        return 1
    fi

    # 如果有要覆盖的规则，先删除它
    if [[ -n "$existing_rule" ]]; then
        echo -e "${BLUE}[INFO]${NC} 删除现有规则: $existing_rule"
        if ! delete_existing_rule_silent "$existing_rule"; then
            echo -e "${RED}[ERROR]${NC} 删除现有规则失败"
            return 1
        fi
    fi

    # 直接操作，不创建不必要的备份

    # 创建临时文件
    local temp_file
    temp_file=$(mktemp /tmp/hysteria_temp_XXXXXX.yaml)
    chmod 600 "$temp_file"
    echo -e "${BLUE}[INFO]${NC} 创建临时文件: $temp_file"

    if ! cp "$HYSTERIA_CONFIG" "$temp_file" 2>/dev/null; then
        echo -e "${RED}[ERROR]${NC} 无法创建临时文件"
        return 1
    fi

    # 添加出站配置
    echo -e "${BLUE}[INFO]${NC} 添加出站配置到临时文件"

    if grep -q "^[[:space:]]*outbounds:" "$temp_file" 2>/dev/null; then
        echo -e "${BLUE}[INFO]${NC} 检测到现有outbounds配置，插入新规则"

        # 创建新的临时文件用于正确插入
        local temp_file2
        temp_file2=$(mktemp /tmp/hysteria_merge_XXXXXX.yaml)
        chmod 600 "$temp_file2"
        local in_outbounds=false
        local inserted=false

        while IFS= read -r line || [[ -n "$line" ]]; do
            # 检测outbounds节点开始
            if [[ "$line" =~ ^[[:space:]]*outbounds: ]]; then
                in_outbounds=true
                echo "$line" >> "$temp_file2"
                continue
            fi

            # 在outbounds节点中，找到合适位置插入
            if [[ "$in_outbounds" == true ]] && [[ "$inserted" == false ]]; then
                # 如果遇到其他顶级节点，在此之前插入新规则
                if [[ "$line" =~ ^[[:space:]]*[a-zA-Z]+:[[:space:]]*$ ]] && [[ ! "$line" =~ ^[[:space:]]*- ]]; then
                    # 插入新规则
                    echo "" >> "$temp_file2"
                    write_outbound_entry "$temp_file2" "$name" "$type" "  "
                    echo "" >> "$temp_file2"
                    inserted=true
                    in_outbounds=false
                fi
            fi

            echo "$line" >> "$temp_file2"
        done < "$temp_file"

        # 如果在文件末尾仍未插入，在outbounds节点末尾添加
        if [[ "$inserted" == false ]] && [[ "$in_outbounds" == true ]]; then
            echo "" >> "$temp_file2"
            write_outbound_entry "$temp_file2" "$name" "$type" "  "
        fi

        # 替换原文件
        mv "$temp_file2" "$temp_file"

        # 智能ACL规则同步
        echo -e "${BLUE}[INFO]${NC} 同步ACL路由规则"
        if grep -q "^[[:space:]]*acl:" "$temp_file" 2>/dev/null; then
            echo -e "${BLUE}[INFO]${NC} 检测到现有ACL规则，智能添加路由条目"

            # 创建ACL添加的临时文件
            local temp_acl
            temp_acl=$(mktemp /tmp/hysteria_acl_add_XXXXXX.yaml)
            chmod 600 "$temp_acl"
            local in_acl_section=false
            local in_inline_section=false
            local acl_base_indent=""
            local added_acl_rule=false

            while IFS= read -r line || [[ -n "$line" ]]; do
                # 检测ACL节点
                if [[ "$line" =~ ^[[:space:]]*acl: ]]; then
                    in_acl_section=true
                    acl_base_indent=$(echo "$line" | sed 's/acl:.*//')
                    echo "$line" >> "$temp_acl"
                    continue
                fi

                # 在ACL节点中
                if [[ "$in_acl_section" == true ]]; then
                    # 检查是否离开ACL节点
                    if [[ "$line" =~ ^[[:space:]]*[a-zA-Z]+:[[:space:]]*$ ]] && [[ ! "$line" =~ ^[[:space:]]*(inline|file): ]]; then
                        local line_indent
                        line_indent=$(echo "$line" | sed 's/[a-zA-Z].*//')
                        if [[ ${#line_indent} -le ${#acl_base_indent} ]]; then
                            # 离开ACL节点前，如果还没添加规则，则添加
                            if [[ "$added_acl_rule" == false ]]; then
                                printf '    - %s  # 新增出站规则\n' "$(yaml_quote_scalar "${name}(all)")" >> "$temp_acl"
                                added_acl_rule=true
                            fi
                            in_acl_section=false
                            in_inline_section=false
                        fi
                    fi

                    # 检测inline节点
                    if [[ "$line" =~ ^[[:space:]]*inline:[[:space:]]*$ ]]; then
                        in_inline_section=true
                        echo "$line" >> "$temp_acl"
                        continue
                    fi

                    # 在inline节点中，添加新规则（在第一个条目后）
                    if [[ "$in_inline_section" == true ]] && [[ "$added_acl_rule" == false ]] && [[ "$line" =~ ^[[:space:]]*-[[:space:]] ]]; then
                        echo "$line" >> "$temp_acl"
                        printf '    - %s  # 新增出站规则\n' "$(yaml_quote_scalar "${name}(all)")" >> "$temp_acl"
                        added_acl_rule=true
                        continue
                    fi
                fi

                echo "$line" >> "$temp_acl"
            done < "$temp_file"

            # 如果文件末尾仍在ACL中且未添加规则
            if [[ "$in_acl_section" == true ]] && [[ "$added_acl_rule" == false ]]; then
                printf '    - %s  # 新增出站规则\n' "$(yaml_quote_scalar "${name}(all)")" >> "$temp_acl"
            fi

            # 替换原文件
            mv "$temp_acl" "$temp_file"
        else
            echo -e "${BLUE}[INFO]${NC} 创建新的ACL规则配置"
            cat >> "$temp_file" << EOF

# ACL规则 - 路由配置
acl:
  inline:
EOF
            printf '    - %s  # 新增出站规则路由\n' "$(yaml_quote_scalar "${name}(all)")" >> "$temp_file"
        fi

    else
        echo -e "${BLUE}[INFO]${NC} 未检测到outbounds配置，创建新节点"
        case $type in
            "direct")
                cat >> "$temp_file" << EOF

# 出站规则配置
outbounds:
EOF
                write_outbound_entry "$temp_file" "$name" "$type" "  "
                cat >> "$temp_file" << EOF

# ACL规则 - 路由配置
acl:
  inline:
EOF
                printf '    - %s  # 所有流量通过此规则直连\n' "$(yaml_quote_scalar "${name}(all)")" >> "$temp_file"
                ;;
            "socks5")
                cat >> "$temp_file" << EOF

# 出站规则配置
outbounds:
EOF
                write_outbound_entry "$temp_file" "$name" "$type" "  "
                cat >> "$temp_file" << EOF

# ACL规则 - 路由配置
acl:
  inline:
EOF
                printf '    - %s  # 所有流量通过此规则代理\n' "$(yaml_quote_scalar "${name}(all)")" >> "$temp_file"
                ;;
        esac
    fi

    # 语法验证功能已移除 - 验证结果不准确且没有实际作用

    # 应用配置
    echo -e "${BLUE}[INFO]${NC} 应用新配置"
    if safe_move_config "$temp_file" "$HYSTERIA_CONFIG"; then
        echo -e "${GREEN}[SUCCESS]${NC} 配置已成功应用"
        return 0
    else
        echo -e "${RED}[ERROR]${NC} 配置应用失败"
        rm -f "$temp_file" 2>/dev/null
        return 1
    fi
}

apply_outbound_to_config() {
    local name="$1" type="$2"

    # 检查配置文件是否存在
    if [[ ! -f "$HYSTERIA_CONFIG" ]]; then
        log_error "Hysteria2 配置文件不存在: $HYSTERIA_CONFIG"
        return 1
    fi

    # 创建安全的临时文件
    local temp_config
    log_info "开始创建临时文件..."
    temp_config=$(create_temp_config)
    if [[ $? -ne 0 ]] || [[ -z "$temp_config" ]]; then
        log_error "创建临时文件失败"
        return 1
    fi
    log_info "临时文件已创建: $temp_config"

    # 复制原配置并检查结果
    log_info "复制配置文件到临时位置..."
    if ! cp "$HYSTERIA_CONFIG" "$temp_config"; then
        log_error "无法复制配置文件到临时位置"
        log_error "源文件: $HYSTERIA_CONFIG"
        log_error "目标文件: $temp_config"
        rm -f "$temp_config"
        return 1
    fi
    log_info "配置文件复制成功"

    # 备份功能已移除，直接应用配置

    # 智能合并配置
    case $type in
        "direct"|"socks5"|"http")
            merge_outbound_config "$temp_config" "$name" "$type"
            ;;
        *)
            log_error "不支持的出站类型: $type"
            rm -f "$temp_config"
            return 1
            ;;
    esac

    # 语法验证功能已移除 - 验证结果不准确且没有实际作用

    # 原子性替换配置文件
    if replace_config_file_securely "$temp_config" "$HYSTERIA_CONFIG"; then
        log_success "配置已成功应用到: $HYSTERIA_CONFIG"
        return 0
    else
        log_error "配置应用失败，请检查文件权限和磁盘空间"
        return 1
    fi
}

create_temp_config() {
    local temp_config

    if ! command -v mktemp >/dev/null 2>&1; then
        log_error "系统缺少 mktemp，无法安全创建临时文件"
        return 1
    fi

    # 尝试不同的 mktemp 选项以确保兼容性
    if temp_config=$(mktemp -t hysteria_config_XXXXXX.yaml 2>/dev/null); then
        log_debug "使用mktemp -t创建临时文件: $temp_config"
    elif temp_config=$(mktemp /tmp/hysteria_config_XXXXXX.yaml 2>/dev/null); then
        log_debug "使用mktemp备选方式创建临时文件: $temp_config"
    else
        log_error "无法安全创建临时文件"
        return 1
    fi

    # 设置适当权限
    if ! chmod 600 "$temp_config" 2>/dev/null; then
        log_warn "无法设置临时文件权限，继续执行"
    fi

    echo "$temp_config"
}

merge_outbound_config() {
    local config_file="$1" name="$2" type="$3"

    # 检查是否已存在outbounds节点
    if grep -q "^[[:space:]]*outbounds:" "$config_file"; then
        log_info "检测到现有outbounds配置，添加到现有列表"
        add_to_existing_outbounds "$config_file" "$name" "$type"
    else
        log_info "未检测到outbounds配置，创建新的outbounds节点"
        add_new_outbounds_section "$config_file" "$name" "$type"
    fi
}

add_to_existing_outbounds() {
    local config_file="$1" name="$2" type="$3"

    echo "" >> "$config_file"
    write_outbound_entry "$config_file" "$name" "$type" "  "
}

add_new_outbounds_section() {
    local config_file="$1" name="$2" type="$3"

    echo "" >> "$config_file"
    echo "# 出站规则配置" >> "$config_file"
    generate_direct_yaml_config "$name" >> "$config_file"
}

safe_move_config() {
    local temp_file="$1"
    local target_file="$2"

    replace_config_file_securely "$temp_file" "$target_file"
}

prompt_config_sync() {
    local rule_name="$1"

    # 检查规则是否已应用到配置文件
    if check_rule_applied_status "$rule_name"; then
        echo ""
        echo -e "${YELLOW}⚠️  检测到此规则已应用到配置文件中${NC}"
        echo -e "${YELLOW}是否需要同步更新到配置文件？${NC}"
        echo ""
        read -r -p "同步更新到配置文件？ [y/N]: " sync_choice

        if [[ $sync_choice =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}正在同步更新到配置文件...${NC}"
            # 调用应用规则函数来同步更新
            if apply_rule_to_config_simple "$rule_name"; then
                echo -e "${GREEN}✅ 配置文件已同步更新${NC}"
                echo -e "${YELLOW}⚠️  配置已更新，需要重启服务生效 ⚠️${NC}"
                echo ""
                ask_restart_service
            else
                echo -e "${RED}❌ 配置文件同步失败${NC}"
            fi
        else
            echo -e "${BLUE}仅更新了规则库，配置文件未变更${NC}"
        fi
    else
        echo -e "${BLUE}✅ 规则库已更新${NC}"
    fi
}

