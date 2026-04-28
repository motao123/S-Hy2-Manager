#!/bin/bash
# 证书管理（ACME/自签名/自定义上传）
#
# 依赖: common.sh, domain.sh
# 导出函数: certificate_management, generate_self_signed_cert, upload_custom_cert, update_tls_config, manage_certificate_paths

# 转义域名中可能破坏 OpenSSL -subj DN 的特殊字符（/ = +）
_escape_dn_value() {
    local value="${1:-}"
    value=${value//\\/\\\\}
    value=${value//\//\\/}
    value=${value//=/\\=}
    value=${value//+/\\+}
    printf '%s' "$value"
}

update_tls_config_secure() {
    local cert_file="$1"
    local key_file="$2"
    local config_file="${3:-$HYSTERIA_CONFIG}"
    local temp_file line in_tls=false in_acme=false tls_found=false cert_updated=false key_updated=false

    if [[ ! -f "$config_file" ]]; then
        log_error "配置文件不存在"
        return 1
    fi

    temp_file=$(create_temp_file)

    while IFS= read -r line || [[ -n "$line" ]]; do
        # 跳过 acme 块
        if [[ "$line" =~ ^[[:space:]]*acme:[[:space:]]*$ ]]; then
            in_acme=true
            continue
        fi
        if [[ "$in_acme" == true ]]; then
            if [[ "$line" =~ ^[[:alpha:]][^:]*:[[:space:]]*$ ]] || [[ -z "$line" ]]; then
                in_acme=false
            else
                continue
            fi
        fi

        # 处理 tls 块
        if [[ "$line" =~ ^[[:space:]]*tls:[[:space:]]*$ ]]; then
            in_tls=true
            tls_found=true
            echo "$line" >> "$temp_file"
            continue
        fi

        if [[ "$in_tls" == true ]]; then
            if [[ "$line" =~ ^[[:alpha:]][^:]*:[[:space:]]*$ ]]; then
                in_tls=false
                # 补上缺失的字段
                if [[ "$cert_updated" == false ]]; then
                    yaml_write_kv "  " "cert" "$cert_file" >> "$temp_file"
                fi
                if [[ "$key_updated" == false ]]; then
                    yaml_write_kv "  " "key" "$key_file" >> "$temp_file"
                fi
                echo "$line" >> "$temp_file"
                continue
            fi

            if [[ "$line" =~ ^[[:space:]]*cert:[[:space:]]* ]]; then
                yaml_write_kv "  " "cert" "$cert_file" >> "$temp_file"
                cert_updated=true
                continue
            fi

            if [[ "$line" =~ ^[[:space:]]*key:[[:space:]]* ]]; then
                yaml_write_kv "  " "key" "$key_file" >> "$temp_file"
                key_updated=true
                continue
            fi

            # 保留 tls 块中的其他行（如 acme 引用等）
            echo "$line" >> "$temp_file"
            continue
        fi

        echo "$line" >> "$temp_file"
    done < "$config_file"

    # tls 块存在但到文件末尾，补上缺失字段
    if [[ "$in_tls" == true ]]; then
        if [[ "$cert_updated" == false ]]; then
            yaml_write_kv "  " "cert" "$cert_file" >> "$temp_file"
        fi
        if [[ "$key_updated" == false ]]; then
            yaml_write_kv "  " "key" "$key_file" >> "$temp_file"
        fi
    fi

    # tls 块不存在，追加
    if [[ "$tls_found" == false ]]; then
        printf '\ntls:\n' >> "$temp_file"
        yaml_write_kv "  " "cert" "$cert_file" >> "$temp_file"
        yaml_write_kv "  " "key" "$key_file" >> "$temp_file"
    fi

    replace_config_file_securely "$temp_file" "$config_file"
}

certificate_management() {
    while true; do
        clear
        echo -e "${CYAN}=== 证书管理 ===${NC}"
        echo ""
        
        # 检查当前证书状态
        show_certificate_status
        
        echo ""
        echo -e "${YELLOW}证书管理选项:${NC}"
        echo -e "${GREEN}1.${NC} 生成自签名证书"
        echo -e "${GREEN}2.${NC} 上传自定义证书"
        echo -e "${GREEN}3.${NC} 查看证书信息"
        echo -e "${GREEN}4.${NC} 删除证书文件"
        echo -e "${GREEN}5.${NC} 证书文件路径管理"
        echo -e "${RED}0.${NC} 返回主菜单"
        echo ""
        echo -n -e "${BLUE}请选择操作 [0-5]: ${NC}"
        read -r choice

        case $choice in
            1) generate_self_signed_cert ;;
            2) upload_custom_cert ;;
            3) show_certificate_info ;;
            4) remove_certificate_files ;;
            5) manage_certificate_paths ;;
            0) break ;;
            *) 
                log_error "无效选项"
                sleep 1
                ;;
        esac
    done
}

