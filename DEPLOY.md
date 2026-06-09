# 部署指南

## 服务器信息

| | 阿里云 | 美国服务器 |
|---|---|---|
| IP | 47.102.144.62 | 70.39.197.158 |
| SSH 端口 | 22 | 55202 |
| SSH 用户 | sakuranda | root |
| 访问地址 | https://web.hldeepseek.xyz:2931/ | https://yxai.sakuranda.site/ |
| 系统 | Debian 11 x86_64 | Debian 11 x86_64 |

SSH 配置已写入 `~/.ssh/config`，直接用别名登录：
```bash
ssh aliyun      # 阿里云
ssh usserver    # 美国服务器
```

---

## 一键更新

### 有代码改动时（最常用）
```bash
cd ~/temp/opencode
./deploy.sh
```

构建（~3分钟）→ 并行传输两台 → 备份旧版 → 替换 → 重启 → 验证。

### 只更新某一台
```bash
./deploy.sh aliyun       # 只更新阿里云
./deploy.sh usserver     # 只更新美国服务器
```

### 跳过构建（代码没变，只重新部署现有二进制）
```bash
./deploy.sh --no-build
```

---

## 手动更新步骤

如果不用脚本，手动流程如下：

### 1. 构建 Linux 二进制
```bash
cd ~/temp/opencode
export PATH="$HOME/.bun/bin:$PATH"
OPENCODE_BUILD_TARGET=linux-x64-baseline \
OPENCODE_VERSION=1.16.2 \
  bun run packages/opencode/script/build.ts
# 产物：packages/opencode/dist/opencode-linux-x64-baseline/bin/opencode
```

### 2. 传输到服务器
```bash
# 阿里云
scp packages/opencode/dist/opencode-linux-x64-baseline/bin/opencode \
  aliyun:/tmp/opencode-new

# 美国服务器
scp packages/opencode/dist/opencode-linux-x64-baseline/bin/opencode \
  usserver:/tmp/opencode-new
```

### 3. 替换并重启

**阿里云**（需要 sudo，密码见 1Password）：
```bash
ssh aliyun
sudo cp /usr/local/bin/opencode /usr/local/bin/opencode.bak-$(date +%Y%m%d)
sudo install -m 755 /tmp/opencode-new /usr/local/bin/opencode
sudo systemctl restart opencode
systemctl is-active opencode
```

**美国服务器**（root 直接操作）：
```bash
ssh usserver
cp /usr/local/bin/opencode /usr/local/bin/opencode.bak-$(date +%Y%m%d)
install -m 755 /tmp/opencode-new /usr/local/bin/opencode
systemctl restart opencode
systemctl is-active opencode
```

---

## 回滚

```bash
# 阿里云
ssh aliyun "sudo install -m755 /usr/local/bin/opencode.bak-YYYYMMDD \
  /usr/local/bin/opencode && sudo systemctl restart opencode"

# 美国服务器
ssh usserver "install -m755 /usr/local/bin/opencode.bak-YYYYMMDD \
  /usr/local/bin/opencode && systemctl restart opencode"
```

备份文件保留在 `/usr/local/bin/opencode.bak-YYYYMMDD`，确认新版稳定后可删除。

---

## 服务管理

```bash
# 查看状态
ssh aliyun "sudo systemctl status opencode"
ssh usserver "systemctl status opencode"

# 查看实时日志
ssh aliyun "sudo journalctl -u opencode -f"
ssh usserver "journalctl -u opencode -f"

# 重启
ssh aliyun "sudo systemctl restart opencode"
ssh usserver "systemctl restart opencode"
```

---

## 数据目录

| 路径 | 内容 |
|---|---|
| `/var/lib/opencode/workspace/` | 工作区（AI 操作文件、uploads） |
| `/var/lib/opencode/.local/share/opencode/opencode.db` | 会话数据库 |
| `/var/lib/opencode/workspace/uploads/<sid>/` | 用户上传的文件 |
| `/etc/opencode/opencode.env` | 环境变量（含登录密码，权限 640） |
| `/usr/local/bin/opencode` | 当前运行的二进制 |

---

## 项目分支说明

代码改动在 `binary-uploads` 分支（基于上游 opencode）：

| Commit | 内容 |
|---|---|
| `06b8d2c` | 上传功能：拖拽上传 Office/ZIP 等文件 |
| `ff4287c` | 下载功能：侧边栏文件下载 + AI write 内联下载按钮 |
| `e4379c1` | 文件树默认打开 + 中文文件名兼容 |
| `d9f38ea` | deploy.sh 一键部署脚本 |

---

## 注意事项

1. **前端更新后需硬刷新**：Cmd+Shift+R，或 F12 → Application → Clear site data，否则旧 bundle 可能缓存在浏览器。
2. **重启会中断进行中的 AI 任务**，选低峰期操作。
3. **阿里云外部代理**：流量经过阿里云 SLB，实际端口可能不是 443，当前 web 跑在 2931。
4. **美国服务器 DNS**：当前 `yxai.sakuranda.site` 为 Cloudflare 灰云（直连），Caddy 自动续期 Let's Encrypt 证书。若切换为橙云（CDN 代理），SSE 长连接可能断开，需在 Cloudflare 开启"禁用缓冲"规则。
5. **sudo 密码**（阿里云 sakuranda 用户）：见 1Password 或团队内部文档，不要写入代码。
