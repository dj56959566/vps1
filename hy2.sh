#!/bin/bash

# 等待1秒, 避免curl下载脚本的打印与脚本本身的显示冲突
sleep 1

# 设置所有输出为绿色，并且不会被重置
echo -e "\e[92m"

# Djkyc的logo
echo -e "  _____     _   _                 "
echo -e " |  __ \   (_) | |                "
echo -e " | |  | |   _  | | __  _   _   ___ "
echo -e " | |  | |  | | | |/ / | | | | / __|"
echo -e " | |__| |  | | |   <  | |_| | | (__ "
echo -e " |_____/   |_| |_|\_\  \__, |  \___|"
echo -e "                        __/ |       "
echo -e "                       |___/        "

# 所有颜色变量都设为空，因为我们已经在开头设置了全局绿色
green=''
none=''
red=''
yellow=''
magenta=''
cyan=''

error() {
    echo -e " 输入错误! "
}

warn() {
    echo -e " $1 "
}

pause() {
    read -rsp "$(echo -e "按 Enter 回车键 继续....或按 Ctrl + C 取消.")" -d $'\n'
    echo
}

# 卸载 Hysteria2 函数
uninstall_hy2() {
    echo
    echo -e "确定要卸载 Hysteria2 吗?"
    echo -e "此操作将删除所有 Hysteria2 相关文件和配置!"
    echo

    read -p "$(echo -e "输入 Y 确认卸载, 输入其他取消: ")" confirm

    if [[ "$confirm" != "Y" && "$confirm" != "y" ]]; then
        echo -e "已取消卸载操作"
        return
    fi

    # 停止并禁用服务
    echo -e "停止 Hysteria2 服务..."
    systemctl stop hysteria-server.service
    systemctl disable hysteria-server.service

    # 删除程序文件
    echo -e "删除 Hysteria2 程序文件..."
    rm -f /usr/local/bin/hysteria

    # 删除配置文件和证书
    echo -e "删除配置文件和证书..."
    rm -rf /etc/hysteria
    rm -rf /etc/ssl/private/*.crt /etc/ssl/private/*.key

    # 删除节点信息文件
    echo -e "删除节点信息文件..."
    rm -f ~/_hy2_url_

    echo
    echo -e "Hysteria2 已成功卸载!"
    echo
    exit 0
}

# 安装 Hysteria2 函数
install_hy2() {
    # 说明
    echo
    echo -e "此脚本仅兼容于Debian 10+系统. 如果你的系统不符合,请Ctrl+C退出脚本"
    echo -e "可以去查看脚本整体思路和关键命令, 以便针对你自己的系统做出调整."
    echo -e "有问题电报反映:https://t.me/djkyc2_bot"
    echo -e "本脚本支持带参数执行, 省略交互过程, 详见hy2官方GitHub."
    echo "----------------------------------------------------------------"

    # 本机 IP
    InFaces=($(ls /sys/class/net/ | grep -E '^(eth|ens|eno|esp|enp|venet|vif)'))  #找所有的网口

    for i in "${InFaces[@]}"; do  # 从网口循环获取IP
        # 增加超时时间, 以免在某些网络环境下请求IPv6等待太久
        Public_IPv4=$(curl -4s --interface "$i" -m 2 https://www.cloudflare.com/cdn-cgi/trace | grep -oP "ip=\K.*$")
        Public_IPv6=$(curl -6s --interface "$i" -m 2 https://www.cloudflare.com/cdn-cgi/trace | grep -oP "ip=\K.*$")

        if [[ -n "$Public_IPv4" ]]; then  # 检查是否获取到IP地址
            IPv4="$Public_IPv4"
        fi
        if [[ -n "$Public_IPv6" ]]; then  # 检查是否获取到IP地址            
            IPv6="$Public_IPv6"
        fi
    done

    # 通过IP, host, 时区, 生成UUID. 重装脚本不改变, 不改变节点信息, 方便个人使用
    uuidSeed=${IPv4}${IPv6}$(cat /proc/sys/kernel/hostname)$(cat /etc/timezone)
    default_uuid=$(curl -sL https://www.uuidtools.com/api/generate/v3/namespace/ns:dns/name/${uuidSeed} | grep -oP '[^-]{8}-[^-]{4}-[^-]{4}-[^-]{4}-[^-]{12}')

    # 默认端口2096
    default_port=2096

    # 执行脚本带参数
    if [ $# -ge 1 ]; then
        # 第1个参数是搭在ipv4还是ipv6上
        case ${1} in
        4)
            netstack=4
            ip=${IPv4}
            ;;
        6)
            netstack=6
            ip=${IPv6}
            ;;
        *) # initial
            if [[ -n "$IPv4" ]]; then  # 检查是否获取到IP地址
                netstack=4
                ip=${IPv4}
            elif [[ -n "$IPv6" ]]; then  # 检查是否获取到IP地址            
                netstack=6
                ip=${IPv6}
            else
                warn "没有获取到公共IP"
            fi
            ;;
        esac

        # 第2个参数是port
        port=${2}
        if [[ -z $port ]]; then
          port=${default_port}
        fi

        # 第3个参数是域名
        domain=${3}
        if [[ -z $domain ]]; then
          domain="learn.microsoft.com"
        fi

        # 第4个参数是密码
        pwd=${4}
        if [[ -z $pwd ]]; then
            pwd=${default_uuid}
        fi

        echo -e "netstack = ${netstack}"
        echo -e "本机IP = ${ip}"
        echo -e "端口 (Port) = ${port}"
        echo -e "密码 (Password) = ${pwd}"
        echo -e "自签证书所用域名 (Certificate Domain) = ${domain}"
        echo "----------------------------------------------------------------"
    fi

    pause

    # 准备工作
    apt update
    apt install -y curl openssl qrencode net-tools lsof

    # Hy2官方脚本 安装最新版本
    echo
    echo -e "Hy2官方脚本 安装最新版本"
    echo "----------------------------------------------------------------"
    bash <(curl -fsSL https://get.hy2.sh/)

    systemctl start hysteria-server.service
    systemctl enable hysteria-server.service

    # 配置 Hy2, 使用自签证书, 需要:端口, 密码, 证书所用域名(不必拥有该域名)
    echo
    echo -e "配置 Hy2, 使用自签证书"
    echo "----------------------------------------------------------------"

    # 网络栈
    if [[ -z $netstack ]]; then
      echo
      echo -e "如果你的小鸡是双栈(同时有IPv4和IPv6的IP)，请选择你把Hy2搭在哪个'网口'上"
      echo "想ipv4就输入ipv4即可反之ipv6,如果你不懂,默认请直接回车"
      read -p "$(echo -e "Input 4 for IPv4, 6 for IPv6: ")" netstack

      if [[ $netstack == "4" ]]; then
        ip=${IPv4}
      elif [[ $netstack == "6" ]]; then
        ip=${IPv6}
      else
        if [[ -n "$IPv4" ]]; then  # 检查是否获取到IP地址
            netstack=4
            ip=${IPv4}
        elif [[ -n "$IPv6" ]]; then  # 检查是否获取到IP地址            
            netstack=6
            ip=${IPv6}
        else
            warn "没有获取到公共IP"
        fi    
      fi
    fi

    # 端口
    if [[ -z $port ]]; then
      while :; do
        read -p "$(echo -e "请输入端口 [1-65535] Input port (默认Default ${default_port}):")" port
        [ -z "$port" ] && port=$default_port
        case $port in
        [1-9] | [1-9][0-9] | [1-9][0-9][0-9] | [1-9][0-9][0-9][0-9] | [1-5][0-9][0-9][0-9][0-9] | 6[0-4][0-9][0-9][0-9] | 65[0-4][0-9][0-9] | 655[0-3][0-5])
          echo
          echo
          echo -e "端口 (Port) = ${port}"
          echo "----------------------------------------------------------------"
          echo
          break
          ;;
        *)
          error
          ;;
        esac
      done
    fi

# 域名选择
if [[ -z $domain ]]; then
    echo
    echo -e "请选择自签证书使用的域名（这些域名对三网都比较友好）："
    echo -e "  1. learn.microsoft.com (默认)"
    echo -e "  2. www.apple.com"
    echo -e "  3. www.bing.com"
    echo -e "  4. www.office.com"
    echo -e "  5. www.azure.com"
    echo -e "  6. www.amazon.com"
    echo -e "  7. www.linkedin.com"
    echo -e "  8. www.adobe.com"
    echo -e "  9. www.github.com"
    echo -e "  10. www.cloudflare.com"
    echo -e "  0. 自定义域名"
    
    read -p "请选择 [1-10，默认1]: " domain_choice
    
    case "$domain_choice" in
        1|"")
            domain="learn.microsoft.com"
            ;;
        2)
            domain="www.apple.com"
            ;;
        3)
            domain="www.bing.com"
            ;;
        4)
            domain="www.office.com"
            ;;
        5)
            domain="www.azure.com"
            ;;
        6)
            domain="www.amazon.com"
            ;;
        7)
            domain="www.linkedin.com"
            ;;
        8)
            domain="www.adobe.com"
            ;;
        9)
            domain="www.github.com"
            ;;
        10)
            domain="www.cloudflare.com"
            ;;
        0)
            echo -e "请输入自定义域名："
            read -p "(例如: example.com): " domain
            [ -z "$domain" ] && domain="learn.microsoft.com"
            ;;
        *)
            domain="learn.microsoft.com"
            ;;
    esac
    
    echo
    echo
    echo -e "证书域名 Certificate Domain = ${domain}"
    echo "----------------------------------------------------------------"
    echo
fi


    # 密码
    if [[ -z $pwd ]]; then
        echo -e "请输入密码"
        read -p "$(echo -e "(默认ID: ${default_uuid}):")" pwd
        [ -z "$pwd" ] && pwd=${default_uuid}
        echo
        echo
        echo -e "密码 (Password) = ${pwd}"
        echo "----------------------------------------------------------------"
        echo
    fi

    # 生成证书
    echo -e "生成证书"
    echo "----------------------------------------------------------------"
    cert_dir="/etc/ssl/private"
    mkdir -p ${cert_dir}
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout "${cert_dir}/${domain}.key" -out "${cert_dir}/${domain}.crt" -subj "/CN=${domain}" -days 36500
    chmod -R 777 ${cert_dir}

    # 配置 /etc/hysteria/config.yaml
    echo
    echo -e "配置 /etc/hysteria/config.yaml"
    echo "----------------------------------------------------------------"
    cat >/etc/hysteria/config.yaml <<-EOF
listen: :${port}     # 工作端口

tls:
  cert: ${cert_dir}/${domain}.crt    # 证书路径
  key: ${cert_dir}/${domain}.key     # 证书路径
auth:
  type: password
  password: ${pwd}    # 密码

ignoreClientBandwidth: true

acl:
  inline:
    # 如果你想利用 *ray 的分流规则, 那么在hy2自己的分流规则里面设置全部走socks5出去, 将下面一行的注释取消
    # - s5_outbound(all)

outbounds:
  # 没有分流规则, 默认生效第一个出站 直接出站
  - name: direct_outbound
    type: direct
  # 如果你想利用 *ray 的分流规则, 那么在hy2自己的分流规则里面设置全部走socks5出去
  - name: s5_outbound
    type: socks5
    socks5:
      addr: 127.0.0.1:1080

EOF

    # 重启 Hy2
    echo
    echo -e "重启 Hy2"
    echo "----------------------------------------------------------------"
    service hysteria-server restart

    echo
    echo
    echo "---------- Hy2 客户端配置信息 ----------"
    echo -e "地址 (Address) = ${ip}"
    echo -e "端口 (Port) = ${port}"
    echo -e "密码 (Password) = ${pwd}"
    echo -e "传输层安全 (TLS) = tls"
    echo -e "应用层协议协商 (Alpn) = h3"
    echo -e "跳过证书验证 (allowInsecure) = true"
    echo

    # 如果是 IPv6 那么在生成节点分享链接时, 要用[]把IP包起来
    if [[ $netstack == "6" ]]; then
        ip="[${ip}]"
    fi
    echo "---------- 链接 URL ----------"
    hy2_url="hysteria2://${pwd}@${ip}:${port}?alpn=h3&insecure=1#HY2_${ip}"
    echo -e "${hy2_url}"
    echo
    sleep 3
    echo "以下两个二维码完全一样的内容"
    qrencode -t UTF8 $hy2_url
    qrencode -t ANSI $hy2_url
    echo
    echo "---------- END -------------"
    echo "以上节点信息保存在 ~/_hy2_url_ 中"

    # 节点信息保存到文件中
    echo $hy2_url > ~/_hy2_url_
    echo "以下两个二维码完全一样的内容" >> ~/_hy2_url_
    qrencode -t UTF8 $hy2_url >> ~/_hy2_url_
    qrencode -t ANSI $hy2_url >> ~/_hy2_url_
}

# 主菜单
echo "----------------------------------------------------------------"
echo -e "                Djkyc Hysteria2 安装/卸载脚本                 "
echo "----------------------------------------------------------------"
echo -e "  1. 安装 Hysteria2"
echo -e "  2. 卸载 Hysteria2"
echo

read -p "$(echo -e "请选择 [1-2]：")" choice

case $choice in
    1)
        install_hy2 "$@"
        ;;
    2)
        uninstall_hy2
        ;;
    *)
        error
        exit 1
        ;;
esac

# 脚本结束时不重置颜色，保持绿色
