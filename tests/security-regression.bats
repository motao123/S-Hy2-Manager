#!/usr/bin/env bats
# 安全回归测试：防止已修复的高风险模式回归

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

@test "security: Shell 脚本禁止 bash <(curl ...) 远程执行" {
    run grep -RInE 'bash[[:space:]]+<\(curl' "$PROJECT_ROOT" \
        --include='*.sh' \
        --exclude-dir='.git'
    [ "$status" -ne 0 ]
}

@test "security: 可执行脚本禁止 curl/wget 管道到 shell" {
    run grep -RInE '(curl|wget).*\|.*(bash|sh)' "$PROJECT_ROOT" \
        --include='*.sh' \
        --exclude-dir='.git'
    [ "$status" -ne 0 ]
}

@test "security: 不允许把 Hysteria 配置权限降级为 644" {
    run grep -RInE 'chmod[[:space:]]+644[[:space:]]+"?\$HYSTERIA_CONFIG"?' "$PROJECT_ROOT" \
        --include='*.sh' \
        --exclude-dir='.git'
    [ "$status" -ne 0 ]
}

@test "security: --add-user 不再接受密码位置参数" {
    run grep -RIn -- '--add-user USERNAME [PASSWORD]' "$PROJECT_ROOT" \
        --include='*.sh' \
        --exclude-dir='.git'
    [ "$status" -ne 0 ]
}

@test "security: Shell 脚本禁止可预测 /tmp 临时文件名" {
    run grep -RInE '/tmp/[^"'"' ]*(\$\$|date[[:space:]]+\+%s|date[[:space:]]+\+%N)' "$PROJECT_ROOT" \
        --include='*.sh' \
        --exclude-dir='.git'
    [ "$status" -ne 0 ]
}


@test "security: 危险 rm -rf 只能出现在白名单删除或临时目录清理中" {
    run grep -RInE 'rm[[:space:]]+-rf' "$PROJECT_ROOT" \
        --include='*.sh' \
        --exclude-dir='.git'

    if [ "$status" -eq 0 ]; then
        while IFS= read -r line; do
            case "$line" in
                *'rm -rf -- "$target"'*|*'rm -rf -- "$SECURE_TEMP_DIR"'*|*'rm -rf -- "$temp_dir"'*|*'"rm -rf /"'*) ;;
                *) echo "unexpected rm -rf: $line"; return 1 ;;
            esac
        done <<< "$output"
    fi
}

@test "security: 伪装域名配置禁止直接 sed 拼接 URL" {
    run grep -RInE 'sed[[:space:]]+-i(\.bak)?[^\n]*(url:.*\$|\$.*url:)' "$PROJECT_ROOT/modules" "$PROJECT_ROOT/scripts" \
        --include='*.sh' \
        --exclude-dir='.git'
    [ "$status" -ne 0 ]
}

@test "security: 出站规则修改禁止直接 sed 拼接规则名" {
    run grep -RInE 'sed[[:space:]]+-i(\.bak)?[^\n]*(\$old_name|\$new_name)' "$PROJECT_ROOT/modules" \
        --include='*.sh' \
        --exclude-dir='.git'
    [ "$status" -ne 0 ]
}

@test "security: YAML 写入应使用统一安全标量函数" {
    run grep -RInE 'echo[[:space:]]+"\$\{?indent\}?[a-zA-Z_]+:[[:space:]]*\$' "$PROJECT_ROOT/modules" "$PROJECT_ROOT/scripts" \
        --include='*.sh' \
        --exclude-dir='.git'
    [ "$status" -ne 0 ]
}

@test "security: 规则状态文件禁止 sed 拼接规则名" {
    run grep -RInE 'sed[[:space:]]+-i[^\n]*\$rule_name' "$PROJECT_ROOT/modules" \
        --include='*.sh' \
        --exclude-dir='.git'
    [ "$status" -ne 0 ]
}

@test "security: 出站新增规则禁止裸拼接敏感 YAML 字段" {
    run grep -RInE '(description|addr|url|username|password):[[:space:]]*"?\$(rule_desc|desc|addr|url|username|password|SOCKS5_|HTTP_)' "$PROJECT_ROOT/modules/outbound-add.sh"
    [ "$status" -ne 0 ]
}

@test "security: 出站应用禁止裸拼接敏感 YAML 字段" {
    run grep -RInE '(name|addr|url|username|password|bindDevice|bindIPv4|bindIPv6|insecure):[[:space:]]*"?\$(name|SOCKS5_|HTTP_|DIRECT_)' "$PROJECT_ROOT/modules/outbound-apply.sh"
    [ "$status" -ne 0 ]
}

@test "security: 出站应用不得将配置权限降级为 644" {
    run grep -RInE 'chmod[[:space:]]+644[[:space:]]+"?\$target_file"?' "$PROJECT_ROOT/modules/outbound-apply.sh"
    [ "$status" -ne 0 ]
}

@test "security: 规则应用状态检测禁止 grep 拼接规则名" {
    run grep -RInE 'grep[[:space:]].*\$\{?rule_name\}?' "$PROJECT_ROOT/modules/outbound-view.sh"
    [ "$status" -ne 0 ]
}

@test "security: 出站模块禁止规则名进入 grep/sed/正则" {
    run grep -RInE '\[\[.*=~.*\$\{?rule_name\}?|grep.*\$\{?rule_name\}?|sed.*\$\{?rule_name\}?' "$PROJECT_ROOT/modules" \
        --include='*.sh' \
        --exclude-dir='.git'
    [ "$status" -ne 0 ]
}

