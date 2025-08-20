#!/bin/bash
# ===========================================
# Socks5 Proxy Manager - Microsocks Enhanced
# By: djkyc   鸣谢: eooce
# 本脚本: microsocks 专用版本
# ===========================================

GREEN="\033[32m"
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
CONFIG_FILE="${CONFIG_DIR}/users.conf"
SERVICE_FILE="/etc/systemd/system/microsocks.service"
PORT=1080

# ---------------------------
# 获取公网 IP
# ---------------------------
get_ip() {
    IP=$(curl -s ipv4.icanhazip.com || curl -s ifconfig.me || echo "127.0.0.1")
    echo "$IP"
}

# ---------------------------
# 自动安装 microsocks
# ---------------------------
install_microsocks() {
    if ! command -v microsocks >/dev/null 2>&1; then
        echo "未检测到 microsocks，正在安装..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -y && apt-get install -y microsocks
        elif command -v yum >/dev/null 2>&1; then
            yum install -y epel-release -y
            yum install -y microsocks
        else
            echo "不支持的系统，请手动安装 microsocks"
            exit 1
        fi
    fi
}

# ---------------------------
# 配置用户（多账号）
# ---------------------------
config_users() {
    mkdir -p "$CONFIG_DIR"
    echo "# 格式: user:pass (一行一个)" > "$CONFIG_FILE"
    while true; do
        read -rp "请输入用户名 (留空结束): " user
        [ -z "$user" ] && break
        read -rp "请输入密码: " pass
        echo "${user}:${pass}" >> "$CONFIG_FILE"
    done
    echo "已保存到 $CONFIG_FILE"
}
print_links() {
    PORT=$(grep -oP '(?<=ExecStart=/usr/bin/microsocks -i 0.0.0.0 -p )\d+' /etc/systemd/system/microsocks.service)
    [[ -z "$PORT" ]] && PORT=1080

    IP=$(curl -s ipv4.ip.sb || curl -s ifconfig.me || curl -s ipinfo.io/ip)

    echo -e "\n${GREEN}=== SOCKS5 一键链接 ===${RESET}"
    while IFS=: read -r USER PASS; do
        [[ -z "$USER" || -z "$PASS" ]] && continue
        echo -e "账号: ${USER} / 密码: ${PASS}"
        echo "socks://$USER:$PASS@$IP:$PORT"
        echo "https://t.me/socks?server=$IP&port=$PORT&user=$USER&pass=$PASS"
        echo "----------------------------------"
    done < /etc/microsocks/users.conf
}

# ---------------------------
# 生成 systemd 服务文件
# ---------------------------
create_service() {
    USERS=$(cat "$CONFIG_FILE" | awk -F: '{print "-u "$1" -P "$2}' | xargs)
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
# 修改配置
# ---------------------------
modify_config() {
    echo "当前端口: ${PORT}"
    read -rp "请输入新端口(回车保持默认): " newport
    [ -n "$newport" ] && PORT=$newport
    config_users
    create_service
    systemctl restart microsocks
    echo "配置已更新并重启"
}

# ---------------------------
# 卸载
# ---------------------------
uninstall() {
    systemctl stop microsocks
    systemctl disable microsocks
    rm -f "$SERVICE_FILE"
    rm -rf "$CONFIG_DIR"
    systemctl daemon-reload
    echo "microsocks 已卸载"
}

# ---------------------------
# 状态 & 生成 socks 链接
# ---------------------------
status() {
    systemctl status microsocks --no-pager
    echo
    echo "监听端口: ${PORT}"
    echo "账号列表:"
    cat "$CONFIG_FILE"

    echo
    echo "📌 可用的 socks5 链接："
    IP=$(get_ip)
    while IFS=: read -r user pass; do
        [[ "$user" =~ ^# ]] && continue
        echo "socks5://${user}:${pass}@${IP}:${PORT}"
        echo "https://t.me/socks?server=${IP}&port=${PORT}&user=${user}&pass=${pass}"
    done < "$CONFIG_FILE"
}

# ---------------------------
# 主菜单
# ---------------------------
main_menu() {
    echo -e "
请选择操作:
1) 安装 socks5
2) 修改 socks5 配置
3) 卸载 socks5
4) 状态 (含 socks 链接)
5) 退出
"
    read -rp "请选择 (1-5): " choice
    case "$choice" in
        1)
            install_microsocks
            config_users
            create_service
            ;;
        2)
            modify_config
            ;;
        3)
            uninstall
            ;;
        4)
            status
            ;;
        5)
            exit 0
            ;;
        *)
            echo "无效选择"
            ;;
    esac
}

main_menu
