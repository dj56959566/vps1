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
    if [[ "${PACKAGE_MANAGER}" == "yum" ]]; 键，然后
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

# 配置VLESS+XTLS+Reality
configure_vless_xtls_reality() {
    echo -e "${GREEN}开始配置VLESS+XTLS+Reality...${PLAIN}"
    
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
    cat > /tmp/vless_xtls_reality.json << EOF
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
            "www.microsoft.com",
            "microsoft.com"
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
    ${SUDO} jq -s '.[0].inbounds += .[1].inbounds | .[0]' /usr/local/etc/xray/config.json /tmp/vless_xtls_reality.json > /tmp/merged_config.json
    ${SUDO} mv /tmp/merged_config.json /usr/local/etc/xray/config.json
    
    # 重启Xray服务
    ${SUDO} systemctl restart xray
    
    # 返回配置信息
    echo "$PUBLIC_KEY $SHORT_ID"
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

# 配置Hysteria2
configure_hysteria2() {
    echo -e "${GREEN}开始配置Hysteria2...${PLAIN}"
    
    # 获取参数
    PORT=$1
    
    # 生成随机密码
    PASSWORD=$(openssl rand -base64 16)
    
    # 下载并安装Hysteria2
    ${SUDO} bash -c "$(curl -fsSL https://get.hy2.sh/)"
    
    # 创建配置文件
    cat > /tmp/hysteria2.yaml << EOF
listen: :${PORT}

auth:
  type: password
  password: ${PASSWORD}

masquerade:
  type: proxy
  proxy:
    url: https://www.microsoft.com
    rewriteHost: true
EOF
    
    ${SUDO} mv /tmp/hysteria2.yaml /etc/hysteria/config.yaml
    
    # 启动Hysteria2服务
    ${SUDO} systemctl enable hysteria-server.service
    ${SUDO} systemctl restart hysteria-server.service
    
    # 返回配置信息
    echo "$PASSWORD"
}

# 配置Tuic
configure_tuic() {
    echo -e "${GREEN}开始配置Tuic...${PLAIN}"
    
    # 获取参数
    PORT=$1
    
    # 生成UUID和密码
    UUID=$(generate_uuid)
    PASSWORD=$(openssl rand -base64 16)
    
    # 下载并安装Tuic
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            ARCH="x86_64-unknown-linux-gnu"
            ;;
        aarch64)
            ARCH="aarch64-unknown-linux-gnu"
            ;;
        *)
            echo -e "${RED}不支持的系统架构: ${ARCH}${PLAIN}"
            exit 1
            ;;
    esac
    
    TUIC_VERSION=$(curl -s https://api.github.com/repos/EAimTY/tuic/releases/latest | grep tag_name | cut -d '"' -f 4)
    ${SUDO} curl -Lo /tmp/tuic.tar.gz https://github.com/EAimTY/tuic/releases/download/${TUIC_VERSION}/tuic-server-${TUIC_VERSION}-${ARCH}.tar.gz
    ${SUDO} tar -xzf /tmp/tuic.tar.gz -C /tmp
    ${SUDO} mv /tmp/tuic-server /usr/local/bin/
    ${SUDO} chmod +x /usr/local/bin/tuic-server
    
    # 创建配置文件
    cat > /tmp/tuic.json << EOF
{
    "server": "[::]:${PORT}",
    "users": {
        "${UUID}": "${PASSWORD}"
    },
    "certificate": "/etc/ssl/certs/tuic.crt",
    "private_key": "/etc/ssl/private/tuic.key",
    "congestion_control": "bbr",
    "alpn": ["h3"]
}
EOF
    
    ${SUDO} mkdir -p /etc/tuic
    ${SUDO} mv /tmp/tuic.json /etc/tuic/config.json
    
    # 生成自签名证书
    ${SUDO} openssl req -x509 -nodes -newkey rsa:2048 -days 365 -keyout /etc/ssl/private/tuic.key -out /etc/ssl/certs/tuic.crt -subj "/CN=tuic.server"
    
    # 创建systemd服务
    cat > /tmp/tuic.service << EOF
[Unit]
Description=Tuic Server
After=network.target

[Service]
ExecStart=/usr/local/bin/tuic-server -c /etc/tuic/config.json
Restart=on-failure
RestartSec=5
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
    
    ${SUDO} mv /tmp/tuic.service /etc/systemd/system/
    ${SUDO} systemctl daemon-reload
    ${SUDO} systemctl enable tuic.service
    ${SUDO} systemctl restart tuic.service
    
    # 返回配置信息
    echo "$UUID $PASSWORD"
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
        "VLESS+XTLS+Reality")
            echo -e "${GREEN}UUID: $4${PLAIN}"
            echo -e "${GREEN}Public Key: $5${PLAIN}"
            echo -e "${GREEN}Short ID: $6${PLAIN}"
            echo -e "${GREEN}SNI: www.microsoft.com${PLAIN}"
            echo -e "${GREEN}Flow: xtls-rprx-vision${PLAIN}"
            ;;
        "Shadowsocks-2022")
            echo -e "${GREEN}密码: $4${PLAIN}"
            echo -e "${GREEN}加密方式: 2022-blake3-aes-128-gcm${PLAIN}"
            ;;
        "VMess+WebSocket")
            echo -e "${GREEN}UUID: $4${PLAIN}"
            echo -e "${GREEN}路径: /vmess${PLAIN}"
            echo -e "${GREEN}Argo域名: $5${PLAIN}"
            ;;
        "Hysteria2")
            echo -e "${GREEN}密码: $4${PLAIN}"
            ;;
        "Tuic")
            echo -e "${GREEN}UUID: $4${PLAIN}"
            echo -e "${GREEN}密码: $5${PLAIN}"
            ;;
    esac
    
    echo -e "${GREEN}===============================${PLAIN}"
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
        "VLESS+XTLS+Reality")
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
        "Hysteria2")
            PASSWORD=$4
            cat > ${config_file} << EOF
{
  "server": "${server_ip}:${port}",
  "auth": "${PASSWORD}",
  "tls": {
    "sni": "${server_ip}",
    "insecure": true
  }
}
EOF
            ;;
        "Tuic")
            UUID=$4
            PASSWORD=$5
            cat > ${config_file} << EOF
{
  "relay": {
    "server": "${server_ip}:${port}",
    "uuid": "${UUID}",
    "password": "${PASSWORD}",
    "congestion_control": "bbr",
    "alpn": ["h3"]
  },
  "local": {
    "server": "127.0.0.1:1080"
  },
  "log_level": "info"
}
EOF
            ;;
    esac
    
    echo -e "${GREEN}客户端配置已生成: ${config_file}${PLAIN}"
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
  ${GREEN}2.${PLAIN} 安装 VLESS+XTLS+Reality
  ${GREEN}3.${PLAIN} 安装 Shadowsocks-2022
  ${GREEN}4.${PLAIN} 安装 VMess+WebSocket+Argo
  ${GREEN}5.${PLAIN} 安装 Hysteria2
  ${GREEN}6.${PLAIN} 安装 Tuic
  ${GREEN}7.${PLAIN} 安装 WARP全局出站
  ${GREEN}8.${PLAIN} 重置所有配置
  ————————————————————————————————————
  "
    echo && read -p "请输入选择 [0-8]: " num
    case "${num}" in
        0) exit 0
        ;;
        1) install_vless_reality_vision
        ;;
        2) install_vless_xtls_reality
        ;;
        3) install_ss2022
        ;;
        4) install_vmess_ws_argo
        ;;
        5) install_hysteria2
        ;;
        6) install_tuic
        ;;
        7) install_warp
        ;;
        8) reset_all
        ;;
        *) echo -e "${RED}请输入正确的数字 [0-8]${PLAIN}"
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

