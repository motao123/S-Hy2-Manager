#!/bin/bash
# ACL 规则管理模块
#
# 依赖: common.sh
# 导出函数: acl_management, generate_acl_file, edit_acl_rules, show_acl_status

ACL_DIR="${ACL_DIR:-/etc/hysteria}"
ACL_FILE="${ACL_FILE:-$ACL_DIR/acl.txt}"

# 安全编辑器调用：只允许 nano/vim/vi
_run_safe_editor() {
    local target_file="$1"
    local preferred_editor="${2:-${EDITOR:-nano}}"
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

    # 回退到 vi
    if command -v vi >/dev/null 2>&1; then
        vi "$target_file"
        return $?
    fi

    log_error "未找到可用编辑器"
    return 1
}

# 安全更新 ACL 配置行：逐行重写
# Hysteria v2.8+ acl 字段必须是结构化格式：
#   acl:              (旧字符串格式 acl: "/path" 已废弃)
#     file: /path
#   或:
#     inline:
#       - "direct(all, geoip:cn)"
_update_acl_in_config() {
    local acl_path="$1"
    local action="$2"   # "enable" 或 "disable"
    local config_file="${3:-$HYSTERIA_CONFIG}"
    local temp_file line acl_updated=false

    if [[ ! -f "$config_file" ]]; then
        log_error "配置文件不存在"
        return 1
    fi

    temp_file=$(create_temp_file)

    local in_acl_block=false
    local acl_base_indent=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$action" == "enable" ]]; then
            # 检测 acl: 行（结构化格式：acl: 后面无值或换行）
            if [[ "$line" =~ ^#[[:space:]]*acl: ]]; then
                # 注释掉的 acl 行：取消注释，替换为新的结构化格式
                printf 'acl:\n  file: %s\n' "$(yaml_quote_scalar "$acl_path")" >> "$temp_file"
                acl_updated=true
                # 跳过被注释掉的 acl 子行（如 #   file: ... 或 #   inline: ...）
                while IFS= read -r sub_line || [[ -n "$sub_line" ]]; do
                    if [[ "$sub_line" =~ ^#[[:space:]]+(file|inline): ]]; then
                        continue
                    else
                        # 这行不属于注释的 acl 块，处理它
                        line="$sub_line"
                        break
                    fi
                done
                # 继续处理当前行（可能是从内层 while 读到的非 acl 子行）
                if [[ "$acl_updated" == true && "$line" =~ ^#[[:space:]]+(file|inline): ]]; then
                    continue
                fi
                echo "$line" >> "$temp_file"
                continue
            fi

            # 检测旧格式 acl: "/path"（字符串值，v2.8+ 不支持）
            if [[ "$line" =~ ^[[:space:]]*acl:[[:space:]]+ ]]; then
                # 替换为新的结构化格式
                printf 'acl:\n  file: %s\n' "$(yaml_quote_scalar "$acl_path")" >> "$temp_file"
                acl_updated=true
                continue
            fi

            # 检测结构化格式 acl: 行（无值，后面跟 file: 或 inline:）
            if [[ "$line" =~ ^[[:space:]]*acl:[[:space:]]*$ ]]; then
                # 已有结构化 acl 块，更新 file 路径
                acl_updated=true
                acl_base_indent=$(echo "$line" | sed 's/acl:.*//')
                echo "$line" >> "$temp_file"
                in_acl_block=true
                # 写入/替换 file: 行
                printf '%sfile: %s\n' "${acl_base_indent}  " "$(yaml_quote_scalar "$acl_path")" >> "$temp_file"
                continue
            fi

            # 在 acl 块内，跳过旧的 file: 行（已经写入了新的）
            if [[ "$in_acl_block" == true ]]; then
                local sub_indent
                sub_indent=$(echo "$line" | sed 's/[a-zA-Z].*//')
                if [[ "$line" =~ ^[[:space:]]*file: ]]; then
                    # 跳过旧的 file 行
                    continue
                elif [[ ${#sub_indent} -le ${#acl_base_indent} && "$line" =~ ^[[:space:]]*[a-zA-Z]+: ]]; then
                    # 离开 acl 块
                    in_acl_block=false
                fi
                echo "$line" >> "$temp_file"
                continue
            fi

            echo "$line" >> "$temp_file"

        elif [[ "$action" == "disable" ]]; then
            # 检测 acl: 行（结构化或旧格式）
            if [[ "$line" =~ ^[[:space:]]*acl:[[:space:]]*$ ]]; then
                # 结构化格式：注释整个 acl 块
                echo "#acl:" >> "$temp_file"
                acl_updated=true
                in_acl_block=true
                acl_base_indent=$(echo "$line" | sed 's/acl:.*//')
                continue
            elif [[ "$line" =~ ^[[:space:]]*acl:[[:space:]]+ ]]; then
                # 旧字符串格式：注释整行
                echo "#$line" >> "$temp_file"
                acl_updated=true
                continue
            fi

            # 在 acl 块内，注释子行
            if [[ "$in_acl_block" == true ]]; then
                local sub_indent
                sub_indent=$(echo "$line" | sed 's/[a-zA-Z].*//')
                if [[ ${#sub_indent} -le ${#acl_base_indent} && "$line" =~ ^[[:space:]]*[a-zA-Z]+: ]]; then
                    # 离开 acl 块
                    in_acl_block=false
                    echo "$line" >> "$temp_file"
                    continue
                fi
                echo "#$line" >> "$temp_file"
                continue
            fi

            echo "$line" >> "$temp_file"
        fi
    done < "$config_file"

    # 如果没有找到 acl 行且需要启用，插入新的结构化 acl 块
    if [[ "$action" == "enable" && "$acl_updated" == false ]]; then
        # 在 masquerade 行之前插入
        rm -f "$temp_file"
        temp_file=$(create_temp_file)
        acl_updated=false

        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$acl_updated" == false && "$line" =~ ^masquerade: ]]; then
                printf 'acl:\n  file: %s\n' "$(yaml_quote_scalar "$acl_path")" >> "$temp_file"
                acl_updated=true
            fi
            echo "$line" >> "$temp_file"
        done < "$config_file"

        if [[ "$acl_updated" == false ]]; then
            printf 'acl:\n  file: %s\n' "$(yaml_quote_scalar "$acl_path")" >> "$temp_file"
        fi
    fi

    replace_config_file_securely "$temp_file" "$config_file"
}

# ========== ACL 管理菜单 ==========
acl_management() {
    while true; do
        clear
        echo -e "${CYAN}================================================${NC}"
        echo -e "${CYAN}           ACL 规则管理${NC}"
        echo -e "${CYAN}================================================${NC}"
        echo ""

        show_acl_status
        echo ""

        echo -e "${YELLOW}请选择操作:${NC}"
        echo ""
        echo -e "${GREEN} 1.${NC} 生成常用 ACL 规则"
        echo -e "${GREEN} 2.${NC} 编辑 ACL 规则"
        echo -e "${GREEN} 3.${NC} 启用/禁用 ACL"
        echo -e "${GREEN} 4.${NC} 查看当前 ACL 规则"
        echo -e "${CYAN} 5.${NC} 导入远程 ACL 规则"
        echo -e "${RED} 0.${NC} 返回主菜单"
        echo ""
        echo -n -e "${BLUE}请输入选项 [0-5]: ${NC}"

        local choice
        read -r choice

        case $choice in
            1) generate_acl_file ;;
            2) edit_acl_rules ;;
            3) toggle_acl ;;
            4) view_acl_rules ;;
            5) import_remote_acl ;;
            0) return 0 ;;
            *) echo -e "${RED}无效选项${NC}" ;;
        esac

        echo ""
        echo -n "按回车键继续..."
        read -r
    done
}

# ========== 显示 ACL 状态 ==========
show_acl_status() {
    if [[ -f "$ACL_FILE" ]]; then
        local rule_count
        rule_count=$(grep -cve '^\s*$' -e '^\s*#' "$ACL_FILE" 2>/dev/null || echo 0)
        echo -e "ACL 状态: ${GREEN}已配置（$rule_count 条规则）${NC}"
        echo -e "规则文件: ${CYAN}$ACL_FILE${NC}"

        # 检查是否在配置中启用（兼容旧字符串格式和新结构化格式）
        if grep -q "^[[:space:]]*acl:" "$HYSTERIA_CONFIG" 2>/dev/null; then
            echo -e "配置中: ${GREEN}已启用${NC}"
        else
            echo -e "配置中: ${YELLOW}未启用${NC}"
        fi
    else
        echo -e "ACL 状态: ${YELLOW}未配置${NC}"
    fi
}

# ========== 生成常用 ACL 规则 ==========
generate_acl_file() {
    echo -e "${CYAN}=== 生成 ACL 规则 ===${NC}"
    echo ""

    echo -e "${YELLOW}选择 ACL 规则模板:${NC}"
    echo ""
    echo -e "  ${GREEN}1.${NC} 中国 IP 直连（其余走代理）"
    echo -e "  ${GREEN}2.${NC} 中国 IP + 私有 IP 直连"
    echo -e "  ${GREEN}3.${NC} 屏蔽广告域名"
    echo -e "  ${GREEN}4.${NC} 屏蔽中国区追踪"
    echo -e "  ${GREEN}5.${NC} 自定义规则"
    echo ""
    echo -n "请选择 [1-5]: "
    local choice
    read -r choice

    local rules=""
    case $choice in
        1)
            rules="# 中国 IP 直连\n\ndirect(all, geoip:cn)\n"
            ;;
        2)
            rules="# 中国 IP + 私有 IP 直连\n\ndirect(all, geoip:cn)\ndirect(all, geoip:private)\n"
            ;;
        3)
            rules="# 屏蔽广告域名\n\nblock(all, geosite:category-ads-all)\n"
            ;;
        4)
            rules="# 屏蔽中国区追踪 + 广告\n\nblock(all, geosite:cn-trackers)\nblock(all, geosite:category-ads-all)\n"
            ;;
        5)
            echo -e "${YELLOW}规则语法:${NC}"
            echo -e "  direct(all, geoip:cn)       # 中国IP直连"
            echo -e "  block(all, geosite:ads)     # 屏蔽广告"
            echo -e "  proxy(all, geosite:netflix) # Netflix走代理"
            echo ""
            edit_acl_rules
            return
            ;;
        *)
            log_error "无效选择"
            return 1
            ;;
    esac

    echo -e "$rules" > "$ACL_FILE"
    chmod 644 "$ACL_FILE"

    log_success "ACL 规则已生成"
    echo -e "文件: ${CYAN}$ACL_FILE${NC}"

    # 提示启用
    if ! grep -q "^[[:space:]]*acl:" "$HYSTERIA_CONFIG" 2>/dev/null; then
        echo -n "是否在配置中启用 ACL？[y/N]: "
        local confirm
        read -r confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            enable_acl_in_config
        fi
    fi
}

