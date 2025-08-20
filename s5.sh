#!/bin/bash
# 一键安装 Socks5，支持主流 VPS 系统 (CentOS, Ubuntu, Debian)
# By:Djkyc, Modified to use microsocks

set -e

# 检查 root
if [[ $EUID -ne 0 ]]; then
  echo "请用 root 权限运行此脚本。" >&2
  exit 1
fi

# 生成默认参数
default_port=$((10000 + RANDOM % 50000))
default_user="user$(date +%s | tail -c 5)"
default_pass="pass$(openssl rand -hex 3)"

read -p "请输入端口 [默认:${default_port}]: " port
port=${port:-$default_port}
read -p "请输入用户名 [默认:${default_user}]: " user
user=${user:-$default_user}
read -p "请输入密码 [默认:${default_pass}]: " pass
pass=${pass:-$default_pass}

# 安装依赖
echo "正在安装依赖..."
if command -v apt-get &>/dev/null; then
  apt-get update
  apt-get install -y git build-essential curl
elif command -v yum &>/dev/null; then
  yum groupinstall -y "Development Tools"
  yum install -y git curl
elif command -v dnf &>/dev/null; then
  dnf groupinstall -y "Development Tools"
  dnf install -y git curl
else
  echo "未检测到包管理器，请自行安装编译工具和git。" >&2
  exit 1
fi

# 下载和编译 microsocks
echo "正在下载和编译 microsocks..."
cd /tmp
git clone https://github.com/rofl0r/microsocks.git
cd microsocks
make

# 安装 microsocks
install -m755 microsocks /usr/local/bin/

# 创建 systemd 服务
cat >/etc/systemd/system/microsocks.service <<EOF
[Unit]
Description=MicroSocks Proxy Server
After=network.target

[Service]
ExecStart=/usr/local/bin/microsocks -i 0.0.0.0 -p ${port} -u ${user} -P ${pass}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reload
systemctl enable microsocks
systemctl start microsocks

# 获取服务器 IP (使用多个备选方案)
server_ip=$(curl -s -4 ip.sb || curl -s -4 ifconfig.me || curl -s -4 api.ipify.org || hostname -I | awk '{print $1}')

# 清理临时文件
cd /
rm -rf /tmp/microsocks

# 保存配置到文件
cat >/root/socks5_info.txt <<EOF
服务器信息：
IP: ${server_ip}
端口: ${port}
用户名: ${user}
密码: ${pass}

Telegram一键链接:
https://t.me/socks?server=${server_ip}&port=${port}&user=${user}&pass=${pass}

管理命令：
启动: systemctl start microsocks
停止: systemctl stop microsocks
状态: systemctl status microsocks
卸载: systemctl stop microsocks; systemctl disable microsocks; rm -f /usr/local/bin/microsocks /etc/systemd/system/microsocks.service

配置文件位置：
systemd服务: /etc/systemd/system/microsocks.service
EOF

echo ""
echo "安装完成！"
echo "服务器IP: ${server_ip}"
echo "端口: ${port}"
echo "用户名: ${user}"
echo "密码: ${pass}"
echo ""
echo "Telegram一键链接:"
echo "https://t.me/socks?server=${server_ip}&port=${port}&user=${user}&pass=${pass}"
echo ""
echo "详细信息已保存到: /root/socks5_info.txt"
echo "卸载命令: systemctl stop microsocks; systemctl disable microsocks; rm -f /usr/local/bin/microsocks /etc/systemd/system/microsocks.service"
echo "修改参数：请重新运行本脚本"
