#!/bin/bash

# 一键无交互轻便脚本，内核Xray，Cloudflared-argo内核自动搭
# 支持Linux类主流VPS系统，SSH脚本支持非root环境运行
# By: djkyc $(date +%Y-%m-%d)

# 定义颜色
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

# 显示欢迎信息
echo -e "${GREEN}欢迎使用Xray+Argo一键安装脚本${PLAIN}"
echo -e "${GREEN}By: djkyc    $(date +%Y-%m-%d)${PLAIN}"
echo -e "————————————————————————————————————"

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${YELLOW}当前非root用户，部分功能可能受限${PLAIN}"
        SUDO="sudo"
    else
        SUDO=""
    fi
}

# 检查系统类型
check_system() {
    if [[ -f /etc/redhat-release ]]; then
        RELEASE="centos"
        PACKAGE_MANAGER="yum"
        PACKAGE_UPDATE="yum -y update"
        PACKAGE_INSTALL="yum -y install"
    elif cat /etc/issue | grep -Eqi "debian"; then
        RELEASE="debian"
        PACKAGE_MANAGER="apt"
        PACKAGE_UPDATE="apt update -y"
        PACKAGE_INSTALL="apt install -y"
    elif cat /etc/issue | grep -Eqi "ubuntu"; then
        RELEASE="ubuntu"
        PACKAGE_MANAGER="apt"
        PACKAGE_UPDATE="apt update -y"
        PACKAGE_INSTALL="apt install -y"
    elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
        RELEASE="centos"
        PACKAGE_MANAGER="yum"
        PACKAGE_UPDATE="yum -y update"
        PACKAGE_INSTALL="yum -y install"
    elif cat /proc/version | grep -Eqi "debian"; then
        RELEASE="debian"
        PACKAGE_MANAGER="apt"
        PACKAGE_UPDATE="apt update -y"
        PACKAGE_INSTALL="apt install -y"
    elif cat /proc/version | grep -Eqi "ubuntu"; then
        RELEASE="ubuntu"
        PACKAGE_MANAGER="apt"
        PACKAGE_UPDATE="apt update -y"
        PACKAGE_INSTALL="apt install -y"
    elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
        RELEASE="centos"
        PACKAGE_MANAGER="yum"
        PACKAGE_UPDATE="yum -y update"
        PACKAGE_INSTALL="yum -y install"
    else
        echo -e "${RED}未检测到系统版本，请联系脚本作者！${PLAIN}" && exit 1
    fi

    echo -e "${GREEN}检测到系统为: ${RELEASE}${PLAIN}"
}

# 安装基础依赖
install_base() {
    echo -e "${GREEN}开始安装基础依赖...${PLAIN}"
    if [[ "${PACKAGE_MANAGER}" == "yum" ]]; then
        ${SUDO} ${PACKAGE_INSTALL} curl wget tar socat jq openssl iputils net-tools
    else
        ${SUDO} ${PACKAGE_UPDATE}
        ${SUDO} ${PACKAGE_INSTALL} curl wget tar socat jq openssl iproute2 net-tools
    fi
    echo -e "${GREEN}基础依赖安装完成${PLAIN}"
}

# 获取服务器IP地址
get_ip() {
    IP=$(curl -s4m8 https://ip.gs) || IP=$(curl -s6m8 https://ip.gs)
    if [[ -z "${IP}" ]]; then
        IP=$(curl -s4m8 https://ifconfig.co) || IP=$(curl -s6m8 https://ifconfig.co)
    fi
    echo -e "${GREEN}当前服务器IP: ${IP}${PLAIN}"
}

# 安装Xray
install_xray() {
    echo -e "${GREEN}开始安装Xray...${PLAIN}"
    
    # 检查是否已安装
    if [[ -f "/usr/local/bin/xray" ]]; then
        echo -e "${YELLOW}检测到Xray已安装，跳过安装步骤${PLAIN}"
        return
    fi
    
    # 下载并安装Xray
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    
    # 检查安装结果
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Xray安装失败，请检查网络或手动安装${PLAIN}"
        exit 1
    fi
    
    echo -e "${GREEN}Xray安装成功${PLAIN}"
}

# 安装Cloudflared
install_cloudflared() {
    echo -e "${GREEN}开始安装Cloudflared...${PLAIN}"
    
    # 检查是否已安装
    if [[ -f "/usr/local/bin/cloudflared" ]]; then
        echo -e "${YELLOW}检测到Cloudflared已安装，跳过安装步骤${PLAIN}"
        return
    fi
    
    # 根据系统架构下载对应版本
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64)
            ARCH="arm64"
            ;;
        *)
            echo -e "${RED}不支持的系统架构: ${ARCH}${PLAIN}"
            exit 1
            ;;
    esac
    
    # 下载并安装Cloudflared
    ${SUDO} curl -Lo /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}
    ${SUDO} chmod +x /usr/local/bin/cloudflared
    
    # 检查安装结果
    if [[ ! -f "/usr/local/bin/cloudflared" ]]; then
        echo -e "${RED}Cloudflared安装失败，请检查网络或手动安装${PLAIN}"
        exit 1
    fi
    
    echo -e "${GREEN}Cloudflared安装成功${PLAIN}"
}

