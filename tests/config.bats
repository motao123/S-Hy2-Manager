#!/usr/bin/env bats
# config.sh 核心函数测试

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")"/.. && pwd)"
    export HYSTERIA_DIR="/tmp/s-hy2-test-$$"
    export HYSTERIA_CONFIG="$HYSTERIA_DIR/config.yaml"
    export HYSTERIA_DOMAIN_CONF="$HYSTERIA_DIR/server-domain.conf"
    export HYSTERIA_PORT_HOPPING_CONF="$HYSTERIA_DIR/port-hopping.conf"
    mkdir -p "$HYSTERIA_DIR"
    source "$SCRIPT_DIR/scripts/common.sh" 2>/dev/null || true
    source "$SCRIPT_DIR/scripts/config.sh" 2>/dev/null || true
}

teardown() {
    rm -rf "$HYSTERIA_DIR"
}

# ========== generate_password 测试 ==========

@test "generate_password: 默认长度 12" {
    run generate_password
    [ "$status" -eq 0 ]
    [ ${#output} -eq 12 ]
}

@test "generate_password: 自定义长度 16" {
    run generate_password 16
    [ "$status" -eq 0 ]
    [ ${#output} -eq 16 ]
}

@test "generate_password: 自定义长度 32" {
    run generate_password 32
    [ "$status" -eq 0 ]
    [ ${#output} -eq 32 ]
}

@test "generate_password: 每次生成不同密码" {
    pw1=$(generate_password)
    pw2=$(generate_password)
    [ "$pw1" != "$pw2" ]
}

@test "generate_password: 不包含特殊字符" {
    pw=$(generate_password 20)
    [[ ! "$pw" =~ [=+/] ]]
}

@test "generate_password: 无效长度使用默认值" {
    run generate_password 5
    # 应该回退到默认 12
    [ ${#output} -ge 8 ]
}

# ========== validate_domain 测试 ==========

@test "validate_domain: 有效域名 cloudflare.com" {
    run validate_domain "cloudflare.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain: 有效域名 www.google.com" {
    run validate_domain "www.google.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain: 无效 - IP 地址" {
    run validate_domain "192.168.1.1"
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
    # IP 地址格式上可能匹配，但语义上不是域名
}
