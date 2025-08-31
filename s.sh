#!/usr/bin/env bash
# 一键安装 SOCKS5（增强版）
# 功能：自动检测 VPS 类型、架构，下载 microsocks，支持 systemd 自启

set -e

GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

echo -e "${GREEN}=== SOCKS5 安装脚本 ===${RESET}"

# -------------------- VPS 类型检测（仅提示） --------------------
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
echo -e "${GREEN}VPS 类型: $VPS_TYPE${RESET}"

# -------------------- 公网 IP --------------------
IP=$(curl -s https://api.ipify.org || echo "")
if [[ -z "$IP" ]]; then
    read -rp "未检测到公网 IP，请手动输入: " IP
fi
echo -e "${GREEN}公网 IP: $IP${RESET}"

# -------------------- 架构检测 --------------------
ARCH=$(uname -m)
echo -e "${GREEN}检测 VPS 架构: $ARCH${RESET}"
case $ARCH in
    x86_64) BIN_URL="https://github.com/rofl0r/microsocks/releases/latest/download/microsocks.x86_64" ;;
    aarch64) BIN_URL="https://github.com/rofl0r/microsocks/releases/latest/download/microsocks.aarch64" ;;
    armv7l) BIN_URL="https://github.com/rofl0r/microsocks/releases/latest/download/microsocks.armhf" ;;
    *) echo "不支持的架构: $ARCH"; exit 1 ;;
esac

# -------------------- 下载 microsocks --------------------
sudo rm -f /usr/local/bin/microsocks
echo -e "${GREEN}正在下载 microsocks...${RESET}"
wget -qO /usr/local/bin/microsocks "$BIN_URL"
chmod +x /usr/local/bin/microsocks
echo -e "${GREEN}microsocks 下载完成${RESET}"

# -------------------- 用户输入 --------------------
read -rp "请输入 SOCKS5 端口 (默认 1080): " PORT
PORT=${PORT:-1080}
read -rp "请输入用户名 (默认 s5user): " USER
USER=${USER:-s5user}
read -rp "请输入密码 (默认随机生成): " PASS
if [[ -z "$PASS" ]]; then
    PASS=$(head -c 12 /dev/urandom | base64)
fi

# -------------------- systemd 服务 --------------------
SERVICE_PATH="/etc/systemd/system/microsocks.service"
sudo tee "$SERVICE_PATH" >/dev/null <<EOF
[Unit]
Description=microsocks SOCKS5 Server
After=network.target

[Service]
ExecStart=/usr/local/bin/microsocks -1 -p $PORT -u $USER -P $PASS
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now microsocks
echo -e "${GREEN}microsocks 已启动并设置开机自启${RESET}"

# -------------------- 输出 Telegram Proxy URL --------------------
TG_URL="tg://socks?server=$IP&port=$PORT&user=$USER&pass=$PASS"
echo -e "${GREEN}Telegram Proxy URL:${RESET} $TG_URL"

# -------------------- 停止/卸载提示 --------------------
echo -e "${YELLOW}停止/卸载 SOCKS5:${RESET} sudo systemctl stop microsocks && sudo systemctl disable microsocks && sudo rm -f /usr/local/bin/microsocks && sudo rm -f $SERVICE_PATH"
