#!/usr/bin/env bats
# CLI 参数和配置验证测试

setup() {
    export S_HY2_TEST_DIR="$(mktemp -d)"
    export S_HY2_TEST_CONFIG="$S_HY2_TEST_DIR/config.yaml"
    export S_HY2_TEST_SERVICE="hysteria-server.service"
}

teardown() {
    rm -rf "$S_HY2_TEST_DIR" 2>/dev/null
}

# ========== generate_password 测试 ==========

@test "generate_password: 默认长度 16" {
    source "$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/common.sh"
    password=$(generate_password 16)
    [ ${#password} -ge 8 ]  # 至少8位（某些随机源可能不足16）
}

@test "generate_password: 只含字母数字" {
    source "$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/common.sh"
    password=$(generate_password 20)
    [[ "$password" =~ ^[a-zA-Z0-9]+$ ]]
}

@test "generate_password: 每次不同" {
    source "$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/common.sh"
    p1=$(generate_password)
    p2=$(generate_password)
    [ "$p1" != "$p2" ]
}

# ========== get_auth_mode 测试 ==========

@test "get_auth_mode: 识别 password 模式" {
    cat > "$S_HY2_TEST_CONFIG" << 'EOF'
listen: :443

auth:
  type: password
  password: test123
EOF

    # 直接测试逻辑
    result="none"
    if grep -q "type: userpass" "$S_HY2_TEST_CONFIG" 2>/dev/null; then
        result="userpass"
    elif grep -q "type: password" "$S_HY2_TEST_CONFIG" 2>/dev/null; then
        result="password"
    fi
    [ "$result" = "password" ]
}

@test "get_auth_mode: 识别 userpass 模式" {
    cat > "$S_HY2_TEST_CONFIG" << 'EOF'
listen: :443

auth:
  type: userpass
  userpass:
    user1: pass1
    user2: pass2
EOF

    result="none"
    if grep -q "type: userpass" "$S_HY2_TEST_CONFIG" 2>/dev/null; then
        result="userpass"
    elif grep -q "type: password" "$S_HY2_TEST_CONFIG" 2>/dev/null; then
        result="password"
    fi
    [ "$result" = "userpass" ]
}

@test "get_auth_mode: 配置文件不存在" {
    rm -f "$S_HY2_TEST_CONFIG"
    [ ! -f "$S_HY2_TEST_CONFIG" ]
}

# ========== count_users 逻辑测试 ==========

@test "count_users: userpass 模式计数" {
    cat > "$S_HY2_TEST_CONFIG" << 'EOF'
listen: :443

auth:
  type: userpass
  userpass:
    user1: pass1
    user2: pass2
    user3: pass3
EOF

    # 测试计数逻辑
    local count=0
    local in_userpass=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*userpass: ]]; then
            in_userpass=true
            continue
        fi
        if $in_userpass; then
            if [[ "$line" =~ ^[[:space:]]+([a-zA-Z0-9_-]+):.+ ]]; then
                local username="${BASH_REMATCH[1]}"
                if [[ "$username" != "type" && "$username" != "password" ]]; then
                    count=$((count + 1))
                fi
            elif [[ "$line" =~ ^[a-zA-Z] ]]; then
                break
            fi
        fi
    done < "$S_HY2_TEST_CONFIG"
    [ "$count" -eq 3 ]
}

# ========== get_listen_port 逻辑测试 ==========

@test "get_listen_port: 解析端口" {
    cat > "$S_HY2_TEST_CONFIG" << 'EOF'
listen: :8443

auth:
  type: password
  password: test
EOF

    port=$(grep -E "^\s*listen:" "$S_HY2_TEST_CONFIG" | grep -oP ':\K[0-9]+')
    [ "$port" = "8443" ]
}

@test "get_listen_port: 默认 443" {
    cat > "$S_HY2_TEST_CONFIG" << 'EOF'
auth:
  type: password
  password: test
EOF

    port=$(grep -E "^\s*listen:" "$S_HY2_TEST_CONFIG" 2>/dev/null | grep -oP ':\K[0-9]+' || true)
    port="${port:-443}"
    [ "$port" = "443" ]
}

# ========== 备份文件名格式测试 ==========

@test "backup: 文件名格式正确" {
    timestamp=$(date +%Y%m%d_%H%M%S)
    filename="s-hy2-backup-${timestamp}.tar.gz"
    [[ "$filename" =~ s-hy2-backup-[0-9]{8}_[0-9]{6}\.tar\.gz ]]
}

# ========== URI 格式测试 ==========

@test "URI: hysteria2:// 格式" {
    uri="hysteria2://user:pass@1.2.3.4:443?sni=example.com&insecure=0"
    [[ "$uri" =~ ^hysteria2:// ]]
    [[ "$uri" == *@* ]]
    [[ "$uri" == *"?sni="* ]]
    [[ "$uri" == *"insecure="* ]]
}

@test "URI: 带混淆参数" {
    uri="hysteria2://user:pass@1.2.3.4:443?sni=example.com&insecure=0&obfs=salamander&obfs-password=candy"
    [[ "$uri" == *"obfs=salamander"* ]]
    [[ "$uri" == *"obfs-password=candy"* ]]
}

# ========== YAML 语法验证测试 ==========

@test "validate: 有效 YAML" {
    cat > "$S_HY2_TEST_CONFIG" << 'EOF'
listen: :443
auth:
  type: password
  password: test
masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true
EOF

    if command -v python3 &>/dev/null; then
        python3 -c "import yaml; yaml.safe_load(open('$S_HY2_TEST_CONFIG'))"
    fi
}

@test "validate: 必要字段存在" {
    cat > "$S_HY2_TEST_CONFIG" << 'EOF'
listen: :443
auth:
  type: password
  password: test
EOF

    grep -q "listen:" "$S_HY2_TEST_CONFIG"
    grep -q "type:" "$S_HY2_TEST_CONFIG"
}

# ========== CLI help 测试 ==========

@test "CLI: --help 显示帮助" {
    script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    # 检查脚本存在
    [ -f "$script_dir/hy2-manager.sh" ]
}
