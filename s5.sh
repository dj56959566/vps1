#!/usr/bin/env bash
# 自动安装并启动 SOCKS5（自动识别 aarch64 / x86_64）
set -o errexit
set -o nounset
set -o pipefail

GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
RESET="\e[0m"

WORKDIR="${HOME:-/root}/.s5_manager"
PID_FILE="${WORKDIR}/s5.pid"
META_FILE="${WORKDIR}/meta.env"
CONFIG_S5="${WORKDIR}/config.json"
DEFAULT_PORT=1080
DEFAULT_USER="s5user"

ARCH=$(uname -m)
S5_BIN="${WORKDIR}/s5_binary"

ensure_workdir() {
  mkdir -p "${WORKDIR}"
  chmod 700 "${WORKDIR}"
}

random_pass() {
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12 || echo "s5pass123"
}

prompt() {
  local prompt_text="$1"
  local default="${2:-}"
  local varname="$3"
  local input
  if [ -n "${default}" ]; then
    printf "%s [%s]: " "${prompt_text}" "${default}" > /dev/tty
  else
    printf "%s: " "${prompt_text}" > /dev/tty
  fi
  read -r input < /dev/tty || input=""
  if [ -z "${input}" ]; then
    input="${default}"
  fi
  printf -v "${varname}" "%s" "${input}"
}

save_meta() {
  cat > "${META_FILE}" <<EOF
PORT='${PORT}'
USERNAME='${USERNAME}'
PASSWORD='${PASSWORD}'
EOF
  chmod 600 "${META_FILE}"
}

generate_s5_json() {
  cat > "${CONFIG_S5}" <<EOF
{
  "log": {"access": "/dev/null","error": "/dev/null","loglevel": "none"},
  "inbounds": [{"port": ${PORT},"protocol": "socks","tag": "socks","settings": {"auth": "password","udp": false,"ip": "0.0.0.0","userLevel": 0,"accounts": [{"user": "${USERNAME}","pass": "${PASSWORD}"}]}}],
  "outbounds": [{"tag": "direct","protocol": "freedom"}]
}
EOF
  chmod 600 "${CONFIG_S5}"
}

download_s5_binary() {
  echo "检测架构：${ARCH}，下载对应 s5 二进制..."
  case "${ARCH}" in
    x86_64) URL="https://github.com/s5u/s5/releases/download/v1.0/s5-linux-amd64" ;;
    aarch64) URL="https://github.com/s5u/s5/releases/download/v1.0/s5-linux-arm64" ;;
    *) echo -e "${RED}不支持的架构 ${ARCH}${RESET}" ; exit 1 ;;
  esac
  curl -L -o "${S5_BIN}" "${URL}"
  chmod +x "${S5_BIN}"
}

start_s5() {
  generate_s5_json
  nohup "${S5_BIN}" -c "${CONFIG_S5}" &> "${WORKDIR}/s5.log" &
  echo $! > "${PID_FILE}"
  sleep 1
  if kill -0 $(cat "${PID_FILE}") >/dev/null 2>&1; then
    echo -e "${GREEN}s5 已启动，PID=$(cat "${PID_FILE}")${RESET}"
  else
    echo -e "${RED}启动失败，请查看日志 ${WORKDIR}/s5.log${RESET}"
    exit 1
  fi
}

show_links() {
  local ip=$(curl -s https://icanhazip.com || echo 127.0.0.1 | tr -d '\n')
  local enc_user=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${USERNAME}'))")
  local enc_pass=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${PASSWORD}'))")
  local enc_ip=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${ip}'))")
  echo "socks 地址：socks://${USERNAME}:${PASSWORD}@${ip}:${PORT}"
  echo "Telegram 快链：https://t.me/socks?server=${enc_ip}&port=${PORT}&user=${enc_user}&pass=${enc_pass}"
}

install_flow() {
  ensure_workdir
  prompt "监听端口" "${DEFAULT_PORT}" PORT
  prompt "用户名" "${DEFAULT_USER}" USERNAME
  prompt "密码（留空则自动生成）" "" PASSWORD
  [ -z "${PASSWORD}" ] && PASSWORD=$(random_pass) && echo "已生成密码：${PASSWORD}"

  download_s5_binary
  save_meta
  start_s5
  show_links
}

main() {
  echo -e "${GREEN}自动安装并启动 SOCKS5（支持 aarch64 / x86_64）${RESET}"
  install_flow
}

main

