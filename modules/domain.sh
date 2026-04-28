#!/bin/bash
# 域名管理（ACME 域名 + 伪装域名）
#
# 依赖: common.sh, domain-test.sh
# 导出函数: domain_management, acme_domain_management, masquerade_domain_management, set_server_domain, verify_domain_resolution

domain_management() {
    while true; do
        clear
        echo -e "${CYAN}=== 域名管理 ===${NC}"
        echo ""

        # 显示当前域名配置状态
        echo -e "${YELLOW}当前域名配置状态:${NC}"
        
        # 检查ACME域名
        if [[ -f "$SERVER_DOMAIN_CONFIG" ]]; then
            local acme_domain
            acme_domain=$(cat "$SERVER_DOMAIN_CONFIG")
            echo -e "ACME域名: ${GREEN}$acme_domain${NC}"
        else
            echo -e "ACME域名: ${YELLOW}未配置${NC}"
        fi
        
        # 检查伪装域名
        local masquerade_domain=""
        if [[ -f "$CONFIG_PATH" ]]; then
            masquerade_domain=$(grep -A 3 "masquerade:" "$CONFIG_PATH" 2>/dev/null | grep "url:" | awk '{print $2}' | sed 's|https\?://||' | sed 's|/.*||')
        fi
        
        if [[ -n "$masquerade_domain" ]]; then
            echo -e "伪装域名: ${GREEN}$masquerade_domain${NC}"
        else
            echo -e "伪装域名: ${YELLOW}未配置${NC}"
        fi

        echo ""
        echo -e "${YELLOW}域名管理选项:${NC}"
        echo -e "${GREEN}1.${NC} ACME域名管理"
        echo -e "${GREEN}2.${NC} 伪装域名管理"
        echo -e "${GREEN}3.${NC} 测试域名连通性"
        echo -e "${RED}0.${NC} 返回主菜单"
        echo ""
        echo -n -e "${BLUE}请选择操作 [0-3]: ${NC}"
        read -r choice

        case $choice in
            1) acme_domain_management ;;
            2) masquerade_domain_management ;;
            3) test_domain_connectivity ;;
            0) break ;;
            *) 
                log_error "无效选项"
                sleep 1
                ;;
        esac
    done
}

acme_domain_management() {
    while true; do
        clear
        echo -e "${CYAN}=== ACME域名管理 ===${NC}"
        echo ""
        echo -e "${BLUE}ACME域名用于申请SSL证书，需要域名解析到本服务器${NC}"
        echo ""

        # 显示当前配置
        if [[ -f "$SERVER_DOMAIN_CONFIG" ]]; then
            local current_domain
            current_domain=$(cat "$SERVER_DOMAIN_CONFIG")
            echo -e "${GREEN}当前ACME域名: $current_domain${NC}"
        else
            echo -e "${YELLOW}当前未配置ACME域名${NC}"
        fi

        echo ""
        echo -e "${YELLOW}ACME域名选项:${NC}"
        echo -e "${GREEN}1.${NC} 设置ACME域名"
        echo -e "${GREEN}2.${NC} 验证域名解析"
        echo -e "${GREEN}3.${NC} 删除ACME域名配置"
        echo -e "${RED}0.${NC} 返回上级菜单"
        echo ""
        echo -n -e "${BLUE}请选择操作 [0-3]: ${NC}"
        read -r choice

        case $choice in
            1) set_server_domain ;;
            2) verify_domain_resolution ;;
            3) remove_server_domain ;;
            0) break ;;
            *) 
                log_error "无效选项"
                sleep 1
                ;;
        esac
    done
}

masquerade_domain_management() {
    while true; do
        clear
        echo -e "${CYAN}=== 伪装域名管理 ===${NC}"
        echo ""
        echo -e "${BLUE}伪装域名用于TLS握手，提高连接的隐蔽性${NC}"
        echo ""

        # 显示当前伪装域名配置
        local current_masquerade=""
        if [[ -f "$CONFIG_PATH" ]]; then
            current_masquerade=$(grep -A 3 "masquerade:" "$CONFIG_PATH" 2>/dev/null | grep "url:" | awk '{print $2}')
        fi
        
        if [[ -n "$current_masquerade" ]]; then
            echo -e "${GREEN}当前伪装域名: $current_masquerade${NC}"
        else
            echo -e "${YELLOW}当前未配置伪装域名${NC}"
        fi

        echo ""
        echo -e "${YELLOW}伪装域名选项:${NC}"
        echo -e "${GREEN}1.${NC} 手动设置伪装域名"
        echo -e "${GREEN}2.${NC} 自动测试选择最佳伪装域名"
        echo -e "${GREEN}3.${NC} 删除伪装域名配置"
        echo -e "${RED}0.${NC} 返回上级菜单"
        echo ""
        echo -n -e "${BLUE}请选择操作 [0-3]: ${NC}"
        read -r choice

        case $choice in
            1) set_masquerade_domain ;;
            2) auto_select_masquerade_domain ;;
            3) remove_masquerade_domain ;;
            0) break ;;
            *) 
                log_error "无效选项"
                sleep 1
                ;;
        esac
    done
}