# 安装WARP
install_warp() {
    echo -e "${GREEN}开始安装WARP...${PLAIN}"
    
    # 检查是否已安装
    if [[ -f "/usr/bin/warp-cli" ]]; then
        echo -e "${YELLOW}检测到WARP已安装，跳过安装步骤${PLAIN}"
        return
    fi
    
    # 下载并安装WARP
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | ${SUDO} gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | ${SUDO} tee /etc/apt/sources.list.d/cloudflare-client.list
    ${SUDO} ${PACKAGE_UPDATE}
    ${SUDO} ${PACKAGE_INSTALL} cloudflare-warp
    
    # 检查安装结果
    if [[ ! -f "/usr/bin/warp-cli" ]]; then
        echo -e "${RED}WARP安装失败，请检查网络或手动安装${PLAIN}"
        exit 1
    fi
    
    # 配置WARP
    ${SUDO} warp-cli register
    ${SUDO} warp-cli set-mode proxy
    ${SUDO} warp-cli connect
    
    echo -e "${GREEN}WARP安装成功${PLAIN}"
}

# 生成随机UUID
generate_uuid() {
    echo $(cat /proc/sys/kernel/random/uuid)
}

# 生成随机端口
generate_port() {
    echo $(shuf -i 10000-65535 -n 1)
}

# 获取用户输入的端口或使用随机端口
get_port() {
    local random_port=$(generate_port)
    echo -e "${GREEN}端口号 [1-65535] 自定义natvps或直接回车使用随机端口 ${random_port}:${PLAIN}"
    read -p "" input_port
    
    if [[ -z "$input_port" ]]; then
        echo -e "${GREEN}使用随机端口: ${random_port}${PLAIN}"
        echo $random_port
    else
        if ! [[ "$input_port" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}错误: 端口号必须是数字，将使用随机端口 ${random_port}${PLAIN}"
            echo $random_port
        elif [ "$input_port" -lt 1 ] || [ "$input_port" -gt 65535 ]; then
            echo -e "${RED}错误: 端口号必须在1-65535之间，将使用随机端口 ${random_port}${PLAIN}"
            echo $random_port
        else
            echo -e "${GREEN}使用自定义端口: ${input_port}${PLAIN}"
            echo $input_port
        fi
    fi
}

# 配置Xray
configure_xray() {
    echo -e "${GREEN}开始配置Xray...${PLAIN}"
    
    # 生成随机参数
    UUID=$(generate_uuid)
    
    # 显示端口选择提示
    echo -e "${GREEN}端口设置选择:${PLAIN}"
    PORT=$(get_port)
    
    # 验证端口号
    if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}错误: 端口号无效，将使用默认端口 443${PLAIN}"
        PORT=443
    fi
    
    # 创建配置目录
    ${SUDO} mkdir -p /usr/local/etc/xray
    
    # 创建基础配置文件
    cat > /tmp/config.json << EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF
    
    ${SUDO} mv /tmp/config.json /usr/local/etc/xray/config.json
    
    echo -e "${GREEN}Xray基础配置完成${PLAIN}"
    
    # 返回生成的UUID和端口
    echo "$UUID $PORT"
}

# 配置Argo隧道
configure_argo() {
    echo -e "${GREEN}开始配置Argo隧道...${PLAIN}"
    
    # 生成随机隧道名称
    TUNNEL_NAME="tunnel-$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)"
    
    # 创建临时隧道
    echo -e "${YELLOW}创建Argo临时隧道...${PLAIN}"
    ARGO_PORT=$1
    
    # 启动Argo隧道服务
    nohup ${SUDO} cloudflared tunnel --url http://localhost:${ARGO_PORT} > /tmp/argo.log 2>&1 &
    
    # 等待隧道建立
    sleep 3
    
    # 获取隧道地址
    ARGO_DOMAIN=$(grep -o "https://.*trycloudflare.com" /tmp/argo.log | head -n 1)
    
    if [[ -z "${ARGO_DOMAIN}" ]]; then
        echo -e "${RED}Argo隧道创建失败，请检查日志: /tmp/argo.log${PLAIN}"
        exit 1
    fi
    
    echo -e "${GREEN}Argo隧道创建成功: ${ARGO_DOMAIN}${PLAIN}"
    
    # 返回隧道域名
    echo "$ARGO_DOMAIN"
}

# 配置VLESS+Reality+Vision
configure_vless_reality_vision() {
    echo -e "${GREEN}开始配置VLESS+Reality+Vision...${PLAIN}"
    
    # 获取参数
    UUID=$1
    PORT=$2
    
    # 生成私钥和公钥
    if command -v xray &> /dev/null; then
        ${SUDO} xray x25519 > /tmp/x25519.keys 2>/dev/null
        PRIVATE_KEY=$(cat /tmp/x25519.keys | grep Private | awk '{print $3}')
        PUBLIC_KEY=$(cat /tmp/x25519.keys | grep Public | awk '{print $3}')
    else
        # 如果xray命令不可用，使用openssl生成密钥
        PRIVATE_KEY=$(openssl rand -base64 32)
        PUBLIC_KEY=$(openssl rand -base64 32)
    fi
    
    # 生成短ID
    SHORT_ID=$(openssl rand -hex 8)
    
    # 配置Xray
    cat > /tmp/vless_reality_vision.json << EOF
{
  "inbounds": [
    {
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "www.microsoft.com:443",
          "xver": 0,
          "serverNames": [
            "www.microsoft.com"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [
            "${SHORT_ID}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls"
        ]
      }
    }
  ]
}
EOF
    
    # 合并配置
    if ${SUDO} jq -s '.[0].inbounds += .[1].inbounds | .[0]' /usr/local/etc/xray/config.json /tmp/vless_reality_vision.json > /tmp/merged_config.json 2>/dev/null; then
        ${SUDO} mv /tmp/merged_config.json /usr/local/etc/xray/config.json
    else
        echo -e "${YELLOW}配置合并失败，使用新配置覆盖...${PLAIN}"
        ${SUDO} cp /tmp/vless_reality_vision.json /usr/local/etc/xray/config.json
    fi
    
    # 重启Xray服务
    ${SUDO} systemctl restart xray
    
    # 返回配置信息
    echo "$PUBLIC_KEY $SHORT_ID"
}

