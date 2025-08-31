#!/bin/bash

# 颜色定义
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;36m"
RED="\033[0;31m"
PLAIN="\033[0m"

# 检查是否为root用户
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误: 请使用root用户运行此脚本${PLAIN}"
    exit 1
fi

# 检测虚拟化环境
check_virt() {
    echo -e "${BLUE}正在检测虚拟化环境...${PLAIN}"
    
    if grep -q docker /proc/1/cgroup 2>/dev/null; then
        echo -e "${YELLOW}检测到Docker环境${PLAIN}"
    elif grep -q lxc /proc/1/cgroup 2>/dev/null; then
        echo -e "${YELLOW}检测到LXC环境${PLAIN}"
    elif [[ -f /proc/user_beancounters ]]; then
        echo -e "${YELLOW}检测到OpenVZ环境${PLAIN}"
    elif grep -q -E "(vmx|svm)" /proc/cpuinfo; then
        echo -e "${YELLOW}检测到KVM环境${PLAIN}"
    elif dmesg | grep -q -i "vmware"; then
        echo -e "${YELLOW}检测到VMware环境${PLAIN}"
    elif dmesg | grep -q -i "xen"; then
        echo -e "${YELLOW}检测到Xen环境${PLAIN}"
    elif dmesg | grep -q -i "hyper-v"; then
        echo -e "${YELLOW}检测到Hyper-V环境${PLAIN}"
    fi
    
    # 检测NAT
    local wan_ip=$(curl -s https://api.ipify.org)
    local lan_ip=$(hostname -I | awk '{print $1}')
    
    if [[ "$wan_ip" != "$lan_ip" ]]; then
        echo -e "${YELLOW}检测到可能是NAT环境${PLAIN}"
    fi
}

# 获取公网IP
get_ip() {
    echo -e "${BLUE}正在获取公网IP...${PLAIN}"
    IP=$(curl -s https://api.ipify.org)
    if [[ -z "$IP" ]]; then
        IP=$(curl -s https://ipinfo.io/ip)
    fi
    if [[ -z "$IP" ]]; then
        IP=$(curl -s https://api.ip.sb/ip)
    fi
    if [[ -z "$IP" ]]; then
        echo -e "${RED}无法获取公网IP，请检查网络连接${PLAIN}"
        exit 1
    fi
    echo -e "${GREEN}公网IP: ${IP}${PLAIN}"
}

# 检测系统架构
check_arch() {
    echo -e "${BLUE}正在检测系统架构...${PLAIN}"
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64)
            ARCH="arm64"
            ;;
        armv7l)
            ARCH="arm"
            ;;
        *)
            echo -e "${RED}不支持的架构: $ARCH${PLAIN}"
            exit 1
            ;;
    esac
    echo -e "${GREEN}系统架构: $ARCH${PLAIN}"
}

# 安装依赖
install_deps() {
    echo -e "${BLUE}正在安装依赖...${PLAIN}"
    
    if command -v apt &>/dev/null; then
        apt update -y
        apt install -y curl wget tar gzip
    elif command -v yum &>/dev/null; then
        yum install -y curl wget tar gzip
    elif command -v dnf &>/dev/null; then
        dnf install -y curl wget tar gzip
    else
        echo -e "${RED}不支持的包管理器${PLAIN}"
        exit 1
    fi
}

# 下载并安装microsocks
install_microsocks() {
    echo -e "${BLUE}正在下载并安装microsocks...${PLAIN}"
    
    # 创建临时目录
    TMP_DIR=$(mktemp -d)
    cd $TMP_DIR
    
    # 下载microsocks
    GITHUB_URL="https://github.com/rofl0r/microsocks/archive/refs/heads/master.tar.gz"
    wget -q $GITHUB_URL -O microsocks.tar.gz
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}下载microsocks失败${PLAIN}"
        exit 1
    fi
    
    # 解压
    tar -xzf microsocks.tar.gz
    cd microsocks-master
    
    # 安装编译依赖
    if command -v apt &>/dev/null; then
        apt install -y gcc make
    elif command -v yum &>/dev/null; then
        yum install -y gcc make
    elif command -v dnf &>/dev/null; then
        dnf install -y gcc make
    fi
    
    # 编译
    make
    
    # 安装
    cp microsocks /usr/local/bin/
    
    # 清理
    cd /
    rm -rf $TMP_DIR
    
    echo -e "${GREEN}microsocks安装完成${PLAIN}"
}

