#!/bin/bash
# 自动更新检查模块
#
# 依赖: common.sh
# 导出函数: check_for_updates, update_hysteria, update_s-hy2
#
# 【安全说明】
# SHA256 哈希用于以下两种场景，性质不同：
#   1. 变化检测（S-Hy2-Manager 脚本对比）：仅判断远程文件是否与本地不同，不构成安全校验
#   2. 完整性验证（Hysteria2 二进制）：下载后计算 SHA256 并记录，后续可检测篡改
# 官方 Hysteria2 Release 未提供签名或 checksums 文件，因此无法做发布者真实性验证。
# 如需最高安全保证，应手动下载并离线校验。

# 已安装版本记录文件（用于版本固定与完整性追踪）
_INSTALLED_VERSION_FILE="/etc/hysteria/.installed_version"
_INSTALLED_SHA256_FILE="/etc/hysteria/.installed_sha256"

# ========== 记录已安装版本信息 ==========
# 在成功安装/更新后调用，记录版本号和二进制 SHA256
_record_installed_version() {
    local version="$1"
    local binary_path

    binary_path=$(command -v hysteria 2>/dev/null || echo "")

    if [[ -z "$binary_path" || ! -f "$binary_path" ]]; then
        log_warn "无法定位 hysteria 二进制，跳过版本记录"
        return
    fi

    local sha256
    sha256=$(sha256sum "$binary_path" 2>/dev/null | awk '{print $1}')

    if [[ -n "$version" ]]; then
        echo "$version" > "$_INSTALLED_VERSION_FILE"
        chmod 600 "$_INSTALLED_VERSION_FILE"
    fi

    if [[ -n "$sha256" ]]; then
        echo "$sha256" > "$_INSTALLED_SHA256_FILE"
        chmod 600 "$_INSTALLED_SHA256_FILE"
        log_info "已记录 Hysteria2 $version SHA256: ${sha256:0:16}..."
    fi
}

# ========== 验证已安装二进制完整性 ==========
# 对比当前 hysteria 二进制的 SHA256 与上次记录的值
# 返回 0 = 一致, 1 = 不一致或无法验证
verify_installed_integrity() {
    local binary_path
    binary_path=$(command -v hysteria 2>/dev/null || echo "")

    if [[ -z "$binary_path" || ! -f "$binary_path" ]]; then
        echo -e "${YELLOW}Hysteria2 未安装，无法验证完整性${NC}"
        return 1
    fi

    if [[ ! -f "$_INSTALLED_SHA256_FILE" ]]; then
        echo -e "${YELLOW}无历史 SHA256 记录，跳过完整性比对${NC}"
        return 1
    fi

    local current_sha256 recorded_sha256
    current_sha256=$(sha256sum "$binary_path" | awk '{print $1}')
    recorded_sha256=$(cat "$_INSTALLED_SHA256_FILE" | tr -d '[:space:]')

    if [[ "$current_sha256" == "$recorded_sha256" ]]; then
        echo -e "${GREEN}二进制完整性验证通过${NC}"
        return 0
    else
        echo -e "${RED}警告：当前二进制 SHA256 与上次记录不一致！${NC}"
        echo -e "  记录值: ${recorded_sha256:0:16}..."
        echo -e "  当前值: ${current_sha256:0:16}..."
        echo -e "${YELLOW}可能原因：手动替换、包管理器更新、或文件被篡改${NC}"
        return 1
    fi
}

# ========== 检查 Hysteria2 更新 ==========
check_for_updates() {
    echo -e "${CYAN}=== 检查更新 ===${NC}"
    echo ""

    # 先验证已安装二进制完整性
    echo -e "${YELLOW}正在验证 Hysteria2 二进制完整性...${NC}"
    verify_installed_integrity
    echo ""

    # 检查 Hysteria2 更新
    echo -e "${YELLOW}正在检查 Hysteria2 更新...${NC}"

    local current_version
    current_version=$(hysteria version 2>/dev/null | grep -oP 'v[\d.]+' | head -1)

    if [[ -z "$current_version" ]]; then
        echo -e "${YELLOW}Hysteria2 未安装或无法获取版本${NC}"
    else
        echo -e "当前版本: ${GREEN}$current_version${NC}"

        # 从 GitHub 获取最新版本
        local latest_version
        latest_version=$(curl -sI "https://github.com/apernet/hysteria/releases/latest" 2>/dev/null | grep -i "location:" | grep -oP 'v[\d.]+' | head -1)

        if [[ -n "$latest_version" ]]; then
            echo -e "最新版本: ${GREEN}$latest_version${NC}"
            if [[ "$current_version" != "$latest_version" ]]; then
                echo -e "${YELLOW}发现新版本！${NC}"
                echo -n "是否更新？[y/N]: "
                local confirm
                read -r confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    update_hysteria
                fi
            else
                echo -e "${GREEN}已是最新版本${NC}"
            fi
        else
            echo -e "${YELLOW}无法检查最新版本（网络问题）${NC}"
        fi
    fi

    echo ""

    # 检查 S-Hy2-Manager 脚本更新
    # 注意：SHA256 对比仅用于变化检测，不构成安全完整性校验
    echo -e "${YELLOW}正在检查 S-Hy2-Manager 脚本更新...${NC}"
    local s_hy2_remote_hash
    s_hy2_remote_hash=$(curl -fsSL --proto "=https" --tlsv1.2 "https://raw.githubusercontent.com/motao123/S-Hy2-Manager/main/hy2-manager.sh" 2>/dev/null | sha256sum | awk '{print $1}')
    local s_hy2_local_hash
    s_hy2_local_hash=$(sha256sum "$SCRIPT_DIR/hy2-manager.sh" 2>/dev/null | awk '{print $1}')

    if [[ "$s_hy2_remote_hash" != "$s_hy2_local_hash" ]] && [[ -n "$s_hy2_remote_hash" ]]; then
        echo -e "${YELLOW}发现 S-Hy2-Manager 脚本更新${NC}"
        echo -n "是否更新脚本？[y/N]: "
        local confirm
        read -r confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            update_s-hy2
        fi
    else
        echo -e "${GREEN}S-Hy2-Manager 脚本已是最新${NC}"
    fi
}

# ========== 更新 Hysteria2 ==========
update_hysteria() {
    echo -e "${YELLOW}正在更新 Hysteria2...${NC}"

    # 统一通过 fetch_and_run_script 安全下载、语法校验、完整性校验后执行
    fetch_and_run_script "https://get.hy2.sh/" "hysteria-install"
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        # 更新成功后记录新版本信息
        local new_version
        new_version=$(hysteria version 2>/dev/null | grep -oP 'v[\d.]+' | head -1)
        _record_installed_version "${new_version:-unknown}"
        log_success "Hysteria2 更新完成"
    else
        log_error "Hysteria2 更新失败"
        return $exit_code
    fi
}

# ========== 更新 S-Hy2-Manager 脚本 ==========
update_s-hy2() {
    echo -e "${YELLOW}正在更新 S-Hy2-Manager 脚本...${NC}"

    # 统一通过 fetch_and_run_script 安全下载校验后执行（避免 sudo 管道执行）
    # 注意：脚本更新以当前权限执行 quick-install.sh（管理脚本通常以 root/sudo 运行）
    fetch_and_run_script "https://raw.githubusercontent.com/motao123/S-Hy2-Manager/main/quick-install.sh" "s-hy2-update"
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_success "S-Hy2-Manager 脚本更新完成"
    else
        log_error "S-Hy2-Manager 脚本更新失败"
        return $exit_code
    fi
}