# 配置VMess+WebSocket
configure_vmess_ws() {
    echo -e "${GREEN}开始配置VMess+WebSocket...${PLAIN}"
    
    # 获取参数
    UUID=$1
    PORT=$2
    ARGO_DOMAIN=$3
    
    # 提取Argo域名的主机部分
    ARGO_HOST=$(echo $ARGO_DOMAIN | awk -F[/:] '{print $4}')
    
    # 配置Xray
    cat > /tmp/vmess_ws.json << EOF
{
  "inbounds": [
    {
      "port": ${PORT},
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${UUID}"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vmess"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls"
        ]
      }
    }
  ]
}
EOF
    
    # 合并配置
    ${SUDO} jq -s '.[0].inbounds += .[1].inbounds | .[0]' /usr/local/etc/xray/config.json /tmp/vmess_ws.json > /tmp/merged_config.json
    ${SUDO} mv /tmp/merged_config.json /usr/local/etc/xray/config.json
    
    # 重启Xray服务
    ${SUDO} systemctl restart xray
    
    # 返回配置信息
    echo "$ARGO_HOST"
}

# 生成节点链接
generate_link() {
    local protocol=$1
    local server_ip=$2
    local port=$3
    
    # 确保参数是数字
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo "错误: 端口号必须是数字"
        return 1
    fi
    
    case $protocol in
        "VLESS+Reality+Vision")
            local uuid=$4
            local public_key=$5
            local short_id=$6
            echo "vless://${uuid}@${server_ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#VLESS-Reality-Vision"
            ;;
        "VMess+WebSocket")
            local uuid=$4
            local argo_host=$5
            # 生成VMess配置JSON
            local vmess_config="{\"v\":\"2\",\"ps\":\"VMess-WebSocket-Argo\",\"add\":\"${argo_host}\",\"port\":443,\"id\":\"${uuid}\",\"aid\":0,\"net\":\"ws\",\"type\":\"none\",\"host\":\"${argo_host}\",\"path\":\"/vmess\",\"tls\":\"tls\",\"sni\":\"${argo_host}\"}"
            # Base64编码
            echo "vmess://$(echo -n "$vmess_config" | base64 | tr -d '\n')"
            ;;
        "Shadowsocks-2022")
            local password=$4
            # 使用标准Base64编码
            local method_password="2022-blake3-aes-128-gcm:${password}"
            local userinfo=$(echo -n "${method_password}" | base64 | tr -d '\n')
            echo "ss://${userinfo}@${server_ip}:${port}#Shadowsocks-2022"
            ;;
    esac
}

# 显示连接信息
show_connection_info() {
    echo -e "\n${GREEN}============安装完成============${PLAIN}"
    echo -e "${GREEN}协议: $1${PLAIN}"
    echo -e "${GREEN}服务器: $2${PLAIN}"
    echo -e "${GREEN}端口: $3${PLAIN}"
    
    # 生成并显示节点链接
    echo -e "\n${GREEN}V2rayN节点链接:${PLAIN}"
    local link=""
    case $1 in
        "VLESS+Reality+Vision")
            link=$(generate_link "$1" "$2" "$3" "$4" "$5" "$6")
            ;;
        "VMess+WebSocket")
            link=$(generate_link "$1" "$2" "$3" "$4" "$5")
            ;;
        "Shadowsocks-2022")
            link=$(generate_link "$1" "$2" "$3" "$4")
            ;;
    esac
    
    echo -e "${YELLOW}${link}${PLAIN}"
    
    echo -e "\n${GREEN}===============================${PLAIN}"
    echo -e "${GREEN}请复制上方链接到V2rayN客户端导入使用${PLAIN}"
    echo -e "${GREEN}By: djkyc    $(date +%Y-%m-%d)${PLAIN}"
    echo -e "${GREEN}===============================${PLAIN}"
}

# 生成Clash配置
generate_clash_config() {
    local protocol=$1
    local server_ip=$2
    local port=$3
    local clash_file="clash_${protocol// /_}_config.yaml"
    
    # 创建基础Clash配置
    cat > ${clash_file} << EOF
port: 7890
socks-port: 7891
allow-lan: true
mode: Rule
log-level: info
external-controller: 127.0.0.1:9090
proxies:
EOF
    
    # 根据协议添加不同的代理配置
    case $protocol in
        "VLESS+Reality+Vision")
            UUID=$4
            PUBLIC_KEY=$5
            SHORT_ID=$6
            cat >> ${clash_file} << EOF
  - name: VLESS-Reality-Vision
    type: vless
    server: ${server_ip}
    port: ${port}
    uuid: ${UUID}
    network: tcp
    tls: true
    udp: true
    flow: xtls-rprx-vision
    servername: www.microsoft.com
    reality-opts:
      public-key: ${PUBLIC_KEY}
      short-id: ${SHORT_ID}
    client-fingerprint: chrome