@test "security: 出站删除状态文件应使用安全逐行解析" {
    run grep -RInE 'awk[[:space:]]+-v[[:space:]]+rule="?\$rule_name"?' "$PROJECT_ROOT/modules/outbound-delete.sh"
    [ "$status" -ne 0 ]
}

@test "security: 配置编辑模块密码禁止 sed 替换进 YAML" {
    run grep -RInE 'sed[[:space:]]+-i.*password.*\$' "$PROJECT_ROOT/modules/config-edit.sh"
    [ "$status" -ne 0 ]
}

@test "security: 配置编辑模块端口禁止全文件 sed 替换" {
    run grep -RInE 'sed[[:space:]]+-i.*s/:\$current_port' "$PROJECT_ROOT/modules/config-edit.sh"
    [ "$status" -ne 0 ]
}

@test "security: 配置编辑模块禁止 source 外部配置文件" {
    run grep -RInE 'source[[:space:]]+/etc/hysteria/port-hopping' "$PROJECT_ROOT/modules/config-edit.sh"
    [ "$status" -ne 0 ]
}

@test "security: 配置编辑模块禁止未白名单编辑器调用" {
    run grep -RInE '\$\{EDITOR:[^-]' "$PROJECT_ROOT/modules/config-edit.sh"
    [ "$status" -ne 0 ]
}

@test "security: 证书模块 TLS 配置禁止 sed 替换证书路径" {
    run grep -RInE 'sed[[:space:]]+-i.*/cert:/c' "$PROJECT_ROOT/modules/certificate.sh"
    [ "$status" -ne 0 ]
}

@test "security: 证书模块禁止裸写 YAML cert/key 路径" {
    run grep -RInE 'echo[[:space:]]+"[[:space:]]*cert:[[:space:]]*\$' "$PROJECT_ROOT/modules/certificate.sh"
    [ "$status" -ne 0 ]
}

@test "security: 带宽模块禁止裸写带宽值到 YAML" {
    run grep -RInE 'echo[[:space:]]+"[[:space:]]*(up|down):[[:space:]]*\$' "$PROJECT_ROOT/modules/bandwidth.sh"
    [ "$status" -ne 0 ]
}

@test "security: 带宽模块配置替换禁止直接 mv" {
    run grep -RInE 'mv[[:space:]]+"\$temp_file"[[:space:]]+"\$HYSTERIA_CONFIG"' "$PROJECT_ROOT/modules/bandwidth.sh"
    [ "$status" -ne 0 ]
}

@test "security: 带宽模块 ignoreClientBandwidth 禁止 sed 替换" {
    run grep -RInE 'sed[[:space:]]+-i.*ignoreClientBandwidth' "$PROJECT_ROOT/modules/bandwidth.sh"
    [ "$status" -ne 0 ]
}

@test "security: ACL 模块禁止未白名单编辑器调用" {
    run grep -RInE '\$\{EDITOR:[^-]' "$PROJECT_ROOT/modules/acl-manager.sh"
    [ "$status" -ne 0 ]
}

@test "security: ACL 配置行禁止 sed 裸拼接路径" {
    run grep -RInE 'sed[[:space:]]+-i.*acl:.*\$ACL_FILE' "$PROJECT_ROOT/modules/acl-manager.sh"
    [ "$status" -ne 0 ]
}

@test "security: ACL 取消注释禁止丢失路径" {
    run grep -RInE "sed.*'s/\^#.*acl:.*/acl:/'" "$PROJECT_ROOT/modules/acl-manager.sh"
    [ "$status" -ne 0 ]
}

@test "security: ACL 远程导入禁止非 HTTPS 下载" {
    run grep -RInE 'curl.*-o[[:space:]]+"?\$ACL_FILE' "$PROJECT_ROOT/modules/acl-manager.sh"
    [ "$status" -ne 0 ]
}

@test "security: 全项目禁止 source 外部 port-hopping 配置执行" {
    run grep -RInE 'source.*port-hopping\.conf' "$PROJECT_ROOT/modules" "$PROJECT_ROOT/scripts" \
        --include='*.sh' \
        --exclude-dir='.git'
    [ "$status" -ne 0 ]
}

@test "security: 配置文件替换禁止直接 mv 临时文件" {
    run grep -RInE 'mv[[:space:]]+"\$temp_file"[[:space:]]+"\$(HYSTERIA_CONFIG|CONFIG_PATH)"' "$PROJECT_ROOT/modules" "$PROJECT_ROOT/scripts" \
        --include='*.sh' \
        --exclude-dir='.git'
    [ "$status" -ne 0 ]
}

@test "security: DNS 模块禁止裸写 DNS 地址到 YAML" {
    run grep -RInE 'echo.*addr:[[:space:]]*\$dns' "$PROJECT_ROOT/modules/dns-manager.sh"
    [ "$status" -ne 0 ]
}

@test "security: 客户端导出禁止 grep 拼接用户名" {
    run grep -RInE 'grep.*\$\{?username\}?' "$PROJECT_ROOT/modules/client-export.sh"
    [ "$status" -ne 0 ]
}

@test "security: 自动更新脚本禁止使用 MD5 做变化检测（应使用 SHA256）" {
    run grep -RInE 'md5sum' "$PROJECT_ROOT/modules/auto-update.sh"
    [ "$status" -ne 0 ]
}

@test "security: 安全下载模块禁止 placeholder 哈希值" {
    run grep -RInE 'placeholder_hash' "$PROJECT_ROOT/scripts/secure-download.sh"
    [ "$status" -ne 0 ]
}

@test "security: 安全下载模块默认输出权限应为 600 而非 644" {
    run grep -RInE 'chmod[[:space:]]+644[[:space:]]+"?\$output_file"?' "$PROJECT_ROOT/scripts/secure-download.sh"
    [ "$status" -ne 0 ]
}







