#!/bin/bash
# ===========================================
# Microsocks 单账号自动安装版
# By: djkyc   鸣谢: eooce
# 安装完成即启动并打印 SOCKS 链接
# ===========================================

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

echo -e "${GREEN}
  ____   ___   ____ _  ______ ____  
 / ___| / _ \\ / ___| |/ / ___| ___|  
 \\___ \\| | | | |   | ' /\\___ \\___ \\ 
  ___) | |_| | |___| . \\ ___) |__) |           
 |____/ \\___/ \\____|_|\\_\\____/____/            
 By:djkyc 鸣谢:eooce 本脚本:microsocks
${RESET}"

CONFIG_DIR="/etc/microsocks"
CONFIG_FILE="${CONFIG_DIR}/user.conf"
SERVICE_FILE="/etc/systemd/system/microsocks.service"
PORT=1080
USERNAME=""
PASSWORD=""

# ---------------------------
# 获取公网 IP
# ---------------------------
get_ip() {
    IP=$(curl -s ipv4.icanhazip.com || curl -s ifconfig.me || curl -s ipinfo.io/ip)
    [[ -z "$IP" ]] && IP="127.0.0.1"
    echo "$IP"
}

# ---------------------------
# 安装 microsocks
# ---------------------------
install_microsocks() {
    if ! command -v microsocks >/dev/null 2>&1; then
        echo "未检测到 microsocks，正在尝试安装..."
        if command -v apt-get >/dev/null 2>&1; then
            if ! apt-get install -y microsocks; then
                echo "安装失败，尝试更新包源并修复依赖..."
                apt-get update -y
                apt --fix-broken install -y
                apt-get install -y microsocks || { echo "自动安装失败，请手动安装 microsocks"; exit 1; }
            fi
        else
            echo "当前系统不支持自动安装，请手动安装 microsocks"
            exit 1
        fi
        echo "microsocks 安装完成"
    fi
}

# ---------------------------
# 配置账号
# ---------------------------
config_user() {
    mkdir -p "$CONFIG_DIR"
    read -rp "请输入用户名: " USERNAME
    read -rp "请输入密码: " PASSWORD
    echo "${USERNAME}:${PASSWORD}" > "$CONFIG_FILE"
    echo "已保存账号到 $CONFIG_FILE"
}

# ---------------------------
# 提示端口
# ---------------------------
prompt_port() {
    read -rp "请输入监听端口 (默认1080): " port_input
    if [[ -n "$port_input" && "$port_input" =~ ^[0-9]+$ && "$port_input" -ge 1 && "$port_input" -le 65535 ]]; then
        PORT=$port_input
    else
        echo "使用默认端口 $PORT"
    fi
}

# ---------------------------
# 生成 systemd 服务文件并启动
# ---------------------------
create_service() {
    USERS="-u $USERNAME -P $PASSWORD"
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Microsocks Socks5 Proxy
After=network.target

[Service]
ExecStart=/usr/bin/microsocks -i 0.0.0.0 -p ${PORT} ${USERS}
Restart=always
User=nobody
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now microsocks
    echo "microsocks 已安装并设置开机自启"
}

# ---------------------------
# 打印 SOCKS 链接
# ---------------------------
print_link() {
    IP=$(get_ip)
    echo -e "\n${GREEN}=== SOCKS5 链接 ===${RESET}"
    echo "账号: ${USERNAME} / 密码: ${PASSWORD}"
    echo "socks://$USERNAME:$PASSWORD@$IP:$PORT"
    echo "Telegram 快链: https://t.me/socks?server=$IP&port=$PORT&user=$USERNAME&pass=$PASSWORD"
}

# ---------------------------
# 执行安装
# ---------------------------
install_microsocks
prompt_port
config_user
create_service
print_link