EOF
            ;;
        "VMess+WebSocket")
            UUID=$4
            ARGO_HOST=$5
            cat >> ${clash_file} << EOF
  - name: VMess-WebSocket-Argo
    type: vmess
    server: ${ARGO_HOST}
    port: 443
    uuid: ${UUID}
    alterId: 0
    cipher: auto
    udp: true
    tls: true
    network: ws
    ws-opts:
      path: /vmess
      headers:
        Host: ${ARGO_HOST}
    servername: ${ARGO_HOST}
EOF
            ;;
        "Shadowsocks-2022")
            PASSWORD=$4
            cat >> ${clash_file} << EOF
  - name: Shadowsocks-2022
    type: ss
    server: ${server_ip}
    port: ${port}
    cipher: 2022-blake3-aes-128-gcm
    password: ${PASSWORD}
    udp: true
EOF
            ;;
    esac
    
    # 添加代理组和规则
    cat >> ${clash_file} << EOF

proxy-groups:
  - name: 🚀 节点选择
    type: select
    proxies:
      - 自动选择
      - DIRECT
EOF
    
    # 添加对应的代理名称
    case $protocol in
        "VLESS+Reality+Vision")
            echo "      - VLESS-Reality-Vision" >> ${clash_file}
            ;;
        "VMess+WebSocket")
            echo "      - VMess-WebSocket-Argo" >> ${clash_file}
            ;;
        "Shadowsocks-2022")
            echo "      - Shadowsocks-2022" >> ${clash_file}
            ;;
    esac
    
    # 继续添加其他代理组和规则
    cat >> ${clash_file} << EOF
  - name: 自动选择
    type: url-test
    url: http://www.gstatic.com/generate_204
    interval: 300
    tolerance: 50
    proxies:
EOF
    
    # 添加对应的代理名称
    case $protocol in
        "VLESS+Reality+Vision")
            echo "      - VLESS-Reality-Vision" >> ${clash_file}
            ;;
        "VMess+WebSocket")
            echo "      - VMess-WebSocket-Argo" >> ${clash_file}
            ;;
        "Shadowsocks-2022")
            echo "      - Shadowsocks-2022" >> ${clash_file}
            ;;
    esac
    
    # 添加规则
    cat >> ${clash_file} << EOF
rules:
  - DOMAIN-SUFFIX,google.com,🚀 节点选择
  - DOMAIN-SUFFIX,facebook.com,🚀 节点选择
  - DOMAIN-SUFFIX,youtube.com,🚀 节点选择
  - DOMAIN-SUFFIX,netflix.com,🚀 节点选择
  - DOMAIN-SUFFIX,spotify.com,🚀 节点选择
  - DOMAIN-SUFFIX,telegram.org,🚀 节点选择
  - DOMAIN-KEYWORD,google,🚀 节点选择
  - DOMAIN-KEYWORD,facebook,🚀 节点选择
  - DOMAIN-KEYWORD,youtube,🚀 节点选择
  - DOMAIN-KEYWORD,twitter,🚀 节点选择
  - DOMAIN-KEYWORD,instagram,🚀 节点选择
  - DOMAIN-KEYWORD,telegram,🚀 节点选择
  - IP-CIDR,192.168.0.0/16,DIRECT
  - IP-CIDR,10.0.0.0/8,DIRECT
  - IP-CIDR,172.16.0.0/12,DIRECT
  - IP-CIDR,127.0.0.0/8,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,🚀 节点选择
EOF
    
    # 不显示生成提示信息
}

# 生成客户端配置
generate_client_config() {
    local protocol=$1
    local server_ip=$2
    local port=$3
    local config_file="client_${protocol// /_}_config.json"
    
    case $protocol in
        "VLESS+Reality+Vision")
            UUID=$4
            PUBLIC_KEY=$5
            SHORT_ID=$6
            cat > ${config_file} << EOF
{
  "outbounds": [
    {
      "type": "vless",
      "tag": "proxy",
      "server": "${server_ip}",
      "server_port": ${port},
      "uuid": "${UUID}",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "www.microsoft.com",
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
        "reality": {
          "enabled": true,
          "public_key": "${PUBLIC_KEY}",
          "short_id": "${SHORT_ID}"
        }
      }
    }
  ]
}
EOF
            ;;
        "VMess+WebSocket")
            UUID=$4
            ARGO_HOST=$5
            cat > ${config_file} << EOF
{
  "outbounds": [
    {
      "type": "vmess",
      "tag": "proxy",
      "server": "${ARGO_HOST}",
      "server_port": 443,
      "uuid": "${UUID}",
      "security": "auto",
      "transport": {
        "type": "ws",
        "path": "/vmess"
      },
      "tls": {
        "enabled": true,
        "server_name": "${ARGO_HOST}",
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        }
      }
    }
  ]
}
EOF
            ;;
        "Shadowsocks-2022")
            PASSWORD=$4
            cat > ${config_file} << EOF
{
  "outbounds": [
    {
      "type": "shadowsocks",
      "tag": "proxy",
      "server": "${server_ip}",
      "server_port": ${port},
      "method": "2022-blake3-aes-128-gcm",
      "password": "${PASSWORD}"
    }
  ]
}
EOF
            ;;
    esac
    
    # 同时生成Clash配置，但不显示提示信息
    generate_clash_config "$protocol" "$server_ip" "$port" "$4" "$5" "$6"
}

