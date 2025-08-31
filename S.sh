#!/bin/bash
# 一键部署轻量 SOCKS5 代理（支持自定义端口+TG格式输出）
# Author: ChatGPT

# ---------- 配置 ----------
# 用户名和密码
USERNAME="socksuser"
PASSWORD="sockspass"

# 端口列表，自行修改，例如: 1080 1081 1082
read -p "请输入要开启的端口（用空格分隔，例如: 1080 1081 1082）: " PORTS

# VPS 公网 IP
IP=$(curl -s https://api.ipify.org)

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
for PORT in $PORTS; do
    pkill -f "microsocks.*:$PORT" 2>/dev/null
    nohup microsocks -p $PORT -u $USERNAME -P $PASSWORD >/dev/null 2>&1 &
done

sleep 1

# ---------- 输出 TG URL 格式 ----------
echo -e "\nSocks5 代理已启动，TG 格式连接信息如下："
for PORT in $PORTS; do
    echo "socks5://$USERNAME:$PASSWORD@$IP:$PORT"
done

echo -e "\n全部端口已启动完成"
