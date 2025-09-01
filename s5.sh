#!/bin/bash

# 3proxy 管理器 - By:Djkyc
# 专注3proxy内核，自定义端口用户密码

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
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
    echo -e "${GREEN}3proxy内核版 - ${GREEN}By:Djkyc${NC}"
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
    echo -e "${CYAN}=== 配置设置 ===${NC}"
    read -p "用户名 [proxy]: " user
    user=${user:-proxy}
    read -s -p "密码 [自动生成]: " pass
    echo
    if [[ -z "$pass" ]]; then
        pass=$(openssl rand -base64 12 2>/dev/null || date +%s | head -c 12)
        echo -e "${GREEN}生成密码: $pass${NC}"
    fi
    
    read -p "SOCKS5端口 [1080]: " socks_port
    socks_port=${socks_port:-1080}
    read -p "HTTP代理端口 [3128]: " http_port
    http_port=${http_port:-3128}
    
    # 安装依赖
    echo -e "${BLUE}[1/3]${NC} 安装编译依赖..."
    if command -v apt-get >/dev/null; then
        apt-get update -qq && apt-get install -y -qq build-essential wget make gcc curl
    elif command -v yum >/dev/null; then
        yum install -y -q gcc make wget curl
    fi
    
    # 编译3proxy
    echo -e "${BLUE}[2/3]${NC} 编译3proxy内核..."
    cd /tmp
    wget -q https://github.com/z3APA3A/3proxy/archive/0.9.4.tar.gz
    tar -xf 0.9.4.tar.gz >/dev/null 2>&1
    cd 3proxy-0.9.4
    make -f Makefile.Linux >/dev/null 2>&1
    mkdir -p /usr/local/etc/3proxy /usr/local/bin /var/log/3proxy
    cp bin/3proxy bin/mycrypt /usr/local/bin/
    chmod +x /usr/local/bin/3proxy /usr/local/bin/mycrypt
    
    # 配置3proxy
    echo -e "${BLUE}[3/3]${NC} 配置3proxy服务..."
    hash=$(/usr/local/bin/mycrypt "$pass")
    cat > /usr/local/etc/3proxy/3proxy.cfg << EOF
# 3proxy配置 - By:Djkyc
nserver 8.8.8.8
nserver 8.8.4.4
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
daemon
log /var/log/3proxy/3proxy.log D
logformat "- +_L%t.%. %N.%p %E %U %C:%c %R:%r %O %I %h %T"
rotate 30

# 用户认证
users $user:CL:$hash
auth strong
allow $user
deny *

# 代理服务
socks -p$socks_port
proxy -p$http_port
EOF
    
    # 配置3proxy服务
    cat > /etc/systemd/system/3proxy.service << EOF
[Unit]
Description=3proxy Proxy Server - By:Djkyc
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
Restart=on-failure
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF
    
    # 启动服务
    systemctl daemon-reload
    systemctl enable 3proxy >/dev/null 2>&1
    systemctl start 3proxy
    
    sleep 2
    
    # 获取IP并输出连接信息
    ip=$(get_ip)
    echo
    echo -e "${GREEN}安装完成!${NC}"
    echo
    echo -e "${CYAN}=== 连接信息 ===${NC}"
    echo -e "${WHITE}服务器IP:${NC} ${GREEN}$ip${NC}"
    echo -e "${WHITE}用户名:${NC} ${GREEN}$user${NC}"
    echo -e "${WHITE}密码:${NC} ${GREEN}$pass${NC}"
    echo
    echo -e "${WHITE}SOCKS5 连接:${NC}"
    echo -e "  • ${YELLOW}socks://${user}:${pass}@${ip}:${socks_port}${NC}"
    echo
    echo -e "${WHITE}HTTP 连接:${NC}"
    echo -e "  • ${YELLOW}http://${ip}:${http_port}${NC}"
    echo
    echo -e "${WHITE}Telegram 快链:${NC}"
    echo -e "  • ${BLUE}https://t.me/socks?server=${ip}&port=${socks_port}&user=${user}&pass=${pass}${NC}"
    echo
    echo -e "${GREEN}By:Djkyc - 3proxy内核版${NC}"
    echo
}

# 卸载
uninstall() {
    echo -e "${YELLOW}卸载3proxy中...${NC}"
    systemctl stop 3proxy 2>/dev/null || true
    systemctl disable 3proxy 2>/dev/null || true
    rm -f /etc/systemd/system/3proxy.service
    rm -f /usr/local/bin/3proxy /usr/local/bin/mycrypt
    rm -rf /usr/local/etc/3proxy
    rm -rf /var/log/3proxy
    systemctl daemon-reload
    echo -e "${GREEN}卸载完成 - By:Djkyc${NC}"
}