show_certificate_status() {
    echo -e "${YELLOW}当前证书状态:${NC}"

    # 检查配置文件中的证书配置
    if [[ -f "$HYSTERIA_CONFIG" ]]; then
        if grep -q "^acme:" "$HYSTERIA_CONFIG"; then
            echo -e "证书模式: ${GREEN}ACME自动证书${NC}"
            local domains
            domains=$(grep -A 5 "^acme:" "$HYSTERIA_CONFIG" | grep "domains:" -A 5 | grep -E "^\s*-" | sed 's/^\s*-\s*//' | tr '\n' ' ')
            echo -e "ACME域名: ${domains:-未设置}"
        elif grep -q "^tls:" "$HYSTERIA_CONFIG"; then
            local cert_file
            local key_file
            cert_file=$(grep -A 5 "^tls:" "$HYSTERIA_CONFIG" | grep "cert:" | awk '{print $2}' | tr -d '"' | tr -d "'")
            key_file=$(grep -A 5 "^tls:" "$HYSTERIA_CONFIG" | grep "key:" | awk '{print $2}' | tr -d '"' | tr -d "'")

            # 判断证书类型：自签名 or 自定义
            if [[ -n "$cert_file" && -f "$cert_file" ]]; then
                local issuer
                issuer=$(openssl x509 -in "$cert_file" -noout -issuer 2>/dev/null)
                if echo "$issuer" | grep -qi "self-signed\|O=Organization\|CN=.*test\|Issuer:.*Subject:"; then
                    echo -e "证书模式: ${GREEN}自签名证书${NC}"
                elif echo "$issuer" | grep -qi "Let's Encrypt\|ZeroSSL\|Buypass"; then
                    echo -e "证书模式: ${GREEN}ACME证书(已生成)${NC}"
                else
                    echo -e "证书模式: ${GREEN}自定义证书${NC}"
                fi
            else
                echo -e "证书模式: ${YELLOW}手动证书${NC}"
            fi

            echo -e "证书文件: ${cert_file:-未设置}"
            echo -e "密钥文件: ${key_file:-未设置}"

            # 检查文件是否存在
            if [[ -n "$cert_file" && -f "$cert_file" ]]; then
                echo -e "证书文件状态: ${GREEN}存在${NC}"
            else
                echo -e "证书文件状态: ${RED}不存在${NC}"
            fi

            if [[ -n "$key_file" && -f "$key_file" ]]; then
                echo -e "密钥文件状态: ${GREEN}存在${NC}"
            else
                echo -e "密钥文件状态: ${RED}不存在${NC}"
            fi
        else
            echo -e "证书模式: ${YELLOW}未配置${NC}"
        fi
    else
        echo -e "证书模式: ${RED}配置文件不存在${NC}"
    fi
}

