#!/bin/bash

# 3proxy 管理器 - By:Djkyc
# 专注3proxy内核，自定义端口用户密码

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
    read -p "密码 [自动生成]: " pass
    if [[ -z "$pass" ]]; then
        pass=$(openssl rand -base64 8 2>/dev/null || date +%s | head -c 8)
        echo -e "${GREEN}生成密码: $pass${NC}"
    else
        echo -e "${GREEN}使用密码: $pass${NC}"
    fi
    
    read -p "SOCKS5端口 [1080]: " socks_port
    socks_port=${socks_port:-1080}
    
    # 安装依赖
    echo -e "${BLUE}[1/3]${NC} 安装编译依赖..."
    if command -v apt-get >/dev/null; then
        apt-get update -qq 2>/dev/null || true
        apt-get install -y -qq gcc make wget curl 2>/dev/null || {
            echo -e "${RED}错误: 无法安装编译依赖${NC}"
            exit 1
        }
    elif command -v yum >/dev/null; then
        yum install -y -q gcc make wget curl
    fi
    
    # 编译3proxy
    echo -e "${BLUE}[2/3]${NC} 编译3proxy内核..."
    cd /tmp
    rm -rf 3proxy-0.9.4* 2>/dev/null || true
    
    echo "下载3proxy源码..."
    if ! wget -q --timeout=30 https://github.com/z3APA3A/3proxy/archive/0.9.4.tar.gz; then
        echo -e "${RED}错误: 下载3proxy源码失败${NC}"
        exit 1
    fi
    
    echo "解压并编译..."
    tar -xf 0.9.4.tar.gz
    cd 3proxy-0.9.4
    
    if ! make -f Makefile.Linux >/dev/null 2>&1; then
        echo -e "${RED}错误: 编译3proxy失败${NC}"
        exit 1
    fi
    
    echo "安装3proxy..."
    mkdir -p /usr/local/etc/3proxy /usr/local/bin /var/log/3proxy
    cp bin/3proxy /usr/local/bin/
    chmod +x /usr/local/bin/3proxy
    
    # 清理
    cd /tmp
    rm -rf 3proxy-0.9.4*
    
    # 配置3proxy - 使用最简单的配置
    echo -e "${BLUE}[3/3]${NC} 配置3proxy服务..."
    
    # 创建密码文件
    echo "$user:$pass" > /usr/local/etc/3proxy/passwd
    
    # 创建最简配置
    cat > /usr/local/etc/3proxy/3proxy.cfg << EOF
nserver 8.8.8.8
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
log /var/log/3proxy/3proxy.log D
rotate 30
users $/usr/local/etc/3proxy/passwd
auth strong
allow $user
deny *
socks -p$socks_port
EOF
    
    # 创建启动脚本
    cat > /usr/local/bin/start_3proxy.sh << 'EOF'
#!/bin/bash
cd /usr/local/etc/3proxy
/usr/local/bin/3proxy 3proxy.cfg
EOF
    chmod +x /usr/local/bin/start_3proxy.sh
    
    # 创建systemd服务
    cat > /etc/systemd/system/3proxy.service << EOF
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/start_3proxy.sh
Restart=always
RestartSec=5
User=root
WorkingDirectory=/usr/local/etc/3proxy

[Install]
WantedBy=multi-user.target
EOF
    
    # 启动服务
    echo "启动3proxy服务..."
    systemctl daemon-reload
    systemctl enable 3proxy
    
    # 先测试直接启动
    echo "测试3proxy启动..."
    cd /usr/local/etc/3proxy
    
    # 杀死可能存在的进程
    pkill -f "3proxy" 2>/dev/null || true
    sleep 1
    
    # 直接启动测试
    /usr/local/bin/3proxy 3proxy.cfg &
    sleep 3
    
    if pgrep -f "3proxy" >/dev/null; then
        echo -e "${GREEN}✓ 3proxy启动成功${NC}"
        
        # 杀死测试进程，用systemd启动
        pkill -f "3proxy"
        sleep 1
        
        if systemctl start 3proxy; then
            echo -e "${GREEN}✓ systemd服务启动成功${NC}"
        else
            echo -e "${YELLOW}systemd启动失败，使用直接启动${NC}"
            /usr/local/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg &
        fi
    else
        echo -e "${RED}错误: 3proxy启动失败${NC}"
        echo "检查配置文件..."
        cat /usr/local/etc/3proxy/3proxy.cfg
        exit 1
    fi
    
    # 最终验证
    sleep 2
    if pgrep -f "3proxy" >/dev/null; then
        echo -e "${GREEN}✓ 3proxy运行正常${NC}"
    else
        echo -e "${RED}✗ 3proxy未运行${NC}"
        exit 1
    fi
    
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
    echo -e "${WHITE}Telegram 快链:${NC}"
    echo -e "  • ${BLUE}https://t.me/socks?server=${ip}&port=${socks_port}&user=${user}&pass=${pass}${NC}"
    echo
}

