#!/bin/bash
# ===========================================
# Microsocks 单账号自动安装/二进制下载版
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

PORT=1080
USERNAME=""
PASSWORD=""
MICROBIN="/usr/local/bin/microsocks"

# ---------------------------
# 获取公网 IP
# ---------------------------
get_ip() {
    IP=$(curl -s ipv4.icanhazip.com || curl -s ifconfig.me || curl -s ipinfo.io/ip)
    [[ -z "$IP" ]] && IP="127.0.0.1"
    echo "$IP"
}

# ---------------------------
# 安装或下载 microsocks
# ---------------------------
install_microsocks() {
    if command -v microsocks >/dev/null 2>&1; then
        MICROBIN="$(command -v microsocks)"
        echo "已检测到 microsocks: $MICROBIN"
        return
    fi

    echo "未检测到 microsocks，尝试用 apt-get 安装..."
    if command -v apt-get >/dev/null 2>&1; then
        if ! apt-get install -y microsocks >/dev/null 2>&1; then
            echo "apt 安装失败，尝试下载官方二进制..."
            download_binary
        else
            MICROBIN="$(command -v microsocks)"
        fi
    else
        download_binary
    fi
}

download_binary() {
    mkdir -p /usr/local/bin
    echo "下载 microsocks 二进制到 $MICROBIN ..."
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) BIN_URL="https://github.com/rofl0r/microsocks/releases/download/0.5.1/microsocks-0.5.1-linux-x86_64" ;;
        aarch64|arm64) BIN_URL="https://github.com/rofl0r/microsocks/releases/download/0.5.1/microsocks-0.5.1-linux-arm64" ;;
        *) echo "未支持的架构 $ARCH"; exit 1 ;;
    esac
    curl -L -o "$MICROBIN" "$BIN_URL" || { echo "下载失败"; exit 1; }
    chmod +x "$MICROBIN"
}

# ---------------------------
# 配置账号
# ---------------------------
config_user() {
    read -rp "请输入用户名: " USERNAME
    read -rp "请输入密码: " PASSWORD
    echo "$USERNAME:$PASSWORD" > /etc/microsocks_user.conf
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
# 创建 systemd 服务
# ---------------------------
create_service() {
    mkdir -p /etc/systemd/system
    cat > /etc/systemd/system/microsocks.service <<EOF
[Unit]
Description=Microsocks Socks5 Proxy
After=network.target

[Service]
ExecStart=$MICROBIN -i 0.0.0.0 -p $PORT -u $USERNAME -P $PASSWORD
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
# 执行流程
# ---------------------------
install_microsocks
prompt_port
config_user
create_service
print_link
