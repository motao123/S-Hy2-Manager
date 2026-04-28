#!/bin/bash
# 客户端配置导出模块
#
# 依赖: common.sh, user-manager.sh
# 导出函数: client_export, generate_client_yaml, generate_client_uri, generate_qr_code, generate_subscription_link

# ========== 客户端导出菜单 ==========
client_export() {
    while true; do
        clear
        echo -e "${CYAN}================================================${NC}"
        echo -e "${CYAN}           客户端配置导出${NC}"
        echo -e "${CYAN}================================================${NC}"
        echo ""

        # 显示当前服务器信息
        local server_ip
        server_ip=$(get_server_ip)
        local server_domain
        server_domain=$(get_server_domain)
        local listen_port
        listen_port=$(get_listen_port)

        echo -e "服务器IP: ${GREEN}${server_ip}${NC}"
        if [[ -n "$server_domain" ]]; then
            echo -e "服务器域名: ${GREEN}${server_domain}${NC}"
        fi
        echo -e "端口: ${GREEN}${listen_port:-443}${NC}"
        echo ""

        echo -e "${YELLOW}请选择导出方式:${NC}"
        echo ""
        echo -e "${GREEN} 1.${NC} 生成客户端配置文件 (YAML)"
        echo -e "${GREEN} 2.${NC} 生成 Hysteria2 URI 链接"
        echo -e "${GREEN} 3.${NC} 生成二维码 (需 qrencode)"
        echo -e "${GREEN} 4.${NC} 生成订阅链接 (Base64)"
        echo -e "${CYAN} 5.${NC} 一键导出全部"
        echo -e "${RED} 0.${NC} 返回主菜单"
        echo ""
        echo -n -e "${BLUE}请输入选项 [0-5]: ${NC}"

        local choice
        read -r choice

        case $choice in
            1) generate_client_yaml ;;
            2) generate_client_uri ;;
            3) generate_qr_code ;;
            4) generate_subscription_link ;;
            5) export_all ;;
            0) return 0 ;;
            *) echo -e "${RED}无效选项${NC}" ;;
        esac

        echo ""
        echo -n "按回车键继续..."
        read -r
    done
}

# ========== 获取监听端口 ==========
get_listen_port() {
    if [[ ! -f "$HYSTERIA_CONFIG" ]]; then
        echo "443"
        return
    fi
    local port
    port=$(grep -E "^\s*listen:" "$HYSTERIA_CONFIG" | grep -oP ':\K[0-9]+')
    echo "${port:-443}"
}

# ========== 获取认证信息 ==========
get_client_auth_info() {
    # 输出格式: mode|user_or_pass（仅最终结果走 stdout，交互菜单走 stderr）
    # 密码值会去除 YAML 引号
    local auth_mode
    auth_mode=$(get_auth_mode 2>/dev/null || echo "password")

    if [[ "$auth_mode" == "userpass" ]]; then
        # 多用户模式，让用户选择（菜单输出到 stderr，不污染返回值）
        echo -e "${YELLOW}选择要导出的用户:${NC}" >&2
        local users
        users=$(get_all_users)
        local i=1
        while IFS= read -r user; do
            echo -e "  ${GREEN}$i.${NC} $user" >&2
            ((i++))
        done <<< "$users"
        echo -n "请选择 [1-$((i-1))]: " >&2
        local choice
        read -r choice

        local selected_user
        selected_user=$(echo "$users" | sed -n "${choice}p")
        local password
        # 从 userpass 段逐行解析密码，避免用户名进入 grep 正则，并去除 YAML 引号
        password=""
        local line in_userpass=false
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ ^[[:space:]]*userpass:[[:space:]]*$ ]]; then
                in_userpass=true
                continue
            elif [[ "$in_userpass" == true && "$line" =~ ^[[:space:]]*([a-zA-Z0-9_.-]+):[[:space:]]*(.*)$ ]]; then
                if [[ "${BASH_REMATCH[1]}" == "$selected_user" ]]; then
                    password=$(yaml_unquote_scalar "${BASH_REMATCH[2]}")
                    break
                fi
            elif [[ "$in_userpass" == true && "$line" =~ ^[a-zA-Z] ]]; then
                break
            fi
        done < "$HYSTERIA_CONFIG"
        echo "userpass|${selected_user}:${password}"
    else
        # 单密码模式
        local password
        password=$(grep -A1 "type: password" "$HYSTERIA_CONFIG" 2>/dev/null | grep "password:" | awk '{print $2}')
        password=$(yaml_unquote_scalar "$password")
        echo "password|${password}"
    fi
}

