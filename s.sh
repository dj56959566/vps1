#!/bin/bash
# 最终版 SOCKS5 安装启动脚本
# 功能: LXC/Docker 检测 + 自定义端口/用户名/密码 + Telegram Proxy URL + 卸载提示

set -e

GREEN='\033[0;32m'
NC='\033[0m'

echo "---------------------------------"
echo "   一键 SOCKS5 安装 & 启动脚本   "
echo "---------------------------------"

# ---------- 检测虚拟化环境 ----------
if grep -qa docker /proc/1/cgroup || grep -qa lxc /proc/1/cgroup; then
    echo "⚠️  检测到可能运行在 LXC/Docker 容器中，请确保容器网络允许外部访问端口"
fi

# ---------- 输入端口 ----------
read -p "请输入 SOCKS5 端口 (默认 1080): " PORT
PORT=${PORT:-1080}

# ---------- 输入用户名 ----------
read -p "请输入用户名 (默认随机): " USERNAME
if [[ -z "$USERNAME" ]]; then
    USERNAME="u$(head -c 4 /dev/urandom | xxd -p)"
fi

# ---------- 输入密码 ----------
read -p "请输入密码 (默认随机): " PASSWORD
if [[ -z "$PASSWORD" ]]; then
    PASSWORD="p$(head -c 6 /dev/urandom | xxd -p)"
fi

# ---------- 获取公网 IP ----------
echo "[INFO] 获取公网 IP..."
IP=$(curl -s https://api.ipify.org)
if [[ -z "$IP" ]]; then
    echo "❌ 无法获取公网 IP"
    exit 1
fi
echo "[INFO] 公网 IP: $IP"

# ---------- 安装 microsocks ----------
if ! command -v microsocks &>/dev/null; then
    echo "[INFO] 安装 microsocks..."
    ARCH=$(uname -m)
    URL=""
    case "$ARCH" in
        x86_64) URL="https://github.com/rofl0r/microsocks/releases/download/v1.0.1/microsocks-x86_64" ;;
        aarch64) URL="https://github.com/rofl0r/microsocks/releases/download/v1.0.1/microsocks-arm64" ;;
        *) echo "❌ 不支持的架构: $ARCH" && exit 1 ;;
    esac
    curl -L -o /usr/local/bin/microsocks "$URL"
    chmod +x /usr/local/bin/microsocks
fi

# ---------- 启动 SOCKS5 ----------
pkill -f "microsocks.*:$PORT" 2>/dev/null || true
nohup microsocks -p $PORT -u $USERNAME -P $PASSWORD >/dev/null 2>&1 &
sleep 1

# ---------- 生成 Telegram Proxy URL ----------
SECRET_HEX=$(echo -n "$USERNAME:$PASSWORD" | xxd -p | tr -d '\n')

echo
echo "✅ SOCKS5 已成功启动！"
echo "---------------------------------"
echo "📡 地址: $IP:$PORT"
echo "👤 用户名: $USERNAME"
echo "🔑 密码: $PASSWORD"
echo
echo -e "👉 Telegram Proxy URL:\n${GREEN}https://t.me/proxy?server=$IP&port=$PORT&secret=$SECRET_HEX${NC}"
echo "---------------------------------"
echo "⚠️ 卸载/停止 SOCKS5 一行命令："
echo "pkill -f microsocks && rm -f /usr/local/bin/microsocks"
echo "---------------------------------"
