#!/bin/bash
# OpenCode 一键更新部署脚本
# 用法: ./update_opencode.sh
#
# 功能:
#   1. 检查当前分支和未提交改动
#   2. 本地编译 linux-arm64 二进制
#   3. 上传到服务器
#   4. 重启 opencode.service
#
# 前置条件:
#   - 在 opencode 仓库根目录运行
#   - bun 已安装
#   - SSH 配置了 oci 别名(免密登录)

set -e  # 遇错即停

echo "=== OpenCode 更新部署开始 ==="
echo

# 检查当前目录
if [ ! -f "packages/opencode/package.json" ]; then
    echo "❌ 错误: 请在 opencode 仓库根目录运行此脚本"
    exit 1
fi

# 显示当前分支和提交
BRANCH=$(git branch --show-current)
COMMIT=$(git log --oneline -1)
echo "📋 当前分支: $BRANCH"
echo "📋 最新提交: $COMMIT"
echo

# 检查未提交的改动
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo "⚠️  检测到未提交的改动:"
    git status --short
    echo
    read -p "继续部署未提交的改动? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "取消部署"
        exit 0
    fi
fi

# 编译
echo "🔨 开始编译 linux-arm64 二进制..."
OPENCODE_BUILD_TARGET=linux-arm64 bun run --cwd packages/opencode script/build.ts
BINARY="packages/opencode/dist/opencode-linux-arm64/bin/opencode"

if [ ! -f "$BINARY" ]; then
    echo "❌ 编译失败: $BINARY 不存在"
    exit 1
fi

SIZE=$(ls -lh "$BINARY" | awk '{print $5}')
echo "✅ 编译完成,大小: $SIZE"
echo

# 上传
echo "📤 上传到服务器..."
scp "$BINARY" oci:/tmp/opencode-new
echo "✅ 上传完成"
echo

# 部署并重启
echo "🚀 部署并重启服务..."
ssh oci 'sudo bash -s' <<'REMOTE'
set -e
# 停服务
systemctl stop opencode.service 2>/dev/null || true
# 替换二进制
mv /tmp/opencode-new /opt/opencode/opencode
chmod +x /opt/opencode/opencode
# 启动服务
systemctl start opencode.service
# 等待启动
sleep 2
# 检查状态
if systemctl is-active --quiet opencode.service; then
    echo "✅ OpenCode 服务已启动"
    systemctl status opencode.service --no-pager -l | head -10
else
    echo "❌ 服务启动失败"
    journalctl -u opencode.service --no-pager -n 20
    exit 1
fi
REMOTE

echo
echo "🎉 部署完成!"
echo "📍 访问地址: https://yxai.sakuranda.site"
echo "🔐 用户名: opencode"
echo "🔑 密码: $(cat /tmp/opencode-password.txt 2>/dev/null || echo '见 /tmp/opencode-password.txt')"
