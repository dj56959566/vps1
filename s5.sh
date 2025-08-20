#!/bin/bash
# 一键安装 Socks5，支持主流 VPS 系统 (CentOS, Ubuntu, Debian)
# By:dj56959566
# Date: 2025-08-20 09:10:59
#!/bin/bash

#!/bin/bash

# 获取当前用户名
USER=$(whoami)
FILE_PATH="/home/${USER}/.s5"

# 彩色输出函数
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}
  ____   ___   ____ _  ______ ____  
 / ___| / _ \ / ___| |/ / ___| ___|  
 \___ \| | | | |   | ' /\___ \___ \ 
  ___) | |_| | |___| . \ ___) |__) |     
 |____/ \___/ \____|_|\_\____/____/  
${NC}"

socks5_config(){
    # 提示用户输入socks5端口号
    read -p "请输入socks5端口号: " SOCKS5_PORT
    
    # 检查端口号是否有效
    if ! [[ "$SOCKS5_PORT" =~ ^[0-9]+$ ]] || [ "$SOCKS5_PORT" -lt 1 ] || [ "$SOCKS5_PORT" -gt 65535 ]; then
        echo -e "${RED}错误：无效的端口号，请输入1-65535之间的数字${NC}"
        return 1
    fi

    read -p "请输入socks5用户名: " SOCKS5_USER
    if [ -z "$SOCKS5_USER" ]; then
        echo -e "${RED}错误：用户名不能为空${NC}"
        return 1
    fi

    while true; do
        read -p "请输入socks5密码（不能包含@和:）：" SOCKS5_PASS
        if [ -z "$SOCKS5_PASS" ]; then
            echo -e "${RED}错误：密码不能为空${NC}"
            continue
        fi
        if [[ "$SOCKS5_PASS" == *"@"* || "$SOCKS5_PASS" == *":"* ]]; then
            echo -e "${RED}密码中不能包含@和:符号，请重新输入。${NC}"
            continue
        fi
        break
    done

    # 创建配置文件
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
    return 0
}

install_socks5(){
    echo -e "${GREEN}开始安装 socks5...${NC}"
    
    # 配置 socks5
    if ! socks5_config; then
        echo -e "${RED}配置失败，安装终止${NC}"
        return 1
    fi

    # 下载 socks5 程序
    echo "下载 socks5 程序..."
    if ! curl -L -sS -o "${FILE_PATH}/s5" "https://github.com/eooce/test/releases/download/freebsd/web"; then
        echo -e "${RED}下载失败${NC}"
        return 1
    fi

    # 设置执行权限
    chmod 777 "${FILE_PATH}/s5"

    # 终止现有进程
    pkill s5 >/dev/null 2>&1
    
    # 启动服务
    echo "启动 socks5 服务..."
    nohup ${FILE_PATH}/s5 -c ${FILE_PATH}/config.json >/dev/null 2>&1 &
    sleep 2

    # 检查服务是否正常运行
    if ! pgrep -x "s5" > /dev/null; then
        echo -e "${RED}服务启动失败${NC}"
        return 1
    fi

    # 测试代理
    echo "测试代理连接..."
    CURL_OUTPUT=$(curl -s 4.ipw.cn --socks5 $SOCKS5_USER:$SOCKS5_PASS@localhost:$SOCKS5_PORT)
    if [[ $CURL_OUTPUT =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${GREEN}代理创建成功，IP: $CURL_OUTPUT${NC}"
        echo -e "${GREEN}代理链接: socks://${SOCKS5_USER}:${SOCKS5_PASS}@${CURL_OUTPUT}:${SOCKS5_PORT}${NC}"
    else
        echo -e "${RED}代理创建失败，请检查配置${NC}"
        return 1
    fi
}

uninstall() {
    echo -e "${GREEN}开始卸载...${NC}"
    
    # 停止服务
    if pgrep s5 > /dev/null; then
        echo "停止 socks5 服务..."
        pkill s5
    fi
    
    # 删除文件
    if [ -d "$FILE_PATH" ]; then
        echo "删除安装目录..."
        rm -rf "$FILE_PATH"
    fi
    
    echo -e "${GREEN}卸载完成！${NC}"
}

# 主菜单
while true; do
    echo -e "\n${GREEN}请选择操作：${NC}"
    echo "1. 安装 socks5"
    echo "2. 卸载"
    echo "3. 退出"
    
    read -p "请输入选项 (1-3): " choice
    
    case $choice in
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
            echo -e "${RED}无效选项，请重新选择${NC}"
            ;;
    esac
done