test_domain_connectivity() {
    echo ""
    echo -e "${BLUE}测试域名连通性${NC}"
    echo ""
    
    # 测试ACME域名
    if [[ -f "$SERVER_DOMAIN_CONFIG" ]]; then
        local acme_domain
        acme_domain=$(cat "$SERVER_DOMAIN_CONFIG")
        echo -e "${YELLOW}测试ACME域名: $acme_domain${NC}"
        verify_domain_resolution
    fi
    
    # 测试伪装域名
    if [[ -f "$CONFIG_PATH" ]]; then
        local masquerade_url
        masquerade_url=$(grep -A 3 "masquerade:" "$CONFIG_PATH" 2>/dev/null | grep "url:" | awk '{print $2}')
        if [[ -n "$masquerade_url" ]]; then
            echo ""
            echo -e "${YELLOW}测试伪装域名连通性: $masquerade_url${NC}"
            test_masquerade_connectivity "$masquerade_url"
        fi
    fi
    
    wait_for_user
}

set_masquerade_domain() {
    echo ""
    echo -e "${BLUE}设置伪装域名${NC}"
    echo "请输入伪装域名 URL (例如: https://www.bing.com):"
    echo -n -e "${YELLOW}伪装URL: ${NC}"
    read -r masquerade_url

    if [[ -z "$masquerade_url" ]]; then
        log_error "伪装URL不能为空"
        wait_for_user
        return
    fi

    # 验证URL格式
    if [[ ! "$masquerade_url" =~ ^https?:// ]]; then
        masquerade_url="https://$masquerade_url"
    fi

    # 备份配置文件
    if [[ -f "$CONFIG_PATH" ]]; then
        cp "$CONFIG_PATH" "$CONFIG_PATH.bak"
        
        # 更新或添加伪装域名配置
        if ! yaml_set_masquerade_url "$CONFIG_PATH" "$masquerade_url"; then
            log_error "伪装域名配置写入失败"
            wait_for_user
            return
        fi
        
        log_success "伪装域名已设置: $masquerade_url"
        
        echo ""
        echo -n -e "${YELLOW}是否重启服务以应用更改? [Y/n]: ${NC}"
        read -r restart
        if [[ ! $restart =~ ^[Nn]$ ]]; then
            systemctl restart "$SERVICE_NAME"
            log_success "服务已重启"
        fi
    else
        log_error "配置文件不存在"
    fi
    
    wait_for_user
}

auto_select_masquerade_domain() {
    echo ""
    echo -e "${BLUE}自动测试并选择最佳伪装域名${NC}"
    
    if safe_source_script "$SCRIPTS_DIR/domain-test.sh" "域名测试脚本"; then
        test_masquerade_domains
    fi
}

remove_masquerade_domain() {
    echo ""
    echo -e "${YELLOW}删除伪装域名配置${NC}"

    if [[ ! -f "$CONFIG_PATH" ]]; then
        log_warn "配置文件不存在"
        wait_for_user
        return
    fi

    if ! grep -q "masquerade:" "$CONFIG_PATH"; then
        log_warn "未配置伪装域名"
        wait_for_user
        return
    fi

    local current_masquerade
    current_masquerade=$(grep -A 3 "masquerade:" "$CONFIG_PATH" | grep "url:" | awk '{print $2}')
    echo "当前伪装域名: $current_masquerade"
    echo ""
    echo -n -e "${RED}确定要删除伪装域名配置吗? [y/N]: ${NC}"
    read -r confirm

    if [[ $confirm =~ ^[Yy]$ ]]; then
        cp "$CONFIG_PATH" "$CONFIG_PATH.bak"
        # 删除 masquerade 配置块
        if yaml_remove_masquerade_block "$CONFIG_PATH"; then
            log_success "伪装域名配置已删除"
        else
            log_error "伪装域名配置删除失败"
            wait_for_user
            return
        fi
        
        echo ""
        echo -n -e "${YELLOW}是否重启服务以应用更改? [Y/n]: ${NC}"
        read -r restart
        if [[ ! $restart =~ ^[Nn]$ ]]; then
            systemctl restart "$SERVICE_NAME"
            log_success "服务已重启"
        fi
    else
        echo -e "${BLUE}取消删除${NC}"
    fi

    wait_for_user
}

test_masquerade_connectivity() {
    local url="$1"
    local domain
    domain=$(echo "$url" | sed 's|https\?://||' | sed 's|/.*||')
    
    echo "正在测试 $url..."
    
    # 测试HTTP连接
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "$url" 2>/dev/null)
    
    if [[ "$http_code" =~ ^[23] ]]; then
        echo -e "${GREEN}✅ HTTP连接测试成功 (状态码: $http_code)${NC}"
    else
        echo -e "${YELLOW}⚠️  HTTP连接测试异常 (状态码: $http_code)${NC}"
    fi
    
    # 测试DNS解析
    if command -v dig &> /dev/null; then
        local ip
        ip=$(dig +short "$domain" A 2>/dev/null | head -1)
        if [[ -n "$ip" && "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo -e "${GREEN}✅ DNS解析成功: $ip${NC}"
        else
            echo -e "${RED}❌ DNS解析失败${NC}"
        fi
    fi
}

set_server_domain() {
    echo ""
    echo -e "${BLUE}设置服务器域名${NC}"
    echo "请输入解析到此服务器的域名 (例如: example.com):"
    echo -n -e "${YELLOW}域名: ${NC}"
    read -r domain

    if [[ -z "$domain" ]]; then
        log_error "域名不能为空"
        wait_for_user
        return
    fi

    if ! validate_domain "$domain"; then
        log_error "域名格式不正确"
        wait_for_user
        return
    fi

    # 创建目录（如果不存在）
    mkdir -p "$(dirname "$SERVER_DOMAIN_CONFIG")"
    
    # 保存域名配置
    echo "$domain" > "$SERVER_DOMAIN_CONFIG"
    log_success "服务器域名已设置: $domain"

    # 询问是否立即验证
    echo ""
    echo -n -e "${YELLOW}是否立即验证域名解析? [Y/n]: ${NC}"
    read -r verify
    if [[ ! $verify =~ ^[Nn]$ ]]; then
        verify_domain_resolution
    fi

    wait_for_user
}

verify_domain_resolution() {
    echo ""
    echo -e "${BLUE}验证域名解析${NC}"

    if [[ ! -f "$SERVER_DOMAIN_CONFIG" ]]; then
        log_error "未配置服务器域名"
        wait_for_user
        return
    fi

    local domain
    domain=$(cat "$SERVER_DOMAIN_CONFIG")
    local server_ip
    server_ip=$(get_server_ip)

    echo "正在验证域名: $domain"
    echo "服务器IP: $server_ip"
    echo ""

    # 使用多种方法解析域名
    local resolved_ips=()
    local dns_tools=("dig" "nslookup" "host")
    
    for tool in "${dns_tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            local result
            case $tool in
                dig)
                    result=$(dig +short "$domain" A | head -5)
                    ;;
                nslookup)
                    result=$(nslookup "$domain" 2>/dev/null | grep "Address:" | tail -n +2 | awk '{print $2}' | head -5)
                    ;;
                host)
                    result=$(host "$domain" 2>/dev/null | grep "has address" | awk '{print $4}' | head -5)
                    ;;
            esac
            
            if [[ -n "$result" ]]; then
                echo "使用 $tool 解析结果:"
                echo "$result" | while read -r ip; do
                    if [[ -n "$ip" && "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                        if [[ "$ip" == "$server_ip" ]]; then
                            echo -e "  ${GREEN}✅ $ip (匹配)${NC}"
                        else
                            echo -e "  ${YELLOW}⚠️  $ip (不匹配)${NC}"
                        fi
                        resolved_ips+=("$ip")
                    fi
                done
                break
            fi
        fi
    done

    if [[ ${#resolved_ips[@]} -eq 0 ]]; then
        log_error "无法解析域名，可能原因:"
        echo "1. 域名DNS设置未生效"
        echo "2. 网络连接问题"
        echo "3. DNS服务器问题"
    fi

    wait_for_user
}

remove_server_domain() {
    echo ""
    echo -e "${YELLOW}删除服务器域名配置${NC}"

    if [[ ! -f "$SERVER_DOMAIN_CONFIG" ]]; then
        log_warn "未配置服务器域名"
        wait_for_user
        return
    fi

    local domain
    domain=$(cat "$SERVER_DOMAIN_CONFIG")
    echo "当前配置域名: $domain"
    echo ""
    echo -n -e "${RED}确定要删除域名配置吗? [y/N]: ${NC}"
    read -r confirm

    if [[ $confirm =~ ^[Yy]$ ]]; then
        rm -f "$SERVER_DOMAIN_CONFIG"
        log_success "域名配置已删除"
    else
        echo -e "${BLUE}取消删除${NC}"
    fi

    wait_for_user
}

