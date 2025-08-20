#!/usr/bin/env bash
set -euo pipefail

GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
RESET="\e[0m"

WORKDIR="/etc/microsocks"
BIN_PATH="${WORKDIR}/microsocks"
SERVICE_FILE="/etc/systemd/system/microsocks.service"
USERS_FILE="${WORKDIR}/users.conf"
DEFAULT_PORT=1080

mkdir -p "$WORKDIR"

echo -e "${GREEN}
  ____   ___   ____ _  ______ ____  
 / ___| / _ \\ / ___| |/ / ___| ___|  
 \\___ \\| | | | |   | ' /\\___ \\___ \\ 
  ___) | |_| | |___| . \\ ___) |__) |           
 |____/ \\___/ \\____|_|\\_\\____/____/            
 By:djkyc 鸣谢:eooce 本脚本:microsocks
${RESET}"

prompt() {
  local prompt_text="$1"
  local default="$2"
  local var
  read -rp "$prompt_text [$default]: " var
  if [ -z "$var" ]; then
    var="$default"
  fi
  echo "$var"
}

get_ip() {
  for svc in "https://icanhazip.com" "https://ifconfig.me" "https://ipinfo.io/ip" "https://4.ipw.cn"; do
    ip=$(curl -s --max-time 5 "$svc" || true)
    ip=$(echo "$ip" | tr -d '[:space:]')
    if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "$ip"
      return
    fi
  done
  echo "127.0.0.1"
}

urlencode() {
  local s="$1"
  python3 -c "import urllib.parse; print(urllib.parse.quote('''$s'''))" 2>/dev/null || echo "$s"
}

install_microsocks() {
  if ! command -v microsocks >/dev/null && [ ! -f "$BIN_PATH" ]; then
    echo -e "${YELLOW}未检测到 microsocks，正在下载预编译二进制...${RESET}"
    arch=$(uname -m)
    if [[ "$arch" == "x86_64" ]]; then
      url="https://github.com/rofl0r/microsocks/releases/download/2.1/microsocks-2.1-linux-x86_64"
    elif [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
      url="https://github.com/rofl0r/microsocks/releases/download/2.1/microsocks-2.1-linux-arm64"
    else
      echo -e "${RED}未识别的架构：$arch${RESET}"
      exit 1
    fi
    curl -L -o "$BIN_PATH" "$url"
    chmod +x "$BIN_PATH"
    echo -e "${GREEN}microsocks 下载完成${RESET}"
  fi
}

setup_service() {
  local port="$1"
  local user="$2"
  local pass="$3"

  cat > "$USERS_FILE" <<EOF
$user:$pass
EOF

  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=microsocks
After=network.target

[Service]
ExecStart=$BIN_PATH -p $port -u $user -P $pass
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable microsocks
  systemctl restart microsocks
}

show_links() {
  if [ -f "$USERS_FILE" ]; then
    PORT=$(grep -oP '(?<=-p )\d+' "$SERVICE_FILE" || echo "$DEFAULT_PORT")
    USER=$(cut -d':' -f1 "$USERS_FILE")
    PASS=$(cut -d':' -f2 "$USERS_FILE")
    IP=$(get_ip)
    SOCKS="socks://$USER:$PASS@$IP:$PORT"
    TLINK="https://t.me/socks?server=$(urlencode $IP)&port=$PORT&user=$(urlencode $USER)&pass=$(urlencode $PASS)"
    echo "SOCKS 链接: $SOCKS"
    echo "Telegram 快链: $TLINK"
  else
    echo -e "${YELLOW}未检测到用户配置${RESET}"
  fi
}

uninstall() {
  systemctl stop microsocks 2>/dev/null || true
  systemctl disable microsocks 2>/dev/null || true
  rm -f "$BIN_PATH" "$SERVICE_FILE" "$USERS_FILE"
  systemctl daemon-reload
  echo -e "${GREEN}microsocks 已卸载${RESET}"
}

modify_config() {
  PORT=$(prompt "请输入监听端口" "$DEFAULT_PORT")
  USERNAME=$(prompt "请输入用户名" "admin")
  PASSWORD=$(prompt "请输入密码" "admin")
  setup_service "$PORT" "$USERNAME" "$PASSWORD"
  echo -e "${GREEN}配置已更新并重启服务${RESET}"
  show_links
}

while true; do
  echo -e "\n请选择操作:"
  echo "1) 安装/重新安装 microsocks"
  echo "2) 修改配置"
  echo "3) 卸载 microsocks"
  echo "4) 状态 (含 SOCKS 链接)"
  echo "5) 退出"
  read -rp "请选择 (1-5): " CHOICE
  case "$CHOICE" 在
    1)
      install_microsocks
      modify_config
      ;;
    2)
      modify_config
      ;;
    3)
      uninstall
      ;;
    4)
      show_links
      ;;
    5)
      exit 0
      ;;
    *)
      echo -e "${RED}无效选择${RESET}"
      ;;
  esac
done
