#!/bin/bash
# 出站规则核心（初始化/配置检查/临时文件/锁）
#
# 依赖: common.sh
# 导出函数: init_outbound_manager, create_basic_hysteria_config, check_config_file_permissions, init_rules_library

init_outbound_manager() {
    log_info "初始化出站规则管理器"

    # 检查必要的命令
    require_command "awk"
    require_command "grep"
    require_command "sed"

    # 检查 Hysteria2 安装状态
    check_hysteria2_installation
}

create_basic_hysteria_config() {
    cat > "$HYSTERIA_CONFIG" << 'EOF'
# Hysteria2 服务器配置文件
# 此文件由 S-Hy2-Manager 出站规则管理器创建

listen: :443

# TLS 配置 (请根据实际情况修改)
# tls:
#   cert: /path/to/your/cert.crt
#   key: /path/to/your/private.key

# 认证配置 (请根据实际情况修改)
auth:
  type: password
  password: "your_password_here"

# 混淆配置 (可选)
# obfs:
#   type: salamander
#   salamander:
#     password: "your_obfs_password"

# 出站配置将由规则管理器自动管理
# outbounds 段落请勿手动编辑
EOF

    # 设置配置文件权限
    chmod 600 "$HYSTERIA_CONFIG" 2>/dev/null || true
    chown hysteria:hysteria "$HYSTERIA_CONFIG" 2>/dev/null || true

    if [[ -f "$HYSTERIA_CONFIG" ]]; then
        echo -e "${GREEN}✅ 基础配置文件创建成功${NC}"
        echo -e "${YELLOW}⚠️  请编辑配置文件设置 TLS 证书和认证密码:${NC}"
        echo -e "${CYAN}  $HYSTERIA_CONFIG${NC}"
    else
        echo -e "${RED}❌ 配置文件创建失败${NC}"
        return 1
    fi
}

check_config_file_permissions() {
    if [[ ! -f "$HYSTERIA_CONFIG" ]]; then
        return 1
    fi

    # 检查文件权限
    local file_perms
    file_perms=$(stat -c "%a" "$HYSTERIA_CONFIG" 2>/dev/null || stat -f "%A" "$HYSTERIA_CONFIG" 2>/dev/null || echo "unknown")

    # 配置文件包含密码等敏感信息，应保持 600 权限（仅 owner 可读写）
    # 若权限过于宽松（644/666 等），主动收紧以保护敏感信息
    if [[ "$file_perms" != "600" ]] && [[ "$file_perms" != "unknown" ]]; then
        echo ""
        echo -e "${YELLOW}⚠️  配置文件权限不安全: $file_perms（应为 600）${NC}"
        echo -e "${BLUE}正在收紧权限...${NC}"

        if chmod 600 "$HYSTERIA_CONFIG" 2>/dev/null; then
            echo -e "${GREEN}✅ 权限修复成功 (600)${NC}"
        else
            echo -e "${RED}❌ 权限修复失败，可能需要 root 权限${NC}"
            echo "请手动执行: sudo chmod 600 $HYSTERIA_CONFIG"
        fi
    fi

    # 检查文件属主
    local file_owner
    file_owner=$(stat -c "%U" "$HYSTERIA_CONFIG" 2>/dev/null || stat -f "%Su" "$HYSTERIA_CONFIG" 2>/dev/null || echo "unknown")
    if [[ "$file_owner" != "hysteria" ]] && id "hysteria" &>/dev/null; then
        echo -e "${YELLOW}⚠️  配置文件属主不正确: $file_owner（应为 hysteria）${NC}"
        echo -e "${BLUE}正在修复属主...${NC}"
        if chown hysteria:hysteria "$HYSTERIA_CONFIG" 2>/dev/null; then
            echo -e "${GREEN}✅ 属主修复成功 (hysteria:hysteria)${NC}"
        else
            echo -e "${RED}❌ 属主修复失败，可能需要 root 权限${NC}"
            echo "请手动执行: sudo chown hysteria:hysteria $HYSTERIA_CONFIG"
        fi
    fi

    # 检查目录权限
    local config_dir
    config_dir=$(dirname "$HYSTERIA_CONFIG")
    if [[ ! -r "$config_dir" ]]; then
        echo -e "${YELLOW}⚠️  配置目录权限问题${NC}"
        echo "请检查目录权限: $config_dir"
    fi
}

init_rules_library() {
    if [[ ! -d "$RULES_DIR" ]]; then
        mkdir -p "$RULES_DIR" 2>/dev/null || {
            log_error "无法创建规则库目录: $RULES_DIR"
            return 1
        }
        chmod 700 "$RULES_DIR"
    fi

    if [[ ! -f "$RULES_LIBRARY" ]]; then
        cat > "$RULES_LIBRARY" << 'EOF'
# Hysteria2 出站规则库
# 格式：每个规则包含type、description和config字段
version: "1.0"
last_modified: ""
rules:
  # 示例规则（已注释）:
  # direct_rule:
  #   type: direct
  #   description: "直连规则示例"
  #   config:
  #     mode: auto
  #     bindDevice: eth0
EOF
    fi

    if [[ ! -f "$RULES_STATE" ]]; then
        cat > "$RULES_STATE" << 'EOF'
# Hysteria2 出站规则状态
applied_rules: []
last_sync: ""
EOF
    fi
}

