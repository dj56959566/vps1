#!/usr/bin/env bash
#
# 交互式 socks5 管理脚本（安装 / 修改 / 卸载）
# 安装并启动后会自动检测本机公网 IP（若不可用则回退本地 IP），并输出：
#  - socks://user:pass@IP:PORT
#  - Telegram 快链：https://t.me/socks?server=IP&port=PORT&user=USER&pass=PASS
# 头部显示：djkyc
#
set -o errexit
set -o nounset
set -o pipefail

GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
RESET="\e[0m"

echo -e "${GREEN}
  ____   ___   ____ _  ______ ____  
 / ___| / _ \\ / ___| |/ / ___| ___|  
 \\___ \\| | | | |   | ' /\\___ \\___ \\ 
  ___) | |_| | |___| . \\ ___) |__) |           
 |____/ \\___/ \\____|_|\\_\\____/____/  没有售后   
 djkyc
${RESET}"

WORKDIR="${HOME:-/root}/.s5_manager"
PID_FILE="${WORKDIR}/s5.pid"
META_FILE="${WORKDIR}/meta.env"
CONFIG_S5="${WORKDIR}/config.json"
CONFIG_3PROXY="${WORKDIR}/3proxy.cfg"
FALLBACK_S5_URL="https://github.com/eooce/test/releases/download/freebsd/web"
FALLBACK_S5_BIN="${WORKDIR}/s5_fallback"
DEFAULT_PORT=1080
DEFAULT_USER="s5user"

PREFERRED_IMPLS=("s5" "3proxy" "microsocks" "ss5" "danted" "sockd")

ensure_workdir() {
  mkdir -p "${WORKDIR}"
  chmod 700 "${WORKDIR}"
}

load_meta() {
  if [ -f "${META_FILE}" ]; then
    # shellcheck disable=SC1090
    source "${META_FILE}"
  else
    PORT=""
    USERNAME=""
    PASSWORD=""
    BIN_TYPE=""
  fi
}

save_meta() {
  cat > "${META_FILE}" <<EOF
PORT='${PORT}'
USERNAME='${USERNAME}'
PASSWORD='${PASSWORD}'
BIN_TYPE='${BIN_TYPE}'
EOF
  chmod 600 "${META_FILE}"
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

random_pass() {
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12 || echo "s5pass123"
}

detect_existing_impl() {
  for impl in "${PREFERRED_IMPLS[@]}"; do
    case "${impl}" in
      s5)
        if command -v s5 >/dev/null 2>&1 || [ -f "${FALLBACK_S5_BIN}" ]; then
          echo "s5"
          return 0
        fi
        ;;
      3proxy)
        if command -v 3proxy >/dev/null 2>&1; then
          echo "3proxy"
          return 0
        fi
        ;;
      microsocks)
        if command -v microsocks >/dev/null 2>&1; then
          echo "microsocks"
          return 0
        fi
        ;;
      ss5)
        if command -v ss5 >/dev/null 2>&1; then
          echo "ss5"
          return 0
        fi
        ;;
      danted|sockd)
        if command -v sockd >/dev/null 2>&1 || command -v danted >/dev/null 2>&1; then
          echo "danted"
          return 0
        fi
        ;;
    esac
  done
  echo ""
}

try_install_3proxy() {
  echo "尝试通过包管理器安装 3proxy..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y && apt-get install -y 3proxy && return 0 || return 1
  elif command -v yum >/dev/null 2>&1; then
    yum install -y 3proxy && return 0 || return 1
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y 3proxy && return 0 || return 1
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache 3proxy && return 0 || return 1
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm 3proxy && return 0 || return 1
  elif command -v pkg >/dev/null 2>&1; then
    pkg install -y 3proxy && return 0 || return 1
  fi
  return 1
}

download_fallback_s5() {
  echo "下载备用 s5 二进制到 ${FALLBACK_S5_BIN} ..."
  curl -L -sS -o "${FALLBACK_S5_BIN}" "${FALLBACK_S5_URL}" || return 1
  chmod 700 "${FALLBACK_S5_BIN}"
  return 0
}

