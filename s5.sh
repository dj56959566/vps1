#!/usr/bin/env bash
#
# 自适应 socks5 管理脚本（安装 / 修改 / 卸载）
# 特点：自动检测系统环境并选择最佳实现方式
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
  ___) | |_| | |___| . \\ ___) |__) |           不要直连
 |____/ \\___/ \\____|_|\\_\\____/____/            没有售后   
 djkyc
${RESET}"

# 全局路径与文件
WORKDIR="${HOME:-/root}/.s5_manager"
PID_FILE="${WORKDIR}/s5.pid"
META_FILE="${WORKDIR}/meta.env"
CONFIG_S5="${WORKDIR}/config.json"
CONFIG_3PROXY="${WORKDIR}/3proxy.cfg"
LOG_FILE="${WORKDIR}/s5.log"
DEFAULT_PORT=1080
DEFAULT_USER="s5user"

# 系统信息变量
OS_TYPE=""
OS_VERSION=""
OS_ARCH=""
PACKAGE_MANAGER=""
INIT_SYSTEM=""

# 检测系统环境
detect_system() {
  # 检测操作系统类型
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_TYPE="${ID}"
    OS_VERSION="${VERSION_ID}"
  elif [ -f /etc/redhat-release ]; then
    OS_TYPE="rhel"
  elif [ -f /etc/debian_version ]; then
    OS_TYPE="debian"
  elif uname -s | grep -q "FreeBSD"; then
    OS_TYPE="freebsd"
  else
    OS_TYPE="unknown"
  fi
  
  # 检测系统架构
  OS_ARCH=$(uname -m)
  case "${OS_ARCH}" in
    x86_64) OS_ARCH="amd64" ;;
    i*86) OS_ARCH="386" ;;
    aarch64|arm64) OS_ARCH="arm64" ;;
    armv7*|armv6*) OS_ARCH="arm" ;;
  esac
  
  # 检测包管理器
  if command -v apt-get >/dev/null 2>&1; then
    PACKAGE_MANAGER="apt"
  elif command -v yum >/dev/null 2>&1; then
    PACKAGE_MANAGER="yum"
  elif command -v dnf >/dev/null 2>&1; then
    PACKAGE_MANAGER="dnf"
  elif command -v apk >/dev/null 2>&1; then
    PACKAGE_MANAGER="apk"
  elif command -v pacman >/dev/null 2>&1; then
    PACKAGE_MANAGER="pacman"
  elif command -v pkg >/dev/null 2>&1; then
    PACKAGE_MANAGER="pkg"
  else
    PACKAGE_MANAGER="unknown"
  fi
  
  # 检测初始化系统
  if command -v systemctl >/dev/null 2>&1; then
    INIT_SYSTEM="systemd"
  elif [ -d /etc/init.d ]; then
    INIT_SYSTEM="sysvinit"
  elif [ -f /sbin/openrc ]; then
    INIT_SYSTEM="openrc"
  else
    INIT_SYSTEM="unknown"
  fi
  
  echo "系统检测结果: ${OS_TYPE} ${OS_VERSION} (${OS_ARCH}), 包管理器: ${PACKAGE_MANAGER}, 初始化系统: ${INIT_SYSTEM}"
}

# 根据系统选择最佳实现
select_best_implementation() {
  # 首先检查是否已有实现
  local existing_impl=""
  for impl in "microsocks" "3proxy" "s5" "ss5" "danted" "sockd"; do
    if command -v "${impl}" >/dev/null 2>&1; then
      existing_impl="${impl}"
      break
    fi
  done
  
  # 如果已有实现，直接使用
  if [ -n "${existing_impl}" ]; then
    echo "${existing_impl}"
    return 0
  fi
  
  # 根据系统类型选择最佳实现
  case "${OS_TYPE}" in
    debian|ubuntu|raspbian)
      echo "microsocks"  # Debian系统首选microsocks
      ;;
    centos|rhel|fedora|rocky|almalinux)
      echo "3proxy"  # RHEL系统首选3proxy
      ;;
    alpine)
      echo "microsocks"  # Alpine首选microsocks
      ;;
    arch|manjaro)
      echo "microsocks"  # Arch首选microsocks
      ;;
    freebsd)
      echo "3proxy"  # FreeBSD首选3proxy
      ;;
    *)
      # 默认选择
      if [ "${OS_ARCH}" = "arm" ] || [ "${OS_ARCH}" = "arm64" ]; then
        echo "microsocks"  # ARM架构首选microsocks
      else
        echo "3proxy"  # 其他架构首选3proxy
      fi
      ;;
  esac
}

