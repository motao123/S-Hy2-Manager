#!/bin/bash
# 配置备份与恢复模块
#
# 依赖: common.sh
# 导出函数: backup_management, create_backup, restore_backup, list_backups, auto_backup

# 备份目录
BACKUP_DIR="${BACKUP_DIR:-/opt/s-hy2/backups}"

# ========== 备份管理菜单 ==========
backup_management() {
    while true; do
        clear
        echo -e "${CYAN}================================================${NC}"
        echo -e "${CYAN}           配置备份与恢复${NC}"
        echo -e "${CYAN}================================================${NC}"
        echo ""

        # 显示备份统计
        local backup_count=0
        if [[ -d "$BACKUP_DIR" ]]; then
            backup_count=$(find "$BACKUP_DIR" -name "*.tar.gz" | wc -l)
        fi
        echo -e "已保存备份: ${GREEN}${backup_count}${NC} 个"
        echo ""

        echo -e "${YELLOW}请选择操作:${NC}"
        echo ""
        echo -e "${GREEN} 1.${NC} 创建备份"
        echo -e "${GREEN} 2.${NC} 恢复备份"
        echo -e "${GREEN} 3.${NC} 查看备份列表"
        echo -e "${GREEN} 4.${NC} 删除备份"
        echo -e "${CYAN} 5.${NC} 设置自动备份"
        echo -e "${RED} 0.${NC} 返回主菜单"
        echo ""
        echo -n -e "${BLUE}请输入选项 [0-5]: ${NC}"

        local choice
        read -r choice

        case $choice in
            1) create_backup ;;
            2) restore_backup ;;
            3) list_backups ;;
            4) delete_backup ;;
            5) setup_auto_backup ;;
            0) return 0 ;;
            *) echo -e "${RED}无效选项${NC}" ;;
        esac

        echo ""
        echo -n "按回车键继续..."
        read -r
    done
}

# ========== 创建备份 ==========
create_backup() {
    echo -e "${CYAN}=== 创建备份 ===${NC}"
    echo ""

    mkdir -p "$BACKUP_DIR"

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/s-hy2-backup-${timestamp}.tar.gz"
    local backup_list=()

    # 收集需要备份的文件
    echo -e "${YELLOW}正在收集配置文件...${NC}"

    # Hysteria2 配置
    if [[ -d "$HYSTERIA_DIR" ]]; then
        backup_list+=("$HYSTERIA_DIR")
        echo -e "  ✅ $HYSTERIA_DIR"
    fi

    # 端口跳跃配置
    if [[ -f "$HYSTERIA_PORT_HOPPING_CONF" ]]; then
        echo -e "  ✅ $HYSTERIA_PORT_HOPPING_CONF"
    fi

    # s-hy2 自身配置
    if [[ -d "/opt/s-hy2" ]]; then
        backup_list+=("/opt/s-hy2/config")
        echo -e "  ✅ /opt/s-hy2/config"
    fi

    # systemd 服务文件
    if [[ -f "/etc/systemd/system/hysteria-server.service" ]]; then
        backup_list+=("/etc/systemd/system/hysteria-server.service")
        echo -e "  ✅ hysteria-server.service"
    fi

    # 创建备份
    echo ""
    echo -n "请输入备份说明（可选）: "
    local description
    read -r description

    echo -e "${YELLOW}正在创建备份...${NC}"

    # 创建临时清单文件
    local manifest
    manifest=$(create_temp_file)
    cat > "$manifest" << MANIFEST
# S-Hy2 备份清单
# 创建时间: $(date '+%Y-%m-%d %H:%M:%S')
# 说明: ${description:-无}
# 版本: 1.1.2
MANIFEST

    # 打包备份
    local items_to_backup=("${backup_list[@]}" "$manifest")
    tar -czf "$backup_file" "${items_to_backup[@]}" 2>/dev/null

    if [[ -f "$backup_file" ]]; then
        local size
        size=$(du -h "$backup_file" | awk '{print $1}')
        log_success "备份创建成功"
        echo -e "  文件: ${CYAN}$backup_file${NC}"
        echo -e "  大小: ${GREEN}$size${NC}"

        # 清理旧备份（保留最近 10 个）
        cleanup_old_backups 10
    else
        log_error "备份创建失败"
    fi

    rm -f "$manifest"
}