generate_3proxy_cfg() {
  local port="$1" user="$2" pass="$3" cfg="${CONFIG_3PROXY}"
  cat > "${cfg}" <<EOF
daemon
maxconn 100
nserver 8.8.8.8
nserver 8.8.4.4
timeouts 1 5 30 60 180 1800 15 60
users ${user}:CL:${pass}
auth strong
allow ${user}
socks -p${port}
EOF
  chmod 600 "${cfg}"
  echo "${cfg}"
}

generate_s5_json() {
  local port="$1" user="$2" pass="$3" cfg="${CONFIG_S5}"
  cat > "${cfg}" <<EOF
{
  "log": {
    "access": "/dev/null",
    "error": "/dev/null",
    "loglevel": "none"
  },
  "inbounds": [
    {
      "port": ${port},
      "protocol": "socks",
      "tag": "socks",
      "settings": {
        "auth": "password",
        "udp": false,
        "ip": "0.0.0.0",
        "userLevel": 0,
        "accounts": [
          {
            "user": "${user}",
            "pass": "${pass}"
          }
        ]
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom"
    }
  ]
}
EOF
  chmod 600 "${cfg}"
  echo "${cfg}"
}

# 获取公网 IP（优先），回退到本地路由/hostname，最后回退 127.0.0.1
get_best_ip() {
  local ip
  for svc in "https://icanhazip.com" "https://ifconfig.me" "https://ipinfo.io/ip" "https://4.ipw.cn"; do
    ip=$(curl -s --max-time 5 "$svc" || true)
    ip=$(echo "$ip" | tr -d '[:space:]')
    if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "$ip"
      return 0
    fi
  done

  if command -v ip >/dev/null 2>&1; then
    ip=$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {print $7; exit}')
    ip=$(echo "$ip" | tr -d '[:space:]')
    if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "$ip"
      return 0
    fi
  fi

  if command -v hostname >/dev/null 2>&1; then
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    ip=$(echo "$ip" | tr -d '[:space:]')
    if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "$ip"
      return 0
    fi
  fi

  echo "127.0.0.1"
}

# URL 编码（尝试 python3 / python / perl，否者原样返回）
urlencode() {
  local s="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import sys,urllib.parse as u; print(u.quote(sys.argv[1], safe=''))" "$s"
  elif command -v python >/dev/null 2>&1; then
    python -c "import sys,urllib as u; print(u.quote(sys.argv[1]))" "$s"
  elif command -v perl >/dev/null 2>&1; then
    perl -MURI::Escape -e 'print uri_escape($ARGV[0]);' "$s"
  else
    printf '%s' "$s"
  fi
}

# 在启动成功后显示链接（socks 和 Telegram 快链）
show_links() {
  local ip port user pass enc_user enc_pass enc_ip tlink socksurl
  ip="$(get_best_ip)"
  port="${PORT}"
  user="${USERNAME}"
  pass="${PASSWORD}"
  enc_user="$(urlencode "$user")"
  enc_pass="$(urlencode "$pass")"
  enc_ip="$(urlencode "$ip")"

  socksurl="socks://${user}:${pass}@${ip}:${port}"
  tlink="https://t.me/socks?server=${enc_ip}&port=${port}&user=${enc_user}&pass=${enc_pass}"

  echo
  echo -e "${GREEN}安装并启动完成:${RESET}"
  echo "socks 地址示例：${socksurl}"
  echo "Telegram 快链：${tlink}"
  echo
}

start_by_type() {
  local type="$1"
  case "${type}" in
    3proxy)
      cfg="$(generate_3proxy_cfg "${PORT}" "${USERNAME}" "${PASSWORD}")"
      nohup 3proxy "${cfg}" >/dev/null 2>&1 &
      echo "$!" > "${PID_FILE}"
      ;;
    s5)
      if command -v s5 >/dev/null 2>&1; then
        BIN_PATH="$(command -v s5)"
        generate_s5_json "${PORT}" "${USERNAME}" "${PASSWORD}" >/dev/null
        nohup "${BIN_PATH}" -c "${CONFIG_S5}" >/dev/null 2>&1 &
        echo "$!" > "${PID_FILE}"
      else
        generate_s5_json "${PORT}" "${USERNAME}" "${PASSWORD}" >/dev/null
        nohup "${FALLBACK_S5_BIN}" -c "${CONFIG_S5}" >/dev/null 2>&1 &
        echo "$!" > "${PID_FILE}"
      fi
      ;;
    microsocks)
      nohup microsocks -p "${PORT}" -u "${USERNAME}" -P "${PASSWORD}" >/dev/null 2>&1 &
      echo "$!" > "${PID_FILE}"
      ;;
    ss5)
      nohup ss5 -u "${USERNAME}:${PASSWORD}" -p "${PORT}" >/dev/null 2>&1 &
      echo "$!" > "${PID_FILE}"
      ;;
    danted)
      echo -e "${YELLOW}检测到 danted/sockd，脚本不会自动生成完整服务配置。请手动配置并启动 danted。${RESET}"
      return 1
      ;;
    *)
      echo -e "${RED}未知实现类型：${type}${RESET}"
      return 1
      ;;
  esac

  sleep 1
  if [ -f "${PID_FILE}" ] && kill -0 "$(cat "${PID_FILE}")" >/dev/null 2>&1; then
    echo -e "${GREEN}已启动 ${type}，PID=$(cat "${PID_FILE}")${RESET}"
    show_links
    return 0
  else
    echo -e "${RED}启动失败（查看日志或手动启动）。${RESET}"
    return 1
  fi
}

