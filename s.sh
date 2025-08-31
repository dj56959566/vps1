#!/bin/bash
# 一键 SOCKS5 安装脚本（全功能版）

# -------------------- VPS 类型检测 --------------------
VPS_TYPE="未知"
if [[ -f /proc/1/cgroup ]]; then
    CGROUP=$(cat /proc/1/cgroup)
    if echo "$CGROUP" | grep -q "docker"; then
        VPS_TYPE="Docker"
    elif echo "$CGROUP" | grep -q "lxc"; then
        VPS_TYPE="LXC"
    else
        VPS_TYPE="KVM/NAT/未知"
    fi
fi
echo "检测到 VPS 类型: $VPS_TYPE (仅提示，不阻塞运行)"

# -------------------- 公网 IP --------------------
IP=$(curl -s https://api.ipify.org)
echo "公网 IP: $IP"

# -------------------- 架构检测 --------------------
ARCH=$(uname -m)
echo "检测 VPS 架构: $ARCH"
if [[ "$ARCH" == "x86_64" ]]; then
    BIN_URL="https://github.com/rofl0r/microsocks/releases/latest/download/microsocks.x86_64"
elif [[ "$ARCH" == "aarch64" ]]; then
    BIN_URL="https://github.com/rofl0r/microsocks/releases/latest/download/microsocks.aarch64"
elif [[ "$ARCH" == "armv7l" ]]; then
    BIN_URL="https://github.com/rofl0r/microsocks/releases/latest/download/microsocks.armhf"
else
    echo "不支持的架构: $ARCH"
    exit 1
fi

# -------------------- 下载 microsocks --------------------
sudo rm -f /usr/local/bin/microsocks
wget -O /usr/local/bin/microsocks "$BIN_URL"
chmod +x /usr/local/bin/microsocks

# -------------------- 用户输入 --------------------
read -p "请输入 SOCKS5 端口 (默认 1080): " PORT
PORT=${PORT:-1080}
read -p "请输入用户名 (默认 admin): " USER
USER=${USER:-admin}
read -p "请输入密码 (默认 admin): " PASS
PASS=${PASS:-admin}

# -------------------- 启动 SOCKS5 --------------------
sudo pkill microsocks >/dev/null 2>&1
/usr/local/bin/microsocks -1 -p "$PORT" -u "$USER" -P "$PASS" >/dev/null 2>&1 &
sleep 1

# -------------------- 输出 Telegram Proxy URL --------------------
SECRET=$(echo -n "$USER:$PASS" | xxd -p -c 256)
echo -e "\e[32mTelegram Proxy URL:\e[0m"
echo "https://t.me/proxy?server=$IP&port=$PORT&secret=$SECRET"

# -------------------- 卸载提示 --------------------
echo -e "\e[33m停止/卸载 SOCKS5:\e[0m sudo pkill microsocks"
