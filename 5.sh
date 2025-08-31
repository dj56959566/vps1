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
    
    # 临时提高进程优先级，确保依赖安装顺利完成
    renice -n -10 -p $$ > /dev/null 2>&1
    
    # 释放缓存，为安装腾出内存
    echo 3 > /proc/sys/vm/drop_caches
    
    if command -v apt &>/dev/null; then
        # 设置apt优先级
        echo 'APT::Immediate-Configure "false";' > /etc/apt/apt.conf.d/99defer-configure
        echo 'Acquire::Queue-Mode "access";' >> /etc/apt/apt.conf.d/99defer-configure
        
        # 更新和安装依赖
        apt update -y
        apt install -y --no-install-recommends curl wget tar gzip
    elif command -v yum &>/dev/null; then
        yum install -y curl wget tar gzip
    elif command -v dnf &>/dev/null; then
        dnf install -y curl wget tar gzip
    else
        echo -e "${RED}不支持的包管理器${PLAIN}"
        exit 1
    fi
    
    # 恢复正常优先级
    renice -n 0 -p $$ > /dev/null 2>&1
}

# 下载并安装microsocks
install_microsocks() {
    echo -e "${BLUE}正在下载并安装microsocks...${PLAIN}"
    
    # 临时提高进程优先级，确保下载和安装顺利完成
    renice -n -10 -p $$ > /dev/null 2>&1
    
    # 创建临时目录
    TMP_DIR=$(mktemp -d)
    cd $TMP_DIR
    
    # 尝试下载预编译的二进制文件
    BINARY_URL=""
    case $ARCH in
        amd64)
            BINARY_URL="https://github.com/rofl0r/microsocks/releases/download/v1.0.3/microsocks-linux-amd64"
            ;;
        arm64)
            BINARY_URL="https://github.com/rofl0r/microsocks/releases/download/v1.0.3/microsocks-linux-arm64"
            ;;
        arm)
            BINARY_URL="https://github.com/rofl0r/microsocks/releases/download/v1.0.3/microsocks-linux-arm"
            ;;
    esac
    
    if [[ -n "$BINARY_URL" ]]; then
        echo -e "${BLUE}尝试下载预编译二进制文件...${PLAIN}"
        # 使用多个下载源尝试下载
        if wget -q $BINARY_URL -O microsocks || 
           wget -q --no-check-certificate $BINARY_URL -O microsocks || 
           curl -s -o microsocks $BINARY_URL; then
            chmod +x microsocks
            mv microsocks /usr/local/bin/
            echo -e "${GREEN}预编译二进制文件安装完成${PLAIN}"
            cd /
            rm -rf $TMP_DIR
            # 恢复正常优先级
            renice -n 0 -p $$ > /dev/null 2>&1
            return
        else
            echo -e "${YELLOW}预编译二进制文件下载失败，将尝试从源码编译...${PLAIN}"
        fi
    fi
    
    # 如果预编译二进制下载失败，则从源码编译
    # 释放缓存，为编译腾出内存
    echo 3 > /proc/sys/vm/drop_caches
    
    # 下载microsocks
    GITHUB_URL="https://github.com/rofl0r/microsocks/archive/refs/heads/master.tar.gz"
    if ! wget -q $GITHUB_URL -O microsocks.tar.gz; then
        if ! wget -q --no-check-certificate $GITHUB_URL -O microsocks.tar.gz; then
            if ! curl -s -o microsocks.tar.gz $GITHUB_URL; then
                echo -e "${RED}下载microsocks失败${PLAIN}"
                # 恢复正常优先级
                renice -n 0 -p $$ > /dev/null 2>&1
                exit 1
            fi
        fi
    fi
    
    # 解压
    tar -xzf microsocks.tar.gz
    cd microsocks-master
    
    # 安装编译依赖
    if command -v apt &>/dev/null; then
        apt install -y --no-install-recommends gcc make
    elif command -v yum &>/dev/null; then
        yum install -y gcc make
    elif command -v dnf &>/dev/null; then
        dnf install -y gcc make
    fi
    
    # 编译前再次释放缓存
    echo 3 > /proc/sys/vm/drop_caches
    
    # 编译（使用优化选项，减少二进制大小和内存占用）
    make CFLAGS="-Os -ffunction-sections -fdata-sections" LDFLAGS="-Wl,--gc-sections"
    
    # 安装
    cp microsocks /usr/local/bin/
    strip -s /usr/local/bin/microsocks
    
    # 清理
    cd /
    rm -rf $TMP_DIR
    
    # 恢复正常优先级
    renice -n 0 -p $$ > /dev/null 2>&1
    
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
# 资源限制
CPUQuota=30%
MemoryLimit=50M
TasksMax=10
Nice=10
IOSchedulingClass=2
IOSchedulingPriority=7

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

# 优化系统资源
optimize_system() {
    echo -e "${BLUE}正在优化系统资源...${PLAIN}"
    
    # 停止非必要服务
    for svc in apache2 nginx mysql postgresql mongodb docker snapd; do
        if systemctl is-active $svc &>/dev/null; then
            echo -e "${YELLOW}临时停止 $svc 服务以释放资源${PLAIN}"
            systemctl stop $svc
        fi
    done
    
    # 释放缓存
    echo 3 > /proc/sys/vm/drop_caches
    
    # 调整swappiness
    if [[ -f /proc/sys/vm/swappiness ]]; then
        echo 10 > /proc/sys/vm/swappiness
    fi
    
    # 调整OOM killer
    if [[ -f /proc/self/oom_score_adj ]]; then
        echo -1000 > /proc/self/oom_score_adj
    fi
    
    echo -e "${GREEN}系统资源优化完成${PLAIN}"
}

# 主函数
main() {
    clear
    echo -e "${GREEN}========================================${PLAIN}"
    echo -e "${GREEN}      SOCKS5 一键安装脚本              ${PLAIN}"
    echo -e "${GREEN}========================================${PLAIN}"
    
    # 优化系统资源
    optimize_system
    
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
