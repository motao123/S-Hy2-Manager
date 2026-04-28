#!/bin/bash
# 出站规则查看/展示
#
# 依赖: common.sh, outbound-core.sh
# 导出函数: show_outbound_menu, view_current_outbound, view_outbound_rules, manage_outbound

show_outbound_menu() {
    clear
    echo -e "${CYAN}=== Hysteria2 出站规则管理 ===${NC}"
    echo ""
    echo -e "${GREEN}1.${NC} 查看出站规则"
    echo -e "${GREEN}2.${NC} 新增出站规则"
    echo -e "${GREEN}3.${NC} 应用出站规则"
    echo -e "${GREEN}4.${NC} 修改出站规则"
    echo -e "${GREEN}5.${NC} 删除出站规则"
    echo ""
    echo -e "${RED}0.${NC} 返回主菜单"
    echo ""
}

view_current_outbound() {
    log_info "查看当前出站配置"

    # 使用统一的检查函数
    if ! check_hysteria2_ready "config"; then
        return 0  # 友好返回，不退出脚本
    fi

    echo -e "${BLUE}=== 当前出站配置 ===${NC}"
    echo ""

    # 检查是否有出站配置 - 改进的匹配模式
    if grep -q "^[[:space:]]*outbounds:" "$HYSTERIA_CONFIG"; then
        echo -e "${GREEN}出站规则：${NC}"
        # 使用更精确的sed匹配，支持缩进
        sed -n '/^[[:space:]]*outbounds:/,/^[a-zA-Z]/p' "$HYSTERIA_CONFIG" | sed '$d'
        echo ""

        # 显示出站规则统计
        local outbound_count
        outbound_count=$(grep -c "^[[:space:]]*-[[:space:]]*name:" "$HYSTERIA_CONFIG" || echo "0")
        echo -e "${CYAN}共找到 $outbound_count 个出站规则${NC}"
        echo ""
    else
        echo -e "${YELLOW}当前配置中没有出站规则（使用默认直连）${NC}"
        echo ""
    fi

    # 检查是否有 ACL 配置 - 改进的匹配和显示
    if grep -q "^[[:space:]]*acl:" "$HYSTERIA_CONFIG"; then
        echo -e "${GREEN}ACL 规则：${NC}"
        # 改进的ACL显示逻辑，完整显示inline内容
        local in_acl=false
        local acl_indent=""
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*acl: ]]; then
                in_acl=true
                echo "$line"
                # 记录ACL节点的缩进级别
                acl_indent=$(echo "$line" | sed 's/acl:.*//')
            elif [[ "$in_acl" == true ]]; then
                # 检查是否是同级或更高级的配置节点（结束ACL显示）
                if [[ "$line" =~ ^[[:space:]]*[a-zA-Z]+:[[:space:]]*$ ]] && [[ ! "$line" =~ ^[[:space:]]*(inline|file): ]]; then
                    local line_indent
                    line_indent=$(echo "$line" | sed 's/[a-zA-Z].*//')
                    # 如果缩进级别等于或小于ACL节点，说明ACL节点结束
                    if [[ ${#line_indent} -le ${#acl_indent} ]]; then
                        break
                    fi
                fi
                echo "$line"
            fi
        done < "$HYSTERIA_CONFIG"
    else
        echo -e "${YELLOW}当前配置中没有 ACL 规则（使用默认路由）${NC}"
    fi

    echo ""
    wait_for_user
}

view_outbound_rules() {
    init_rules_library

    echo -e "${BLUE}=== 出站规则总览 ===${NC}"
    echo ""

    # 显示配置文件中的规则
    echo -e "${GREEN}📄 配置文件中的规则：${NC}"
    local config_rule_count=0
    while IFS= read -r rule_name; do
        if [[ -n "$rule_name" ]]; then
            ((config_rule_count++))
            echo "  $config_rule_count. $rule_name ✅"
        fi
    done < <(get_config_outbound_rules)

    if [[ $config_rule_count -eq 0 ]]; then
        echo "  (无规则)"
    fi

    echo ""

    # 显示规则库中的规则
    echo -e "${CYAN}📚 规则库中的规则：${NC}"
    if [[ -f "$RULES_LIBRARY" ]] && grep -q "rules:" "$RULES_LIBRARY"; then
        local lib_count=0
        # 使用简单可靠的grep方法直接提取规则名
        while IFS= read -r rule_name; do
            if [[ -n "$rule_name" ]]; then
                ((lib_count++))
                # 检查是否已应用 - 只根据配置文件实际状态
                local status
                status=$(get_rule_status_text "$rule_name")
                echo "  $lib_count. $rule_name $status"
            fi
        done < <(grep -o "^[[:space:]]\{2\}[a-zA-Z_][a-zA-Z0-9_]*:" "$RULES_LIBRARY" | sed 's/^[[:space:]]\{2\}\([^:]*\):.*/\1/')

        if [[ $lib_count -eq 0 ]]; then
            echo "  (无规则)"
        fi
    else
        echo "  (无规则)"
    fi

    echo ""

    # 询问是否查看单个规则详细参数
    echo -e "${BLUE}是否查看特定规则的详细参数？${NC}"
    echo -e "${GREEN}1.${NC} 是，选择规则查看详细参数"
    echo -e "${YELLOW}2.${NC} 否，返回上级菜单"
    echo ""
    read -r -p "请选择 [1-2]: " detail_choice

    case $detail_choice in
        1)
            view_single_rule_details
            ;;
        2)
            ;;
        *)
            echo ""
            echo -e "${YELLOW}无效选择，返回上级菜单${NC}"
            ;;
    esac

    wait_for_user
}