stop_socks() {
  if [ -f "${PID_FILE}" ]; then
    pid="$(cat "${PID_FILE}")"
    if kill "${pid}" >/dev/null 2>&1; then
      echo "正在停止 PID ${pid} ..."
      sleep 1
      rm -f "${PID_FILE}" || true
    fi
  fi
  for p in s5 3proxy microsocks ss5 danted sockd; do
    if pgrep -x "${p}" >/dev/null 2>&1; then
      pkill -x "${p}" || true
    fi
  done
}

install_flow() {
  ensure_workdir
  echo "安装/配置 socks5（交互）"
  prompt "监听端口" "${DEFAULT_PORT}" PORT
  if ! [[ "${PORT}" =~ ^[0-9]+$ ]] || [ "${PORT}" -lt 1 ] || [ "${PORT}" -gt 65535 ]; then
    echo "端口输入无效，使用默认 ${DEFAULT_PORT}"
    PORT="${DEFAULT_PORT}"
  fi
  prompt "用户名" "${DEFAULT_USER}" USERNAME
  prompt "密码（留空则自动生成）" "" PASSWORD
  if [ -z "${PASSWORD}" ]; then
    PASSWORD="$(random_pass)"
    echo "已生成密码：${PASSWORD}"
  fi

  EXIST="$(detect_existing_impl || true)"
  if [ -n "${EXIST}" ]; then
    echo "检测到系统可用实现：${EXIST}（将尝试使用它）"
    BIN_TYPE="${EXIST}"
  else
    echo "未检测到受支持的实现，尝试安装 3proxy ..."
    if try_install_3proxy; then
      if command -v 3proxy >/dev/null 2>&1; then
        BIN_TYPE="3proxy"
        echo "已安装 3proxy"
      fi
    fi
  fi

  if [ -z "${BIN_TYPE}" ]; then
    if download_fallback_s5; then
      BIN_TYPE="s5"
      echo "使用下载的备用 s5 二进制（已保存到 ${FALLBACK_S5_BIN}）"
    else
      echo -e "${RED}未能安装或下载任何 socks5 实现。请手动安装 3proxy/danted/microsocks，或检查网络。${RESET}"
      return 1
    fi
  fi

  save_meta
  start_by_type "${BIN_TYPE}" || { echo "启动失败"; return 1; }
  return 0
}

