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

# 配置Xray
configure_xray() {
    echo -e "${GREEN}开始配置Xray...${PLAIN}"
    
    # 生成随机参数
    UUID=$(generate_uuid)
    PORT=$(generate_port)
    
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
    ${SUDO} x25519 > /tmp/x25519.keys
    PRIVATE_KEY=$(cat /tmp/x25519.keys | grep Private | awk '{print $3}')
    PUBLIC_KEY=$(cat /tmp/x25519.keys | grep Public | awk '{print $3}')
    
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
    ${SUDO} jq -s '.[0].inbounds += .[1].inbounds | .[0]' /usr/local/etc/xray/config.json /tmp/vless_reality_vision.json > /tmp/merged_config.json
    ${SUDO} mv /tmp/merged_config.json /usr/local/etc/xray/config.json
    
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
    
    case $protocol in
        "VLESS+Reality+Vision")
            UUID=$4
            PUBLIC_KEY=$5
            SHORT_ID=$6
            echo "vless://${UUID}@${server_ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#VLESS-Reality-Vision"
            ;;
        "VMess+WebSocket")
            UUID=$4
            ARGO_HOST=$5
            # 生成VMess配置JSON
            local vmess_config="{\"v\":\"2\",\"ps\":\"VMess-WebSocket-Argo\",\"add\":\"${ARGO_HOST}\",\"port\":443,\"id\":\"${UUID}\",\"aid\":0,\"net\":\"ws\",\"type\":\"none\",\"host\":\"${ARGO_HOST}\",\"path\":\"/vmess\",\"tls\":\"tls\",\"sni\":\"${ARGO_HOST}\"}"
            # Base64编码
            echo "vmess://$(echo $vmess_config | base64 -w 0)"
            ;;
        "Shadowsocks-2022")
            PASSWORD=$4
            # 使用URL安全的Base64编码
            local userinfo=$(echo -n "2022-blake3-aes-128-gcm:${PASSWORD}" | base64 -w 0 | tr '+/' '-_' | tr -d '=')
            echo "ss://${userinfo}@${server_ip}:${port}#Shadowsocks-2022"
            ;;
    esac
}

# 显示连接信息
show_connection_info() {
    echo -e "${GREEN}============连接信息============${PLAIN}"
    echo -e "${GREEN}协议: $1${PLAIN}"
    echo -e "${GREEN}服务器: $2${PLAIN}"
    echo -e "${GREEN}端口: $3${PLAIN}"
    
    # 根据协议类型显示不同的信息
    case $1 in
        "VLESS+Reality+Vision")
            echo -e "${GREEN}UUID: $4${PLAIN}"
            echo -e "${GREEN}Public Key: $5${PLAIN}"
            echo -e "${GREEN}Short ID: $6${PLAIN}"
            echo -e "${GREEN}SNI: www.microsoft.com${PLAIN}"
            echo -e "${GREEN}Flow: xtls-rprx-vision${PLAIN}"
            ;;
        "VMess+WebSocket")
            echo -e "${GREEN}UUID: $4${PLAIN}"
            echo -e "${GREEN}路径: /vmess${PLAIN}"
            echo -e "${GREEN}Argo域名: $5${PLAIN}"
            ;;
        "Shadowsocks-2022")
            echo -e "${GREEN}密码: $4${PLAIN}"
            echo -e "${GREEN}加密方式: 2022-blake3-aes-128-gcm${PLAIN}"
            ;;
    esac
    
    # 生成并显示节点链接
    echo -e "\n${GREEN}节点链接:${PLAIN}"
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
    echo -e "${GREEN}By: djkyc    $(date +%Y-%m-%d)${PLAIN}"
}

# 生成客户端配置
generate_client_config() {
    local protocol=$1
    local server_ip=$2
    local port=$3
    local config_file="client_${protocol}_config.json"
    
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
    
    echo -e "${GREEN}客户端配置已生成: ${config_file}${PLAIN}"
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
    
    # 配置Xray
    XRAY_CONFIG=$(configure_xray)
    PORT=$(echo $XRAY_CONFIG | awk '{print $2}')
    
    # 配置Shadowsocks-2022
    PASSWORD=$(configure_ss2022 $PORT)
    
    # 显示连接信息
    show_connection_info "Shadowsocks-2022" $IP $PORT $PASSWORD
    
    # 生成客户端配置
    generate_client_config "Shadowsocks-2022" $IP $PORT $PASSWORD
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
    echo "$PASSWORD"
}

# 主菜单
show_menu() {
    echo -e "
  ${GREEN}一键无交互轻便脚本，内核Xray，Cloudflared-argo内核自动搭${PLAIN}
  ${GREEN}支持Linux类主流VPS系统，SSH脚本支持非root环境运行${PLAIN}
  ${GREEN}By: djkyc    $(date +%Y-%m-%d)${PLAIN}
  ————————————————————————————————————
  ${GREEN}0.${PLAIN} 退出脚本
  ${GREEN}1.${PLAIN} 安装 VLESS+Reality+Vision
  ${GREEN}2.${PLAIN} 安装 VMess+WebSocket+Argo
  ${GREEN}3.${PLAIN} 安装 Shadowsocks-2022
  ${GREEN}4.${PLAIN} 安装 WARP全局出站
  ${GREEN}5.${PLAIN} 重置所有配置
  ————————————————————————————————————
  "
    echo && read -p "请输入选择 [0-5]: " num
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
        5) reset_all
        ;;
        *) echo -e "${RED}请输入正确的数字 [0-5]${PLAIN}"
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
    
    # 配置Xray
    XRAY_CONFIG=$(configure_xray)
    UUID=$(echo $XRAY_CONFIG | awk '{print $1}')
    PORT=$(echo $XRAY_CONFIG | awk '{print $2}')
    
    # 配置VLESS+Reality+Vision
    REALITY_CONFIG=$(configure_vless_reality_vision $UUID $PORT)
    PUBLIC_KEY=$(echo $REALITY_CONFIG | awk '{print $1}')
    SHORT_ID=$(echo $REALITY_CONFIG | awk '{print $2}')
    
    # 显示连接信息
    show_connection_info "VLESS+Reality+Vision" $IP $PORT $UUID $PUBLIC_KEY $SHORT_ID
    
    # 生成客户端配置
    generate_client_config "VLESS+Reality+Vision" $IP $PORT $UUID $PUBLIC_KEY $SHORT_ID
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
    
    # 配置Xray
    XRAY_CONFIG=$(configure_xray)
    UUID=$(echo $XRAY_CONFIG | awk '{print $1}')
    PORT=$(echo $XRAY_CONFIG | awk '{print $2}')
    
    # 配置Argo隧道
    ARGO_DOMAIN=$(configure_argo $PORT)
    
    # 配置VMess+WebSocket
    ARGO_HOST=$(configure_vmess_ws $UUID $PORT $ARGO_DOMAIN)
    
    # 显示连接信息
    show_connection_info "VMess+WebSocket" $IP $PORT $UUID $ARGO_HOST
    
    # 生成客户端配置
    generate_client_config "VMess+WebSocket" $IP $PORT $UUID $ARGO_HOST
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

# 主程序入口
main() {
    clear
    show_menu
}

# 执行主程序
main
