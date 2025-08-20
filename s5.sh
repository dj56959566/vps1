#!/bin/bash
# 一键安装 Socks5，支持主流 VPS 系统 (CentOS, Ubuntu, Debian)
# By:djkyc
# Date: 2025-08-20 09:00:50

# 检查 root
if [[ $EUID -ne 0 ]]; then
    echo "请用 root 权限运行此脚本。"
    exit 1
fi

# 清屏函数
clear_screen() {
    clear
}

# 暂停函数
pause() {
    echo ""
    read -p "按回车键继续..." key
}

# 安装依赖函数
install_deps() {
    clear_screen
    echo "正在安装依赖..."
    if command -v apt-get &>/dev/null; then
        apt-get update
        apt-get install -y git build-essential curl
    elif command -v yum &>/dev/null; then
        yum groupinstall -y "Development Tools"
        yum install -y git curl
    elif command -v dnf &>/dev/null; then
        dnf groupinstall -y "Development Tools"
        dnf install -y git curl
    else
        echo "未检测到包管理器，请自行安装编译工具和git。"
        exit 1
    fi

    echo "正在下载和编译 microsocks..."
    cd /tmp
    git clone https://github.com/rofl0r/microsocks.git
    cd microsocks
    make
    install -m755 microsocks /usr/local/bin/
    cd /
    rm -rf /tmp/microsocks
    echo "依赖安装完成！"
    pause
}

# 安装 Socks5 函数
install_socks5() {
    clear_screen
    echo "------------------------"
    echo "Socks5 安装配置"
    echo "------------------------"
    echo "请选择配置方式:"
    echo "1. 自定义配置"
    echo "2. 随机配置（直接回车）"
    read -p "请选择 [1-2]: " config_choice

    if [ "$config_choice" = "1" ]; then
        read -p "请输入端口 (1024-65535): " PORT
        read -p "请输入用户名: " USER
        read -p "请输入密码: " PASS
    else
        PORT=$((10000 + RANDOM % 50000))
        USER="user$(date +%s | tail -c 5)"
        PASS="pass$(openssl rand -hex 3)"
    fi

    # 创建 systemd 服务
    cat >/etc/systemd/system/microsocks.service <<EOF
[Unit]
Description=MicroSocks Proxy Server
After=network.target

[Service]
ExecStart=/usr/local/bin/microsocks -i 0.0.0.0 -p ${PORT} -u ${USER} -P ${PASS}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable microsocks
    systemctl start microsocks

    SERVER_IP=$(curl -s -4 ip.sb || curl -s -4 ifconfig.me || curl -s -4 api.ipify.org || hostname -I | awk '{print $1}')

    # 保存配置信息
    cat >/root/socks5_info.txt <<EOF
服务器信息：
IP: ${SERVER_IP}
端口: ${PORT}
用户名: ${USER}
密码: ${PASS}

Telegram一键链接:
https://t.me/socks?server=${SERVER_IP}&port=${PORT}&user=${USER}&pass=${PASS}
EOF

    clear_screen
    echo "安装完成！"
    echo "------------------------"
    echo "服务器IP: ${SERVER_IP}"
    echo "端口: ${PORT}"
    echo "用户名: ${USER}"
    echo "密码: ${PASS}"
    echo "------------------------"
    echo ""
    echo "Telegram一键链接:"
    echo "https://t.me/socks?server=${SERVER_IP}&port=${PORT}&user=${USER}&pass=${PASS}"
    echo ""
    echo "配置信息已保存到: /root/socks5_info.txt"
    pause
}

# 卸载函数
uninstall_socks5() {
    clear_screen
    echo "正在卸载 Socks5..."
    systemctl stop microsocks
    systemctl disable microsocks
    rm -f /usr/local/bin/microsocks /etc/systemd/system/microsocks.service
    echo "Socks5 已卸载完成！"
    pause
}

# 修改配置函数
modify_config() {
    while true; do
        clear_screen
        echo "------------------------"
        echo "修改 Socks5 配置"
        echo "------------------------"
        echo "1. 修改端口"
        echo "2. 修改用户名"
        echo "3. 修改密码"
        echo "4. 返回主菜单"
        read -p "请选择 [1-4]: " modify_choice

        case $modify_choice in
            1)
                read -p "请输入新端口 (1024-65535): " new_port
                sed -i "s/-p [0-9]*/-p ${new_port}/" /etc/systemd/system/microsocks.service
                ;;
            2)
                read -p "请输入新用户名: " new_user
                sed -i "s/-u [^ ]*/-u ${new_user}/" /etc/systemd/system/microsocks.service
                ;;
            3)
                read -p "请输入新密码: " new_pass
                sed -i "s/-P [^ ]*/-P ${new_pass}/" /etc/systemd/system/microsocks.service
                ;;
            4)
                return
                ;;
            *)
                echo "无效选择"
                pause
                continue
                ;;
        esac

        systemctl daemon-reload
        systemctl restart microsocks
        echo "配置已更新，服务已重启！"
        pause
    done
}

# 主菜单
while true; do
    clear_screen
    echo "------------------------"
    echo "Socks5 管理脚本"
    echo "------------------------"
    echo "1. 安装 Socks5"
    echo "2. 卸载 Socks5"
    echo "3. 修改配置"
    echo "4. 退出"
    read -p "请选择 [1-4]: " choice

    case $choice in
        1)
            if ! command -v microsocks &>/dev/null; then
                install_deps
            fi
            install_socks5
            ;;
        2)
            uninstall_socks5
            ;;
        3)
            if ! command -v microsocks &>/dev/null; then
                echo "Socks5 未安装！"
                pause
            else
                modify_config
            fi
            ;;
        4)
            clear_screen
            exit 0
            ;;
        *)
            echo "无效选择"
            pause
            ;;
    esac
done