# ========== 编辑 ACL 规则 ==========
edit_acl_rules() {
    if [[ ! -f "$ACL_FILE" ]]; then
        touch "$ACL_FILE"
    fi

    echo -e "${YELLOW}正在打开编辑器...${NC}"
    _run_safe_editor "$ACL_FILE"

    # 验证规则
    if [[ -s "$ACL_FILE" ]]; then
        log_success "ACL 规则已保存"
        ask_restart_service
    fi
}

# ========== 查看 ACL 规则 ==========
view_acl_rules() {
    echo -e "${CYAN}=== 当前 ACL 规则 ===${NC}"
    echo ""

    if [[ ! -f "$ACL_FILE" ]]; then
        echo -e "${YELLOW}未找到 ACL 规则文件${NC}"
        return 0
    fi

    cat "$ACL_FILE"
}

# ========== 启用/禁用 ACL ==========
toggle_acl() {
    # 兼容旧字符串格式和新结构化格式
    if grep -q "^[[:space:]]*acl:" "$HYSTERIA_CONFIG" 2>/dev/null; then
        # 已启用，禁用它
        echo -e "${YELLOW}当前 ACL 已启用${NC}"
        echo -n "是否禁用？[y/N]: "
        local confirm
        read -r confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            _update_acl_in_config "$ACL_FILE" "disable"
            log_success "ACL 已禁用"
            ask_restart_service
        fi
    else
        # 未启用，启用它
        if [[ ! -f "$ACL_FILE" ]]; then
            echo -e "${YELLOW}ACL 规则文件不存在，先生成规则${NC}"
            generate_acl_file
        fi
        enable_acl_in_config
    fi
}