# ========== 获取混淆信息 ==========
get_obfs_info() {
    # 输出格式: type:password 或空（密码已去除 YAML 引号）
    if [[ ! -f "$HYSTERIA_CONFIG" ]]; then
        return
    fi

    if grep -q "type: salamander" "$HYSTERIA_CONFIG" 2>/dev/null; then
        local obfs_pass
        obfs_pass=$(grep -A3 "type: salamander" "$HYSTERIA_CONFIG" | grep "password:" | awk '{print $2}')
        obfs_pass=$(yaml_unquote_scalar "$obfs_pass")
        echo "salamander:${obfs_pass}"
    fi
}

# ========== 获取 SNI 信息 ==========
get_sni_info() {
    local server_domain
    server_domain=$(get_server_domain)

    if [[ -n "$server_domain" ]]; then
        echo "$server_domain"
        return
    fi

    # 从 ACME 配置获取
    if [[ -f "$HYSTERIA_CONFIG" ]]; then
        grep -A2 "acme:" "$HYSTERIA_CONFIG" 2>/dev/null | grep "  - " | head -1 | sed 's/.*- //'
    fi
}

# ========== 生成客户端 YAML 配置 ==========
generate_client_yaml() {
    echo -e "${CYAN}=== 生成客户端配置文件 ===${NC}"
    echo ""

    local auth_info
    auth_info=$(get_client_auth_info)
    local auth_mode="${auth_info%%|*}"
    local auth_value="${auth_info##*|}"

    local server_address
    server_address=$(get_server_address)
    local port
    port=$(get_listen_port)
    local sni
    sni=$(get_sni_info)
    local obfs_info
    obfs_info=$(get_obfs_info)

    # 判断证书类型
    local insecure="false"
    if grep -q "^tls:" "$HYSTERIA_CONFIG" 2>/dev/null; then
        insecure="true"
    fi

    # 生成配置
    local client_config
    client_config=$(cat << YAMLCONF
# Hysteria2 客户端配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

server: ${server_address}:${port}

auth: $(yaml_quote_scalar "${auth_value}")

tls:
  sni: ${sni:-$server_address}
  insecure: ${insecure}
YAMLCONF
)

    # 添加混淆配置
    if [[ -n "$obfs_info" ]]; then
        local obfs_type="${obfs_info%%:*}"
        local obfs_pass="${obfs_info##*:}"
        client_config+=$(cat << YAMLCONF

obfs:
  type: ${obfs_type}
  ${obfs_type}:
    password: $(yaml_quote_scalar "${obfs_pass}")
YAMLCONF
)
    fi

    # 添加代理配置
    client_config+=$(cat << YAMLCONF

socks5:
  listen: 127.0.0.1:1080

http:
  listen: 127.0.0.1:8080
YAMLCONF
)

    # 保存到文件
    local output_dir="$HYSTERIA_DIR/client-configs"
    mkdir -p "$output_dir"
    local output_file
    output_file="$output_dir/client-$(date +%Y%m%d_%H%M%S).yaml"

    echo "$client_config" > "$output_file"
    chmod 600 "$output_file"

    echo ""
    echo -e "${GREEN}✅ 客户端配置已生成${NC}"
    echo -e "文件: ${CYAN}$output_file${NC}"
    echo ""
    echo "--- 配置内容 ---"
    echo "$client_config"
    echo "--- 结束 ---"
}