# 修改配置
modify_config() {
    show_banner
    echo -e "${YELLOW}修改3proxy配置${NC}"
    
    # 检查服务是否存在
    if [[ ! -f /usr/local/etc/3proxy/3proxy.cfg ]]; then
        echo -e "${RED}错误: 3proxy未安装，请先安装${NC}"
        read -p "按回车键继续..."
        return
    fi
    
    echo -e "${CYAN}=== 当前配置 ===${NC}"
    # 显示当前端口
    socks_port=$(grep "socks -p" /usr/local/etc/3proxy/3proxy.cfg | sed 's/socks -p//')
    http_port=$(grep "proxy -p" /usr/local/etc/3proxy/3proxy.cfg | sed 's/proxy -p//')
    current_user=$(grep "users " /usr/local/etc/3proxy/3proxy.cfg | cut -d: -f1 | cut -d' ' -f2)
    
    echo -e "${WHITE}当前用户:${NC} ${GREEN}$current_user${NC}"
    echo -e "${WHITE}SOCKS5端口:${NC} ${GREEN}$socks_port${NC}"
    echo -e "${WHITE}HTTP端口:${NC} ${GREEN}$http_port${NC}"
    echo
    
    echo -e "${CYAN}=== 修改配置 ===${NC}"
    read -p "新用户名 [$current_user]: " new_user
    new_user=${new_user:-$current_user}
    
    read -s -p "新密码 [不修改]: " new_pass
    echo
    
    read -p "新SOCKS5端口 [$socks_port]: " new_socks_port
    new_socks_port=${new_socks_port:-$socks_port}
    
    read -p "新HTTP端口 [$http_port]: " new_http_port
    new_http_port=${new_http_port:-$http_port}
    
    # 如果密码为空，保持原密码
    if [[ -z "$new_pass" ]]; then
        # 从配置文件获取原密码哈希
        old_hash=$(grep "users " /usr/local/etc/3proxy/3proxy.cfg | cut -d: -f3)
        new_hash=$old_hash
        echo -e "${YELLOW}密码保持不变${NC}"
    else
        new_hash=$(/usr/local/bin/mycrypt "$new_pass")
        echo -e "${GREEN}密码已更新${NC}"
    fi
    
    # 更新配置文件
    cat > /usr/local/etc/3proxy/3proxy.cfg << EOF
# 3proxy配置 - By:Djkyc
nserver 8.8.8.8
nserver 8.8.4.4
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
daemon
log /var/log/3proxy/3proxy.log D
logformat "- +_L%t.%. %N.%p %E %U %C:%c %R:%r %O %I %h %T"
rotate 30

# 用户认证
users $new_user:CL:$new_hash
auth strong
allow $new_user
deny *

# 代理服务
socks -p$new_socks_port
proxy -p$new_http_port
EOF
    
    # 重启服务
    echo -e "${BLUE}重启3proxy服务...${NC}"
    systemctl restart 3proxy
    sleep 2
    
    if systemctl is-active 3proxy >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 配置更新成功${NC}"
        
        # 显示新的连接信息
        ip=$(get_ip)
        echo
        echo -e "${CYAN}=== 新连接信息 ===${NC}"
        echo -e "${WHITE}服务器IP:${NC} ${GREEN}$ip${NC}"
        echo -e "${WHITE}用户名:${NC} ${GREEN}$new_user${NC}"
        if [[ -n "$new_pass" ]]; then
            echo -e "${WHITE}密码:${NC} ${GREEN}$new_pass${NC}"
        else
            echo -e "${WHITE}密码:${NC} ${YELLOW}未修改${NC}"
        fi
        echo
        echo -e "${WHITE}SOCKS5 连接:${NC}"
        if [[ -n "$new_pass" ]]; then
            echo -e "  • ${YELLOW}socks://${new_user}:${new_pass}@${ip}:${new_socks_port}${NC}"
        else
            echo -e "  • ${YELLOW}socks://${new_user}:[原密码]@${ip}:${new_socks_port}${NC}"
        fi
        echo
        echo -e "${WHITE}HTTP 连接:${NC}"
        echo -e "  • ${YELLOW}http://${ip}:${new_http_port}${NC}"
        echo
        if [[ -n "$new_pass" ]]; then
            echo -e "${WHITE}Telegram 快链:${NC}"
            echo -e "  • ${BLUE}https://t.me/socks?server=${ip}&port=${new_socks_port}&user=${new_user}&pass=${new_pass}${NC}"
            echo
        fi
        echo -e "${GREEN}By:Djkyc - 3proxy内核版${NC}"
    else
        echo -e "${RED}✗ 服务启动失败，请检查配置${NC}"
    fi
    
    read -p "按回车键继续..."
}

# 主菜单
main() {
    show_banner
    echo -e "${WHITE}1)${NC} 安装3proxy"
    echo -e "${WHITE}2)${NC} 卸载3proxy" 
    echo -e "${WHITE}3)${NC} 修改自定义"
    echo -e "${WHITE}0)${NC} 退出"
    echo
    echo -e "${GREEN}By:Djkyc${NC}"
    echo
    read -p "选择 [0-3]: " choice
    
    case $choice in
        1) install ;;
        2) uninstall ;;
        3) modify_config ;;
        0) exit 0 ;;
        *) echo "无效选择" ;;
    esac
}

main
