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

# 系统检查
check_system() {
    echo -e "${BLUE}检查系统环境...${NC}"
    
    # 检查磁盘空间
    local available_space=$(df /tmp | tail -1 | awk '{print $4}')
    if [[ $available_space -lt 100000 ]]; then  # 小于100MB
        echo -e "${RED}错误: 磁盘空间不足 (可用: ${available_space}KB)${NC}"
        echo -e "${YELLOW}正在清理系统缓存...${NC}"
        
        # 清理APT缓存
        apt-get clean >/dev/null 2>&1 || true
        apt-get autoclean >/dev/null 2>&1 || true
        
        # 清理临时文件
        rm -rf /tmp/3proxy* /tmp/*.tar.gz >/dev/null 2>&1 || true
        
        # 清理日志文件
        journalctl --vacuum-size=50M >/dev/null 2>&1 || true
        
        # 再次检查空间
        available_space=$(df /tmp | tail -1 | awk '{print $4}')
        if [[ $available_space -lt 50000 ]]; then  # 小于50MB
            echo -e "${RED}清理后仍然空间不足，需要至少50MB空间${NC}"
            echo "请手动清理磁盘空间后重试"
            return 1
        else
            echo -e "${GREEN}清理完成，可用空间: ${available_space}KB${NC}"
        fi
    fi
    
    # 检查必要命令
    local missing_cmds=()
    for cmd in wget tar make gcc; do
        if ! command -v $cmd >/dev/null 2>&1; then
            missing_cmds+=($cmd)
        fi
    done
    
    if [[ ${#missing_cmds[@]} -gt 0 ]]; then
        echo -e "${YELLOW}缺少命令: ${missing_cmds[*]}${NC}"
        return 1
    fi
    
    # 检查端口占用
    if [[ -n "$1" ]] && netstat -tlnp 2>/dev/null | grep -q ":$1 "; then
        echo -e "${YELLOW}警告: 端口 $1 已被占用${NC}"
        return 1
    fi
    
    return 0
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
        pass=$(openssl rand -base64 12 2>/dev/null || date +%s | head -c 12)
        echo -e "${GREEN}生成密码: $pass${NC}"
    else
        echo -e "${GREEN}使用密码: $pass${NC}"
    fi
    
    read -p "SOCKS5端口 [1080]: " socks_port
    socks_port=${socks_port:-1080}
    http_port=3128
    
    # 显示磁盘空间
    echo -e "${CYAN}磁盘空间检查:${NC}"
    df -h / | tail -1 | awk '{print "根分区: " $3 " 已用, " $4 " 可用, " $5 " 使用率"}'
    df -h /tmp | tail -1 | awk '{print "临时目录: " $3 " 已用, " $4 " 可用, " $5 " 使用率"}'
    echo
    
    # 检查系统环境
    if ! check_system "$socks_port"; then
        echo -e "${YELLOW}继续安装? [y/N]: ${NC}"
        read -r continue_install
        if [[ ! "$continue_install" =~ ^[Yy]$ ]]; then
            echo "安装已取消"
            return
        fi
    fi
    
    # 安装依赖
    echo -e "${BLUE}[1/3]${NC} 安装编译依赖..."
    if command -v apt-get >/dev/null; then
        echo "清理APT缓存..."
        apt-get clean >/dev/null 2>&1 || true
        
        echo "修复APT依赖问题..."
        apt --fix-broken install -y >/dev/null 2>&1 || true
        dpkg --configure -a >/dev/null 2>&1 || true
        
        # 检查是否已安装必要工具
        local need_install=false
        for cmd in gcc make wget curl; do
            if ! command -v $cmd >/dev/null 2>&1; then
                need_install=true
                break
            fi
        done
        
        if [[ "$need_install" == "true" ]]; then
            echo "更新软件包列表..."
            if ! apt-get update -qq 2>/dev/null; then
                echo -e "${YELLOW}警告: 软件源更新失败，尝试使用现有包...${NC}"
            fi
            
            echo "安装编译工具..."
            if ! apt-get install -y -qq gcc make wget curl 2>/dev/null; then
                echo -e "${YELLOW}尝试最小化安装...${NC}"
                apt-get install -y -qq --no-install-recommends gcc make wget curl 2>/dev/null || {
                    echo -e "${RED}错误: 无法安装编译依赖，磁盘空间不足${NC}"
                    echo "请清理磁盘空间后重试"
                    exit 1
                }
            fi
        else
            echo -e "${GREEN}编译工具已安装${NC}"
        fi
    elif command -v yum >/dev/null; then
        yum install -y -q gcc make wget curl
    fi
    
    # 编译3proxy
    echo -e "${BLUE}[2/3]${NC} 编译3proxy内核..."
    
    # 使用/var/tmp作为工作目录（通常有更多空间）
    WORK_DIR="/var/tmp"
    if [[ $(df $WORK_DIR | tail -1 | awk '{print $4}') -lt $(df /tmp | tail -1 | awk '{print $4}') ]]; then
        WORK_DIR="/tmp"
    fi
    
    cd $WORK_DIR
    
    # 清理旧文件
    rm -rf 3proxy-0.9.4* 2>/dev/null || true
    
    echo "下载3proxy源码..."
    if ! wget -q --timeout=30 https://github.com/z3APA3A/3proxy/archive/0.9.4.tar.gz; then
        echo -e "${RED}错误: 下载3proxy源码失败${NC}"
        echo "请检查网络连接"
        exit 1
    fi
    
    echo "解压源码..."
    if ! tar -xf 0.9.4.tar.gz >/dev/null 2>&1; then
        echo -e "${RED}错误: 解压源码失败${NC}"
        rm -f 0.9.4.tar.gz
        exit 1
    fi
    
    # 删除压缩包节省空间
    rm -f 0.9.4.tar.gz
    
    cd 3proxy-0.9.4
    echo "编译3proxy..."
    if ! make -f Makefile.Linux >/dev/null 2>&1; then
        echo -e "${RED}错误: 编译3proxy失败${NC}"
        echo "请检查编译环境是否完整"
        cd ..
        rm -rf 3proxy-0.9.4
        exit 1
    fi
    
    echo "安装3proxy..."
    mkdir -p /usr/local/etc/3proxy /usr/local/bin /var/log/3proxy
    cp bin/3proxy bin/mycrypt /usr/local/bin/
    chmod +x /usr/local/bin/3proxy /usr/local/bin/mycrypt
    
    # 清理编译文件
    cd ..
    rm -rf 3proxy-0.9.4
    
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
    echo "启动3proxy服务..."
    systemctl daemon-reload
    systemctl enable 3proxy >/dev/null 2>&1
    
    if ! systemctl start 3proxy; then
        echo -e "${RED}错误: 3proxy服务启动失败${NC}"
        echo "检查配置文件..."
        journalctl -u 3proxy --no-pager -n 10
        exit 1
    fi
    
    sleep 2
    
    # 验证服务状态
    if ! systemctl is-active 3proxy >/dev/null 2>&1; then
        echo -e "${RED}错误: 3proxy服务未正常运行${NC}"
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
    rm -f /etc/systemd/system/3proxy.service
    rm -f /usr/local/bin/3proxy /usr/local/bin/mycrypt
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
    # 显示当前端口
    socks_port=$(grep "socks -p" /usr/local/etc/3proxy/3proxy.cfg | sed 's/socks -p//')
    http_port=$(grep "proxy -p" /usr/local/etc/3proxy/3proxy.cfg | sed 's/proxy -p//')
    current_user=$(grep "users " /usr/local/etc/3proxy/3proxy.cfg | cut -d: -f1 | cut -d' ' -f2)
    
    echo -e "${WHITE}当前用户:${NC} ${GREEN}$current_user${NC}"
    echo -e "${WHITE}SOCKS5端口:${NC} ${GREEN}$socks_port${NC}"
    echo
    
    echo -e "${CYAN}=== 修改配置 ===${NC}"
    read -p "新用户名 [$current_user]: " new_user
    new_user=${new_user:-$current_user}
    
    read -p "新密码 [不修改]: " new_pass
    
    read -p "新SOCKS5端口 [$socks_port]: " new_socks_port
    new_socks_port=${new_socks_port:-$socks_port}
    
    new_http_port=3128
    
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
        if [[ -n "$new_pass" ]]; then
            echo -e "${WHITE}Telegram 快链:${NC}"
            echo -e "  • ${BLUE}https://t.me/socks?server=${ip}&port=${new_socks_port}&user=${new_user}&pass=${new_pass}${NC}"
            echo
        fi
    else
        echo -e "${RED}✗ 服务启动失败，请检查配置${NC}"
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