# ========== 生成 Hysteria2 URI ==========
generate_client_uri() {
    echo -e "${CYAN}=== 生成 Hysteria2 URI ===${NC}"
    echo ""

    local auth_info
    auth_info=$(get_client_auth_info)
    local auth_mode="${auth_info%%|*}"
    local auth_value="${auth_info##*|}"

    local server_address
    server_address=$(get_server_address)
    local port
    port=$(get_listen_port)
    local sni
    sni=$(get_sni_info)
    local obfs_info
    obfs_info=$(get_obfs_info)

    # 判断证书类型
    local insecure="0"
    if grep -q "^tls:" "$HYSTERIA_CONFIG" 2>/dev/null; then
        insecure="1"
    fi

    # 构建 URI
    # hysteria2://auth@server:port?sni=xxx&insecure=0&obfs=salamander&obfs-password=xxx
    # auth 中的特殊字符必须 URL 编码
    # 多用户模式: auth_value = "username:password"，需要分别编码
    local encoded_auth
    if [[ "$auth_mode" == "userpass" ]]; then
        local uri_user="${auth_value%%:*}"
        local uri_pass="${auth_value#*:}"
        encoded_auth="$(urlencode "$uri_user"):$(urlencode "$uri_pass")"
    else
        encoded_auth=$(urlencode "$auth_value")
    fi
    local uri="hysteria2://${encoded_auth}@${server_address}:${port}"
    local params=""

    if [[ -n "$sni" ]]; then
        params+="sni=${sni}"
    fi

    if [[ -n "$params" ]]; then
        params+="&"
    fi
    params+="insecure=${insecure}"

    if [[ -n "$obfs_info" ]]; then
        local obfs_type="${obfs_info%%:*}"
        local obfs_pass="${obfs_info##*:}"
        local encoded_obfs_pass
        encoded_obfs_pass=$(urlencode "$obfs_pass")
        params+="&obfs=${obfs_type}&obfs-password=${encoded_obfs_pass}"
    fi

    uri+="?${params}"

    echo ""
    echo -e "${GREEN}✅ Hysteria2 URI:${NC}"
    echo -e "${CYAN}${uri}${NC}"
    echo ""
    echo -e "${YELLOW}提示: 复制此链接到 Hysteria2 客户端即可使用${NC}"
}

# ========== 生成二维码 ==========
generate_qr_code() {
    echo -e "${CYAN}=== 生成二维码 ===${NC}"
    echo ""

    # 检查 qrencode 是否安装
    if ! command -v qrencode &>/dev/null; then
        echo -e "${YELLOW}qrencode 未安装，正在安装...${NC}"
        apt-get update -qq && apt-get install -y -qq qrencode
    fi

    local auth_info
    auth_info=$(get_client_auth_info)
    local auth_mode="${auth_info%%|*}"
    local auth_value="${auth_info##*|}"

    local server_address
    server_address=$(get_server_address)
    local port
    port=$(get_listen_port)
    local sni
    sni=$(get_sni_info)
    local obfs_info
    obfs_info=$(get_obfs_info)

    local insecure="0"
    if grep -q "^tls:" "$HYSTERIA_CONFIG" 2>/dev/null; then
        insecure="1"
    fi

    local encoded_auth
    if [[ "$auth_mode" == "userpass" ]]; then
        local uri_user="${auth_value%%:*}"
        local uri_pass="${auth_value#*:}"
        encoded_auth="$(urlencode "$uri_user"):$(urlencode "$uri_pass")"
    else
        encoded_auth=$(urlencode "$auth_value")
    fi
    local uri="hysteria2://${encoded_auth}@${server_address}:${port}?sni=${sni:-$server_address}&insecure=${insecure}"

    if [[ -n "$obfs_info" ]]; then
        local obfs_type="${obfs_info%%:*}"
        local obfs_pass="${obfs_info##*:}"
        local encoded_obfs_pass
        encoded_obfs_pass=$(urlencode "$obfs_pass")
        uri+="&obfs=${obfs_type}&obfs-password=${encoded_obfs_pass}"
    fi

    echo -e "${GREEN}✅ 二维码:${NC}"
    echo ""
    qrencode -t ANSIUTF8 "$uri"
    echo ""
    echo -e "${YELLOW}提示: 用手机 Hysteria2 客户端扫描此二维码${NC}"
}