modify_flow() {
  ensure_workdir
  load_meta
  if [ -z "${BIN_TYPE}" ]; then
    EXIST="$(detect_existing_impl || true)"
    BIN_TYPE="${EXIST:-}"
  fi
  if [ -z "${BIN_TYPE}" ]; then
    echo -e "${YELLOW}未检测到现有安装。请先运行 安装。${RESET}"
    return 1
  fi

  echo "修改 socks5 配置（当前实现：${BIN_TYPE}）"
  prompt "新的监听端口（回车保留当前: ${PORT:-unset})" "${PORT:-${DEFAULT_PORT}}" NEW_PORT
  if ! [[ "${NEW_PORT}" =~ ^[0-9]+$ ]] || [ "${NEW_PORT}" -lt 1 ] || [ "${NEW_PORT}" -gt 65535 ]; then
    echo "端口无效，保留原值"
    NEW_PORT="${PORT}"
  fi
  prompt "新的用户名（回车保留当前: ${USERNAME:-unset})" "${USERNAME:-${DEFAULT_USER}}" NEW_USER
  prompt "新的密码（留空则自动生成）" "" NEW_PASS
  if [ -z "${NEW_PASS}" ]; then
    NEW_PASS="$(random_pass)"
    echo "已生成新密码：${NEW_PASS}"
  fi

  PORT="${NEW_PORT}"
  USERNAME="${NEW_USER}"
  PASSWORD="${NEW_PASS}"

  save_meta
  echo "正在重启代理以应用修改..."
  stop_socks
  start_by_type "${BIN_TYPE}" || { echo "重启失败，请检查日志"; return 1; }
  echo -e "${GREEN}修改并重启完成。${RESET}"
  return 0
}

uninstall_flow() {
  ensure_workdir
  echo -e "${YELLOW}卸载将停止代理并删除目录：${WORKDIR}。此操作不可恢复。${RESET}"
  prompt "确认卸载并删除所有文件？输入 Y 确认" "N" CONFIRM
  if [ "${CONFIRM}" != "Y" ]; then
    echo "已取消卸载。"
    return 0
  fi
  stop_socks
  rm -rf "${WORKDIR}" && echo "已删除 ${WORKDIR}" || echo "删除 ${WORKDIR} 时出错或该目录不存在。"
  return 0
}

status_flow() {
  ensure_workdir
  load_meta
  if [ -f "${PID_FILE}" ]; then
    pid="$(cat "${PID_FILE}")"
    if kill -0 "${pid}" >/dev/null 2>&1; then
      echo -e "${GREEN}socks5 正在运行，PID=${pid}${RESET}"
    else
      echo -e "${YELLOW}PID 文件存在但进程未运行。${RESET}"
    fi
  else
    if pgrep -x s5 >/dev/null 2>&1 || pgrep -x 3proxy >/dev/null 2>&1; then
      echo -e "${GREEN}检测到 socks5 相关进程在运行（但无 PID 文件）。${RESET}"
    else
      echo -e "${YELLOW}未检测到 socks5 运行。${RESET}"
    fi
  fi
  if [ -f "${META_FILE}" ]; then
    echo "当前配置："
    sed -n '1,3p' "${META_FILE}" || true
  else
    echo "未找到配置（meta）。"
  fi
}

main_menu() {
  while true; do
    echo
    echo "请选择操作："
    echo "1) 安装 socks5"
    echo "2) 修改 socks5 配置"
    echo "3) 卸载 socks5"
    echo "4) 状态"
    echo "5) 退出"
    read -r -p "请选择 (1-5): " opt < /dev/tty || opt="5"
    case "${opt}" in
      1) install_flow ;;
      2) modify_flow ;;
      3) uninstall_flow ;;
      4) status_flow ;;
      5) echo "退出。"; exit 0 ;;
      *) echo "无效选项。" ;;
    esac
  done
}

ensure_workdir
load_meta
main_menu