get_config_outbound_rules() {
    if [[ ! -f "$HYSTERIA_CONFIG" ]]; then
        return 1
    fi

    # 提取配置文件中所有的 outbound/outbounds 规则名称
    # 兼容 outbound: 和 outbounds: 两种格式
    awk '
    /^[[:space:]]*(outbound|outbounds):[[:space:]]*$/ { in_outbound = 1; next }
    in_outbound && /^[[:space:]]*[a-zA-Z]+:[[:space:]]*$/ && !/^[[:space:]]*(outbound|outbounds|transport|auth|masquerade|bandwidth):/ { in_outbound = 0 }
    in_outbound && /^[[:space:]]*-[[:space:]]*name:[[:space:]]*(.+)$/ {
        match($0, /name:[[:space:]]*["\047]?([^"\047[:space:]]+)["\047]?/, arr)
        if (arr[1]) print arr[1]
    }
    ' "$HYSTERIA_CONFIG" 2>/dev/null
}

ask_restart_service() {
    echo ""
    read -r -p "是否重启 Hysteria2 服务以应用配置？ [y/N]: " restart_choice

    if [[ $restart_choice =~ ^[Yy]$ ]]; then
        if systemctl restart hysteria-server 2>/dev/null; then
            log_success "服务已重启"
        else
            log_error "服务重启失败，请手动重启"
        fi
    fi
}

acquire_operation_lock() {
    local operation="${1:-outbound}"
    local lock_file
    lock_file="/tmp/s-hy2-${operation}-$(whoami).lock"
    local max_wait=30
    local wait_count=0

    while [[ $wait_count -lt $max_wait ]]; do
        if (set -C; echo $$ > "$lock_file") 2>/dev/null; then
            # 成功获取锁，收紧权限（仅 owner 可读写）
            chmod 600 "$lock_file" 2>/dev/null || true
            echo "$lock_file"
            return 0
        fi

        # 检查锁文件是否过期（超过5分钟）
        if [[ -f "$lock_file" ]]; then
            local lock_age
            lock_age=$(($(date +%s) - $(stat -c %Y "$lock_file" 2>/dev/null || echo 0)))
            if [[ $lock_age -gt 300 ]]; then
                # 清理过期锁文件
                rm -f "$lock_file" 2>/dev/null
                continue
            fi
        fi

        sleep 1
        ((wait_count++))
    done

    # 获取锁失败
    return 1
}

release_operation_lock() {
    local lock_file="$1"
    [[ -n "$lock_file" && -f "$lock_file" ]] && rm -f "$lock_file"
}

create_hysteria_temp_file() {
    local prefix="${1:-hysteria}"
    local extension="${2:-yaml}"

    # 使用mktemp确保唯一性和安全性
    local temp_file
    temp_file=$(mktemp "/tmp/${prefix}-XXXXXX.${extension}")
    chmod 600 "$temp_file"

    # 添加到清理列表
    TEMP_FILES="${TEMP_FILES:-} $temp_file"

    echo "$temp_file"
}

create_config_temp_file() {
    create_hysteria_temp_file "hysteria-config" "yaml"
}

create_delete_temp_file() {
    create_hysteria_temp_file "hysteria-delete" "yaml"
}

create_apply_temp_file() {
    create_hysteria_temp_file "hysteria-apply" "yaml"
}

check_hysteria2_installation() {
    local has_binary=false
    local has_config_dir=false

    # 检查二进制文件
    if command -v hysteria >/dev/null 2>&1; then
        has_binary=true
    fi

    # 检查配置目录
    if [[ -d "/etc/hysteria" ]]; then
        has_config_dir=true
    fi

    # 根据检查结果提供指导
    if ! $has_binary; then
        echo ""
        echo -e "${RED}❌ Hysteria2 未安装${NC}"
        echo -e "${YELLOW}请先安装 Hysteria2 才能使用出站规则管理功能${NC}"
        echo ""
        echo -e "${BLUE}安装建议：${NC}"
        echo "1. 返回主菜单选择 '1. 安装 Hysteria2'"
        echo "2. 或手动安装: curl -fsSL --proto \"=https\" --tlsv1.2 -o hy2-install.sh https://get.hy2.sh/ && bash -n hy2-install.sh && bash hy2-install.sh"
        echo ""
        read -r -p "按回车键返回主菜单..." -r
        return 1
    fi

    if ! $has_config_dir; then
        echo ""
        echo -e "${YELLOW}⚠️  配置目录不存在${NC}"
        echo -e "${BLUE}正在创建配置目录: /etc/hysteria${NC}"

        if mkdir -p "/etc/hysteria" 2>/dev/null; then
            echo -e "${GREEN}✅ 配置目录创建成功${NC}"
        else
            echo -e "${RED}❌ 无法创建配置目录，可能需要 root 权限${NC}"
            echo "请以 root 用户运行此脚本，或手动创建: sudo mkdir -p /etc/hysteria"
            read -r -p "按回车键继续..." -r
            return 1
        fi
    fi

    # 检查配置文件是否存在，不存在则创建基础配置
    if [[ ! -f "$HYSTERIA_CONFIG" ]]; then
        echo ""
        echo -e "${YELLOW}⚠️  配置文件不存在: $HYSTERIA_CONFIG${NC}"
        echo -e "${BLUE}正在创建基础配置文件...${NC}"

        create_basic_hysteria_config
    fi

    # 检查配置文件权限
    check_config_file_permissions

    return 0
}