# ========== 生成订阅链接 ==========
generate_subscription_link() {
    echo -e "${CYAN}=== 生成订阅链接 ===${NC}"
    echo ""

    local server_address
    server_address=$(get_server_address)
    local port
    port=$(get_listen_port)
    local sni
    sni=$(get_sni_info)
    local obfs_info
    obfs_info=$(get_obfs_info)

    local insecure="0"
    if grep -q "^tls:" "$HYSTERIA_CONFIG" 2>/dev/null; then
        insecure="1"
    fi

    # 构建所有用户的 URI 列表
    local uri_list=""
    local auth_mode
    auth_mode=$(get_auth_mode 2>/dev/null || echo "password")

    if [[ "$auth_mode" == "userpass" ]]; then
        # 多用户：每个用户一个 URI
        while IFS= read -r username; do
            local password
            # 逐行解析 userpass 段获取密码，避免用户名进入 grep 正则
            password=""
            local line in_userpass=false
            while IFS= read -r line || [[ -n "$line" ]]; do
                if [[ "$line" =~ ^[[:space:]]*userpass:[[:space:]]*$ ]]; then
                    in_userpass=true
                    continue
                elif [[ "$in_userpass" == true && "$line" =~ ^[[:space:]]*([a-zA-Z0-9_.-]+):[[:space:]]*(.*)$ ]]; then
                    if [[ "${BASH_REMATCH[1]}" == "$username" ]]; then
                        password=$(yaml_unquote_scalar "${BASH_REMATCH[2]}")
                        break
                    fi
                elif [[ "$in_userpass" == true && "$line" =~ ^[a-zA-Z] ]]; then
                    break
                fi
            done < "$HYSTERIA_CONFIG"

            local encoded_userpass
            encoded_userpass="$(urlencode "${username}"):$(urlencode "${password}")"
            local uri="hysteria2://${encoded_userpass}@${server_address}:${port}?sni=${sni:-$server_address}&insecure=${insecure}"
            if [[ -n "$obfs_info" ]]; then
                local obfs_type="${obfs_info%%:*}"
                local obfs_pass="${obfs_info##*:}"
                local encoded_obfs_pass
                encoded_obfs_pass=$(urlencode "$obfs_pass")
                uri+="&obfs=${obfs_type}&obfs-password=${encoded_obfs_pass}"
            fi
            uri_list+="${uri}"$'\n'
        done < <(get_all_users)
    else
        local auth_info
        auth_info=$(get_client_auth_info)
        local auth_value="${auth_info##*|}"
        local encoded_auth
        encoded_auth=$(urlencode "$auth_value")
        local uri="hysteria2://${encoded_auth}@${server_address}:${port}?sni=${sni:-$server_address}&insecure=${insecure}"
        if [[ -n "$obfs_info" ]]; then
            local obfs_type="${obfs_info%%:*}"
            local obfs_pass="${obfs_info##*:}"
            local encoded_obfs_pass
            encoded_obfs_pass=$(urlencode "$obfs_pass")
            uri+="&obfs=${obfs_type}&obfs-password=${encoded_obfs_pass}"
        fi
        uri_list="${uri}"
    fi

    # Base64 编码
    local encoded
    encoded=$(printf '%s' "$uri_list" | base64_one_line)

    # 保存到文件
    local sub_dir="$HYSTERIA_DIR/subscription"
    mkdir -p "$sub_dir"
    echo "$encoded" > "$sub_dir/default.txt"

    echo -e "${GREEN}✅ 订阅内容已生成${NC}"
    echo ""
    echo -e "${YELLOW}Base64 订阅内容:${NC}"
    echo "$encoded" | fold -w 60
    echo ""
    echo -e "保存位置: ${CYAN}$sub_dir/default.txt${NC}"
    echo ""
    echo -e "${YELLOW}提示: 将此内容托管到 HTTPS URL 即可作为订阅链接使用${NC}"
}

# ========== 一键导出全部 ==========
export_all() {
    echo -e "${CYAN}=== 一键导出全部 ===${NC}"
    echo ""

    generate_client_yaml
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    generate_client_uri
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    generate_qr_code
}