# 安装Shadowsocks-2022
install_ss2022() {
    # 检查系统环境
    check_root
    check_system
    install_base
    get_ip
    
    # 安装Xray
    install_xray
    
    # 提示用户输入端口
    echo -e "${GREEN}开始安装 Shadowsocks-2022...${PLAIN}"
    
    # 配置Xray
    XRAY_CONFIG=$(configure_xray)
    UUID=$(echo $XRAY_CONFIG | awk '{print $1}')
    PORT=$(echo $XRAY_CONFIG | awk '{print $2}')
    
    # 验证端口号
    if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}错误: 端口号无效，将使用默认端口 443${PLAIN}"
        PORT=443
    fi
    
    # 配置Shadowsocks-2022
    PASSWORD=$(configure_ss2022 $PORT)
    
    # 显示连接信息
    show_connection_info "Shadowsocks-2022" $IP $PORT $PASSWORD
}

# 配置Shadowsocks-2022
configure_ss2022() {
    echo -e "${GREEN}开始配置Shadowsocks-2022...${PLAIN}"
    
    # 获取参数
    PORT=$1
    
    # 生成随机密码
    PASSWORD=$(openssl rand -base64 16)
    
    # 配置Xray
    cat > /tmp/ss2022.json << EOF
{
  "inbounds": [
    {
      "port": ${PORT},
      "protocol": "shadowsocks",
      "settings": {
        "method": "2022-blake3-aes-128-gcm",
        "password": "${PASSWORD}",
        "network": "tcp,udp"
      }
    }
  ]
}
EOF
    
    # 合并配置
    ${SUDO} jq -s '.[0].inbounds += .[1].inbounds | .[0]' /usr/local/etc/xray/config.json /tmp/ss2022.json > /tmp/merged_config.json
    ${SUDO} mv /tmp/merged_config.json /usr/local/etc/xray/config.json
    
    # 重启Xray服务
    ${SUDO} systemctl restart xray
    
    # 返回配置信息
    echo "${PASSWORD}"
}

# 主菜单
show_menu() {
    echo -e "
  ${GREEN}一键无交互轻便脚本，内核Xray，Cloudflared-argo内核自动搭${PLAIN}
  ${GREEN}支持Linux类主流VPS系统，SSH脚本支持非root环境运行${PLAIN}
  ${GREEN}By: djkyc    $(date +%Y-%m-%d)${PLAIN}
  ————————————————————————————————————
  ${GREEN}0.${PLAIN} 退出脚本
  ————————————————————————————————————
  ${YELLOW}【安装选项】${PLAIN}
  ${GREEN}1.${PLAIN} 安装 VLESS+Reality+Vision
  ${GREEN}2.${PLAIN} 安装 VMess+WebSocket+Argo
  ${GREEN}3.${PLAIN} 安装 Shadowsocks-2022
  ${GREEN}4.${PLAIN} 安装 WARP全局出站
  ————————————————————————————————————
  ${YELLOW}【修改选项】${PLAIN}
  ${GREEN}5.${PLAIN} 修改端口配置
  ${GREEN}6.${PLAIN} 查看当前配置
  ${GREEN}7.${PLAIN} 重新生成节点链接
  ————————————————————————————————————
  ${YELLOW}【卸载选项】${PLAIN}
  ${GREEN}8.${PLAIN} 重置所有配置
  ${GREEN}9.${PLAIN} 完全卸载所有组件
  ————————————————————————————————————
  "
    echo && read -p "请输入选择 [0-9]: " num
    case "${num}" in
        0) exit 0
        ;;
        1) install_vless_reality_vision
        ;;
        2) install_vmess_ws_argo
        ;;
        3) install_ss2022
        ;;
        4) install_warp
        ;;
        5) modify_port
        ;;
        6) show_current_config
        ;;
        7) regenerate_links
        ;;
        8) reset_all
        ;;
        9) uninstall_all
        ;;
        *) echo -e "${RED}请输入正确的数字 [0-9]${PLAIN}"
        ;;
    esac
}

# 安装VLESS+Reality+Vision
install_vless_reality_vision() {
    # 检查系统环境
    check_root
    check_system
    install_base
    get_ip
    
    # 安装Xray
    install_xray
    
    # 提示用户输入端口
    echo -e "${GREEN}开始安装 VLESS+Reality+Vision...${PLAIN}"
    
    # 配置Xray
    XRAY_CONFIG=$(configure_xray)
    UUID=$(echo $XRAY_CONFIG | awk '{print $1}')
    PORT=$(echo $XRAY_CONFIG | awk '{print $2}')
    
    # 验证端口号
    if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}错误: 端口号无效，将使用默认端口 443${PLAIN}"
        PORT=443
    fi
    
    # 配置VLESS+Reality+Vision
    REALITY_CONFIG=$(configure_vless_reality_vision $UUID $PORT)
    PUBLIC_KEY=$(echo $REALITY_CONFIG | awk '{print $1}')
    SHORT_ID=$(echo $REALITY_CONFIG | awk '{print $2}')
    
    # 显示连接信息
    show_connection_info "VLESS+Reality+Vision" $IP $PORT $UUID $PUBLIC_KEY $SHORT_ID
}