generate_self_signed_cert() {
    echo ""
    echo -e "${BLUE}生成自签名证书${NC}"
    echo ""
    
    # 获取域名
    echo -n -e "${YELLOW}请输入证书域名 (留空使用服务器IP): ${NC}"
    read -r cert_domain
    
    if [[ -z "$cert_domain" ]]; then
        cert_domain=$(get_server_ip)
        echo "使用服务器IP: $cert_domain"
    fi
    
    # 设置证书文件路径
    local cert_dir="/etc/hysteria"
    local cert_file="$cert_dir/server.crt"
    local key_file="$cert_dir/server.key"
    
    # 创建目录
    mkdir -p "$cert_dir"
    
    echo "正在生成自签名证书..."
    
    # 生成私钥和证书（域名中可能包含 / = 等字符，需转义）
    local escaped_domain
    escaped_domain=$(_escape_dn_value "$cert_domain")
    
    if openssl req -x509 -nodes -newkey rsa:2048 -keyout "$key_file" -out "$cert_file" -days 365 \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=$escaped_domain" 2>/dev/null; then
        
        # 设置权限
        chmod 600 "$key_file"
        chmod 644 "$cert_file"
        chown hysteria:hysteria "$cert_file" "$key_file" 2>/dev/null || true
        
        log_success "自签名证书生成成功"
        echo "证书文件: $cert_file"
        echo "密钥文件: $key_file"
        echo "域名: $cert_domain"
        
        # 询问是否更新配置文件
        echo ""
        echo -n -e "${YELLOW}是否更新配置文件使用新证书? [Y/n]: ${NC}"
        read -r update_config
        if [[ ! $update_config =~ ^[Nn]$ ]]; then
            update_tls_config "$cert_file" "$key_file"
        fi
    else
        log_error "自签名证书生成失败"
    fi
    
    wait_for_user
}

upload_custom_cert() {
    echo ""
    echo -e "${BLUE}上传自定义证书${NC}"
    echo ""
    echo "请提供证书文件路径："
    echo ""
    
    echo -n -e "${YELLOW}证书文件路径 (.crt/.pem): ${NC}"
    read -r cert_path
    
    echo -n -e "${YELLOW}私钥文件路径 (.key): ${NC}"
    read -r key_path
    
    # 验证文件存在
    if [[ ! -f "$cert_path" ]]; then
        log_error "证书文件不存在: $cert_path"
        wait_for_user
        return
    fi
    
    if [[ ! -f "$key_path" ]]; then
        log_error "私钥文件不存在: $key_path"
        wait_for_user
        return
    fi
    
    # 验证证书文件格式
    if ! openssl x509 -in "$cert_path" -text -noout &>/dev/null; then
        log_error "无效的证书文件格式"
        wait_for_user
        return
    fi
    
    if ! openssl rsa -in "$key_path" -check &>/dev/null && ! openssl ec -in "$key_path" -check &>/dev/null; then
        log_error "无效的私钥文件格式"
        wait_for_user
        return
    fi
    
    # 复制到标准位置
    local cert_dir="/etc/hysteria"
    local new_cert_file="$cert_dir/custom.crt"
    local new_key_file="$cert_dir/custom.key"
    
    mkdir -p "$cert_dir"
    
    if cp "$cert_path" "$new_cert_file" && cp "$key_path" "$new_key_file"; then
        # 设置权限
        chmod 600 "$new_key_file"
        chmod 644 "$new_cert_file"
        chown hysteria:hysteria "$new_cert_file" "$new_key_file" 2>/dev/null || true
        
        log_success "证书文件上传成功"
        echo "新证书文件: $new_cert_file"
        echo "新私钥文件: $new_key_file"
        
        # 显示证书信息
        echo ""
        echo -e "${CYAN}证书信息:${NC}"
        openssl x509 -in "$new_cert_file" -text -noout | grep -E "(Subject:|Issuer:|Not Before|Not After)"
        
        # 询问是否更新配置文件
        echo ""
        echo -n -e "${YELLOW}是否更新配置文件使用新证书? [Y/n]: ${NC}"
        read -r update_config
        if [[ ! $update_config =~ ^[Nn]$ ]]; then
            update_tls_config "$new_cert_file" "$new_key_file"
        fi
    else
        log_error "证书文件复制失败"
    fi
    
    wait_for_user
}