view_single_rule_details() {
    echo ""
    echo -e "${BLUE}=== 查看规则详细参数 ===${NC}"
    echo ""

    # 列出规则库中的规则
    local rules=()
    local rule_count=0

    echo -e "${CYAN}📚 规则库中的规则：${NC}"
    while IFS= read -r rule_name; do
        if [[ -n "$rule_name" ]]; then
            rules+=("$rule_name")
            ((rule_count++))
            # 检查是否已应用
            local status="❌ 未应用"
            if check_rule_applied_status "$rule_name"; then
                status="✅ 已应用"
            fi
            echo "  $rule_count. $rule_name $status"
        fi
    done < <(grep -o "^[[:space:]]\{2\}[a-zA-Z_][a-zA-Z0-9_]*:" "$RULES_LIBRARY" | sed 's/^[[:space:]]\{2\}\([^:]*\):.*/\1/')

    if [[ ${#rules[@]} -eq 0 ]]; then
        echo "  (无规则)"
        echo ""
        return
    fi

    echo ""
    read -r -p "请选择要查看的规则 [1-$rule_count]: " choice

    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt $rule_count ]]; then
        echo -e "${RED}无效选择${NC}"
        return 1
    fi

    local selected_rule
    selected_rule="${rules[$((choice-1))]}"

    echo ""
    echo -e "${BLUE}=== 规则详细信息: ${CYAN}$selected_rule${NC} ===${NC}"
    echo ""

    # 获取规则基本信息
    echo -e "${GREEN}📋 基本信息：${NC}"
    local rule_type
    rule_type=$(awk -v rule="$selected_rule" '
    BEGIN { in_rule = 0 }
    $0 ~ "^[[:space:]]*" rule ":[[:space:]]*$" { in_rule = 1; next }
    in_rule && /^[[:space:]]*type:[[:space:]]*/ {
        gsub(/^[[:space:]]*type:[[:space:]]*/, "");
        gsub(/[[:space:]]*$/, "");
        print $0;
        exit
    }
    in_rule && /^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*:[[:space:]]*$/ { in_rule = 0 }
    ' "$RULES_LIBRARY")

    local rule_desc
    rule_desc=$(awk -v rule="$selected_rule" '
    BEGIN { in_rule = 0 }
    $0 ~ "^[[:space:]]*" rule ":[[:space:]]*$" { in_rule = 1; next }
    in_rule && /^[[:space:]]*description:[[:space:]]*/ {
        gsub(/^[[:space:]]*description:[[:space:]]*"?/, "");
        gsub(/"?[[:space:]]*$/, "");
        print $0;
        exit
    }
    in_rule && /^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*:[[:space:]]*$/ { in_rule = 0 }
    ' "$RULES_LIBRARY")

    echo "  规则名称: $selected_rule"
    echo "  规则类型: ${rule_type:-"未知"}"
    echo "  规则描述: ${rule_desc:-"无描述"}"

    # 检查应用状态
    local applied_status
    applied_status=$(get_rule_status_text "$selected_rule")
    echo "  应用状态: $applied_status"

    echo ""

    # 显示配置参数
    echo -e "${GREEN}⚙️  配置参数：${NC}"
    case "$rule_type" in
        "direct")
            show_direct_parameters "$selected_rule"
            ;;
        "socks5")
            show_socks5_parameters "$selected_rule"
            ;;
        "http")
            show_http_parameters "$selected_rule"
            ;;
        *)
            echo "  不支持的规则类型: $rule_type"
            ;;
    esac

    echo ""
}

show_direct_parameters() {
    local rule_name="$1"
    echo "  类型: Direct (直连)"

    local mode
    mode=$(get_rule_config_value "$rule_name" "mode")
    local bindIPv4
    bindIPv4=$(get_rule_config_value "$rule_name" "bindIPv4")
    local bindIPv6
    bindIPv6=$(get_rule_config_value "$rule_name" "bindIPv6")
    local bindDevice
    bindDevice=$(get_rule_config_value "$rule_name" "bindDevice")
    local fastOpen
    fastOpen=$(get_rule_config_value "$rule_name" "fastOpen")

    echo "  连接模式 (mode): ${mode:-"auto (默认)"}"
    echo "  绑定IPv4 (bindIPv4): ${bindIPv4:-"未设置"}"
    echo "  绑定IPv6 (bindIPv6): ${bindIPv6:-"未设置"}"
    echo "  绑定设备 (bindDevice): ${bindDevice:-"未设置"}"
    echo "  快速打开 (fastOpen): ${fastOpen:-"false (默认)"}"
}

show_http_parameters() {
    local rule_name="$1"
    echo "  类型: HTTP/HTTPS 代理"

    local url
    url=$(get_rule_config_value "$rule_name" "url")
    local insecure
    insecure=$(get_rule_config_value "$rule_name" "insecure")

    echo "  代理URL (url): ${url:-"未设置"}"
    echo "  忽略TLS验证 (insecure): ${insecure:-"false (默认)"}"
}

manage_outbound() {
    init_outbound_manager

    while true; do
        show_outbound_menu

        local choice
        read -r -p "请选择操作 [0-5]: " choice

        case $choice in
            1) view_outbound_rules ;;
            2) add_outbound_rule_new ;;
            3) apply_outbound_rule ;;
            4) modify_outbound_rule ;;
            5) delete_outbound_rule_new ;;
            0)
                log_info "返回主菜单"
                break
                ;;
            *)
                log_error "无效选择，请重新输入"
                wait_for_user
                ;;
        esac
    done
}