# 卸载
uninstall() {
    echo -e "${YELLOW}卸载3proxy中...${NC}"
    systemctl stop 3proxy 2>/dev/null || true
    systemctl disable 3proxy 2>/dev/null || true
    pkill -f "3proxy" 2>/dev/null || true
    rm -f /etc/systemd/system/3proxy.service
    rm -f /usr/local/bin/3proxy /usr/local/bin/start_3proxy.sh
    rm -rf /usr/local/etc/3proxy
    rm -rf /var/log/3proxy
    systemctl daemon-reload
    echo -e "${GREEN}卸载完成${NC}"
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
    # 显示当前端口和用户
    socks_port=$(grep "socks -p" /usr/local/etc/3proxy/3proxy.cfg | sed 's/socks -p//')
    current_user=$(head -1 /usr/local/etc/3proxy/passwd | cut -d: -f1)
    
    echo -e "${WHITE}当前用户:${NC} ${GREEN}$current_user${NC}"
    echo -e "${WHITE}SOCKS5端口:${NC} ${GREEN}$socks_port${NC}"
    echo
    
    echo -e "${CYAN}=== 修改配置 ===${NC}"
    read -p "新用户名 [$current_user]: " new_user
    new_user=${new_user:-$current_user}
    
    read -p "新密码 [不修改]: " new_pass
    
    read -p "新SOCKS5端口 [$socks_port]: " new_socks_port
    new_socks_port=${new_socks_port:-$socks_port}
    
    # 更新密码文件
    if [[ -n "$new_pass" ]]; then
        echo "$new_user:$new_pass" > /usr/local/etc/3proxy/passwd
        echo -e "${GREEN}密码已更新${NC}"
    else
        # 保持原密码，只更新用户名
        old_pass=$(head -1 /usr/local/etc/3proxy/passwd | cut -d: -f2)
        echo "$new_user:$old_pass" > /usr/local/etc/3proxy/passwd
        echo -e "${YELLOW}密码保持不变${NC}"
    fi
    
    # 更新配置文件
    cat > /usr/local/etc/3proxy/3proxy.cfg << EOF
nserver 8.8.8.8
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
log /var/log/3proxy/3proxy.log D
rotate 30
users $/usr/local/etc/3proxy/passwd
auth strong
allow $new_user
deny *
socks -p$new_socks_port
EOF
    
    # 重启服务
    echo -e "${BLUE}重启3proxy服务...${NC}"
    
    # 停止现有进程
    systemctl stop 3proxy 2>/dev/null || true
    pkill -f "3proxy" 2>/dev/null || true
    sleep 1
    
    # 启动服务
    cd /usr/local/etc/3proxy
    if systemctl start 3proxy 2>/dev/null; then
        sleep 2
        if pgrep -f "3proxy" >/dev/null; then
            echo -e "${GREEN}✓ 配置更新成功${NC}"
        else
            echo -e "${YELLOW}systemctl异常，尝试直接启动...${NC}"
            /usr/local/bin/3proxy 3proxy.cfg &
            sleep 2
            if pgrep -f "3proxy" >/dev/null; then
                echo -e "${GREEN}✓ 配置更新成功${NC}"
            else
                echo -e "${RED}✗ 服务启动失败${NC}"
                return
            fi
        fi
    else
        echo -e "${YELLOW}systemctl启动失败，尝试直接启动...${NC}"
        /usr/local/bin/3proxy 3proxy.cfg &
        sleep 2
        if pgrep -f "3proxy" >/dev/null; then
            echo -e "${GREEN}✓ 配置更新成功${NC}"
        else
            echo -e "${RED}✗ 服务启动失败${NC}"
            return
        fi
    fi
    
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
    if [[ -n "$new_pass" ]]; then
        echo -e "${WHITE}Telegram 快链:${NC}"
        echo -e "  • ${BLUE}https://t.me/socks?server=${ip}&port=${new_socks_port}&user=${new_user}&pass=${new_pass}${NC}"
        echo
    fi
    
    read -p "按回车键继续..."
}

# 主菜单
main() {
    show_banner
    echo -e "${WHITE}1.安装${NC}"
    echo -e "${WHITE}2.卸载${NC}" 
    echo -e "${WHITE}3.修改并自定义${NC}"
    echo -e "${WHITE}4.退出${NC}"
    echo
    echo -e "${GREEN}By:Djkyc${NC}"
    echo
    read -p "选择 [1-4]: " choice
    
    case $choice in
        1) install ;;
        2) uninstall ;;
        3) modify_config ;;
        4) exit 0 ;;
        *) echo "无效选择" ;;
    esac
}

main