# 配置systemd服务
setup_service() {
    echo -e "${BLUE}正在配置systemd服务...${PLAIN}"
    
    cat > /etc/systemd/system/microsocks.service << EOF
[Unit]
Description=MicroSocks SOCKS5 Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/microsocks -i 0.0.0.0 -p $PORT -u $USERNAME -P $PASSWORD
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable microsocks
    systemctl start microsocks
    
    echo -e "${GREEN}systemd服务配置完成并已启动${PLAIN}"
}

# 生成Telegram代理URL
generate_tg_url() {
    echo -e "${BLUE}正在生成Telegram代理URL...${PLAIN}"
    
    # SOCKS5格式
    TG_SOCKS_URL="tg://socks?server=$IP&port=$PORT"
    if [[ -n "$USERNAME" && -n "$PASSWORD" ]]; then
        TG_SOCKS_URL="$TG_SOCKS_URL&user=$USERNAME&pass=$PASSWORD"
    fi
    
    # Telegram网页格式 (使用/socks路径)
    TG_WEB_URL="https://t.me/socks?server=$IP&port=$PORT"
    if [[ -n "$USERNAME" && -n "$PASSWORD" ]]; then
        TG_WEB_URL="$TG_WEB_URL&user=$USERNAME&pass=$PASSWORD"
    fi
    
    echo -e "${GREEN}Telegram SOCKS5代理URL (点击可直接使用): ${TG_SOCKS_URL}${PLAIN}"
    echo -e "${GREEN}Telegram 网页链接格式 (点击可直接使用): ${TG_WEB_URL}${PLAIN}"
}

# 主函数
main() {
    clear
    echo -e "${GREEN}========================================${PLAIN}"
    echo -e "${GREEN}      SOCKS5 一键安装脚本              ${PLAIN}"
    echo -e "${GREEN}========================================${PLAIN}"
    
    # 检测虚拟化环境
    check_virt
    
    # 获取公网IP
    get_ip
    
    # 检测系统架构
    check_arch
    
    # 安装依赖
    install_deps
    
    # 设置端口、用户名和密码
    read -p "请输入SOCKS5端口 [默认: 1080]: " PORT
    PORT=${PORT:-1080}
    
    read -p "请输入SOCKS5用户名 [留空为无认证]: " USERNAME
    
    if [[ -n "$USERNAME" ]]; then
        read -p "请输入SOCKS5密码: " PASSWORD
        if [[ -z "$PASSWORD" ]]; then
            echo -e "${RED}用户名已设置，密码不能为空${PLAIN}"
            exit 1
        fi
    fi
    
    # 下载并安装microsocks
    install_microsocks
    
    # 配置systemd服务
    setup_service
    
    # 生成Telegram代理URL
    generate_tg_url
    
    echo -e "${GREEN}========================================${PLAIN}"
    echo -e "${GREEN}SOCKS5代理安装成功!${PLAIN}"
    echo -e "${GREEN}IP: ${IP}${PLAIN}"
    echo -e "${GREEN}端口: ${PORT}${PLAIN}"
    if [[ -n "$USERNAME" ]]; then
        echo -e "${GREEN}用户名: ${USERNAME}${PLAIN}"
        echo -e "${GREEN}密码: ${PASSWORD}${PLAIN}"
    else
        echo -e "${GREEN}认证: 无${PLAIN}"
    fi
    echo -e "${GREEN}========================================${PLAIN}"
    echo -e "${YELLOW}卸载/停止命令 (复制后可一键卸载): ${PLAIN}"
    UNINSTALL_CMD="systemctl stop microsocks && systemctl disable microsocks && rm -f /etc/systemd/system/microsocks.service /usr/local/bin/microsocks && systemctl daemon-reload"
    echo -e "${BLUE}${UNINSTALL_CMD}${PLAIN}"
    echo -e "${GREEN}========================================${PLAIN}"
}

main