# 安装VMess+WebSocket+Argo
install_vmess_ws_argo() {
    # 检查系统环境
    check_root
    check_system
    install_base
    get_ip
    
    # 安装Xray和Cloudflared
    install_xray
    install_cloudflared
    
    # 提示用户输入端口
    echo -e "${GREEN}开始安装 VMess+WebSocket+Argo...${PLAIN}"
    
    # 配置Xray
    XRAY_CONFIG=$(configure_xray)
    UUID=$(echo $XRAY_CONFIG | awk '{print $1}')
    PORT=$(echo $XRAY_CONFIG | awk '{print $2}')
    
    # 验证端口号
    if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}错误: 端口号无效，将使用默认端口 443${PLAIN}"
        PORT=443
    fi
    
    # 配置Argo隧道
    ARGO_DOMAIN=$(configure_argo $PORT)
    
    # 配置VMess+WebSocket
    ARGO_HOST=$(configure_vmess_ws $UUID $PORT $ARGO_DOMAIN)
    
    # 显示连接信息
    show_connection_info "VMess+WebSocket" $IP $PORT $UUID $ARGO_HOST
}

# 修改端口配置
modify_port() {
    echo -e "${GREEN}修改端口配置${PLAIN}"
    echo -e "${YELLOW}注意: 修改端口后需要重新生成节点链接${PLAIN}"
    
    # 检查是否有配置文件
    if [[ ! -f "/usr/local/etc/xray/config.json" ]]; then
        echo -e "${RED}未找到Xray配置文件，请先安装协议${PLAIN}"
        return
    fi
    
    # 获取当前端口
    CURRENT_PORTS=$(${SUDO} jq -r '.inbounds[].port' /usr/local/etc/xray/config.json 2>/dev/null | tr '\n' ' ')
    echo -e "${GREEN}当前使用的端口: ${CURRENT_PORTS}${PLAIN}"
    
    # 获取新端口
    NEW_PORT=$(get_port)
    
    # 检查端口是否已被使用
    if netstat -tuln | grep -q ":${NEW_PORT} "; then
        echo -e "${RED}端口 ${NEW_PORT} 已被占用，请选择其他端口${PLAIN}"
        return
    fi
    
    # 更新配置文件中的端口
    ${SUDO} jq --arg port "$NEW_PORT" '.inbounds[].port = ($port | tonumber)' /usr/local/etc/xray/config.json > /tmp/new_config.json
    ${SUDO} mv /tmp/new_config.json /usr/local/etc/xray/config.json
    
    # 重启Xray服务
    ${SUDO} systemctl restart xray
    
    echo -e "${GREEN}端口已修改为: ${NEW_PORT}${PLAIN}"
    echo -e "${YELLOW}请选择菜单选项7重新生成节点链接${PLAIN}"
}

# 查看当前配置
show_current_config() {
    echo -e "${GREEN}当前配置信息${PLAIN}"
    
    # 检查是否有配置文件
    if [[ ! -f "/usr/local/etc/xray/config.json" ]]; then
        echo -e "${RED}未找到Xray配置文件，请先安装协议${PLAIN}"
        return
    fi
    
    # 获取服务器IP
    get_ip
    
    # 显示配置信息
    echo -e "${GREEN}服务器IP: ${IP}${PLAIN}"
    
    # 获取端口信息
    PORTS=$(${SUDO} jq -r '.inbounds[] | "端口: \(.port) 协议: \(.protocol)"' /usr/local/etc/xray/config.json 2>/dev/null)
    if [[ -n "$PORTS" ]]; then
        echo -e "${GREEN}已配置的协议:${PLAIN}"
        echo "$PORTS"
    else
        echo -e "${YELLOW}未找到已配置的协议${PLAIN}"
    fi
    
    # 检查服务状态
    if ${SUDO} systemctl is-active --quiet xray; then
        echo -e "${GREEN}Xray服务状态: 运行中${PLAIN}"
    else
        echo -e "${RED}Xray服务状态: 已停止${PLAIN}"
    fi
    
    # 检查Cloudflared进程
    if pgrep -f cloudflared > /dev/null; then
        echo -e "${GREEN}Cloudflared状态: 运行中${PLAIN}"
        ARGO_DOMAIN=$(grep -o "https://.*trycloudflare.com" /tmp/argo.log 2>/dev/null | head -n 1)
        if [[ -n "$ARGO_DOMAIN" ]]; then
            echo -e "${GREEN}Argo域名: ${ARGO_DOMAIN}${PLAIN}"
        fi
    else
        echo -e "${YELLOW}Cloudflared状态: 未运行${PLAIN}"
    fi
}