# ========== 恢复备份 ==========
restore_backup() {
    echo -e "${CYAN}=== 恢复备份 ===${NC}"
    echo ""

    list_backups

    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(find "$BACKUP_DIR" -name "*.tar.gz")" ]]; then
        log_error "没有可用的备份"
        return 1
    fi

    echo ""
    echo -n "请输入要恢复的备份编号: "
    local choice
    read -r choice

    local backups=()
    while IFS= read -r f; do
        backups+=("$f")
    done < <(find "$BACKUP_DIR" -name "*.tar.gz" -type f | sort -r)

    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt "${#backups[@]}" ]]; then
        log_error "无效选择"
        return 1
    fi

    local selected_backup
    selected_backup="${backups[$((choice-1))]}"
    local backup_name
    backup_name=$(basename "$selected_backup")

    echo -e "${RED}⚠️  恢复备份将覆盖当前配置！${NC}"
    echo -e "备份: ${CYAN}$backup_name${NC}"
    echo -n "确认恢复？[y/N]: "
    local confirm
    read -r confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "已取消"
        return 0
    fi

    # 先备份当前配置
    echo -e "${YELLOW}正在备份当前配置...${NC}"
    local pre_restore_backup
    pre_restore_backup="$BACKUP_DIR/pre-restore-$(date +%Y%m%d_%H%M%S).tar.gz"
    if [[ -d "$HYSTERIA_DIR" ]]; then
        tar -czf "$pre_restore_backup" "$HYSTERIA_DIR" 2>/dev/null
    fi

    # 恢复
    echo -e "${YELLOW}正在恢复备份...${NC}"
    tar -xzf "$selected_backup" -C / 2>/dev/null

    if [[ $? -eq 0 ]]; then
        log_success "备份恢复成功"
        echo -e "${YELLOW}建议重启 Hysteria2 服务以应用更改${NC}"
        ask_restart_service
    else
        log_error "恢复失败"
    fi
}

# ========== 查看备份列表 ==========
list_backups() {
    echo -e "${CYAN}=== 备份列表 ===${NC}"
    echo ""

    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(find "$BACKUP_DIR" -name "*.tar.gz")" ]]; then
        echo -e "${YELLOW}暂无备份${NC}"
        return 0
    fi

    local i=1
    while IFS= read -r backup; do
        local name
        name=$(basename "$backup")
        local size
        size=$(du -h "$backup" | awk '{print $1}')
        local date_str
        date_str=$(echo "$name" | grep -oP '\d{8}_\d{6}')
        local formatted_date
        formatted_date=$(echo "$date_str" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)_\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')

        echo -e "  ${GREEN}$i.${NC} $formatted_date  ${CYAN}$size${NC}  $name"
        ((i++))
    done < <(find "$BACKUP_DIR" -name "*.tar.gz" -type f | sort -r)
}

# ========== 删除备份 ==========
delete_backup() {
    echo -e "${CYAN}=== 删除备份 ===${NC}"
    echo ""

    list_backups

    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(find "$BACKUP_DIR" -name "*.tar.gz")" ]]; then
        return 0
    fi

    echo ""
    echo -n "请输入要删除的备份编号（0 取消）: "
    local choice
    read -r choice

    if [[ "$choice" == "0" ]]; then
        return 0
    fi

    local backups=()
    while IFS= read -r f; do
        backups+=("$f")
    done < <(find "$BACKUP_DIR" -name "*.tar.gz" -type f | sort -r)

    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt "${#backups[@]}" ]]; then
        log_error "无效选择"
        return 1
    fi

    local selected
    selected="${backups[$((choice-1))]}"
    rm -f "$selected"
    log_success "备份已删除"
}

# ========== 设置自动备份 ==========
setup_auto_backup() {
    echo -e "${CYAN}=== 设置自动备份 ===${NC}"
    echo ""

    echo -e "${YELLOW}自动备份计划:${NC}"
    echo -e "  1. 每天凌晨 3:00"
    echo -e "  2. 每周日凌晨 3:00"
    echo -e "  3. 关闭自动备份"
    echo ""
    echo -n "请选择 [1-3]: "

    local choice
    read -r choice

    local cron_cmd="/opt/s-hy2/hy2-manager.sh --auto-backup >/dev/null 2>&1"

    # 清除旧的自动备份 cron
    crontab -l 2>/dev/null | grep -v "s-hy2.*auto-backup" | crontab -

    case $choice in
        1)
            (crontab -l 2>/dev/null; echo "0 3 * * * $cron_cmd") | crontab -
            log_success "已设置每天凌晨 3:00 自动备份"
            ;;
        2)
            (crontab -l 2>/dev/null; echo "0 3 * * 0 $cron_cmd") | crontab -
            log_success "已设置每周日凌晨 3:00 自动备份"
            ;;
        3)
            log_info "已关闭自动备份"
            ;;
        *)
            log_error "无效选择"
            ;;
    esac
}

# ========== 清理旧备份 ==========
cleanup_old_backups() {
    local keep_count="${1:-10}"

    if [[ ! -d "$BACKUP_DIR" ]]; then
        return
    fi

    local total
    total=$(find "$BACKUP_DIR" -name "*.tar.gz" -type f | wc -l)

    if [[ "$total" -le "$keep_count" ]]; then
        return
    fi

    local delete_count
    delete_count=$((total - keep_count))
    log_info "清理 $delete_count 个旧备份（保留最近 $keep_count 个）"

    find "$BACKUP_DIR" -name "*.tar.gz" -type f | sort -r | tail -n "$delete_count" | xargs rm -f
}

# ========== 自动备份（由 cron 调用）==========
auto_backup() {
    create_backup
}
