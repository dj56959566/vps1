#!/bin/bash
# 一键安装 Socks5，支持主流 VPS 系统 (CentOS, Ubuntu, Debian)By:Djkyc


set -e

# 检查 root
if [[ $EUID -ne 0 ]]; then
  echo "请用 root 权限运行此脚本。" >&2
  exit 1
fi

# 检查 python3
if ! command -v python3 &>/dev/null; then
  echo "正在安装 Python3..."
  if command -v apt-get &>/dev/null; then
    apt-get update
    apt-get install -y python3 python3-pip
  elif command -v yum &>/dev/null; then
    yum install -y python3 python3-pip
  elif command -v dnf &>/dev/null; then
    dnf install -y python3 python3-pip
  else
    echo "未检测到包管理器，请自行安装 Python3 和 pip3。" >&2
    exit 1
  fi
fi

# 检查 pip3
if ! command -v pip3 &>/dev/null; then
  echo "正在安装 pip3..."
  if command -v apt-get &>/dev/null; then
    apt-get install -y python3-pip
  elif command -v yum &>/dev/null; then
    yum install -y python3-pip
  elif command -v dnf &>/dev/null; then
    dnf install -y python3-pip
  else
    echo "未检测到包管理器，请自行安装 pip3。" >&2
    exit 1
  fi
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

# 安装 python-socks5（兼容PEP 668新规范）
pip3 install --upgrade pip --break-system-packages
pip3 install python-socks5 --break-system-packages

# 写入 socks5 服务
cat >/usr/local/socks5_server.py <<EOF
from python_socks5.server import Socks5Server

def main():
    server = Socks5Server(
        listen_host='0.0.0.0',
        listen_port=${port},
        username='${user}',
        password='${pass}'
    )
    server.serve_forever()

if __name__ == '__main__':
    main()
EOF

cat >/usr/local/socks5_start.sh <<EOF
#!/bin/bash
nohup python3 /usr/local/socks5_server.py &>/tmp/socks5.log &
EOF
chmod +x /usr/local/socks5_start.sh

# 启动 socks5
pkill -f socks5_server.py || true
bash /usr/local/socks5_start.sh

# 获取服务器 IP
server_ip=$(curl -s https://api.ip.sb/ip || hostname -I | awk '{print $1}')

echo ""
echo "安装完成！"
echo "服务器IP:${server_ip} 端口:${port} 用户:${user} 密码:${pass} https://t.me/socks?server=${server_ip}&port=${port}&user=${user}&pass=${pass}"
echo "卸载命令: pkill -f socks5_server.py; rm -f /usr/local/socks5_server.py /usr/local/socks5_start.sh"
echo "修改参数：请重新运行本脚本"
