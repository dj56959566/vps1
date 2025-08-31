#!/bin/bash
# 一键轻量 SOCKS5 安装 + 输出 TG Proxy URL
# Author: ChatGPT

# ---------- 输入用户名密码 ----------
read -p "请输入 SOCKS5 用户名: " USERNAME
read -sp "请输入 SOCKS5 密码: " PASSWORD
echo

# ---------- 输入端口 ----------
read -p "请输入 SOCKS5 端口（如 1080）: " PORT

# ---------- 获取 VPS 公网 IP ----------
IP=$(curl -s https://api.ipify.org)
if [[ -z "$IP" ]]; then
    echo "无法获取公网 IP，请检查网络"
    exit 1
fi

# ---------- 安装 microsocks ----------
if ! command -v microsocks &>/dev/null; then
    echo "安装 microsocks..."
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        curl -L -o /usr/local/bin/microsocks https://github.com/rofl0r/microsocks/releases/download/v1.0.1/microsocks-x86_64
    elif [[ "$ARCH" == "aarch64" ]]; then
        curl -L -o /usr/local/bin/microsocks https://github.com/rofl0r/microsocks/releases/download/v1.0.1/microsocks-arm64
    else
        echo "不支持的架构: $ARCH"
        exit 1
    fi
    chmod +x /usr/local/bin/microsocks
fi

# ---------- 启动 SOCKS5 ----------
pkill -f "microsocks.*:$PORT" 2>/dev/null
nohup microsocks -p $PORT -u $USERNAME -P $PASSWORD >/dev/null 2>&1 &

sleep 1

# ---------- 生成 Telegram Proxy URL ----------
# secret 需要将 user:pass 转为 hex
SECRET_HEX=$(echo -n "$USERNAME:$PASSWORD" | xxd -p | tr -d '\n')

echo -e "\nSOCKS5 已启动，Telegram Proxy URL："
echo "https://t.me/proxy?server=$IP&port=$PORT&secret=$SECRET_HEX"