# ========== 在配置中启用 ACL ==========
enable_acl_in_config() {
    if [[ ! -f "$HYSTERIA_CONFIG" ]]; then
        log_error "配置文件不存在"
        return 1
    fi

    # 备份（收紧权限）
    cp "$HYSTERIA_CONFIG" "${HYSTERIA_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    chmod 600 "${HYSTERIA_CONFIG}.backup."* 2>/dev/null || true

    # 使用安全逐行重写更新 ACL 配置
    _update_acl_in_config "$ACL_FILE" "enable"

    log_success "ACL 已启用"
    ask_restart_service
}

# ========== 导入远程 ACL 规则 ==========
import_remote_acl() {
    echo -e "${CYAN}=== 导入远程 ACL 规则 ===${NC}"
    echo ""

    echo -e "${YELLOW}常用 ACL 规则源:${NC}"
    echo -e "  1. Loyalsoldier/geosite (GitHub)"
    echo -e "  2. 自定义 URL"
    echo ""
    echo -n "请选择 [1-2]: "
    local choice
    read -r choice

    local url=""
    case $choice in
        1) url="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/geosite.dat" ;;
        2)
            echo -n "请输入 URL (仅支持 HTTPS): "
            read -r url
            ;;
        *)
            log_error "无效选择"
            return 1
            ;;
    esac

    if [[ -z "$url" ]]; then
        log_error "URL 不能为空"
        return 1
    fi

    # 强制 HTTPS 协议
    if [[ "$url" != https://* ]]; then
        log_error "安全限制：仅支持 HTTPS 协议的 URL"
        return 1
    fi

    # 先下载到安全临时文件，校验后再替换
    local temp_acl
    temp_acl=$(create_temp_file)

    echo -e "${YELLOW}正在下载...${NC}"
    if ! curl -fsSL --proto "=https" --tlsv1.2 "$url" -o "$temp_acl" 2>/dev/null; then
        log_error "下载失败"
        rm -f "$temp_acl"
        return 1
    fi

    if [[ ! -s "$temp_acl" ]]; then
        log_error "下载内容为空"
        rm -f "$temp_acl"
        return 1
    fi

    # 下载成功，替换到 ACL 文件
    if cp "$temp_acl" "$ACL_FILE"; then
        chmod 644 "$ACL_FILE"
        rm -f "$temp_acl"
        log_success "远程 ACL 规则已导入"
        ask_restart_service
    else
        log_error "ACL 规则写入失败"
        rm -f "$temp_acl"
        return 1
    fi
}
