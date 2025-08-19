#!/bin/bash

# Hysteria2 管理脚本 - 包含安装、配置、端口跳跃和域名管理
# 版本: 1.0.0

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置文件路径
CONFIG_PATH="/etc/hysteria/config.yaml"
SERVER_DOMAIN_CONFIG="/etc/hysteria/server-domain.conf"
SERVICE_NAME="hysteria-server.service"

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

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行，请使用 sudo 运行此脚本"
        exit 1
    fi
}

# 等待用户确认
wait_for_user() {
    echo ""
    read -p "按回车键继续..." -r
}

# 获取服务器IP
get_server_ip() {
    local ip=""
    local timeout=5
    
    # IP获取服务列表
    local ip_services=(
        "ipv4.icanhazip.com"
        "ifconfig.me/ip"
        "ip.sb"
        "checkip.amazonaws.com"
    )

    for service in "${ip_services[@]}"; do
        ip=$(curl -s --connect-timeout "$timeout" --max-time "$timeout" "https://$service" 2>/dev/null)
        if [[ -n "$ip" && "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "$ip"
            return
        fi
    done

    # 如果无法获取公网IP，尝试获取本地IP
    ip=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' | head -1)
    echo "${ip:-127.0.0.1}"
}

# 检查 Hysteria2 是否已安装
check_hysteria_installed() {
    command -v hysteria &> /dev/null
}

# 安装 Hysteria2
install_hysteria2() {
    log_info "开始安装 Hysteria2..."
    
    # 检查是否已安装
    if check_hysteria_installed; then
        log_info "Hysteria2 已安装，跳过安装步骤"
        return 0
    fi
    
    # 安装依赖
    log_info "安装依赖..."
    if command -v apt &>/dev/null; then
        apt update -y
        apt install -y curl wget sudo
    elif command -v yum &>/dev/null; then
        yum install -y curl wget sudo
    fi
    
    # 下载并安装 Hysteria2
    log_info "下载并安装 Hysteria2..."
    bash <(curl -fsSL https://get.hy2.sh/)
    
    if ! check_hysteria_installed; then
        log_error "Hysteria2 安装失败"
        return 1
    fi
    
    log_success "Hysteria2 安装成功"
    return 0
}

# 生成随机密码
generate_password() {
    openssl rand -base64 16 | tr -d "=+/" | cut -c1-16
}

# 生成自签名证书
generate_self_signed_cert() {
    local domain="$1"
    local cert_dir="/etc/hysteria"
    local cert_file="$cert_dir/server.crt"
    local key_file="$cert_dir/server.key"
    
    mkdir -p "$cert_dir"
    
    log_info "生成自签名证书..."
    
    openssl req -x509 -nodes -newkey rsa:2048 -keyout "$key_file" -out "$cert_file" -days 365 \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=$domain" 2>/dev/null
    
    chmod 600 "$key_file"
    chmod 644 "$cert_file"
    
    log_success "自签名证书生成成功"
}

# 配置 Hysteria2
configure_hysteria2() {
    local server_ip=$(get_server_ip)
    local password=$(generate_password)
    local listen_port=443
    local config_dir="/etc/hysteria"
    local config_file="$config_dir/config.yaml"
    
    # 创建配置目录
    mkdir -p "$config_dir"
    
    # 生成自签名证书
    generate_self_signed_cert "$server_ip"
    
    # 创建配置文件
    cat > "$config_file" << EOF
listen: :$listen_port

auth:
  type: password
  password: "$password"

masquerade:
  type: proxy
  url: https://www.bing.com

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
EOF
    
    log_success "Hysteria2 配置文件创建成功"
    log_info "配置文件: $config_file"
    log_info "密码: $password"
    log_info "端口: $listen_port"
    
    # 创建 systemd 服务
    cat > /etc/systemd/system/hysteria-server.service << EOF
[Unit]
Description=Hysteria Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
Restart=on-failure
RestartSec=5
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
    
    # 重载 systemd 并启动服务
    systemctl daemon-reload
    systemctl enable hysteria-server
    systemctl start hysteria-server
    
    # 检查服务状态
    if systemctl is-active --quiet hysteria-server; then
        log_success "Hysteria2 服务启动成功"
    else
        log_error "Hysteria2 服务启动失败"
        return 1
    fi
    
    return 0
}

# 获取当前监听端口
get_current_listen_port() {
    if [[ -f "$CONFIG_PATH" ]]; then
        grep -E "^\s*listen:" "$CONFIG_PATH" | awk -F':' '{print $3}' | tr -d ' ' || echo "443"
    else
        echo "443"
    fi
}

# 检查端口跳跃状态
check_port_hopping_status() {
    if [[ -f "/etc/hysteria/port-hopping.conf" ]]; then
        return 0
    else
        return 1
    fi
}

# 获取端口跳跃信息
get_port_hopping_info() {
    if [[ -f "/etc/hysteria/port-hopping.conf" ]]; then
        source "/etc/hysteria/port-hopping.conf" 2>/dev/null
        if [[ -n "$START_PORT" && -n "$END_PORT" && -n "$TARGET_PORT" ]]; then
            echo "端口范围 $START_PORT-$END_PORT -> 目标端口 $TARGET_PORT"
        fi
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

# 清除所有端口跳跃规则
clear_all_port_hopping_rules() {
    # 清理所有REDIRECT规则
    local rules_cleared=0
    while IFS= read -r line_num; do
        if [[ -n "$line_num" ]]; then
            if iptables -t nat -D PREROUTING "$line_num" 2>/dev/null; then
                ((rules_cleared++))
            fi
        fi
    done < <(iptables -t nat -L PREROUTING --line-numbers 2>/dev/null | grep "REDIRECT.*--to-ports" | awk '{print $1}' | tac)
    
    if [[ $rules_cleared -gt 0 ]]; then
        log_success "清理了 $rules_cleared 条端口跳跃规则"
    else
        log_info "没有找到端口跳跃规则"
    fi
    
    # 删除配置文件
    rm -f "/etc/hysteria/port-hopping.conf" 2>/dev/null
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
    server_ip=$(get_server_ip)

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
        return 1
    fi

    # 验证URL格式
    if [[ ! "$masquerade_url" =~ ^https?:// ]]; then
        masquerade_url="https://$masquerade_url"
    fi

    # 备份配置文件
    if [[ -f "$CONFIG_PATH" ]]; then
        cp "$CONFIG_PATH" "$CONFIG_PATH.bak"
        
        # 更新或添加伪装域名配置
        if grep -q "masquerade:" "$CONFIG_PATH"; then
            # 更新现有配置
            sed -i "/masquerade:/,/url:/s|url:.*|url: $masquerade_url|" "$CONFIG_PATH"
        else
            # 添加新配置
            echo "" >> "$CONFIG_PATH"
            echo "masquerade:" >> "$CONFIG_PATH"
            echo "  type: proxy" >> "$CONFIG_PATH"
            echo "  url: $masquerade_url" >> "$CONFIG_PATH"
        fi
        
        log_success "伪装域名已设置: $masquerade_url"
        
        # 询问是否重启服务
        echo -n "是否重启服务以应用更改? [Y/n]: "
        read -r restart
        if [[ ! $restart =~ ^[Nn]$ ]]; then
            systemctl restart hysteria-server
            log_success "服务已重启"
        fi
    else
        log_error "配置文件不存在"
        return 1
    fi
    
    return 0
}

# 测试伪装域名连通性
test_masquerade_connectivity() {
    local url="$1"
    local domain
    domain=$(echo "$url" | sed 's|https\?://||' | sed 's|/.*||')
    
    echo "正在测试 $url..."
    
    # 测试HTTP连接
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "$url" 2>/dev/null)
    
    if [[ "$http_code" =~ ^[23] ]]; then
        echo -e "${GREEN}✅ HTTP连接测试成功 (状态码: $http_code)${NC}"
    else
        echo -e "${YELLOW}⚠️  HTTP连接测试异常 (状态码: $http_code)${NC}"
    fi
    
    # 测试DNS解析
    if command -v dig &> /dev/null; then
        local ip
        ip=$(dig +short "$domain" A 2>/dev/null | head -1)
        if [[ -n "$ip" && "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo -e "${GREEN}✅ DNS解析成功: $ip${NC}"
        else
            echo -e "${RED}❌ DNS解析失败${NC}"
        fi
    fi
}

# 显示客户端配置
show_client_config() {
    local server_ip=$(get_server_ip)
    local password=""
    local listen_port=$(get_current_listen_port)
    local server_domain=""
    
    # 从配置文件中获取密码
    if [[ -f "$CONFIG_PATH" ]]; then
        password=$(grep -E "^\s*password:" "$CONFIG_PATH" | awk '{print $2}' | tr -d '"')
    fi
    
    # 获取域名
    if [[ -f "$SERVER_DOMAIN_CONFIG" ]]; then
        server_domain=$(cat "$SERVER_DOMAIN_CONFIG")
    fi
    
    if [[ -z "$password" ]]; then
        log_error "无法获取密码，请检查配置文件"
        return 1
    fi
    
    echo ""
    echo -e "${YELLOW}===== Hysteria2 客户端配置 =====${NC}"
    echo ""
    echo -e "${GREEN}服务器信息:${NC}"
    echo "服务器地址: ${server_domain:-$server_ip}"
    echo "服务器端口: $listen_port"
    echo "认证密码: $password"
    
    # 检查端口跳跃配置
    if check_port_hopping_status; then
        local hopping_info=$(get_port_hopping_info)
        if [[ -n "$hopping_info" ]]; then
            echo -e "${YELLOW}端口跳跃:${NC} 已启用 ($hopping_info)"
        fi
    fi
    
    echo ""
    echo -e "${GREEN}客户端配置示例:${NC}"
    echo ""
    echo "```yaml"
    cat << EOF
server: ${server_domain:-$server_ip}:$listen_port
auth: $password

bandwidth:
  up: 100 mbps
  down: 100 mbps

tls:
  sni: ${server_domain:-$server_ip}
EOF

    # 如果使用自签名证书，添加 insecure 选项
    if ! grep -q "^acme:" "$CONFIG_PATH" 2>/dev/null; then
        echo "  insecure: true  # 自签名证书需要设置为 true"
    fi

    cat << EOF

socks5:
  listen: 127.0.0.1:1080
EOF
    echo "```"
    echo ""
    
    # 如果使用自签名证书，添加提示
    if ! grep -q "^acme:" "$CONFIG_PATH" 2>/dev/null; then
        echo -e "${YELLOW}注意: 由于使用自签名证书，客户端需要设置 insecure: true${NC}"
    fi
    
    echo ""
}

# 端口跳跃管理菜单
port_hopping_menu() {
    while true; do
        clear
        echo -e "${CYAN}===== Hysteria2 端口跳跃管理 =====${NC}"
        echo ""
        
        # 显示当前端口跳跃状态
        echo -e "${YELLOW}当前端口跳跃状态:${NC}"
        local current_port=$(get_current_listen_port)
        echo -e "监听端口: ${GREEN}$current_port${NC}"
        
        if check_port_hopping_status; then
            local hopping_info=$(get_port_hopping_info)
            echo -e "端口跳跃: ${GREEN}✅ 已启用${NC}"
            if [[ -n "$hopping_info" ]]; then
                echo "   $hopping_info"
            fi
        else
            echo -e "端口跳跃: ${YELLOW}❌ 未启用${NC}"
        fi
        
        echo ""
        echo -e "${YELLOW}端口跳跃管理选项:${NC}"
        echo "1. 启用端口跳跃"
        echo "2. 禁用端口跳跃"
        echo "3. 查看端口跳跃详情"
        echo "0. 返回主菜单"
        echo ""
        echo -n "请选择操作 [0-3]: "
        read -r choice
        
        case $choice in
            1)
                echo ""
                echo "配置端口跳跃范围:"
                echo -n "起始端口 (默认 20000): "
                read -r start_port
                start_port=${start_port:-20000}
                
                echo -n "结束端口 (默认 50000): "
                read -r end_port
                end_port=${end_port:-50000}
                
                # 验证端口范围
                if [[ ! "$start_port" =~ ^[0-9]+$ ]] || [[ ! "$end_port" =~ ^[0-9]+$ ]] || 
                   [[ "$start_port" -lt 1 ]] || [[ "$end_port" -gt 65535 ]] || 
                   [[ "$start_port" -ge "$end_port" ]]; then
                    log_error "端口范围无效"
                    wait_for_user
                    continue
                fi
                
                current_port=$(get_current_listen_port)
                add_port_hopping_rules "$start_port" "$end_port" "$current_port"
                wait_for_user
                ;;
            2)
                clear_all_port_hopping_rules
                wait_for_user
                ;;
            3)
                echo ""
                echo -e "${YELLOW}当前端口跳跃配置:${NC}"
                if [[ -f "/etc/hysteria/port-hopping.conf" ]]; then
                    cat "/etc/hysteria/port-hopping.conf"
                    
                    echo ""
                    echo -e "${YELLOW}iptables 规则:${NC}"
                    iptables -t nat -L PREROUTING -n | grep "REDIRECT"
                else
                    echo "未配置端口跳跃"
                fi
                wait_for_user
                ;;
            0)
                break
                ;;
            *)
                log_error "无效选项"
                wait_for_user
                ;;
        esac
    done
}

# 域名管理菜单
domain_management_menu() {
    while true; do
        clear
        echo -e "${CYAN}===== Hysteria2 域名管理 =====${NC}"
        echo ""
        
        # 显示当前域名配置状态
        echo -e "${YELLOW}当前域名配置状态:${NC}"
        
        # 检查ACME域名
        if [[ -f "$SERVER_DOMAIN_CONFIG" ]]; then
            local acme_domain
            acme_domain=$(cat "$SERVER_DOMAIN_CONFIG")
            echo -e "ACME域名: ${GREEN}$acme_domain${NC}"
        else
            echo -e "ACME域名: ${YELLOW}未配置${NC}"
        fi
        
        # 检查伪装域名
        local masquerade_domain=""
        if [[ -f "$CONFIG_PATH" ]]; then
            masquerade_domain=$(grep -A 3 "masquerade:" "$CONFIG_PATH" 2>/dev/null | grep "url:" | awk '{print $2}' | sed 's|https\?://||' | sed 's|/.*||')
        fi
        
        if [[ -n "$masquerade_domain" ]]; then
            echo -e "伪装域名: ${GREEN}$masquerade_domain${NC}"
        else
            echo -e "伪装域名: ${YELLOW}未配置${NC}"
        fi
        
        echo ""
        echo -e "${YELLOW}域名管理选项:${NC}"
        echo "1. 设置 ACME 域名"
        echo "2. 验证 ACME 域名解析"
        echo "3. 设置伪装域名"
        echo "4. 测试伪装域名连通性"
        echo "0. 返回主菜单"
        echo ""
        echo -n "请选择操作 [0-4]: "
        read -r choice
        
        case $choice in
            1)
                set_acme_domain
                wait_for_user
                ;;
            2)
                verify_domain_resolution
                wait_for_user
                ;;
            3)
                set_masquerade_domain
                wait_for_user
                ;;
            4)
                if [[ -f "$CONFIG_PATH" ]]; then
                    local masquerade_url
                    masquerade_url=$(grep -A 3 "masquerade:" "$CONFIG_PATH" 2>/dev/null | grep "url:" | awk '{print $2}')
                    if [[ -n "$masquerade_url" ]]; then
                        test_masquerade_connectivity "$masquerade_url"
                    else
                        log_error "未配置伪装域名"
                    fi
                else
                    log_error "配置文件不存在"
                fi
                wait_for_user
                ;;
            0)
                break
                ;;
            *)
                log_error "无效选项"
                wait_for_user
                ;;
        esac
    done
}

# 服务管理菜单
service_management_menu() {
    while true; do
        clear
        echo -e "${CYAN}===== Hysteria2 服务管理 =====${NC}"
        echo ""
        
        # 显示当前服务状态
        echo -e "${YELLOW}当前服务状态:${NC}"
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            echo -e "服务状态: ${GREEN}✅ 运行中${NC}"
        else
            echo -e "服务状态: ${RED}❌ 未运行${NC}"
        fi
        
        if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
            echo -e "开机启动: ${GREEN}✅ 已