# 重新生成节点链接
regenerate_links() {
    echo -e "${GREEN}重新生成节点链接${PLAIN}"
    
    # 检查是否有配置文件
    if [[ ! -f "/usr/local/etc/xray/config.json" ]]; then
        echo -e "${RED}未找到Xray配置文件，请先安装协议${PLAIN}"
        return
    fi
    
    # 获取服务器IP
    get_ip
    
    # 分析配置文件，生成对应的节点链接
    ${SUDO} jq -c '.inbounds[]' /usr/local/etc/xray/config.json | while read -r inbound; do
        PROTOCOL=$(echo "$inbound" | jq -r '.protocol')
        PORT=$(echo "$inbound" | jq -r '.port')
        
        case $PROTOCOL in
            "vless")
                # VLESS+Reality+Vision
                UUID=$(echo "$inbound" | jq -r '.settings.clients[0].id')
                if [[ -f "/tmp/x25519.keys" ]]; then
                    PUBLIC_KEY=$(cat /tmp/x25519.keys | grep Public | awk '{print $3}')
                    SHORT_ID=$(echo "$inbound" | jq -r '.streamSettings.realitySettings.shortIds[0]')
                    
                    echo -e "\n${GREEN}VLESS+Reality+Vision 节点链接:${PLAIN}"
                    LINK=$(generate_link "VLESS+Reality+Vision" "$IP" "$PORT" "$UUID" "$PUBLIC_KEY" "$SHORT_ID")
                    echo -e "${YELLOW}${LINK}${PLAIN}"
                fi
                ;;
            "vmess")
                # VMess+WebSocket
                UUID=$(echo "$inbound" | jq -r '.settings.clients[0].id')
                ARGO_DOMAIN=$(grep -o "https://.*trycloudflare.com" /tmp/argo.log 2>/dev/null | head -n 1)
                if [[ -n "$ARGO_DOMAIN" ]]; then
                    ARGO_HOST=$(echo $ARGO_DOMAIN | awk -F[/:] '{print $4}')
                    
                    echo -e "\n${GREEN}VMess+WebSocket 节点链接:${PLAIN}"
                    LINK=$(generate_link "VMess+WebSocket" "$IP" "$PORT" "$UUID" "$ARGO_HOST")
                    echo -e "${YELLOW}${LINK}${PLAIN}"
                fi
                ;;
            "shadowsocks")
                # Shadowsocks-2022
                PASSWORD=$(echo "$inbound" | jq -r '.settings.password')
                
                echo -e "\n${GREEN}Shadowsocks-2022 节点链接:${PLAIN}"
                LINK=$(generate_link "Shadowsocks-2022" "$IP" "$PORT" "$PASSWORD")
                echo -e "${YELLOW}${LINK}${PLAIN}"
                ;;
        esac
    done
    
    echo -e "\n${GREEN}===============================${PLAIN}"
    echo -e "${GREEN}请复制上方链接到V2rayN客户端导入使用${PLAIN}"
}

# 重置所有配置
reset_all() {
    echo -e "${YELLOW}警告: 此操作将删除所有已安装的服务和配置${PLAIN}"
    read -p "是否继续? (y/n): " confirm
    
    if [[ "$confirm" != "y" ]]; then
        echo -e "${GREEN}已取消重置操作${PLAIN}"
        return
    fi
    
    # 停止并删除服务
    ${SUDO} systemctl stop xray 2>/dev/null
    ${SUDO} systemctl disable xray 2>/dev/null
    ${SUDO} warp-cli disconnect 2>/dev/null
    
    # 杀死cloudflared进程
    ${SUDO} pkill -f cloudflared 2>/dev/null
    
    # 删除配置文件
    ${SUDO} rm -rf /usr/local/etc/xray 2>/dev/null
    
    echo -e "${GREEN}所有配置已重置${PLAIN}"
}

# 生成配置链接HTML页面
generate_html_page() {
    local protocol=$1
    local server_ip=$2
    local port=$3
    local html_file="proxy_links.html"
    
    # 创建HTML页面头部
    cat > ${html_file} << EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>代理配置链接</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            line-height: 1.6;
        }
        h1, h2 {
            color: #333;
        }
        .link-box {
            background-color: #f5f5f5;
            border: 1px solid #ddd;
            border-radius: 5px;
            padding: 15px;
            margin-bottom: 20px;
        }
        .link-title {
            font-weight: bold;
            margin-bottom: 10px;
        }
        .link-content {
            word-break: break-all;
            font-family: monospace;
            background-color: #eee;
            padding: 10px;
            border-radius: 3px;
        }
        .note {
            color: #666;
            font-style: italic;
            margin-top: 5px;
        }
        .button {
            display: inline-block;
            padding: 8px 16px;
            background-color: #4CAF50;
            color: white;
            text-decoration: none;
            border-radius: 4px;
            margin-top: 10px;
            cursor: pointer;
        }
    </style>
</head>
<body>
    <h1>代理配置链接</h1>
    <p>以下是您的代理配置链接，可以直接复制到对应的客户端中使用。</p>
EOF
    
    # 根据协议添加不同的链接
    case $protocol in
        "VLESS+Reality+Vision")
            UUID=$4
            PUBLIC_KEY=$5
            SHORT_ID=$6
            LINK=$(generate_link "$protocol" "$server_ip" "$port" "$UUID" "$PUBLIC_KEY" "$SHORT_ID")
            cat >> ${html_file} << EOF
    <div class="link-box">
        <div class="link-title">VLESS+Reality+Vision 链接 (适用于V2rayN/Shadowrocket等):</div>
        <div class="link-content" id="vless-link">${LINK}</div>
        <button class="button" onclick="copyToClipboard('vless-link')">复制链接</button>
        <p class="note">提示: 点击按钮复制链接，然后在客户端中导入。</p>
    </div>