check_rule_type_conflict() {
    local target_type="$1"
    init_rules_library

    if [[ ! -f "$RULES_LIBRARY" ]]; then
        return 0  # 文件不存在，没有冲突
    fi

    local in_rules_section=false
    local current_rule_name=""
    local current_rule_type=""

    while IFS= read -r line; do
        # 检测rules节点
        if [[ "$line" =~ ^rules:[[:space:]]*$ ]]; then
            in_rules_section=true
            continue
        fi

        # 离开rules节点 - 只有0级缩进的键才退出
        if [[ "$in_rules_section" == true ]] && [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*$ ]]; then
            break
        fi

        # 在rules节点中
        if [[ "$in_rules_section" == true ]]; then
            # 检测规则名（2级缩进）
            if [[ "$line" =~ ^[[:space:]]{2}([a-zA-Z_][a-zA-Z0-9_]+):[[:space:]]*$ ]]; then
                current_rule_name="${BASH_REMATCH[1]}"
                current_rule_type=""
            fi
            # 检测规则类型（4级缩进）
            if [[ "$line" =~ ^[[:space:]]{4}type:[[:space:]]*(.+)$ ]]; then
                current_rule_type="${BASH_REMATCH[1]}"
                # 如果类型匹配，返回规则名
                if [[ "$current_rule_type" == "$target_type" ]]; then
                    echo "$current_rule_name"
                    return 0
                fi
            fi
        fi
    done < "$RULES_LIBRARY"

    return 1  # 没有找到冲突
}

