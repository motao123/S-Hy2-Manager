#!/bin/bash
# 出站规则添加（Direct/SOCKS5/HTTP）
#
# 依赖: common.sh, outbound-core.sh
# 导出函数: add_outbound_rule, add_direct_outbound, add_http_outbound, add_socks5_outbound, apply_outbound_rule

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

add_outbound_rule() {
    log_info "添加新的出站规则"

    echo -e "${BLUE}=== 添加出站规则 ===${NC}"
    echo ""
    echo "选择出站类型："
    echo "1. Direct (直连)"
    echo "2. SOCKS5 代理"
    echo "3. HTTP/HTTPS 代理"
    echo ""

    local choice
    read -r -p "请选择 [1-3]: " choice

    # 确定选择的类型
    local selected_type
    case $choice in
        1) selected_type="direct" ;;
        2) selected_type="socks5" ;;
        3) selected_type="http" ;;
        *)
            log_error "无效选择"
            return 1
            ;;
    esac

    echo -e "${GREEN}已选择类型: $selected_type${NC}"

    # 执行对应的配置函数
    case $choice in
        1) add_direct_outbound ;;
        2) add_socks5_outbound ;;
        3) add_http_outbound ;;
    esac
}

add_direct_outbound() {
    echo -e "${BLUE}=== 配置 Direct 直连出站 ===${NC}"
    echo ""

    local name interface ipv4 ipv6

    # 获取出站名称
    read -r -p "出站名称 (例: china_direct): " name
    if [[ -z "$name" ]]; then
        name="direct_out"
    elif [[ ! "$name" =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo -e "${RED}名称只能包含字母、数字和下划线，使用默认名称${NC}"
        name="direct_out"
    fi

    # 是否绑定特定网卡
    read -r -p "是否绑定特定网卡？ [y/N]: " bind_interface

    if [[ $bind_interface =~ ^[Yy]$ ]]; then
        echo "可用网卡："
        # 优化：缓存网卡信息并使用更高效的命令
        if [[ -z "${CACHED_INTERFACES:-}" ]]; then
            # 使用更快的方法获取网卡列表
            if command -v ip >/dev/null 2>&1; then
                CACHED_INTERFACES=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo")
            else
                # 降级方案
                CACHED_INTERFACES=$(ls /sys/class/net/ | grep -v "lo")
            fi
        fi
        echo "$CACHED_INTERFACES" | nl -w2 -s') '
        read -r -p "请选择网卡名称 (例: eth0): " interface
    fi

    # 是否绑定特定 IP
    read -r -p "是否绑定特定 IP 地址？ [y/N]: " bind_ip

    if [[ $bind_ip =~ ^[Yy]$ ]]; then
        read -r -p "IPv4 地址 (可选): " ipv4
        read -r -p "IPv6 地址 (可选): " ipv6
    fi

    # 保存配置参数供后续使用
    export DIRECT_INTERFACE="$interface"
    export DIRECT_IPV4="$ipv4"
    export DIRECT_IPV6="$ipv6"

    # 生成配置
    generate_direct_config "$name" "$interface" "$ipv4" "$ipv6"
}

add_http_outbound() {
    echo -e "${BLUE}=== 配置 HTTP/HTTPS 代理出站 ===${NC}"
    echo ""

    local name url insecure

    read -r -p "出站名称 (例: http_proxy): " name
    if [[ -z "$name" ]]; then
        name="http_out"
    elif [[ ! "$name" =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo -e "${RED}名称只能包含字母、数字和下划线，使用默认名称${NC}"
        name="http_out"
    fi

    echo "代理类型："
    echo "1. HTTP 代理"
    echo "2. HTTPS 代理"
    read -r -p "选择 [1-2]: " proxy_type

    if [[ "$proxy_type" == "1" ]]; then
        read -r -p "HTTP 代理 URL (例: http://user:pass@proxy.com:8080): " url
    else
        read -r -p "HTTPS 代理 URL (例: https://user:pass@proxy.com:8080): " url
        read -r -p "是否跳过 TLS 验证？ [y/N]: " skip_tls
        if [[ $skip_tls =~ ^[Yy]$ ]]; then
            insecure="true"
        else
            insecure="false"
        fi
    fi

    if [[ -z "$url" ]]; then
        log_error "代理 URL 不能为空"
        return 1
    fi

    # 保存配置参数供后续使用
    export HTTP_URL="$url"
    export HTTP_INSECURE="$insecure"

    # 生成配置
    generate_http_config "$name" "$url" "$insecure"
}

add_outbound_rule_new() {
    init_rules_library

    echo -e "${BLUE}=== 新增出站规则 ===${NC}"
    echo ""

    # 获取规则名称
    local rule_name
    while true; do
        read -r -p "规则名称 (字母、数字、下划线): " rule_name

        if [[ -z "$rule_name" ]]; then
            echo -e "${RED}规则名称不能为空${NC}"
            continue
        fi

        if [[ ! "$rule_name" =~ ^[a-zA-Z0-9_]+$ ]]; then
            echo -e "${RED}规则名称只能包含字母、数字和下划线${NC}"
            continue
        fi

        # 检查是否已存在（检查2级缩进的规则名，避免规则名进入 grep 正则）
        local existing_rule_line existing_rule_name rule_exists=false
        while IFS= read -r existing_rule_line || [[ -n "$existing_rule_line" ]]; do
            if [[ "$existing_rule_line" =~ ^[[:space:]]{2}([a-zA-Z0-9_]+):[[:space:]]*$ ]]; then
                existing_rule_name="${BASH_REMATCH[1]}"
                if [[ "$existing_rule_name" == "$rule_name" ]]; then
                    rule_exists=true
                    break
                fi
            fi
        done < "$RULES_LIBRARY"

        if [[ "$rule_exists" == true ]]; then
            echo -e "${RED}已存在同名的规则，需要重新录入其他名称${NC}"
            continue
        fi

        break
    done

    # 获取规则描述
    read -r -p "规则描述: " rule_desc
    if [[ -z "$rule_desc" ]]; then
        rule_desc="$rule_name 出站规则"
    fi

    # 选择规则类型
    echo ""
    echo "选择规则类型："
    echo "1. Direct (直连)"
    echo "2. SOCKS5 代理"
    echo "3. HTTP/HTTPS 代理"
    echo ""

    local rule_type=""
    local type_choice
    read -r -p "请选择 [1-3]: " type_choice

    case $type_choice in
        1) rule_type="direct" ;;
        2) rule_type="socks5" ;;
        3) rule_type="http" ;;
        *)
            log_error "无效选择"
            return 1
            ;;
    esac

    # 名称冲突已在前面检查，允许同类型多个规则
    echo -e "${GREEN}规则类型: $rule_type${NC}"

    # 收集配置
    local config_data=""
    case $rule_type in
        "direct")
            echo ""
            echo -e "${BLUE}配置 Direct 直连参数${NC}"
            read -r -p "绑定网卡 (可选): " interface
            read -r -p "绑定IPv4 (可选): " ipv4
            read -r -p "绑定IPv6 (可选): " ipv6

            config_data="mode: auto"
            if [[ -n "$interface" ]]; then
                config_data+="\nbindDevice: $(yaml_quote_scalar "$interface")"
            fi
            if [[ -n "$ipv4" ]]; then
                config_data+="\nbindIPv4: $(yaml_quote_scalar "$ipv4")"
            fi
            if [[ -n "$ipv6" ]]; then
                config_data+="\nbindIPv6: $(yaml_quote_scalar "$ipv6")"
            fi
            ;;
        "socks5")
            echo ""
            echo -e "${BLUE}配置 SOCKS5 代理参数${NC}"
            read -r -p "代理地址:端口: " addr
            if [[ -z "$addr" ]]; then
                log_error "代理地址不能为空"
                return 1
            fi

            config_data="addr: $(yaml_quote_scalar "$addr")"

            read -r -p "需要认证？ [y/N]: " need_auth
            if [[ $need_auth =~ ^[Yy]$ ]]; then
                read -r -p "用户名: " username
                read -r -s -p "密码: " password
                echo ""
                if [[ -n "$username" ]]; then
                    config_data+="\nusername: $(yaml_quote_scalar "$username")"
                    config_data+="\npassword: $(yaml_quote_scalar "$password")"
                fi
            fi
            ;;
        "http")
            echo ""
            echo -e "${BLUE}配置 HTTP/HTTPS 代理参数${NC}"
            read -r -p "代理URL: " url
            if [[ -z "$url" ]]; then
                log_error "代理URL不能为空"
                return 1
            fi

            config_data="url: $(yaml_quote_scalar "$url")"

            if [[ "$url" =~ ^https:// ]]; then
                read -r -p "跳过TLS验证？ [y/N]: " skip_tls
                if [[ $skip_tls =~ ^[Yy]$ ]]; then
                    config_data+="\ninsecure: true"
                fi
            fi
            ;;
    esac

    # 保存到规则库
    local temp_file
    temp_file=$(mktemp /tmp/rules_add_XXXXXX.yaml)
    chmod 600 "$temp_file"

    local quoted_desc
    quoted_desc=$(yaml_quote_scalar "$rule_desc")

    # 在rules节点下添加新规则
    awk -v key_name="$rule_name" -v type="$rule_type" -v desc="$quoted_desc" -v config="$config_data" '
    /^rules:/ {
        print $0
        print "  " key_name ":"
        print "    type: " type
        print "    description: " desc
        print "    config:"
        # 处理配置数据，添加正确的缩进
        n = split(config, lines, "\\n")
        for (i = 1; i <= n; i++) {
            if (lines[i] != "") {
                print "      " lines[i]
            }
        }
        print "    created_at: \"" strftime("%Y-%m-%dT%H:%M:%SZ") "\""
        print "    updated_at: \"" strftime("%Y-%m-%dT%H:%M:%SZ") "\""
        next
    }
    /^last_modified:/ {
        print "last_modified: \"" strftime("%Y-%m-%dT%H:%M:%SZ") "\""
        next
    }
    { print }
    ' "$RULES_LIBRARY" > "$temp_file"

    if mv "$temp_file" "$RULES_LIBRARY"; then
        log_success "规则 '$rule_name' 已添加到规则库"

        echo ""
        read -r -p "是否立即应用此规则？ [y/N]: " apply_now
        if [[ $apply_now =~ ^[Yy]$ ]]; then
            apply_rule_to_config_simple "$rule_name"
        fi
    else
        log_error "规则保存失败"
        rm -f "$temp_file"
        return 1
    fi

    wait_for_user
}

generate_direct_config() {
    local name="$1" interface="$2" ipv4="$3" ipv6="$4"

    echo "生成的 Direct 出站配置："
    echo "---"
    echo "outbounds:"
    printf '  - name: %s\n' "$(yaml_quote_scalar "$name")"
    echo "    type: direct"
    echo "    direct:"
    echo "      mode: auto"

    if [[ -n "$interface" ]]; then
        yaml_write_kv "      " "bindDevice" "$interface"
    fi
    if [[ -n "$ipv4" ]]; then
        yaml_write_kv "      " "bindIPv4" "$ipv4"
    fi
    if [[ -n "$ipv6" ]]; then
        yaml_write_kv "      " "bindIPv6" "$ipv6"
    fi
    echo "---"
    echo ""

    apply_outbound_config "$name" "direct" "$existing_rule"
}

generate_http_config() {
    local name="$1" url="$2" insecure="$3"

    echo "生成的 HTTP 出站配置："
    echo "---"
    echo "outbounds:"
    printf '  - name: %s\n' "$(yaml_quote_scalar "$name")"
    echo "    type: http"
    echo "    http:"
    yaml_write_kv "      " "url" "$url"

    if [[ -n "$insecure" ]]; then
        yaml_write_kv "      " "insecure" "$insecure"
    fi
    echo "---"
    echo ""

    apply_outbound_config "$name" "http" "$existing_rule"
}

generate_direct_yaml_config() {
    local name="$1"

    echo ""
    echo "# 出站规则 - $name (Direct)"
    echo "outbounds:"
    printf '  - name: %s\n' "$(yaml_quote_scalar "$name")"
    echo "    type: direct"
    echo "    direct:"
    echo "      mode: auto"

    if [[ -n "${DIRECT_INTERFACE:-}" ]]; then
        yaml_write_kv "      " "bindDevice" "$DIRECT_INTERFACE"
    fi
    if [[ -n "${DIRECT_IPV4:-}" ]]; then
        yaml_write_kv "      " "bindIPv4" "$DIRECT_IPV4"
    fi
    if [[ -n "${DIRECT_IPV6:-}" ]]; then
        yaml_write_kv "      " "bindIPv6" "$DIRECT_IPV6"
    fi
}

generate_http_yaml_config() {
    local name="$1"

    echo ""
    echo "# 出站规则 - $name (HTTP)"
    echo "outbounds:"
    printf '  - name: %s\n' "$(yaml_quote_scalar "$name")"
    echo "    type: http"
    echo "    http:"
    yaml_write_kv "      " "url" "${HTTP_URL:-http://proxy.example.com:8080}"

    if [[ -n "${HTTP_INSECURE:-}" ]]; then
        yaml_write_kv "      " "insecure" "$HTTP_INSECURE"
    fi
}

apply_outbound_rule() {
    init_rules_library

    echo -e "${BLUE}=== 应用出站规则 ===${NC}"
    echo ""

    # 列出规则库中未应用的规则 - 使用可靠的grep方法
    local unapplied_rules=()
    local rule_count=0

    while IFS= read -r rule_name; do
        if [[ -n "$rule_name" ]]; then
            # 检查是否已应用
            if ! check_rule_applied_status "$rule_name"; then
                unapplied_rules+=("$rule_name")
                ((rule_count++))
                echo "$rule_count. $rule_name"
            fi
        fi
    done < <(grep -o "^[[:space:]]\{2\}[a-zA-Z_][a-zA-Z0-9_]*:" "$RULES_LIBRARY" | sed 's/^[[:space:]]\{2\}\([^:]*\):.*/\1/')

    if [[ ${#unapplied_rules[@]} -eq 0 ]]; then
        echo -e "${YELLOW}没有可应用的规则${NC}"
        wait_for_user
        return
    fi

    echo ""
    read -r -p "请选择要应用的规则 [1-$rule_count]: " choice

    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt $rule_count ]]; then
        log_error "无效选择"
        return 1
    fi

    local selected_rule
    selected_rule="${unapplied_rules[$((choice-1))]}"
    apply_rule_to_config_simple "$selected_rule"

    wait_for_user
}

apply_rule_to_config_simple() {
    local rule_name="$1"

    if [[ -z "$rule_name" ]]; then
        log_error "规则名称不能为空"
        return 1
    fi

    # 简化的YAML解析 - 使用更直接的方法
    local rule_type rule_config

    # 检查规则是否存在，避免规则名进入 grep/awk 正则
    rule_type=$(rules_library_value_for_rule "$rule_name" "type" || true)

    if [[ -z "$rule_type" ]]; then
        log_error "规则 '$rule_name' 不存在于规则库中或无法获取类型"
        return 1
    fi

    log_info "检测到规则类型: $rule_type"
    log_debug "开始检查配置文件中的同类型规则: $HYSTERIA_CONFIG"

    # 通用参数提取函数（去除引号）
    extract_rule_parameter() {
        local rule_name="$1"
        local param_name="$2"
        rules_library_value_for_rule "$rule_name" "$param_name"
    }


    # 先提取配置参数（在使用前定义变量）- 完整参数支持
    local mode="" bindDevice="" bindIPv4="" bindIPv6="" fastOpen=""
    local addr="" username="" password="" url="" insecure=""

    case "$rule_type" in
        "direct")
            # 提取direct类型的所有参数
            mode=$(extract_rule_parameter "$rule_name" "mode")
            bindDevice=$(extract_rule_parameter "$rule_name" "bindDevice")
            bindIPv4=$(extract_rule_parameter "$rule_name" "bindIPv4")
            bindIPv6=$(extract_rule_parameter "$rule_name" "bindIPv6")
            fastOpen=$(extract_rule_parameter "$rule_name" "fastOpen")
            ;;

        "socks5")
            # 提取socks5类型的所有参数
            addr=$(extract_rule_parameter "$rule_name" "addr")
            username=$(extract_rule_parameter "$rule_name" "username")
            password=$(extract_rule_parameter "$rule_name" "password")
            ;;

        "http")
            # 提取http类型的所有参数
            url=$(extract_rule_parameter "$rule_name" "url")
            insecure=$(extract_rule_parameter "$rule_name" "insecure")
            ;;
    esac

    local quoted_rule_name quoted_mode quoted_bindDevice quoted_bindIPv4 quoted_bindIPv6 quoted_fastOpen
    local quoted_addr quoted_username quoted_password quoted_url quoted_insecure
    quoted_rule_name=$(yaml_quote_scalar "$rule_name")
    [[ -n "$mode" ]] && quoted_mode=$(yaml_quote_scalar "$mode")
    [[ -n "$bindDevice" ]] && quoted_bindDevice=$(yaml_quote_scalar "$bindDevice")
    [[ -n "$bindIPv4" ]] && quoted_bindIPv4=$(yaml_quote_scalar "$bindIPv4")
    [[ -n "$bindIPv6" ]] && quoted_bindIPv6=$(yaml_quote_scalar "$bindIPv6")
    [[ -n "$fastOpen" ]] && quoted_fastOpen=$(yaml_quote_scalar "$fastOpen")
    [[ -n "$addr" ]] && quoted_addr=$(yaml_quote_scalar "$addr")
    [[ -n "$username" ]] && quoted_username=$(yaml_quote_scalar "$username")
    [[ -n "$password" ]] && quoted_password=$(yaml_quote_scalar "$password")
    [[ -n "$url" ]] && quoted_url=$(yaml_quote_scalar "$url")
    [[ -n "$insecure" ]] && quoted_insecure=$(yaml_quote_scalar "$insecure")

    log_debug "提取的配置参数: mode=$mode, bindDevice=$bindDevice, addr=$addr, url=$url"

    # 检查配置文件中是否存在同类型规则
    local existing_rule=""
    if existing_rule=$(check_existing_outbound_type "$rule_type"); then
        echo ""
        echo -e "${YELLOW}⚠️  类型冲突检测 ⚠️${NC}"
        echo -e "${YELLOW}检测到配置文件中已存在 ${rule_type} 类型规则: ${CYAN}$existing_rule${NC}"
        echo -e "${YELLOW}同类型只能有一个规则在配置文件中生效${NC}"
        echo ""
        echo -e "${BLUE}选择操作：${NC}"
        echo -e "${GREEN}1.${NC} 继续应用并覆盖现有规则 ${CYAN}$existing_rule${NC}"
        echo -e "${RED}2.${NC} 取消应用操作"
        echo ""
        read -r -p "请选择 [1-2]: " conflict_choice

        case $conflict_choice in
            1)
                echo -e "${BLUE}[INFO]${NC} 将覆盖现有的 $rule_type 规则: $existing_rule"
                echo -e "${BLUE}[INFO]${NC} 继续应用新规则..."
                echo ""
                # 先删除现有的同类型规则
                if ! delete_existing_outbound_from_config "$existing_rule"; then
                    log_warn "删除现有规则失败，将尝试直接覆盖"
                fi
                ;;
            2)
                echo -e "${BLUE}[INFO]${NC} 已取消应用操作"
                return 0
                ;;
            *)
                log_error "无效选择"
                return 1
                ;;
        esac
    fi

    echo -e "${GREEN}准备应用 $rule_type 类型规则: $rule_name${NC}"

    # 直接操作，不创建不必要的备份

    # 生成符合官方标准的outbound配置
    local temp_config
    temp_config=$(create_apply_temp_file)

    if [[ -f "$HYSTERIA_CONFIG" ]] && grep -q "^[[:space:]]*outbounds:" "$HYSTERIA_CONFIG"; then
        # 在现有outbounds中添加新规则 - 修复逻辑错误
        awk -v rule="$quoted_rule_name" -v type="$rule_type" \
            -v mode="$quoted_mode" -v device="$quoted_bindDevice" -v ipv4="$quoted_bindIPv4" -v ipv6="$quoted_bindIPv6" -v fastopen="$quoted_fastOpen" \
            -v addr="$quoted_addr" -v user="$quoted_username" -v pass="$quoted_password" \
            -v url="$quoted_url" -v insecure="$quoted_insecure" '
        /^[[:space:]]*outbounds:/ {
            print $0
            # 根据官方格式添加完整的outbound配置
            print "  - name: " rule
            print "    type: " type

            if (type == "direct") {
                print "    direct:"
                if (mode != "") print "      mode: " mode
                if (ipv4 != "") print "      bindIPv4: " ipv4
                if (ipv6 != "") print "      bindIPv6: " ipv6
                if (device != "") print "      bindDevice: " device
                if (fastopen != "") print "      fastOpen: " fastopen
            } else if (type == "socks5") {
                print "    socks5:"
                if (addr != "") print "      addr: " addr
                if (user != "") print "      username: " user
                if (pass != "") print "      password: " pass
            } else if (type == "http") {
                print "    http:"
                if (url != "") print "      url: " url
                if (insecure != "") print "      insecure: " insecure
            }
            # 不使用next，继续处理后续行以保留其他现有规则
        }
        !/^[[:space:]]*outbounds:/ { print }
        ' "$HYSTERIA_CONFIG" > "$temp_config"
    else
        # 创建新的outbounds节点
        if [[ -f "$HYSTERIA_CONFIG" ]]; then
            cp "$HYSTERIA_CONFIG" "$temp_config"
        else
            echo "# Hysteria2 配置文件" > "$temp_config"
        fi

        # 添加符合官方标准的outbounds节点
        cat >> "$temp_config" << EOF

