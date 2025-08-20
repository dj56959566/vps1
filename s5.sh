#!/bin/bash
# 一键安装 Socks5，支持主流 VPS 系统 (CentOS, Ubuntu, Debian)
# By:dj56959566
# Date: 2025-08-20 09:10:59
#!/bin/bash

# 介绍信息
echo -e "\e[32m
  ____   ___   ____ _  ______ ____  
 / ___| / _ \ / ___| |/ / ___| ___|  
 \___ \| | | | |   | ' /\___ \___ \ 
  ___) | |_| | |___| . \ ___) |__) |           不要直连
 |____/ \___/ \____|_|\_\____/____/            没有售后   
 缝合怪：cmliu 原作者们：RealNeoMan、k0baya、eooce
\e[0m"

# 获取当前用户名
USER=$(whoami)
WORKDIR="/home/${USER}/.nezha-agent"
FILE_PATH="/home/${USER}/.s5"

# Add uninstall function
uninstall() {
    echo "开始卸载..."
    
    # Stop socks5 process if running
    if pgrep s5 > /dev/null; then
        echo "停止 socks5 进程..."
        pkill s5
    fi
    
    # Stop nezha-agent if running
    if pgrep nezha-agent > /dev/null; then
        echo "停止 nezha-agent 进程..."
        pgrep -f 'nezha-agent' | xargs -r kill
    fi
    
    # Remove socks5 directory
    if [ -d "$FILE_PATH" ]; then
        echo "删除 socks5 目录..."
        rm -rf "$FILE_PATH"
    fi
    
    # Remove nezha-agent directory
    if [ -d "$WORKDIR" ]; then
        echo "删除 nezha-agent 目录..."
        rm -rf "$WORKDIR"
    fi
    
    # Remove crontab entries
    echo "删除 crontab 计划任务..."
    crontab -l | grep -v 'check_s5.sh' | grep -v 'check_nezha.sh' | crontab -
    
    echo "卸载完成！"
    exit 0
}

# Add uninstall option to menu
echo "请选择操作："
echo "1. 安装"
echo "2. 卸载"
read -p "请输入选项 (1/2): " operation_choice

case $operation_choice in
    2)
        uninstall
        ;;
    1)
        # Original installation code follows...
        [Previous installation code remains the same]
        ;;
    *)
        echo "无效选项"
        exit 1
        ;;
esac

[Rest of the original code remains the same...]