# 安装指定的实现
install_implementation() {
  local impl="$1"
  echo "尝试安装 ${impl}..."
  
  case "${PACKAGE_MANAGER}" in
    apt)
      apt-get update -y && apt-get install -y "${impl}"
      ;;
    yum)
      yum install -y "${impl}"
      ;;
    dnf)
      dnf install -y "${impl}"
      ;;
    apk)
      apk add --no-cache "${impl}"
      ;;
    pacman)
      pacman -Sy --noconfirm "${impl}"
      ;;
    pkg)
      pkg install -y "${impl}"
      ;;
    *)
      echo "未知的包管理器，无法安装 ${impl}"
      return 1
      ;;
  esac
  
  # 检查安装结果
  if command -v "${impl}" >/dev/null 2>&1; then
    echo "${impl} 安装成功"
    return 0
  else
    echo "${impl} 安装失败"
    return 1
  fi
}

# 下载备用二进制
download_fallback_binary() {
  local impl="$1"
  local arch="${OS_ARCH}"
  local url=""
  local bin_path=""
  
  case "${impl}" in
    s5)
      url="https://github.com/eooce/test/releases/download/freebsd/web"
      bin_path="${WORKDIR}/s5_fallback"
      ;;
    microsocks)
      url="https://github.com/rofl0r/microsocks/releases/download/v1.0.3/microsocks-linux-${arch}"
      bin_path="${WORKDIR}/microsocks_fallback"
      ;;
    3proxy)
      url="https://github.com/3proxy/3proxy/releases/download/0.9.4/3proxy-0.9.4-linux-${arch}.tar.gz"
      bin_path="${WORKDIR}/3proxy_fallback"
      ;;
    *)
      echo "不支持下载 ${impl} 的备用二进制"
      return 1
      ;;
  esac
  
  echo "下载 ${impl} 备用二进制到 ${bin_path}..."
  
  if [[ "${url}" == *.tar.gz ]]; then
    # 处理压缩包
    local temp_dir="${WORKDIR}/temp"
    mkdir -p "${temp_dir}"
    curl -L -sS -o "${temp_dir}/archive.tar.gz" "${url}" || return 1
    tar -xzf "${temp_dir}/archive.tar.gz" -C "${temp_dir}" || return 1
    find "${temp_dir}" -name "3proxy" -type f -exec cp {} "${bin_path}" \; || return 1
    rm -rf "${temp_dir}"
  else
    # 直接下载二进制
    curl -L -sS -o "${bin_path}" "${url}" || return 1
  fi
  
  chmod 700 "${bin_path}"
  echo "备用二进制下载完成: ${bin_path}"
  return 0
}

# 记录日志
log() {
  local level="$1"
  local message="$2"
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}" 2>/dev/null || true
  
  case "${level}" in
    ERROR)
      echo -e "${RED}${message}${RESET}"
      ;;
    WARN)
      echo -e "${YELLOW}${message}${RESET}"
      ;;
    INFO)
      echo -e "${GREEN}${message}${RESET}"
      ;;
    *)
      echo "${message}"
      ;;
  esac
}

# 确保工作目录存在
ensure_workdir() {
  mkdir -p "${WORKDIR}"
  chmod 700 "${WORKDIR}"
  touch "${LOG_FILE}" 2>/dev/null || true
  chmod 600 "${LOG_FILE}" 2>/dev/null || true
}

# 从 meta.env 加载（若存在）
load_meta() {
  if [ -f "${META_FILE}" ]; then
    # shellcheck disable=SC1090
    source "${META_FILE}"
  else
    PORT=""
    USERNAME=""
    PASSWORD=""
    BIN_TYPE=""
    BIN_PATH=""
  fi
}

# 保存 meta
save_meta() {
  cat > "${META_FILE}" <<EOF
PORT='${PORT}'
USERNAME='${USERNAME}'
PASSWORD='${PASSWORD}'
BIN_TYPE='${BIN_TYPE}'
BIN_PATH='${BIN_PATH}'
EOF
  chmod 600 "${META_FILE}"
}

# 安全地从终端读取（支持 curl | bash 场景）
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