update_tls_config() {
    local cert_file="$1"
    local key_file="$2"
    
    if [[ ! -f "$HYSTERIA_CONFIG" ]]; then
        log_error "配置文件不存在"
        return 1
    fi
    
    # 备份配置文件（收紧权限）
    if ! backup_config_securely "$HYSTERIA_CONFIG" "$HYSTERIA_CONFIG.bak" 2>/dev/null; then
        cp "$HYSTERIA_CONFIG" "$HYSTERIA_CONFIG.bak"
        chmod 600 "$HYSTERIA_CONFIG.bak" 2>/dev/null || true
    fi
    
    # 使用安全逐行重写替换 TLS 配置
    if ! update_tls_config_secure "$cert_file" "$key_file"; then
        log_error "TLS 配置更新失败"
        return 1
    fi
    
    log_success "配置文件已更新"
    
    # 询问是否重启服务
    echo -n -e "${YELLOW}是否重启服务以应用新证书? [Y/n]: ${NC}"
    read -r restart
    if [[ ! $restart =~ ^[Nn]$ ]]; then
        systemctl restart "$HYSTERIA_SERVICE"
        log_success "服务已重启"
    fi
}

show_certificate_info() {
    echo ""
    echo -e "${BLUE}证书详细信息${NC}"
    echo ""
    
    if [[ ! -f "$HYSTERIA_CONFIG" ]]; then
        log_error "配置文件不存在"
        wait_for_user
        return
    fi
    
    # 获取证书文件路径
    local cert_file
    if grep -q "^tls:" "$HYSTERIA_CONFIG"; then
        cert_file=$(grep -A 5 "^tls:" "$HYSTERIA_CONFIG" | grep "cert:" | awk '{print $2}' | tr -d '"' | tr -d "'")
    else
        log_warn "未配置手动证书，检查ACME证书..."
        # 查找ACME证书
        local acme_dir="/var/lib/hysteria"
        if [[ -d "$acme_dir" ]]; then
            cert_file=$(find "$acme_dir" -name "*.crt" | head -1)
        fi
    fi
    
    if [[ -z "$cert_file" || ! -f "$cert_file" ]]; then
        log_error "未找到证书文件"
        wait_for_user
        return
    fi
    
    echo -e "${CYAN}证书文件: $cert_file${NC}"
    echo ""
    
    # 显示证书详细信息
    echo -e "${YELLOW}证书基本信息:${NC}"
    openssl x509 -in "$cert_file" -text -noout | grep -A 1 "Subject:"
    openssl x509 -in "$cert_file" -text -noout | grep -A 1 "Issuer:"
    
    echo ""
    echo -e "${YELLOW}有效期:${NC}"
    openssl x509 -in "$cert_file" -text -noout | grep -E "Not (Before|After)"
    
    echo ""
    echo -e "${YELLOW}主体备用名称 (SAN):${NC}"
    openssl x509 -in "$cert_file" -text -noout | grep -A 5 "Subject Alternative Name:" || echo "无"
    
    echo ""
    echo -e "${YELLOW}证书指纹:${NC}"
    echo -n "MD5: "
    openssl x509 -in "$cert_file" -noout -fingerprint -md5 | cut -d'=' -f2
    echo -n "SHA1: "
    openssl x509 -in "$cert_file" -noout -fingerprint -sha1 | cut -d'=' -f2
    echo -n "SHA256: "
    openssl x509 -in "$cert_file" -noout -fingerprint -sha256 | cut -d'=' -f2
    
    wait_for_user
}

