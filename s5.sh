#!/bin/bash

# SOCKS5 简洁管理器 - By:Djkyc
# 只包含核心功能，无多余内容

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

show_banner() {
    clear
    echo -e "${CYAN}"
    echo " ____   ___   ____ _  ______ ____  "
    echo "/ ___| / _ \\ / ___| |/ / ___| ___| "
    echo "\\___ \\| | | | |   | ' /\\___ \\___ \\ "
    echo " ___) | |_| | |___| . \\ ___) |__) |"
    echo "|____/ \\___/ \\____|_|\\_\\____/____/ "
    echo -e "${NC}"
    echo -e "${YELLOW}轻量级版 - 仅包含microsocks和3proxy By:Djkyc${NC}"
    echo "=================================================="
}

# 检测IP
get_ip() {
    local ip
    ip=$(curl -s --max-time 5 ipv4.icanhazip.com 2>/dev/null || 
         curl -s --max-time 5 api.ipify.org 2>/dev/null || 
         curl -s --max-time 5 checkip.amazonaws.com 2>/dev/null || 
         hostname -I | awk '{print $1}' 2>/dev/null || 
         echo "127.0.0.1")
    echo "$ip"
}

# 安装
install() {
    show_banner
    echo -e "${YELLOW}开始安装...${NC}"
    
    # 检查root
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}需要root权限${NC}"
        exit 1
    fi
    
    # 用户认证和端口设置
    read -p "用户名 [proxy]: " user
    user=${user:-proxy}
    read -s -p "密码 [自动生成]: " pass
    echo
    if [[ -z "$pass" ]]; then
        pass=$(openssl rand -base64 8 2>/dev/null || date +%s | head -c 8)
        echo -e "${GREEN}生成密码: $pass${NC}"
    fi
    
    read -p "3proxy端口 [1080]: " port1
    port1=${port1:-1080}
    read -p "microsocks端口 [1081]: " port2
    port2=${port2:-1081}
    read -p "HTTP代理端口 [3128]: " port3
    port3=${port3:-3128}
    
    # 安装依赖
    echo "安装依赖..."
    if command -v apt-get >/dev/null; then
        apt-get update -qq && apt-get install -y -qq build-essential wget make gcc git curl
    elif command -v yum >/dev/null; then
        yum install -y -q gcc make wget git curl
    fi
    
    # 编译microsocks
    echo "编译microsocks..."
    cd /tmp
    git clone https://github.com/rofl0r/microsocks.git >/dev/null 2>&1
    cd microsocks
    make >/dev/null 2>&1
    cp microsocks /usr/local/bin/
    
    # 编译3proxy
    echo "编译3proxy..."
    cd /tmp
    wget -q https://github.com/z3APA3A/3proxy/archive/0.9.4.tar.gz
    tar -xf 0.9.4.tar.gz
    cd 3proxy-0.9.4
    make -f Makefile.Linux >/dev/null 2>&1
    mkdir -p /usr/local/etc/3proxy /usr/local/bin
    cp bin/3proxy bin/mycrypt /usr/local/bin/
    
    # 配置microsocks服务
    cat > /etc/systemd/system/microsocks.service << EOF
[Unit]
Description=Microsocks SOCKS5 Proxy
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/microsocks -i 0.0.0.0 -p $port2 -u $user -P $pass
Restart=on-failure
User=nobody

[Install]
WantedBy=multi-user.target
EOF
    
    # 配置3proxy
    hash=$(/usr/local/bin/mycrypt "$pass")
    cat > /usr/local/etc/3proxy/3proxy.cfg << EOF
nserver 8.8.8.8
daemon
log /var/log/3proxy.log
users $user:CL:$hash
auth strong
allow $user
socks -p$port1
proxy -p$port3
EOF
    
    # 配置3proxy服务
    cat > /etc/systemd/system/3proxy.service << EOF
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    
    # 启动服务
    systemctl daemon-reload
    systemctl enable microsocks 3proxy
    systemctl start microsocks 3proxy
    
    # 获取IP并输出连接信息
    ip=$(get_ip)
    echo
    echo -e "${GREEN}安装完成!${NC}"
    echo
    echo -e "${CYAN}=== 连接信息 ===${NC}"
    echo -e "SOCKS5 连接:"
    echo -e "  • socks://${user}:${pass}@${ip}:${port1}"
    echo -e "  • socks://${user}:${pass}@${ip}:${port2}"
    echo -e "  • http://${ip}:${port3}"
    echo
    echo -e "Telegram 快链:"
    echo -e "  • https://t.me/socks?server=${ip}&port=${port1}&user=${user}&pass=${pass}"
    echo -e "  • https://t.me/socks?server=${ip}&port=${port2}&user=${user}&pass=${pass}"
    echo
}

# 卸载
uninstall() {
    echo -e "${YELLOW}卸载中...${NC}"
    systemctl stop microsocks 3proxy 2>/dev/null || true
    systemctl disable microsocks 3proxy 2>/dev/null || true
    rm -f /etc/systemd/system/microsocks.service
    rm -f /etc/systemd/system/3proxy.service
    rm -f /usr/local/bin/microsocks /usr/local/bin/3proxy /usr/local/bin/mycrypt
    rm -rf /usr/local/etc/3proxy
    systemctl daemon-reload
    echo -e "${GREEN}卸载完成${NC}"
}

# 状态
status() {
    echo -e "${CYAN}服务状态:${NC}"
    systemctl is-active microsocks 3proxy
    echo
    echo -e "${CYAN}端口监听:${NC}"
    netstat -tlnp | grep -E ':([0-9]+)' | grep -E '(3proxy|microsocks)'
}

# 主菜单
main() {
    show_banner
    echo "1) 安装"
    echo "2) 卸载" 
    echo "3) 状态"
    echo "0) 退出"
    echo
    read -p "选择 [0-3]: " choice
    
    case $choice in
        1) install ;;
        2) uninstall ;;
        3) status ;;
        0) exit 0 ;;
        *) echo "无效选择" ;;
    esac
}

main
