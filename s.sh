#!/usr/bin/env bash
# 一键安装 SOCKS5 脚本（microsocks）
# 功能：
# - 自动检测 VPS 类型（LXC/Docker/KVM/NAT）
# - 自动获取公网 IP（支持手动输入）
# - 自动检测 CPU 架构（x86_64 / aarch64 / armhf）
# - 下载对应 microsocks 二进制
# - 支持自定义端口、用户名、密码
# - 绿色高亮输出 Telegram Proxy URL
# - 提供一键卸载/停止命令

set -e

GREEN="\033[32m"
RESET="\033[0m"

echo -e "${GREEN}=== SOCKS5 安装脚本 ===${RESET}"

# VPS 类型检测（仅提示）
if [ -f /proc/user_beancounters ]; then
    VPS_TYPE="LXC"
elif [ -f /.dockerenv ]; then
    VPS_TYPE="Docker"
else
    VPS_TYPE="KVM/NAT"
fi
echo -e "${GREEN}VPS 类型检测: $VPS_TYPE${RESET}"

# 获取公网 IP
PUBLIC_IP=$(curl -s ifconfig.me || echo "")
if [[ -z "$PUBLIC_IP" ]]; then
    read -rp "未检测到公网 IP，请手动输入: " PUBLIC_IP
fi
echo -e "${GREEN}使用公网 IP: $PUBLIC_IP${RESET}"

# CPU 架构检测
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH_DL="x86_64" ;;
    aarch64) ARCH_DL="aarch64" ;;
    arm*) ARCH_DL="armhf" ;;
    *) echo "不支持的架构: $ARCH"; exit 1 ;;
esac
echo -e "${GREEN}检测架构: $ARCH${RESET}"

# 下载 microsocks
MS_URL="https://github.com/rofl0r/microsocks/releases/download/2.0.1/microsocks-$ARCH_DL"
curl -L -o /usr/local/bin/microsocks "$MS_URL"
chmod +x /usr/local/bin/microsocks
echo -e "${GREEN}microsocks 下载完成${RESET}"

# 用户自定义端口、用户名、密码
read -rp "监听端口 [1080]: " PORT
PORT=${PORT:-1080}

read -rp "用户名 [s5user]: " USERNAME
USERNAME=${USERNAME:-s5user}

read -rp "密码 (留空则自动生成): " PASSWORD
if [ -z "$PASSWORD" ]; then
    PASSWORD=$(head -c 12 /dev/urandom | base64)
fi

# 启动 microsocks
microsocks -u "$USERNAME" -P "$PASSWORD" -p "$PORT" >/dev/null 2>&1 &
MS_PID=$!

echo -e "${GREEN}SOCKS5 已启动 PID=$MS_PID${RESET}"
echo -e "${GREEN}端口: $PORT 用户名: $USERNAME 密码: $PASSWORD${RESET}"

# 输出 Telegram Proxy URL
# 格式: tg://socks?server=<ip>&port=<port>&user=<user>&pass=<pass>
TG_URL="tg://socks?server=${PUBLIC_IP}&port=${PORT}&user=${USERNAME}&pass=${PASSWORD}"
echo -e "${GREEN}Telegram Proxy URL:${RESET} $TG_URL"

# 一行卸载/停止命令
echo -e "${GREEN}停止/卸载命令:${RESET} kill $MS_PID && rm -f /usr/local/bin/microsocks"