remove_certificate_files() {
    echo ""
    echo -e "${YELLOW}删除证书文件${NC}"
    echo ""
    
    # 列出可删除的证书文件
    local cert_files=()
    if [[ -f "/etc/hysteria/server.crt" ]]; then
        cert_files+=("/etc/hysteria/server.crt和server.key (自签名证书)")
    fi
    if [[ -f "/etc/hysteria/custom.crt" ]]; then
        cert_files+=("/etc/hysteria/custom.crt和custom.key (自定义证书)")
    fi
    
    if [[ ${#cert_files[@]} -eq 0 ]]; then
        log_warn "未找到可删除的证书文件"
        wait_for_user
        return
    fi
    
    echo -e "${YELLOW}找到以下证书文件:${NC}"
    for i in "${!cert_files[@]}"; do
        echo "$((i+1)). ${cert_files[i]}"
    done
    echo "0. 取消"
    echo ""
    echo -n -e "${BLUE}请选择要删除的证书 [0-${#cert_files[@]}]: ${NC}"
    read -r choice
    
    if [[ "$choice" == "0" ]]; then
        echo -e "${BLUE}取消删除${NC}"
        wait_for_user
        return
    fi
    
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt ${#cert_files[@]} ]]; then
        log_error "无效选择"
        wait_for_user
        return
    fi
    
    local selected_cert
    selected_cert="${cert_files[$((choice-1))]}"
    echo ""
    echo -e "${RED}警告: 将删除 $selected_cert${NC}"
    echo -n -e "${YELLOW}确定要删除吗? [y/N]: ${NC}"
    read -r confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        case $choice in
            1)
                if [[ -f "/etc/hysteria/server.crt" ]]; then
                    rm -f /etc/hysteria/server.crt /etc/hysteria/server.key
                    log_success "自签名证书已删除"
                fi
                ;;
            2)
                if [[ -f "/etc/hysteria/custom.crt" ]]; then
                    rm -f /etc/hysteria/custom.crt /etc/hysteria/custom.key
                    log_success "自定义证书已删除"
                fi
                ;;
        esac
    else
        echo -e "${BLUE}取消删除${NC}"
    fi
    
    wait_for_user
}

manage_certificate_paths() {
    echo ""
    echo -e "${BLUE}证书文件路径管理${NC}"
    echo ""
    
    if [[ ! -f "$HYSTERIA_CONFIG" ]]; then
        log_error "配置文件不存在"
        wait_for_user
        return
    fi
    
    # 显示当前配置
    if grep -q "^tls:" "$HYSTERIA_CONFIG"; then
        local current_cert
        local current_key
        current_cert=$(grep -A 5 "^tls:" "$HYSTERIA_CONFIG" | grep "cert:" | awk '{print $2}' | tr -d '"' | tr -d "'")
        current_key=$(grep -A 5 "^tls:" "$HYSTERIA_CONFIG" | grep "key:" | awk '{print $2}' | tr -d '"' | tr -d "'")
        
        echo -e "${YELLOW}当前证书配置:${NC}"
        echo "证书文件: $current_cert"
        echo "私钥文件: $current_key"
    else
        echo -e "${YELLOW}当前未配置手动证书${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}路径管理选项:${NC}"
    echo "1. 修改证书文件路径"
    echo "2. 修改私钥文件路径"
    echo "3. 同时修改证书和私钥路径"
    echo "0. 返回"
    echo ""
    echo -n -e "${BLUE}请选择操作 [0-3]: ${NC}"
    read -r choice
    
    case $choice in
        1)
            echo -n -e "${YELLOW}输入新的证书文件路径: ${NC}"
            read -r new_cert
            if [[ -f "$new_cert" ]]; then
                local current_key
                current_key=$(grep -A 5 "^tls:" "$HYSTERIA_CONFIG" | grep "key:" | awk '{print $2}' | tr -d '"' | tr -d "'")
                update_tls_config "$new_cert" "$current_key"
            else
                log_error "证书文件不存在"
            fi
            ;;
        2)
            echo -n -e "${YELLOW}输入新的私钥文件路径: ${NC}"
            read -r new_key
            if [[ -f "$new_key" ]]; then
                local current_cert
                current_cert=$(grep -A 5 "^tls:" "$HYSTERIA_CONFIG" | grep "cert:" | awk '{print $2}' | tr -d '"' | tr -d "'")
                update_tls_config "$current_cert" "$new_key"
            else
                log_error "私钥文件不存在"
            fi
            ;;
        3)
            echo -n -e "${YELLOW}输入新的证书文件路径: ${NC}"
            read -r new_cert
            echo -n -e "${YELLOW}输入新的私钥文件路径: ${NC}"
            read -r new_key
            
            if [[ -f "$new_cert" && -f "$new_key" ]]; then
                update_tls_config "$new_cert" "$new_key"
            else
                log_error "文件不存在，请检查路径"
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

