#!/bin/bash

# Hysteria2 管理脚本 - 端口跳跃和域名管理

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置文件路径
CONFIG_PATH="/etc/hysteria/config.yaml"
SERVER_DOMAIN_CONFIG="/etc/hysteria/server-domain.conf"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为 root 用户
if [[ $EUID -ne 0 ]]; then
    log_error "此脚本需要 root 权限运行，请使用 sudo 运行此脚本"
    exit 1
fi

# 等待用户确认
wait_for_user() {
    echo ""
    read -p "按回车键继续..." -r
}

# 获取当前监听端口
get_current_listen_port() {
    if [[ -f "$CONFIG_PATH" ]]; then
        grep -E "^\s*listen:" "$CONFIG_PATH" | awk -F':' '{print $3}' | tr -d ' ' || echo "443"
    else
        echo "443"
    fi
}

# 添加端口跳跃规则
add_port_hopping_rules() {
    local start_port="$1"
    local end_port="$2"
    local target_port="$3"
    local interface="$4"
    
    # 如果未指定网络接口，自动检测
    if [[ -z "$interface" ]]; then
        interface=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'dev \K\S+' | head -1)
        if [[ -z "$interface" ]]; then
            interface="eth0"
        fi
    fi
    
    # 添加 iptables 规则
    if iptables -t nat -A PREROUTING -i "$interface" -p udp --dport "$start_port:$end_port" -j REDIRECT --to-ports "$target_port"; then
        # 保存配置
        mkdir -p "/etc/hysteria"
        cat > "/etc/hysteria/port-hopping.conf" << EOF
# 端口跳跃配置
INTERFACE="$interface"
START_PORT="$start_port"
END_PORT="$end_port"
TARGET_PORT="$target_port"
EOF
        
        # 确保重启后规则依然生效
        if command -v iptables-save &>/dev/null; then
            if [[ -d "/etc/iptables" ]]; then
                iptables-save > "/etc/iptables/rules.v4"
            elif [[ -d "/etc/sysconfig" ]]; then
                iptables-save > "/etc/sysconfig/iptables"
            fi
        fi
        
        log_success "端口跳跃规则添加成功"
        log_info "端口范围 $start_port-$end_port 已重定向到端口 $target_port"
        return 0
    else
        log_error "端口跳跃规则添加失败"
        return 1
    fi
}

# 清除端口跳跃规则
clear_port_hopping_rules() {
    if [[ -f "/etc/hysteria/port-hopping.conf" ]]; then
        # 读取配置
        source "/etc/hysteria/port-hopping.conf"
        
        if [[ -n "$INTERFACE" && -n "$START_PORT" && -n "$END_PORT" && -n "$TARGET_PORT" ]]; then
            # 删除规则
            iptables -t nat -D PREROUTING -i "$INTERFACE" -p udp --dport "$START_PORT:$END_PORT" -j REDIRECT --to-ports "$TARGET_PORT" 2>/dev/null
            log_success "端口跳跃规则已清除"
        fi
    fi
}

# 验证域名格式
validate_domain() {
    local domain="$1"
    [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]
}

# 设置 ACME 域名
set_acme_domain() {
    echo ""
    log_info "设置 ACME 域名"
    echo "请输入解析到此服务器的域名 (例如: example.com):"
    echo -n "域名: "
    read -r domain

    if [[ -z "$domain" ]]; then
        log_error "域名不能为空"
        return 1
    fi

    if ! validate_domain "$domain"; then
        log_error "域名格式不正确"
        return 1
    fi

    # 创建目录（如果不存在）
    mkdir -p "$(dirname "$SERVER_DOMAIN_CONFIG")"
    
    # 保存域名配置
    echo "$domain" > "$SERVER_DOMAIN_CONFIG"
    log_success "ACME 域名已设置: $domain"
    
    # 更新配置文件
    if [[ -f "$CONFIG_PATH" ]]; then
        # 备份配置文件
        cp "$CONFIG_PATH" "$CONFIG_PATH.bak"
        
        # 删除现有的 TLS 配置
        sed -i '/^tls:/,/^[[:alpha:]]/{ /^tls:/d; /^[[:alpha:]]/!d; }' "$CONFIG_PATH"
        
        # 添加或更新 ACME 配置
        if grep -q "^acme:" "$CONFIG_PATH"; then
            # 更新现有 ACME 配置
            sed -i "/^acme:/,/domains:/c\\
acme:\\
  domains:\\
    - $domain\\
  email: admin@example.com" "$CONFIG_PATH"
        else
            # 添加新的 ACME 配置
            echo "" >> "$CONFIG_PATH"
            echo "acme:" >> "$CONFIG_PATH"
            echo "  domains:" >> "$CONFIG_PATH"
            echo "    - $domain" >> "$CONFIG_PATH"
            echo "  email: admin@example.com" >> "$CONFIG_PATH"
        fi
        
        log_success "配置文件已更新"
        
        # 询问是否重启服务
        echo -n "是否重启服务以应用更改? [Y/n]: "
        read -r restart
        if [[ ! $restart =~ ^[Nn]$ ]]; then
            systemctl restart hysteria-server
            log_success "服务已重启"
        fi
    fi
    
    return 0
}

# 验证域名解析
verify_domain_resolution() {
    echo ""
    log_info "验证域名解析"

    if [[ ! -f "$SERVER_DOMAIN_CONFIG" ]]; then
        log_error "未配置服务器域名"
        return 1
    fi

    local domain
    domain=$(cat "$SERVER_DOMAIN_CONFIG")
    local server_ip
    server_ip=$(curl -s --connect-timeout 5 --max-time 10 "https://ipv4.icanhazip.com" || 
                curl -s --connect-timeout 5 --max-time 10 "https://ifconfig.me/ip" || 
                curl -s --connect-timeout 5 --max-time 10 "https://ip.sb")

    echo "正在验证域名: $domain"
    echo "服务器IP: $server_ip"
    echo ""

    # 使用多种方法解析域名
    local resolved_ips=()
    local dns_tools=("dig" "nslookup" "host")
    
    for tool in "${dns_tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            local result
            case $tool in
                dig)
                    result=$(dig +short "$domain" A | head -5)
                    ;;
                nslookup)
                    result=$(nslookup "$domain" 2>/dev/null | grep "Address:" | tail -n +2 | awk '{print $2}' | head -5)
                    ;;
                host)
                    result=$(host "$domain" 2>/dev/null | grep "has address" | awk '{print $4}' | head -5)
                    ;;
            esac
            
            if [[ -n "$result" ]]; then
                echo "使用 $tool 解析结果:"
                echo "$result" | while read -r ip; do
                    if [[ -n "$ip" && "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                        if [[ "$ip" == "$server_ip" ]]; then
                            echo -e "  ${GREEN}✅ $ip (匹配)${NC}"
                        else
                            echo -e "  ${YELLOW}⚠️  $ip (不匹配)${NC}"
                        fi
                        resolved_ips+=("$ip")
                    fi
                done
                break
            fi
        fi
    done

    if [[ ${#resolved_ips[@]} -eq 0 ]]; then
        log_error "无法解析域名，可能原因:"
        echo "1. 域名DNS设置未生效"
        echo "2. 网络连接问题"
        echo "3. DNS服务器问题"
        return 1
    fi
    
    return 0
}

# 设置伪装域名
set_masquerade_domain() {
    echo ""
    log_info "设置伪装域名"
    echo "请输入伪装域名 URL (例如: https://www.bing.com):"
    echo -n "伪装URL: "
    read -r masquerade_url

    if [[ -z "$masquerade_url" ]]; then
        log_error "伪装URL不能为空"
        return
