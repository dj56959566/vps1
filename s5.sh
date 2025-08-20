#!/usr/bin/env bash
set -euo pipefail

GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
RESET="\e[0m"

echo -e "${GREEN}
  ____   ___   ____ _  ______ ____  
 / ___| / _ \\ / ___| |/ / ___| ___|  
 \\___ \\| | | | |   | ' /\\___ \\___ \\ 
  ___) | |_| | |___| . \\ ___) |__) |           
 |____/ \\___/ \\____|_|\\_\\____/____/            
 By:djkyc 鸣谢:eooce 本脚本:microsocks
${RESET}"

WORKDIR="/etc/microsocks"
BIN_PATH="${WORKDIR}/microsocks"
SERVICE_FILE="/etc/systemd/system/microsocks.service"
USERS_FILE="${WORKDIR}/users.conf"
DEFAULT_PORT=1080

mkdir -p "$WORKDIR"

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

# 获取公网 IP
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

# URL encode
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

main() {
  install_microsocks

  PORT=$(prompt "请输入监听端口" "$DEFAULT_PORT")
  USERNAME=$(prompt "请输入用户名" "admin")
  PASSWORD=$(prompt "请输入密码" "admin")

  setup_service "$PORT" "$USERNAME" "$PASSWORD"

  IP=$(get_ip)
  SOCKS="socks://$USERNAME:$PASSWORD@$IP:$PORT"
  TLINK="https://t.me/socks?server=$(urlencode $IP)&port=$PORT&user=$(urlencode $USERNAME)&pass=$(urlencode $PASSWORD)"

  echo -e "${GREEN}microsocks 已启动并设置开机自启${RESET}"
  echo "SOCKS 链接: $SOCKS"
  echo "Telegram 快链: $TLINK"
}

main
