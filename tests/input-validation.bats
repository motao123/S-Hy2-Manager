#!/usr/bin/env bats
# input-validation.sh 安全输入验证测试

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")"/.. && pwd)"
    source "$SCRIPT_DIR/scripts/input-validation.sh" 2>/dev/null || true
}

# ========== 域名验证（安全版）==========

@test "validate_domain_secure: 有效的域名" {
    run validate_domain_secure "www.example.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain_secure: 无效 - 过长域名" {
    long_domain=$(python3 -c "print('a'*250 + '.com')")
    run validate_domain_secure "$long_domain"
    [ "$status" -eq 1 ]
}

@test "validate_domain_secure: 无效 - 非法字符" {
    run validate_domain_secure "exam\$()ple.com"
    [ "$status" -eq 1 ]
}

@test "validate_domain_secure: 无效 - 命令注入尝试" {
    run validate_domain_secure "example.com\$(whoami)"
    [ "$status" -eq 1 ]
}

@test "validate_domain_secure: 无效 - 分号注入" {
    run validate_domain_secure "example.com;rm -rf /"
    [ "$status" -eq 1 ]
}

@test "validate_domain_secure: 无效 - 反引号注入" {
    run validate_domain_secure "example.com\`whoami\`"
    [ "$status" -eq 1 ]
}

# ========== 数字验证 ==========

@test "validate_number_secure: 有效数字" {
    run validate_number_secure 100 1 200
    [ "$status" -eq 0 ]
}

@test "validate_number_secure: 小于最小值" {
    run validate_number_secure 0 1 200
    [ "$status" -ne 0 ]
}

@test "validate_number_secure: 大于最大值" {
    run validate_number_secure 300 1 200
    [ "$status" -ne 0 ]
}

@test "validate_number_secure: 非数字" {
    run validate_number_secure "abc" 1 200
    [ "$status" -ne 0 ]
}

# ========== 端口验证 ==========

@test "validate_port_secure: 有效端口 443" {
    run validate_port_secure 443
    [ "$status" -eq 0 ]
}

@test "validate_port_secure: 有效端口 8080" {
    run validate_port_secure 8080
    [ "$status" -eq 0 ]
}

@test "validate_port_secure: 无效 - 端口 0" {
    run validate_port_secure 0
    [ "$status" -ne 0 ]
}

@test "validate_port_secure: 无效 - 端口 65536" {
    run validate_port_secure 65536
    [ "$status" -ne 0 ]
}

@test "validate_port_secure: 无效 - 非数字" {
    run validate_port_secure "abc"
    [ "$status" -ne 0 ]
}
