#!/usr/bin/env bash
# 极简一键安装 SOCKS5

set -e

GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

echo -e "${GREEN}=== 安装 SOCKS5 ===${RESET}"

# 获取公网 IP
IP=$(curl -s https://api.ipify.org || echo "")
[[ -z "$IP" ]] && read -rp "未检测到公网 IP，请输入: " IP
echo -e "${GREEN}公网 IP: $IP${RESET}"

# 检测架构
ARCH=$(uname -m)
case $ARCH in
  x86_64) BIN="https://github.com/rofl0r/microsocks/releases/latest/download/microsocks.x86_64" ;;
  aarch64) BIN="https://github.com/rofl0r/microsocks/releases/latest/download/microsocks.aarch64" ;;
  armv7l) BIN="https://github.com/rofl0r/microsocks/releases/latest/download/microsocks.armhf" ;;
  *) echo "不支持架构: $ARCH"; exit 1 ;;
esac

# 下载 microsocks
sudo wget -qO /usr/local/bin/microsocks "$BIN"
sudo chmod +x /usr/local/bin/microsocks

# 用户输入
read -rp "端口(默认1080): " PORT
PORT=${PORT:-1080}
read -rp "用户名(默认s5user): " USER
USER=${USER:-s5user}
read -rp "密码(默认随机): " PASS
[[ -z "$PASS" ]] && PASS=$(head -c12 /dev/urandom | base64)

# 创建 systemd 服务
SERVICE="/etc/systemd/system/microsocks.service"
sudo tee "$SERVICE" >/dev/null <<EOF
[Unit]
Description=microsocks SOCKS5
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

# 输出 Telegram URL
TG="tg://socks?server=$IP&port=$PORT&user=$USER&pass=$PASS"
echo -e "${GREEN}Telegram Proxy URL:${RESET} $TG"

# 停止/卸载命令
echo -e "${YELLOW}停止/卸载 SOCKS5:${RESET} sudo systemctl stop microsocks && sudo systemctl disable microsocks && sudo rm -f /usr/local/bin/microsocks && sudo rm -f $SERVICE"