# 简单随机密码生成
random_pass() {
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12 || echo "s5pass123"
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

# 检查端口是否有监听
is_port_listening() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | awk '{print $4}' | grep -E "[:.]${port}$" >/dev/null 2>&1 && return 0 || return 1
  elif command -v netstat >/dev/null 2>&1; then
    netstat -ltn 2>/dev/null | awk '{print $4}' | grep -E "[:.]${port}$" >/dev/null 2>&1 && return 0 || return 1
  else
    return 1
  fi
}

# 配置防火墙
configure_firewall() {
  local port="$1"
  
  # 检测防火墙类型并配置
  if command -v ufw >/dev/null 2>&1; then
    # Ubuntu/Debian UFW
    ufw allow "${port}"/tcp
    log "INFO" "已配置 UFW 防火墙规则"
  elif command -v firewall-cmd >/dev/null 2>&1; then
    # CentOS/RHEL/Fedora firewalld
    firewall-cmd --permanent --add-port="${port}"/tcp
    firewall-cmd --reload
    log "INFO" "已配置 firewalld 防火墙规则"
  elif command -v iptables >/dev/null 2>&1; then
    # 通用 iptables
    iptables -A INPUT -p tcp --dport "${port}" -j ACCEPT
    log "INFO" "已配置 iptables 防火墙规则"
  else
    log "WARN" "未检测到支持的防火墙工具，请手动配置防火墙规则"
  fi
}

# 创建系统服务
create_service() {
  local service_name="s5proxy"
  
  if [ "${INIT_SYSTEM}" = "systemd" ]; then
    # systemd
    cat > "/etc/systemd/system/${service_name}.service" <<EOF
[Unit]
Description=SOCKS5 Proxy Service (${BIN_TYPE})
After=network.target

[Service]
Type=simple
User=${USER:-root}
WorkingDirectory=${WORKDIR}
ExecStart=${BIN_PATH} ${SERVICE_ARGS}
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "${service_name}"
    systemctl start "${service_name}"
    log "INFO" "已创建并启动 systemd 服务: ${service_name}"
    return 0
  elif [ "${INIT_SYSTEM}" = "sysvinit" ]; then
    # SysV init
    cat > "/etc/init.d/${service_name}" <<EOF
#!/bin/sh
### BEGIN INIT INFO
# Provides:          ${service_name}
# Required-Start:    \$network \$remote_fs \$syslog
# Required-Stop:     \$network \$remote_fs \$syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: SOCKS5 Proxy Service
### END INIT INFO

DAEMON=${BIN_PATH}
DAEMON_ARGS="${SERVICE_ARGS}"
NAME=${service_name}
DESC="SOCKS5 Proxy Service"
PIDFILE=${PID_FILE}
SCRIPTNAME=/etc/init.d/\$NAME

case "\$1" in
  start)
    echo "Starting \$DESC" "\$NAME"
    start-stop-daemon --start --background --make-pidfile --pidfile \$PIDFILE --exec \$DAEMON -- \$DAEMON_ARGS
    ;;
  stop)
    echo "Stopping \$DESC" "\$NAME"
    start-stop-daemon --stop --pidfile \$PIDFILE --retry=TERM/30/KILL/5
    rm -f \$PIDFILE
    ;;
  restart)
    \$0 stop
    \$0 start
    ;;
  status)
    if [ -f \$PIDFILE ]; then
      if kill -0 \$(cat \$PIDFILE) > /dev/null 2>&1; then
        echo "\$NAME is running"
        exit 0
      fi
    fi
    echo "\$NAME is not running"
    exit 1
    ;;
  *)
    echo "Usage: \$SCRIPTNAME {start|stop|restart|status}" >&2
    exit 3
    ;;
esac

exit 0
EOF
    chmod +x "/etc/init.d/${service_name}"
    if command -v update-rc.d >/dev/null 2>&1; then
      update-rc.d "${service_name}" defaults
    elif command -v chkconfig >/dev/null 2>&1; then
      chkconfig --add "${service_name}"
      chkconfig "${service_name}" on
    fi
    service "${service_name}" start
    log "INFO" "已创建并启动 SysV init 服务: ${service_name}"
    return 0
  else
    log "WARN" "未检测到支持的服务管理器，将使用后台进程方式运行"
    return 1
  fi
}

# 生成配置文件
generate_config() {
  local type="$1"
  local port="$2"
  local user="$3"
  local pass="$4"
  
  case "${type}" in
    3proxy)
      cat > "${CONFIG_3PROXY}" <<EOF