# 出站配置
outbounds:
  - name: $quoted_rule_name
    type: $rule_type
EOF

        # 根据规则类型添加完整的具体配置
        case "$rule_type" in
            "direct")
                echo "    direct:" >> "$temp_config"
                [[ -n "$quoted_mode" ]] && yaml_write_kv "      " "mode" "$mode" >> "$temp_config"
                [[ -n "$quoted_bindIPv4" ]] && yaml_write_kv "      " "bindIPv4" "$bindIPv4" >> "$temp_config"
                [[ -n "$quoted_bindIPv6" ]] && yaml_write_kv "      " "bindIPv6" "$bindIPv6" >> "$temp_config"
                [[ -n "$quoted_bindDevice" ]] && yaml_write_kv "      " "bindDevice" "$bindDevice" >> "$temp_config"
                [[ -n "$quoted_fastOpen" ]] && yaml_write_kv "      " "fastOpen" "$fastOpen" >> "$temp_config"
                ;;
            "socks5")
                echo "    socks5:" >> "$temp_config"
                [[ -n "$quoted_addr" ]] && yaml_write_kv "      " "addr" "$addr" >> "$temp_config"
                [[ -n "$quoted_username" ]] && yaml_write_kv "      " "username" "$username" >> "$temp_config"
                [[ -n "$quoted_password" ]] && yaml_write_kv "      " "password" "$password" >> "$temp_config"
                ;;
            "http")
                echo "    http:" >> "$temp_config"
                [[ -n "$quoted_url" ]] && yaml_write_kv "      " "url" "$url" >> "$temp_config"
                [[ -n "$quoted_insecure" ]] && yaml_write_kv "      " "insecure" "$insecure" >> "$temp_config"
                ;;
        esac
    fi

    # 应用配置
    if [[ -s "$temp_config" ]]; then
        if safe_move_config "$temp_config" "$HYSTERIA_CONFIG"; then
            log_debug "配置文件权限已按安全策略修复"
        else
            log_error "配置应用失败"
            rm -f "$temp_config"
            return 1
        fi

        log_success "规则 '$rule_name' 已应用到配置文件"

        # 更新状态文件：逐行解析和重写，避免规则名进入 grep/sed 正则或命令表达式
        local state_has_rule=false
        local state_line state_item

        if [[ -f "$RULES_STATE" ]]; then
            while IFS= read -r state_line || [[ -n "$state_line" ]]; do
                if [[ "$state_line" =~ ^[[:space:]]*-[[:space:]]*(.*)$ ]]; then
                    state_item=$(yaml_unquote_scalar "${BASH_REMATCH[1]}")
                    if [[ "$state_item" == "$rule_name" ]]; then
                        state_has_rule=true
                        break
                    fi
                fi
            done < "$RULES_STATE"
        fi

        if [[ "$state_has_rule" == false ]]; then
            local temp_state
            temp_state=$(create_temp_file)
            if awk -v rule="$(yaml_quote_scalar "$rule_name")" '
            BEGIN { inserted = 0 }
            /^applied_rules:[[:space:]]*\[[[:space:]]*\][[:space:]]*$/ {
                print "applied_rules:"
                print "  - " rule
                inserted = 1
                next
            }
            /^applied_rules:[[:space:]]*$/ {
                print $0
                print "  - " rule
                inserted = 1
                next
            }
            { print }
            END {
                if (!inserted) {
                    print "applied_rules:"
                    print "  - " rule
                }
            }
            ' "$RULES_STATE" > "$temp_state" 2>/dev/null; then
                if [[ -s "$temp_state" ]]; then
                    replace_config_file_securely "$temp_state" "$RULES_STATE" || rm -f "$temp_state"
                else
                    rm -f "$temp_state"
                fi
            else
                rm -f "$temp_state"
            fi
        fi

        log_info "状态已更新"
        log_success "规则应用完成！"

        # 交互式重启确认
        echo ""
        echo -e "${YELLOW}⚠️  配置已更新，需要重启服务生效 ⚠️${NC}"
        echo -e "${BLUE}是否立即重启 Hysteria2 服务？${NC}"
        echo ""
        echo -e "${GREEN}1.${NC} 是，立即重启服务（推荐）"
        echo -e "${YELLOW}2.${NC} 否，稍后手动重启"
        echo ""
        read -r -p "请选择 [1-2]: " restart_choice

        case $restart_choice in
            1)
                echo ""
                echo -e "${BLUE}[INFO]${NC} 正在重启 Hysteria2 服务..."
                if systemctl restart hysteria-server 2>/dev/null; then
                    echo -e "${GREEN}✅ 服务重启成功，新配置已生效${NC}"
                    # 等待服务启动
                    sleep 2
                    if systemctl is-active hysteria-server >/dev/null 2>&1; then
                        echo -e "${GREEN}✅ 服务运行状态正常${NC}"
                    else
                        echo -e "${RED}⚠️  服务重启后状态异常，请检查配置${NC}"
                        echo -e "${YELLOW}建议执行: journalctl -u hysteria-server -f${NC}"
                    fi
                else
                    echo -e "${RED}❌ 服务重启失败${NC}"
                    echo -e "${YELLOW}请手动重启: systemctl restart hysteria-server${NC}"
                fi
                ;;
            2)
                echo ""
                echo -e "${BLUE}[INFO]${NC} 已跳过自动重启"
                echo -e "${YELLOW}请稍后手动重启服务生效新配置:${NC}"
                echo -e "${CYAN}  systemctl restart hysteria-server${NC}"
                ;;
            *)
                echo ""
                echo -e "${YELLOW}无效选择，已跳过自动重启${NC}"
                echo -e "${YELLOW}请手动重启服务: systemctl restart hysteria-server${NC}"
                ;;
        esac

        return 0
    else
        log_error "配置应用失败"
        rm -f "$temp_config"
        return 1
    fi
}