check_existing_outbound_type() {
    local target_type="$1"
    local config_file="${2:-$HYSTERIA_CONFIG}"

    if [[ ! -f "$config_file" ]]; then
        return 1  # 文件不存在，没有冲突
    fi

    # 查找同类型的规则
    local in_outbounds=false
    local current_rule_type=""
    local current_rule_name=""

    while IFS= read -r line; do
        # 检测outbounds节点
        if [[ "$line" =~ ^[[:space:]]*outbounds: ]]; then
            in_outbounds=true
            continue
        fi

        # 离开outbounds节点
        if [[ "$in_outbounds" == true ]] && [[ "$line" =~ ^[[:space:]]*[a-zA-Z]+:[[:space:]]*$ ]] && [[ ! "$line" =~ ^[[:space:]]*- ]]; then
            in_outbounds=false
        fi

        # 在outbounds节点中
        if [[ "$in_outbounds" == true ]]; then
            # 检测规则名
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*(.+)$ ]]; then
                current_rule_name="${BASH_REMATCH[1]}"
                current_rule_name=$(echo "$current_rule_name" | xargs)  # 去除前后空格
            fi

            # 检测规则类型
            if [[ "$line" =~ ^[[:space:]]*type:[[:space:]]*(.+)$ ]]; then
                current_rule_type="${BASH_REMATCH[1]}"
                current_rule_type=$(echo "$current_rule_type" | xargs)  # 去除前后空格

                # 检查是否与目标类型匹配
                if [[ "$current_rule_type" == "$target_type" ]]; then
                    echo "$current_rule_name"  # 返回现有同类型规则的名称
                    return 0
                fi
            fi
        fi
    done < "$config_file"

    return 1  # 未找到同类型规则
}

check_rule_applied_status() {
    local rule_name="$1"
    local line current_name
    
    if [[ -z "$rule_name" ]]; then
        return 1
    fi
    
    if [[ ! -f "$HYSTERIA_CONFIG" ]]; then
        return 1
    fi

    # 标准检查：逐行解析配置中的 name 字段，避免规则名进入 grep 正则
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*name:[[:space:]]*(.*)$ ]]; then
            current_name=$(yaml_unquote_scalar "${BASH_REMATCH[1]}")
            if [[ "$current_name" == "$rule_name" ]]; then
                return 0
            fi
        fi
    done < "$HYSTERIA_CONFIG"

    return 1
}

get_rule_status_text() {
    local rule_name="$1"
    
    if check_rule_applied_status "$rule_name"; then
        echo "✅ 已应用"
    else
        echo "❌ 未应用"
    fi
}

show_socks5_parameters() {
    local rule_name="$1"
    echo "  类型: SOCKS5 代理"

    local addr
    addr=$(get_rule_config_value "$rule_name" "addr")
    local username
    username=$(get_rule_config_value "$rule_name" "username")
    local password
    password=$(get_rule_config_value "$rule_name" "password")

    echo "  代理地址 (addr): ${addr:-"未设置"}"
    echo "  用户名 (username): ${username:-"未设置"}"
    echo "  密码 (password): ${password:+"***已设置***"}"
    [[ -z "$password" ]] && echo "  密码 (password): 未设置"
}