EOF
            ;;
        "VMess+WebSocket")
            UUID=$4
            ARGO_HOST=$5
            LINK=$(generate_link "$protocol" "$server_ip" "$port" "$UUID" "$ARGO_HOST")
            cat >> ${html_file} << EOF
    <div class="link-box">
        <div class="link-title">VMess+WebSocket+Argo 链接 (适用于V2rayN/Shadowrocket等):</div>
        <div class="link-content" id="vmess-link">${LINK}</div>
        <button class="button" onclick="copyToClipboard('vmess-link')">复制链接</button>
        <p class="note">提示: 点击按钮复制链接，然后在客户端中导入。</p>
    </div>
EOF
            ;;
        "Shadowsocks-2022")
            PASSWORD=$4
            LINK=$(generate_link "$protocol" "$server_ip" "$port" "$PASSWORD")
            cat >> ${html_file} << EOF
    <div class="link-box">
        <div class="link-title">Shadowsocks-2022 链接 (适用于Shadowsocks客户端):</div>
        <div class="link-content" id="ss-link">${LINK}</div>
        <button class="button" onclick="copyToClipboard('ss-link')">复制链接</button>
        <p class="note">提示: 点击按钮复制链接，然后在客户端中导入。</p>
    </div>
EOF
            ;;
    esac
    
    # 添加Clash配置文件链接
    cat >> ${html_file} << EOF
    <div class="link-box">
        <div class="link-title">Clash配置文件:</div>
        <p>已生成Clash配置文件: clash_${protocol// /_}_config.yaml</p>
        <p class="note">提示: 要创建Clash订阅链接，可将配置文件上传至GitHub或使用订阅转换服务。</p>
    </div>
    
    <h2>如何创建Clash订阅链接</h2>
    <ol>
        <li>将生成的clash_*.yaml文件上传到GitHub仓库</li>
        <li>获取文件的原始链接 (Raw链接)</li>
        <li>在Clash客户端中，使用该链接作为订阅地址</li>
    </ol>
    <p>或者使用在线订阅转换服务，将上方的V2ray/SS链接转换为Clash订阅。</p>
    
    <script>
        function copyToClipboard(elementId) {
            const element = document.getElementById(elementId);
            const text = element.textContent;
            
            navigator.clipboard.writeText(text).then(() => {
                alert('已复制到剪贴板!');
            }).catch(err => {
                console.error('复制失败:', err);
                alert('复制失败，请手动复制');
            });
        }
    </script>
</body>
</html>
EOF
    
    echo -e "${GREEN}已生成HTML配置页面: ${html_file}${PLAIN}"
    echo -e "${YELLOW}您可以使用浏览器打开此文件，方便复制各种配置链接${PLAIN}"
}

# 完全卸载
uninstall_all() {
    echo -e "${RED}警告: 此操作将完全卸载所有组件并删除所有相关文件${PLAIN}"
    read -p "是否继续? (y/n): " confirm
    
    if [[ "$confirm" != "y" ]]; then
        echo -e "${GREEN}已取消卸载操作${PLAIN}"
        return
    fi
    
    # 停止并删除服务
    echo -e "${YELLOW}停止并禁用服务...${PLAIN}"
    ${SUDO} systemctl stop xray 2>/dev/null
    ${SUDO} systemctl disable xray 2>/dev/null
    ${SUDO} systemctl stop hysteria-server 2>/dev/null
    ${SUDO} systemctl disable hysteria-server 2>/dev/null
    ${SUDO} systemctl stop tuic 2>/dev/null
    ${SUDO} systemctl disable tuic 2>/dev/null
    
    # 断开WARP连接并卸载
    echo -e "${YELLOW}卸载WARP...${PLAIN}"
    ${SUDO} warp-cli disconnect 2>/dev/null
    if [[ "${PACKAGE_MANAGER}" == "apt" ]]; then
        ${SUDO} apt remove -y cloudflare-warp 2>/dev/null
    elif [[ "${PACKAGE_MANAGER}" == "yum" ]]; then
        ${SUDO} yum remove -y cloudflare-warp 2>/dev/null
    fi
    
    # 杀死cloudflared进程
    echo -e "${YELLOW}停止Cloudflared进程...${PLAIN}"
    ${SUDO} pkill -f cloudflared 2>/dev/null
    
    # 卸载Xray
    echo -e "${YELLOW}卸载Xray...${PLAIN}"
    if [[ -f "/usr/local/bin/xray" ]]; then
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
    fi
    
    # 删除Cloudflared
    echo -e "${YELLOW}删除Cloudflared...${PLAIN}"
    ${SUDO} rm -f /usr/local/bin/cloudflared 2>/dev/null
    
    # 删除配置文件和生成的客户端配置
    echo -e "${YELLOW}删除配置文件...${PLAIN}"
    ${SUDO} rm -rf /usr/local/etc/xray 2>/dev/null
    ${SUDO} rm -rf /etc/hysteria 2>/dev/null
    ${SUDO} rm -rf /etc/tuic 2>/dev/null
    ${SUDO} rm -f /etc/systemd/system/tuic.service 2>/dev/null
    ${SUDO} rm -f client_*.json 2>/dev/null
    
    # 删除日志文件
    echo -e "${YELLOW}删除日志文件...${PLAIN}"
    ${SUDO} rm -f /tmp/argo.log 2>/dev/null
    
    # 重新加载systemd
    ${SUDO} systemctl daemon-reload
    
    echo -e "${GREEN}所有组件已完全卸载，系统已恢复到安装前状态${PLAIN}"
}

# 主程序入口
main() {
    clear
    show_menu
}

# 执行主程序
main
