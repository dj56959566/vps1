#!/usr/bin/env bash
# 最终修复版 SOCKS5 安装脚本

set -e

GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

echo -e "${GREEN}=== 安装 SOCKS5 ===${RESET}"

# -------------------- 获取公网 IP --------------------
IP=$(curl -s https://api.ipify.org || echo "")
[[ -z "$IP" ]] && read -rp "未检测到公网 IP，请输入: " IP
echo -e "${GREEN}公网 IP: $IP${RESET}"

# -------------------- 架构检测 --------------------
ARCH=$(uname -m)
case $ARCH in
    x86_64) BIN_URL="https://github.com/rofl0r/microsocks/releases/latest/download/microsocks.x86_64" ;;
    aarch64) BIN_URL="https://github.com/rofl0r/microsocks/releases/latest/download/microsocks.aarch64" ;;
    armv7l) BIN_URL="https://github.com/rofl0r/microsocks/releases/latest/download/microsocks.armhf" ;;
    *) echo "不支持架构: $ARCH"; exit 1 ;;
esac
echo -e "${GREEN}检测架构: $ARCH${RESET}"

# -------------------- 检查 wget/curl --------------------
if ! command -v wget &>/dev/null && ! command -v curl &>/dev/null; then
    echo "请先安装 wget 或 curl"
    exit 1
fi

# -------------------- 下载 microsocks --------------------
sudo rm -f /usr/local/bin/microsocks
echo -e "${GREEN}正在下载 microsocks...${RESET}"
if ! wget -qO /usr/local/bin/microsocks "$BIN_URL"; then
    echo "wget 下载失败，尝试 curl..."
    curl -L "$BIN_URL" -o /usr/local/bin/microsocks
fi
chmod +x /usr/local/bin/microsocks
echo -e "${GREEN}microsocks 下载完成${RESET}"

# -------------------- 用户自定义 --------------------
read -rp "请输入 SOCKS5 端口 (默认 1080): " PORT
PORT=${PORT:-1080}
read -rp "请输入用户名 (默认 s5user): " USER
USER=${USER:-s5user}
read -rp "请输入密码 (默认随机生成): " PASS
[[ -z "$PASS" ]] && PASS=$(head -c12 /dev/urandom | base64)

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

# -------------------- 检查是否启动成功 --------------------
sleep 1
if systemctl is-active --quiet microsocks; then
    echo -e "${GREEN}microsocks 已启动并设置开机自启${RESET}"
else
    echo -e "${YELLOW}microsocks 启动失败，请检查日志: sudo journalctl -u microsocks -n 20${RESET}"
fi

# -------------------- 输出 Telegram URL --------------------
TG_URL="tg://socks?server=$IP&port=$PORT&user=$USER&pass=$PASS"
echo -e "${GREEN}Telegram Proxy URL:${RESET} $TG_URL"

# -------------------- 停止/卸载提示 --------------------
echo -e "${YELLOW}停止/卸载 SOCKS5:${RESET} sudo systemctl stop microsocks && sudo systemctl disable microsocks && sudo rm -f /usr/local/bin/microsocks && sudo rm -f $SERVICE_PATH"
