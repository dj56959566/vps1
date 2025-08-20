#!/bin/bash

# 获取当前用户名
USER=$(whoami)
FILE_PATH="/home/${USER}/.s5"

# 彩色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# 显示当前时间和用户信息
echo "Current Date and Time (UTC): $(date -u '+%Y-%m-%d %H:%M:%S')"
echo "Current User's Login: ${USER}"

socks5_config(){
    read -p "请输入socks5端口号: " SOCKS5_PORT
    read -p "请输入socks5用户名: " SOCKS5_USER
    read -p "请输入socks5密码（不能包含@和:）：" SOCKS5_PASS
    
    mkdir -p "${FILE_PATH}"
    cat > ${FILE_PATH}/config.json << EOF
{
    "log": {
        "access": "/dev/null",
        "error": "/dev/null",
        "loglevel": "none"
    },
    "inbounds": [
        {
            "port": ${SOCKS5_PORT},
            "protocol": "socks",
            "settings": {
                "auth": "password",
                "udp": false,
                "ip": "0.0.0.0",
                "accounts": [
                    {
                        "user": "${SOCKS5_USER}",
                        "pass": "${SOCKS5_PASS}"
                    }
                ]
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom"
        }
    ]
}
EOF
}

install_socks5(){
    echo -e "${GREEN}开始安装 socks5...${NC}"
    socks5_config
    
    if [ ! -e "${FILE_PATH}/s5" ]; then
        echo "下载 socks5 程序..."
        curl -L -sS -o "${FILE_PATH}/s5" "https://github.com/eooce/test/releases/download/freebsd/web"
    fi
    
    chmod 777 "${FILE_PATH}/s5"
    pkill s5 >/dev/null 2>&1
    nohup ${FILE_PATH}/s5 -c ${FILE_PATH}/config.json >/dev/null 2>&1 &
    sleep 2

    if pgrep -x "s5" > /dev/null; then
        echo -e "${GREEN}socks5 服务已启动${NC}"
        CURL_OUTPUT=$(curl -s 4.ipw.cn --socks5 $SOCKS5_USER:$SOCKS5_PASS@localhost:$SOCKS5_PORT)
        echo -e "${GREEN}代理IP: $CURL_OUTPUT${NC}"
        echo -e "${GREEN}代理链接: socks://${SOCKS5_USER}:${SOCKS5_PASS}@${CURL_OUTPUT}:${SOCKS5_PORT}${NC}"
    else
        echo -e "${RED}socks5 启动失败${NC}"
    fi
}

uninstall() {
    echo -e "${GREEN}开始卸载...${NC}"
    pkill s5 >/dev/null 2>&1
    rm -rf "$FILE_PATH"
    echo -e "${GREEN}卸载完成！${NC}"
}

# 主程序
main() {
    while true; do
        echo -e "\n${GREEN}请选择操作：${NC}"
        echo "1) 安装 socks5"
        echo "2) 卸载"
        echo "3) 退出"
        
        read -p "请输入选项 (1/2/3): " choice
        
        case "$choice" in
            1)
                install_socks5
                break
                ;;
            2)
                uninstall
                break
                ;;
            3)
                echo "退出程序"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项，请输入 1、2 或 3${NC}"
                ;;
        esac
    done
}

# 执行主程序
main