add_socks5_outbound() {
    echo -e "${BLUE}=== 配置 SOCKS5 代理出站 ===${NC}"
    echo ""

    local name addr username password

    read -r -p "出站名称 (例: socks5_proxy): " name
    if [[ -z "$name" ]]; then
        name="socks5_out"
    elif [[ ! "$name" =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo -e "${RED}名称只能包含字母、数字和下划线，使用默认名称${NC}"
        name="socks5_out"
    fi

    read -r -p "代理服务器地址:端口 (例: proxy.example.com:1080): " addr
    if [[ -z "$addr" ]]; then
        log_error "代理地址不能为空"
        return 1
    fi

    read -r -p "是否需要认证？ [y/N]: " need_auth

    if [[ $need_auth =~ ^[Yy]$ ]]; then
        read -r -p "用户名: " username
        read -r -s -p "密码: " password
        echo ""
    fi

    # 保存配置参数供后续使用
    export SOCKS5_ADDR="$addr"
    export SOCKS5_USERNAME="$username"
    export SOCKS5_PASSWORD="$password"

    # 生成配置
    generate_socks5_config "$name" "$addr" "$username" "$password"
}

generate_socks5_config() {
    local name="$1" addr="$2" username="$3" password="$4"

    echo "生成的 SOCKS5 出站配置："
    echo "---"
    echo "outbounds:"
    printf '  - name: %s\n' "$(yaml_quote_scalar "$name")"
    echo "    type: socks5"
    echo "    socks5:"
    yaml_write_kv "      " "addr" "$addr"

    if [[ -n "$username" ]]; then
        yaml_write_kv "      " "username" "$username"
        yaml_write_kv "      " "password" "$password"
    fi
    echo "---"
    echo ""

    apply_outbound_config "$name" "socks5" "$existing_rule"
}

generate_socks5_yaml_config() {
    local name="$1"

    echo ""
    echo "# 出站规则 - $name (SOCKS5)"
    echo "outbounds:"
    printf '  - name: %s\n' "$(yaml_quote_scalar "$name")"
    echo "    type: socks5"
    echo "    socks5:"
    yaml_write_kv "      " "addr" "${SOCKS5_ADDR:-proxy.example.com:1080}"

    if [[ -n "${SOCKS5_USERNAME:-}" ]]; then
        yaml_write_kv "      " "username" "$SOCKS5_USERNAME"
        yaml_write_kv "      " "password" "$SOCKS5_PASSWORD"
    fi
}