# 3proxy config (generated)
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
      chmod 600 "${CONFIG_3PROXY}"
      ;;
    s5)
      cat > "${CONFIG_S5}" <<EOF
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
      chmod 600 "${CONFIG_S5}"
      ;;
  esac
}

# 启动代理
start_proxy() {
  # 根据实现类型设置启动命令和参数
  case "${BIN_TYPE}" in
    3proxy)
      if [ -z "${BIN_PATH}" ]; then
        BIN_PATH="$(command -v 3proxy)"
      fi
      generate_config "3proxy" "${PORT}" "${USERNAME}" "${PASSWORD}"
      SERVICE_ARGS="${CONFIG_3PROXY}"
      ;;
    s5)
      if [ -z "${BIN_PATH}" ]; then
        BIN_PATH="$(command -v s5 || echo "${WORKDIR}/s5_fallback")"
      fi
      generate_config "s5" "${PORT}" "${USERNAME}" "${PASSWORD}"
      SERVICE_ARGS="-c ${CONFIG_S5}"
      ;;
    microsocks)
      if [ -z "${BIN_PATH}" ]; then
        BIN_PATH="$(command -v microsocks || echo "${WORKDIR}/microsocks_fallback")"
      fi
      SERVICE_ARGS="-p ${PORT} -u ${USERNAME} -P ${PASSWORD}"
      ;;
    ss5)
      if [ -z "${BIN_PATH}" ]; then
        BIN_PATH="$(command -v ss5)"
      fi
      SERVICE_ARGS="-u ${USERNAME}:${PASSWORD} -p ${PORT}"
      ;;
    *)
      log "ERROR" "不支持的实现类型: ${BIN_TYPE}"
      return 1
      ;;
  esac
  
  # 尝试创建系统服务
  if [ "${USE_SERVICE}" = "true" ] && create_service; then
    log "INFO" "已通过系统服务启动 ${BIN_TYPE}"
    return 0
  fi
  
  # 如果服务创建失败或不使用服务，则使用后台进程方式启动
  log "INFO" "使用后台进程方式启动 ${BIN_TYPE}"
  nohup "${BIN_PATH}" ${SERVICE_ARGS} > "${WORKDIR}/${BIN_TYPE}.log" 2>&1 &
  echo "$!" > "${PID_FILE}"
  
  # 检查启动结果
  sleep 1
  if [ -f "${PID_FILE}" ] && kill -0 "$(cat "${PID_FILE}")" >/dev/null 2>&1; then
    log "INFO" "已启动 ${BIN_TYPE}，PID=$(cat "${PID_FILE}")"
    return 0
  else
    log "ERROR" "启动失败，请查看日志: ${WORKDIR}/${BIN_TYPE}.log"
    cat "${WORKDIR}/${BIN_TYPE}.log"
    return 1
  fi
}

# 停止代理
stop_proxy() {
  # 尝试停止系统服务
  local service_name="s5proxy"
  local service_stopped=false
  
  if [ "${INIT_SYSTEM}" = "systemd" ] && systemctl is-active --quiet "${service_name}"; then
    systemctl stop "${service_name}"
    systemctl disable "${service_name}" 2>/dev/null || true
    rm -f "/etc/systemd/system/${service_name}.service" 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    service_stopped=true
  elif [ "${INIT_SYSTEM}" = "sysvinit" ] && service "${service_name}" status >/dev/null 2>&1; then
    service "${service_name}" stop
    if command -v update-rc.d >/dev/null 2>&1; then
      update-rc.d -f "${service_name}" remove 2>/dev/null || true
    elif command -v chkconfig >/dev/null 2>&1; then
      chkconfig "${service_name}" off 2>/dev/null || true
      chkconfig --del "${service_name}" 2>/dev/null || true
    fi
    rm -f "/etc/init.d/${service_name}" 2>/dev/null || true
    service_stopped=true
  fi
  
  # 如果服务已停止，则不需要再停止进程
  if [ "${service_stopped}" = "true" ]; then
    log "INFO" "已停止系统服务"
    return 0
  fi
  
  # 停止通过PID文件记录的进程
  if [ -f "${PID_FILE}" ]; then
    pid="$(cat "${PID_FILE}")"
    if kill "${pid}" >/dev/null 2>&1; then
      log "INFO" "正在停止 PID ${pid} ..."
      sleep 1
      rm -f "${PID_FILE}" || true
    fi
  fi
  
  # 尝试停止所有可能的进程
  for p in s5 3proxy microsocks ss5 danted sockd; do
    if pgrep -x "${p}" >/dev/null 2>&1; then
      pkill -x "${p}" || true
    fi
  done
  
  log "INFO" "代理已停止"
}

