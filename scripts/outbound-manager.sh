#!/bin/bash

# Hysteria2 出站规则管理模块
# 功能: 配置和管理 Hysteria2 的出站规则
# 支持: Direct、SOCKS5、HTTP 代理类型
# 特性: 类型唯一性强制、具体参数修改、智能冲突检测

# 适度的错误处理
set -uo pipefail

# 加载公共库
# SCRIPT_DIR 由主脚本定义，此处已移除以避免覆盖
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/common.sh" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
else
    echo "错误: 无法加载公共库" >&2
    exit 1
fi

# 配置路径 (防止重复定义)
if [[ -z "${HYSTERIA_CONFIG:-}" ]]; then
    readonly HYSTERIA_CONFIG="/etc/hysteria/config.yaml"
fi
# 备份功能已移除

# 初始化出站管理
# ========== 模块加载 ==========
# 出站管理功能已拆分到 modules/ 目录
# 此文件保留向后兼容，加载所有子模块

load_outbound_modules() {
    local base_dir="${PROJECT_DIR:-}"
    if [[ -z "$base_dir" ]]; then
        if [[ -n "${SCRIPTS_DIR:-}" ]]; then
            base_dir="$(dirname "$SCRIPTS_DIR")"
        elif [[ -n "${SCRIPT_DIR:-}" && -d "$SCRIPT_DIR/modules" ]]; then
            base_dir="$SCRIPT_DIR"
        else
            base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
        fi
    fi
    local modules_dir="$base_dir/modules"
    for module in outbound-core outbound-add outbound-modify outbound-delete outbound-apply outbound-view; do
        if [[ -f "$modules_dir/$module.sh" ]]; then
            source "$modules_dir/$module.sh"
        else
            echo "警告: 出站管理模块 $module.sh 未找到" >&2
        fi
    done
}

# 自动加载（当被 source 时）
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    load_outbound_modules
fi