# 安装VLESS+XTLS+Reality
install_vless_xtls_reality() {
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
    
    # 配置VLESS+XTLS+Reality
    REALITY_CONFIG=$(configure_vless_xtls_reality $UUID $PORT)
    PUBLIC_KEY=$(echo $REALITY_CONFIG | awk '{print $1}')
    SHORT_ID=$(echo $REALITY_CONFIG | awk '{print $2}')
    
    # 显示连接信息
    show_connection_info "VLESS+XTLS+Reality" $IP $PORT $UUID $PUBLIC_KEY $SHORT_ID
    
    # 生成客户端配置
    generate_client_config "VLESS+XTLS+Reality" $IP $PORT $UUID $PUBLIC_KEY $SHORT_ID
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

# 安装Hysteria2
install_hysteria2() {
    # 检查系统环境
    check_root
    check_system
    install_base
    get_ip
    
    # 生成随机端口
    PORT=$(generate_port)
    
    # 配置Hysteria2
    PASSWORD=$(configure_hysteria2 $PORT)
    
    # 显示连接信息
    show_connection_info "Hysteria2" $IP $PORT $PASSWORD
    
    # 生成客户端配置
    generate_client_config "Hysteria2" $IP $PORT $PASSWORD
}

# 安装Tuic
install_tuic() {
    # 检查系统环境
    check_root
    check_system
    install_base
    get_ip
    
    # 生成随机端口
    PORT=$(generate_port)
    
    # 配置Tuic
    TUIC_CONFIG=$(configure_tuic $PORT)
    UUID=$(echo $TUIC_CONFIG | awk '{print $1}')
    PASSWORD=$(echo $TUIC_CONFIG | awk '{print $2}')
    
    # 显示连接信息
    show_connection_info "Tuic" $IP $PORT $UUID $PASSWORD
    
    # 生成客户端配置
    generate_client_config "Tuic" $IP $PORT $UUID $PASSWORD
}

# 安装WARP全局出站
install_warp() {
    # 检查系统环境
    check_root
    check_system
    install_base
    
    # 安装WARP
    install_warp
    
    # 配置Xray使用WARP出站
    if [[ -f "/usr/local/etc/xray/config.json" ]]; then
        # 添加WARP出站配置
        cat > /tmp/warp_outbound.json << EOF
{
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    },
    {
      "protocol": "socks",
      "tag": "warp",
      "settings": {
        "servers": [
          {
            "address": "127.0.0.1",
            "port": 40000
          }
        ]
      }
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "domain": ["geosite:netflix", "geosite:disney", "geosite:spotify"],
        "outboundTag": "warp"
      }
    ]
  }
}
EOF
        
        # 更新Xray配置
        ${SUDO} jq -s '.[0].outbounds = .[1].outbounds | .[0].routing = .[1].routing | .[0]' /usr/local/etc/xray/config.json /tmp/warp_outbound.json > /tmp/merged_config.json
        ${SUDO} mv /tmp/merged_config.json /usr/local/etc/xray/config.json
        
        # 重启Xray服务
        ${SUDO} systemctl restart xray
        
        echo -e "${GREEN}WARP全局出站配置完成，流媒体流量将通过WARP出站${PLAIN}"
    else
        echo -e "${RED}未检测到Xray配置文件，请先安装Xray${PLAIN}"
    fi
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
    ${SUDO} systemctl stop hysteria-server 2>/dev/null
    ${SUDO} systemctl disable hysteria-server 2>/dev/null
    ${SUDO} systemctl stop tuic 2>/dev/null
    ${SUDO} systemctl disable tuic 2>/dev/null
    ${SUDO} warp-cli disconnect 2>/dev/null
    
    # 杀死cloudflared进程
    ${SUDO} pkill -f cloudflared 2>/dev/null
    
    # 删除配置文件
    ${SUDO} rm -rf /usr/local/etc/xray 2>/dev/null
    ${SUDO} rm -rf /etc/hysteria 2>/dev/null
    ${SUDO} rm -rf /etc/tuic 2>/dev/null
    
    echo -e "${GREEN}所有配置已重置${PLAIN}"
}

# 主程序入口
main() {
    clear
    show_menu
}

# 执行主程序
main
