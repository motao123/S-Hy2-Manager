# S-Hy2 Manager

<div align="center">

Hysteria2 代理服务器一键部署与管理工具

[快速安装](#快速安装) · [功能概览](#功能概览) · [CLI 用法](#cli-用法) · [项目结构](#项目结构) · [开发](#开发)

</div>

---

## 功能概览

| 分类 | 功能 |
|------|------|
| 部署 | 一键安装 / 卸载、快速配置 / 手动配置、部署后自动检查 |
| 用户 | 多用户管理（userpass 认证）、批量添加 / 删除 |
| 导出 | 客户端 YAML / URI 链接 / 二维码 / 订阅链接 |
| 证书 | ACME 自动证书、自签名证书、自定义证书上传 |
| 出站 | Direct / SOCKS5 / HTTP 代理规则管理 |
| 运维 | 配置备份恢复、日志管理、流量统计、速度测试 |
| 网络 | 防火墙自动配置、端口跳跃、DNS 管理、ACL 规则、带宽限制 |
| 安全 | 输入注入防护、安全临时文件、SHA256 完整性校验、安全下载 |
| 更新 | Hysteria2 二进制更新 + 脚本自身更新 |

## 快速安装

```bash
curl -fsSL --proto '=https' --tlsv1.2 \
  -o quick-install.sh \
  https://raw.githubusercontent.com/motao123/S-Hy2-Manager/main/quick-install.sh
bash -n quick-install.sh
sudo bash quick-install.sh
sudo s-hy2
```

### 手动安装

```bash
git clone https://github.com/motao123/S-Hy2-Manager.git
cd s-hy2
chmod +x hy2-manager.sh scripts/*.sh modules/*.sh
sudo ./hy2-manager.sh
```

## 系统要求

- Ubuntu 18.04+ / Debian 9+ / CentOS 7+ / Fedora 30+
- root 或 sudo 权限
- systemd

## CLI 用法

```bash
sudo s-hy2                          # 交互菜单（默认）
sudo s-hy2 --install                # 安装 Hysteria2
sudo s-hy2 --uninstall              # 卸载
sudo s-hy2 --status                 # 服务状态
sudo s-hy2 --restart                # 重启服务
sudo s-hy2 --stop                   # 停止服务
sudo s-hy2 --start                  # 启动服务

# 用户管理
sudo s-hy2 --list-users             # 列出用户
sudo s-hy2 --add-user alice         # 添加用户（自动生成密码）
sudo s-hy2 --del-user alice         # 删除用户

# 导出
sudo s-hy2 --export                 # 导出客户端 YAML
sudo s-hy2 --export-uri             # 导出 URI 链接
sudo s-hy2 --export-sub             # 导出订阅链接

# 运维
sudo s-hy2 --backup                 # 创建备份
sudo s-hy2 --restore                # 恢复最新备份
sudo s-hy2 --validate               # 验证配置文件
sudo s-hy2 --speed-test             # 速度测试
sudo s-hy2 --update                 # 检查更新
sudo s-hy2 -v                       # 显示版本
```

## 交互菜单

```
── 基础操作 ──
 1  安装 Hysteria2       2  快速配置        3  手动配置
 4  修改配置              5  域名管理        6  证书管理
 7  服务管理              8  订阅链接 / 客户端导出

── 高级功能 ──
 9  出站规则             10  防火墙管理     11  多用户管理
12  ACL 规则管理         13  带宽限制       14  DNS 配置管理

── 运维工具 ──
15  配置备份与恢复       16  日志管理       17  速度测试
18  流量统计             19  检查更新

20  卸载服务             21  关于脚本        0  退出
```

## 项目结构

```
s-hy2/
├── hy2-manager.sh              # 主入口（菜单 + CLI 分发 + 核心函数）
├── install.sh                  # 安装 / 卸载脚本
├── quick-install.sh            # 一键安装脚本
│
├── modules/                    # 功能模块（由主脚本 source 加载）
│   ├── install.sh              #   安装逻辑
│   ├── domain.sh               #   域名管理（ACME + 伪装域名）
│   ├── certificate.sh          #   证书管理
│   ├── port-hopping.sh         #   端口跳跃
│   ├── config-edit.sh          #   配置修改（密码 / 端口 / 混淆）
│   ├── user-manager.sh         #   多用户管理
│   ├── client-export.sh        #   客户端导出（YAML / URI / QR / 订阅）
│   ├── backup.sh               #   配置备份与恢复
│   ├── acl-manager.sh          #   ACL 规则管理
│   ├── bandwidth.sh            #   带宽限制
│   ├── traffic-stats.sh        #   流量统计
│   ├── log-manager.sh          #   日志管理
│   ├── auto-update.sh          #   自动更新（SHA256 变更检测）
│   ├── speed-test.sh           #   速度测试
│   ├── dns-manager.sh          #   DNS 配置管理
│   ├── outbound-core.sh        #   出站规则 — 核心初始化
│   ├── outbound-add.sh         #   出站规则 — 添加
│   ├── outbound-modify.sh      #   出站规则 — 修改
│   ├── outbound-delete.sh      #   出站规则 — 删除
│   ├── outbound-apply.sh       #   出站规则 — 应用配置
│   └── outbound-view.sh        #   出站规则 — 查看展示
│
├── scripts/                    # 公共库与辅助脚本
│   ├── common.sh               #   公共函数（日志 / 错误处理 / 路径常量 / 密码生成）
│   ├── config.sh               #   配置生成（快速 / 手动）
│   ├── service.sh              #   服务管理
│   ├── input-validation.sh     #   输入验证与注入防护
│   ├── secure-download.sh      #   安全下载 + SHA256 校验
│   ├── firewall-manager.sh     #   防火墙管理
│   ├── outbound-manager.sh     #   出站规则加载入口
│   ├── domain-test.sh          #   伪装域名优选测试
│   ├── node-info.sh            #   节点信息展示
│   └── post-deploy-check.sh    #   部署后检查
│
├── templates/                  # YAML 配置模板
│   ├── acme-config.yaml        #   ACME 证书配置
│   ├── client-config.yaml      #   客户端配置
│   └── self-cert-config.yaml   #   自签名证书配置
│
├── config/                     # 应用配置
│   └── app.conf                #   全局参数（端口 / 超时 / 安全开关等）
│
├── contrib/                    # 参考材料（非生产代码）
├── tests/                      # bats 单元测试
│   ├── common.bats             #   公共函数测试
│   ├── config.bats             #   配置生成测试
│   ├── input-validation.bats   #   输入验证测试
│   ├── new-features.bats       #   新功能测试
│   └── security-regression.bats#   安全回归测试
│
└── .github/workflows/
    └── shellcheck.yml          # CI — ShellCheck 代码检查
```

## 开发

### 添加模块

1. 在 `modules/` 下创建 `.sh` 文件
2. 头部加 `#!/bin/bash` 和模块说明
3. 使用 `common.sh` 提供的公共函数（日志、错误处理、路径常量等）
4. 在 `hy2-manager.sh` 的 `load_new_modules()` 中追加模块名
5. 在 `print_menu()` 和 `main()` 的 case 中添加菜单入口

### 代码规范

- ShellCheck 检查通过（CI 强制）
- 变量双引号包裹：`"$var"` 而非 `$var`
- `local` 声明与赋值分开：
  ```bash
  local result
  result=$(some_command)
  ```
- 路径使用 `common.sh` 中的常量，不硬编码
- 临时文件用 `create_temp_file()` / `create_temp_dir()`（权限 600/700）
- YAML 写入用 `yaml_write_kv()` / `replace_config_file_securely()`

### 路径常量

| 常量 | 值 |
|------|----|
| `HYSTERIA_DIR` | `/etc/hysteria` |
| `HYSTERIA_CONFIG` | `/etc/hysteria/config.yaml` |
| `HYSTERIA_DOMAIN_CONF` | `/etc/hysteria/server-domain.conf` |
| `HYSTERIA_PORT_HOPPING_CONF` | `/etc/hysteria/port-hopping.conf` |
| `HYSTERIA_SERVICE` | `hysteria-server.service` |

### 运行测试

```bash
# 安装 bats
apt-get install bats

# 全部测试
bats tests/

# 单个文件
bats tests/security-regression.bats
```

## 更新日志

### v2.0.0
- 架构重构：主脚本拆分为 21 个功能模块
- 安全加固：输入注入防护、安全临时文件、SHA256 完整性校验、安全下载
- YAML 安全写入：集中化 `yaml_write_kv()` / `yaml_quote_scalar()`
- 自动更新：MD5 → SHA256 变更检测 + 版本记录
- CI：ShellCheck 自动检查
- 测试：bats 测试框架覆盖核心函数与安全回归

### v1.1.2
- 修复安装 Hysteria2 异常报错

### v1.1.1
- 修复安装模块路径异常、出站规则删除闪退
- 优化伪装域名优选、出站规则状态检查

### v1.1.0
- 新增智能出站规则管理、防火墙自动检测

### v1.0.0
- 初始版本

## 贡献

1. Fork → 创建功能分支 → 提交 → PR
2. 确保 ShellCheck 通过
3. 新功能附对应测试

## 赞助

如果这个项目对你有帮助，可以请作者喝杯咖啡

<div align="center">
<img src="zanzhu.jpg" alt="赞助" width="200">
</div>

## 赞助商

<div align="center">
<a href="https://www.88sup.com" target="_blank">
  <img src="cloud.png" alt="棉花云" width="300" />
</a>
<p><strong>棉花云</strong> — 高性能云服务器</p>
<p>
  <a href="https://yun.88sup.com" target="_blank">购买云服务器</a> ·
  <a href="https://www.88sup.com" target="_blank">官网</a>
</p>
</div>

---

<div align="center">

**如果这个项目对你有帮助，请给个 Star ⭐**

[报告问题](https://github.com/motao123/S-Hy2-Manager/issues) · [提建议](https://github.com/motao123/S-Hy2-Manager/discussions)

</div>