# 显示链接信息
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

# 安装流程
install_flow() {
  ensure_workdir
  detect_system
  
  log "INFO" "安装/配置 socks5（交互）"
  
  # 询问端口/用户/密码
  prompt "监听端口" "${DEFAULT_PORT}" PORT
  if ! [[ "${PORT}" =~ ^[0-9]+$ ]] || [ "${PORT}" -lt 1 ] || [ "${PORT}" -gt 65535 ]; then
    log "WARN" "端口输入无效，使用默认 ${DEFAULT_PORT}"
    PORT="${DEFAULT_PORT}"
  fi
  prompt "用户名" "${DEFAULT_USER}" USERNAME
  prompt "密码（留空则自动生成）" "" PASSWORD
  if [ -z "${PASSWORD}" ]; then
    PASSWORD="$(random_pass)"
    log "INFO" "已生成密码：${PASSWORD}"
  fi
  
  # 询问是否配置防火墙和系统服务
  prompt "是否配置防火墙规则？(Y/n)" "Y" SETUP_FIREWALL
  prompt "是否创建系统服务？(Y/n)" "Y" SETUP_SERVICE
  
  # 选择最佳实现
  BIN_TYPE="$(select_best_implementation)"
  log "INFO" "选择的实现: ${BIN_TYPE}"
  
  # 检查是否已安装
  if ! command -v "${BIN_TYPE}" >/dev/null 2>&1; then
    log "INFO" "未检测到 ${BIN_TYPE}，尝试安装..."
    if ! install_implementation "${BIN_TYPE}"; then
      log "WARN" "安装 ${BIN_TYPE} 失败，尝试下载备用二进制..."
      if ! download_fallback_binary "${BIN_TYPE}"; then
        log "ERROR" "无法安装或下载 ${BIN_TYPE}，尝试备选方案..."
        
        # 尝试备选实现
        for impl in "microsocks" "3proxy" "s5"; do
          if [ "${impl}" != "${BIN_TYPE}" ]; then
            log "INFO" "尝试备选实现: ${impl}"
            if install_implementation "${impl}" || download_fallback_binary "${impl}"; then
              BIN_TYPE="${impl}"
              log "INFO" "成功安装备选实现: ${BIN_TYPE}"
              break
            fi
          fi
        done
        
        if ! command -v "${BIN_TYPE}" >/dev/null 2>&1 && [ ! -f "${WORKDIR}/${BIN_TYPE}_fallback" ]; then
          log "ERROR" "所有实现方式都安装失败，请手动安装 microsocks/3proxy/s5"
          return 1
        fi
      fi
    fi
  fi
  
  # 设置二进制路径
  if command -v "${BIN_TYPE}" >/dev/null 2>&1; then
    BIN_PATH="$(command -v "${BIN_TYPE}")"
  else
    BIN_PATH="${WORKDIR}/${BIN_TYPE}_fallback"
  fi
  
  # 配置防火墙
  if [ "${SETUP_FIREWALL}" = "Y" ] || [ "${SETUP_FIREWALL}" = "y" ]; then
    configure_firewall "${PORT}"
  fi
  
  # 设置是否使用系统服务
  USE_SERVICE="false"
  if [ "${SETUP_SERVICE}" = "Y" ] || [ "${SETUP_SERVICE}" = "y" ]; then
    USE_SERVICE="true"
  fi
  
  # 保存配置
  save_meta
  
  # 启动代理
  if start_proxy; then
    show_links
    return 0
  else
    log "ERROR" "启动失败"
    return 1
  fi
}

# 修改流程
modify_flow() {
  ensure_workdir
  load_meta
  
  if [ -z "${BIN_TYPE}" ]; then
    log "ERROR" "未检测到现有安装。请先运行安装。"
    return 1
  fi
  
  log "INFO" "修改 socks5 配置（当前实现：${BIN_TYPE}）"
  
  prompt "新的监听端口（回车保留当前: ${PORT:-unset})" "${PORT:-${DEFAULT_PORT}}" NEW_PORT
