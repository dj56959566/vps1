#!/bin/bash

# 一键安装脚本
# 用于下载并执行xray-argo-install.sh

# 定义颜色
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

# 显示欢迎信息
echo -e "${GREEN}欢迎使用一键安装脚本${PLAIN}"
echo -e "${GREEN}此脚本将从GitHub下载并执行xray-argo-install.sh${PLAIN}"
echo -e "${GREEN}By: djkyc    $(date +%Y-%m-%d)${PLAIN}"
echo -e "————————————————————————————————————"

# 检查curl是否安装
if ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}curl未安装，正在安装...${PLAIN}"
    if command -v apt &> /dev/null; then
        apt update -y && apt install -y curl
    elif command -v yum &> /dev/null; then
        yum -y update && yum -y install curl
    else
        echo -e "${RED}无法安装curl，请手动安装后重试${PLAIN}"
        exit 1
    fi
fi

# 下载并执行脚本
echo -e "${GREEN}正在下载脚本...${PLAIN}"
curl -fsSL https://raw.githubusercontent.com/dj56959566/vps1/refs/heads/main/xray-argo-install.sh -o xray-argo-install.sh
if [ $? -ne 0 ]; then
    echo -e "${RED}下载失败，请检查网络连接或GitHub仓库是否可访问${PLAIN}"
    exit 1
fi

# 设置执行权限
chmod +x xray-argo-install.sh

# 执行脚本
echo -e "${GREEN}开始执行安装脚本...${PLAIN}"
./xray-argo-install.sh

# 清理
rm -f install.sh
