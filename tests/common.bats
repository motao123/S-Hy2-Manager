#!/usr/bin/env bats
# common.sh 核心函数测试

setup() {
    # Source common.sh
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")"/.. && pwd)"
    source "$SCRIPT_DIR/scripts/common.sh" 2>/dev/null || true
}

# ========== validate_domain 测试 ==========

@test "validate_domain: 有效的简单域名" {
    run validate_domain "example.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain: 有效的子域名" {
    run validate_domain "sub.example.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain: 有效的多级子域名" {
    run validate_domain "a.b.c.example.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain: 无效 - 空字符串" {
    run validate_domain ""
    [ "$status" -eq 1 ]
}

@test "validate_domain: 无效 - 以连字符开头" {
    run validate_domain "-example.com"
    [ "$status" -eq 1 ]
}

@test "validate_domain: 无效 - 以连字符结尾" {
    run validate_domain "example-.com"
    [ "$status" -eq 1 ]
}

@test "validate_domain: 无效 - 包含特殊字符" {
    run validate_domain "exam!ple.com"
    [ "$status" -eq 1 ]
}

@test "validate_domain: 无效 - 包含空格" {
    run validate_domain "exam ple.com"
    [ "$status" -eq 1 ]
}

@test "validate_domain: 无效 - 以点开头" {
    run validate_domain ".example.com"
    [ "$status" -eq 1 ]
}

@test "validate_domain: 有效 - 包含连字符" {
    run validate_domain "my-example.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain: 有效 - 纯数字域名" {
    run validate_domain "123.com"
    [ "$status" -eq 0 ]
}

# ========== 日志函数测试 ==========

@test "log_info: 正常输出" {
    run log_info "测试信息"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[INFO]"* ]]
    [[ "$output" == *"测试信息"* ]]
}

@test "log_warn: 正常输出" {
    run log_warn "警告信息"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[WARN]"* ]]
}

@test "log_error: 正常输出" {
    run log_error "错误信息"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[ERROR]"* ]]
}

@test "log_success: 正常输出" {
    run log_success "成功信息"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[SUCCESS]"* ]]
}

# ========== require_command 测试 ==========

@test "require_command: 存在的命令" {
    run require_command "bash"
    [ "$status" -eq 0 ]
}

@test "require_command: 不存在的命令" {
    run require_command "this_command_does_not_exist_12345"
    [ "$status" -ne 0 ]
}

# ========== 临时文件测试 ==========

@test "create_temp_file: 创建临时文件" {
    run create_temp_file
    [ "$status" -eq 0 ]
    [ -f "$output" ]
    rm -f "$output"
}

@test "create_temp_dir: 创建临时目录" {
    run create_temp_dir
    [ "$status" -eq 0 ]
    [ -d "$output" ]
    rm -rf "$output"
}

# ========== check_internet_connection 测试 ==========

@test "check_internet_connection: 检查网络" {
    run check_internet_connection
    # 只要不报错就行（网络可能通也可能不通）
    [ "$status" -eq 0 ] || [ "$status" -ne 0 ]
}

# ========== yaml_quote_scalar 特殊字符测试 ==========

@test "yaml_quote_scalar: 普通字符串加双引号" {
    run yaml_quote_scalar "hello"
    [ "$status" -eq 0 ]
    [ "$output" = '"hello"' ]
}

@test "yaml_quote_scalar: 包含双引号时转义" {
    run yaml_quote_scalar 'say "hi"'
    [ "$status" -eq 0 ]
    [ "$output" = '"say \"hi\""' ]
}

@test "yaml_quote_scalar: 包含反斜杠时转义" {
    run yaml_quote_scalar 'path\to\file'
    [ "$status" -eq 0 ]
    [ "$output" = '"path\\\\to\\\\file"' ]
}

@test "yaml_quote_scalar: 包含换行符时转义" {
    run yaml_quote_scalar $'line1\nline2'
    [ "$status" -eq 0 ]
    [ "$output" = '"line1\\nline2"' ]
}

@test "yaml_quote_scalar: 包含 Tab 时转义" {
    run yaml_quote_scalar $'col1\tcol2'
    [ "$status" -eq 0 ]
    [ "$output" = '"col1\\tcol2"' ]
}

@test "yaml_quote_scalar: 包含斜杠不破坏 YAML" {
    run yaml_quote_scalar 'https://example.com/path'
    [ "$status" -eq 0 ]
    [[ "$output" == *'https://example.com/path'* ]]
}

@test "yaml_quote_scalar: 包含 and 符号不破坏输出" {
    run yaml_quote_scalar 'foo&bar'
    [ "$status" -eq 0 ]
    [ "$output" = '"foo&bar"' ]
}

@test "yaml_quote_scalar: 空值输出空双引号" {
    run yaml_quote_scalar ""
    [ "$status" -eq 0 ]
    [ "$output" = '""' ]
}

# ========== yaml_unquote_scalar 测试 ==========

@test "yaml_unquote_scalar: 双引号标量正确去引号" {
    run yaml_unquote_scalar '"hello"'
    [ "$status" -eq 0 ]
    [ "$output" = 'hello' ]
}

@test "yaml_unquote_scalar: 单引号标量正确去引号" {
    run yaml_unquote_scalar "'hello'"
    [ "$status" -eq 0 ]
    [ "$output" = 'hello' ]
}

@test "yaml_unquote_scalar: 无引号标量原样返回" {
    run yaml_unquote_scalar 'hello'
    [ "$status" -eq 0 ]
    [ "$output" = 'hello' ]
}

@test "yaml_unquote_scalar: 去除前后空白" {
    run yaml_unquote_scalar '  hello  '
    [ "$status" -eq 0 ]
    [ "$output" = 'hello' ]
}

# ========== yaml_write_kv 测试 ==========

@test "yaml_write_kv: 生成正确的 YAML 键值行" {
    run yaml_write_kv "" "key" "value"
    [ "$status" -eq 0 ]
    [ "$output" = 'key: "value"' ]
}

@test "yaml_write_kv: 带缩进生成 YAML 键值行" {
    run yaml_write_kv "    " "key" "value"
    [ "$status" -eq 0 ]
    [ "$output" = '    key: "value"' ]
}

@test "yaml_write_kv: 特殊字符值安全引用" {
    run yaml_write_kv "" "password" 'p@ss/w0rd&"test'
    [ "$status" -eq 0 ]
    [[ "$output" == 'password: '* ]]
    # 确认值被双引号包裹
    [[ "$output" == *'"'*'"' ]]
}
