#!/usr/bin/env bash
#
# 交互式 socks5 管理脚本（安装 / 修改 / 卸载）
# 支持多种VPS环境（LXC、KVM、NAT VPS）和常用Linux发行版
# 支持多种实现（s5、3proxy、microsocks、ss5、danted）
# 安装并启动后会自动检测本机公网 IP（若不可用则回退本地 IP），并输出：
#  - socks://user:pass@IP:PORT
#  - Telegram 快链：https://t.me/socks?server=IP&port=PORT&user=USER&pass=PASS
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
 多系统多内核版
${RESET}"

WORKDIR="${HOME:-/root}/.s5_manager"
PID_FILE="${WORKDIR}/s5.pid"
META_FILE="${WORKDIR}/meta.env"
CONFIG_S5="${WORKDIR}/config.json"
CONFIG_3PROXY="${WORKDIR}/3proxy.cfg"
# singbox备用下载链接
SINGBOX_URL="https://github.com/SagerNet/sing-box/releases/download/v1.7.0/sing-box-1.7.0-linux-amd64.tar.gz"
SINGBOX_BIN="${WORKDIR}/sing-box"
DEFAULT_PORT=1080
DEFAULT_USER="s5user"

# 按资源占用从少到多排序的实现（只保留三个最轻量级的内核）
PREFERRED_IMPLS=("microsocks" "3proxy" "ss5")

# 检测VPS类型和配置
detect_vps_type() {
  echo -e "${GREEN}正在检测VPS类型和配置...${RESET}"
  
  # 检测虚拟化类型
  local vps_type="未知"
  
  # 检测是否为LXC
  if grep -q "lxc" /proc/1/cgroup 2>/dev/null || grep -q "container=lxc" /proc/1/environ 2>/dev/null; then
    vps_type="LXC容器"
  # 检测是否为Docker
  elif grep -q "docker" /proc/1/cgroup 2>/dev/null || [ -f /.dockerenv ]; then
    vps_type="Docker容器"
  # 检测是否为OpenVZ
  elif [ -d /proc/vz ] || grep -q "envID" /proc/self/status 2>/dev/null; then
    vps_type="OpenVZ容器"
  # 检测是否为KVM
  elif grep -q "kvm" /proc/cpuinfo 2>/dev/null; then
    vps_type="KVM虚拟机"
  # 检测是否为Xen
  elif grep -q "xen" /proc/cpuinfo 2>/dev/null; then
    vps_type="Xen虚拟机"
  # 检测是否为VMware
  elif dmidecode 2>/dev/null | grep -q "VMware"; then
    vps_type="VMware虚拟机"
  # 检测是否为物理机
  elif [ -d /sys/firmware/efi ]; then
    vps_type="物理服务器(EFI)"
  else
    vps_type="未知虚拟化环境"
  fi
  
  echo "VPS类型: $vps_type"
  
  # 检测CPU核心数
  local cpu_cores=$(grep -c "processor" /proc/cpuinfo 2>/dev/null || echo "未知")
  echo "CPU核心数: $cpu_cores"
  
  # 检测内存大小
  local mem_total=$(free -m | awk '/Mem:/ {print $2}' 2>/dev/null || echo "未知")
  echo "内存大小: ${mem_total}MB"
  
  # 检测磁盘空间
  local disk_space=$(df -h / | awk 'NR==2 {print $2}' 2>/dev/null || echo "未知")
  echo "磁盘空间: $disk_space"
  
  # 根据配置推荐最适合的内核
  echo -n "推荐内核: "
  
  # 如果内存小于128MB，推荐microsocks
  if [[ "$mem_total" =~ ^[0-9]+$ ]] && [ "$mem_total" -lt 128 ]; then
    echo "microsocks (超低内存环境)"
    export RECOMMENDED_KERNEL="microsocks"
  # 如果内存小于256MB，推荐3proxy
  elif [[ "$mem_total" =~ ^[0-9]+$ ]] && [ "$mem_total" -lt 256 ]; then
    echo "3proxy (低内存环境)"
    export RECOMMENDED_KERNEL="3proxy"
  # 如果内存大于等于256MB，推荐ss5
  else
    echo "ss5 (标准环境)"
    export RECOMMENDED_KERNEL="ss5"
  fi
  
  return 0
}

# 检测系统类型
detect_os() {
  echo -e "${GREEN}正在检测操作系统...${RESET}"
  
  if [ -f /etc/os-release ]; then
    # freedesktop.org and systemd
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
  elif type lsb_release >/dev/null 2>&1; then
    # linuxbase.org
    OS=$(lsb_release -si)
    VER=$(lsb_release -sr)
  elif [ -f /etc/lsb-release ]; then
    # For some versions of Debian/Ubuntu without lsb_release command
    . /etc/lsb-release
    OS=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
  elif [ -f /etc/debian_version ]; then
    # Older Debian/Ubuntu/etc.
    OS=Debian
    VER=$(cat /etc/debian_version)
  elif [ -f /etc/centos-release ]; then
    # Older CentOS
    OS=CentOS
    VER=$(cat /etc/centos-release | sed 's/^.*release \(.*\)\..*$/\1/')
  elif [ -f /etc/redhat-release ]; then
    # Older Red Hat, CentOS, etc.
    OS=RedHat
    VER=$(cat /etc/redhat-release | sed 's/^.*release \(.*\)\..*$/\1/')
  else
    # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
    OS=$(uname -s)
    VER=$(uname -r)
  fi
  
  echo "$OS $VER"
}

# 检测NAT环境
detect_nat() {
  echo -e "${GREEN}正在检测NAT环境...${RESET}"
  
  # 获取本地IP
  local_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {print $7; exit}')
  
  # 尝试获取公网IP
  public_ip=$(curl -s --max-time 5 https://icanhazip.com || curl -s --max-time 5 https://ifconfig.me || curl -s --max-time 5 https://ipinfo.io/ip || curl -s --max-time 5 https://4.ipw.cn)
  
  if [ -z "$public_ip" ] || [ "$local_ip" = "$public_ip" ]; then
    echo "未检测到NAT环境"
    return 1
  else
    echo "检测到NAT环境，本地IP: $local_ip，公网IP: $public_ip"
    return 0
  fi
}

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
  # 首先检查是否有singbox作为备用
  if [ -f "${SINGBOX_BIN}" ]; then
    echo "singbox"
    return 0
  fi
  
  # 然后按资源占用从少到多检查其他实现
  for impl in "${PREFERRED_IMPLS[@]}"; do
    case "${impl}" in
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

try_install_package() {
  local package="$1"
  echo "尝试安装 $package..."
  
  # 检测包管理器并安装
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y && apt-get install -y "$package" && return 0 || return 1
  elif command -v yum >/dev/null 2>&1; then
    yum install -y "$package" && return 0 || return 1
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y "$package" && return 0 || return 1
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache "$package" && return 0 || return 1
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm "$package" && return 0 || return 1
  elif command -v pkg >/dev/null 2>&1; then
    pkg install -y "$package" && return 0 || return 1
  fi
  return 1
}

try_install_3proxy() {
  echo "尝试通过包管理器安装 3proxy..."
  try_install_package "3proxy" && return 0
  
  # 如果包管理器安装失败，尝试从源码编译
  echo "包管理器安装失败，尝试从源码编译安装..."
  
  # 安装编译依赖
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y && apt-get install -y build-essential wget
  elif command -v yum >/dev/null 2>&1; then
    yum install -y gcc make wget
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y gcc make wget
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache gcc make musl-dev wget
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm base-devel wget
  fi
  
  # 下载并编译3proxy
  local tempdir=$(mktemp -d)
  cd "$tempdir"
  wget -q https://github.com/3proxy/3proxy/archive/0.9.4.tar.gz
  tar -xzf 0.9.4.tar.gz
  cd 3proxy-0.9.4
  
  # 检测系统类型并使用适当的Makefile
  if [ -f /etc/debian_version ] || [ -f /etc/ubuntu-release ]; then
    make -f Makefile.Linux
  elif [ -f /etc/redhat-release ] || [ -f /etc/centos-release ]; then
    make -f Makefile.Linux
  elif [ -f /etc/alpine-release ]; then
    make -f Makefile.Linux
  else
    make -f Makefile.Linux
  fi
  
  make install
  cd /
  rm -rf "$tempdir"
  
  # 检查是否安装成功
  if command -v 3proxy >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

try_install_microsocks() {
  echo "尝试通过包管理器安装 microsocks..."
  try_install_package "microsocks" && return 0
  
  # 如果包管理器安装失败，尝试从源码编译
  echo "包管理器安装失败，尝试从源码编译安装..."
  
  # 安装编译依赖
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y && apt-get install -y build-essential git
  elif command -v yum >/dev/null 2>&1; then
    yum install -y gcc make git
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y gcc make git
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache gcc make musl-dev git
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm base-devel git
  fi
  
  # 下载并编译microsocks
  local tempdir=$(mktemp -d)
  cd "$tempdir"
  git clone https://github.com/rofl0r/microsocks.git
  cd microsocks
  make
  cp microsocks /usr/local/bin/
  cd /
  rm -rf "$tempdir"
  
  # 检查是否安装成功
  if command -v microsocks >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

try_install_ss5() {
  echo "尝试通过包管理器安装 ss5..."
  try_install_package "ss5" && return 0
  return 1
}

try_install_danted() {
  echo "尝试通过包管理器安装 dante-server..."
  try_install_package "dante-server" && return 0
  return 1
}

# 下载singbox作为备用
download_singbox() {
  echo "下载备用 sing-box 到 ${SINGBOX_BIN} ..."
  local tempdir=$(mktemp -d)
  local tempfile="${tempdir}/singbox.tar.gz"
  
  # 下载singbox
  curl -L -sS -o "${tempfile}" "${SINGBOX_URL}" || return 1
  
  # 解压
  tar -xzf "${tempfile}" -C "${tempdir}"
  
  # 查找可执行文件并复制
  find "${tempdir}" -name "sing-box" -type f -exec cp {} "${SINGBOX_BIN}" \;
  
  # 设置权限
  chmod 700 "${SINGBOX_BIN}"
  
  # 清理临时文件
  rm -rf "${tempdir}"
  
  # 检查是否成功
  if [ -f "${SINGBOX_BIN}" ]; then
    return 0
  else
    return 1
  fi
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

generate_singbox_json() {
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
    singbox)
      generate_singbox_json "${PORT}" "${USERNAME}" "${PASSWORD}" >/dev/null
      nohup "${SINGBOX_BIN}" run -c "${CONFIG_S5}" >/dev/null 2>&1 &
      echo "$!" > "${PID_FILE}"
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
  for p in sing-box 3proxy microsocks ss5 danted sockd; do
    if pgrep -x "${p}" >/dev/null 2>&1; then
      pkill -x "${p}" || true
    fi
  done
}

# 系统优化函数
optimize_system() {
  echo -e "${GREEN}正在优化系统性能...${RESET}"
  
  # 检查是否为root用户
  if [ "$(id -u)" -ne 0 ]; then
    echo -e "${YELLOW}警告: 需要root权限才能进行系统优化${RESET}"
    return 1
  fi
  
  # 1. 调整系统文件描述符限制
  if [ -f /etc/security/limits.conf ]; then
    if ! grep -q "* soft nofile 51200" /etc/security/limits.conf; then
      echo "* soft nofile 51200" >> /etc/security/limits.conf
      echo "* hard nofile 51200" >> /etc/security/limits.conf
    fi
  fi
  
  # 2. 调整内核参数
  if [ -f /etc/sysctl.conf ]; then
    # 备份原始配置
    cp /etc/sysctl.conf /etc/sysctl.conf.bak
    
    # 添加优化参数
    cat >> /etc/sysctl.conf << EOF
# SOCKS5代理性能优化
fs.file-max = 51200
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 4096
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mem = 25600 51200 102400
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
EOF
    
    # 应用新的内核参数
    sysctl -p
  fi
  
  # 3. 根据内存大小调整优化策略
  local mem_total=$(free -m | awk '/Mem:/ {print $2}' 2>/dev/null || echo "0")
  if [[ "$mem_total" =~ ^[0-9]+$ ]]; then
    if [ "$mem_total" -lt 128 ]; then
      # 超低内存环境优化
      echo -e "${YELLOW}检测到超低内存环境 (${mem_total}MB)，应用特殊优化...${RESET}"
      # 禁用不必要的服务
      for svc in rsyslog cron atd; do
        if command -v systemctl >/dev/null 2>&1; then
          systemctl stop $svc 2>/dev/null || true
          systemctl disable $svc 2>/dev/null || true
        elif command -v service >/dev/null 2>&1; then
          service $svc stop 2>/dev/null || true
        fi
      done
      
      # 创建swap分区（如果不存在）
      if ! swapon -s | grep -q "/swapfile"; then
        echo "创建128MB swap分区以提高稳定性..."
        dd if=/dev/zero of=/swapfile bs=1M count=128
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo "/swapfile none swap sw 0 0" >> /etc/fstab
      fi
    elif [ "$mem_total" -lt 256 ]; then
      # 低内存环境优化
      echo -e "${YELLOW}检测到低内存环境 (${mem_total}MB)，应用内存优化...${RESET}"
      # 调整内存使用
      if [ -f /etc/sysctl.conf ]; then
        echo "vm.swappiness = 10" >> /etc/sysctl.conf
        echo "vm.vfs_cache_pressure = 50" >> /etc/sysctl.conf
        sysctl -p
      fi
    fi
  fi
  
  echo -e "${GREEN}系统优化完成${RESET}"
  return 0
}

check_environment() {
  echo -e "${GREEN}========================================${RESET}"
  echo -e "${GREEN}系统环境检测${RESET}"
  echo -e "${GREEN}----------------------------------------${RESET}"
  
  # 检测VPS类型和配置
  detect_vps_type
  
  # 检测操作系统
  echo -n "操作系统: "
  detect_os
  
  # 检测NAT环境
  detect_nat
  
  # 检测已安装的SOCKS5实现
  EXIST="$(detect_existing_impl || true)"
  if [ -n "${EXIST}" ]; then
    echo "已安装的SOCKS5实现: ${EXIST}"
  else
    echo "未检测到已安装的SOCKS5实现"
  fi
  
  # 检测公网IP
  echo "公网IP: $(get_best_ip)"
  
  # 检测系统负载
  local load=$(cat /proc/loadavg | awk '{print $1, $2, $3}' 2>/dev/null || echo "未知")
  echo "系统负载: $load"
  
  # 检测网络连接状态
  local connections=$(netstat -n | grep -c ESTABLISHED 2>/dev/null || echo "未知")
  echo "当前连接数: $connections"
  
  echo -e "${GREEN}========================================${RESET}"
  
  # 询问是否进行系统优化
  prompt "是否进行系统性能优化？(Y/n)" "Y" OPTIMIZE
  if [ "$OPTIMIZE" = "Y" ] || [ "$OPTIMIZE" = "y" ]; then
    optimize_system
  fi
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

  # 检测VPS配置并获取推荐内核
  echo "正在检测VPS配置以选择最适合的内核..."
  detect_vps_type
  
  # 检查是否已有可用实现
  EXIST="$(detect_existing_impl || true)"
  if [ -n "${EXIST}" ]; then
    echo "检测到系统可用实现：${EXIST}（将尝试使用它）"
    BIN_TYPE="${EXIST}"
  else
    echo "未检测到受支持的实现，将根据VPS配置安装最适合的内核..."
    
    # 根据VPS配置选择最适合的内核
    if [ "${RECOMMENDED_KERNEL}" = "microsocks" ]; then
      echo "VPS配置较低，优先安装资源占用最少的microsocks..."
      if try_install_microsocks; then
        if command -v microsocks >/dev/null 2>&1; then
          BIN_TYPE="microsocks"
          echo "已安装 microsocks"
        fi
      elif try_install_3proxy; then
        if command -v 3proxy >/dev/null 2>&1; then
          BIN_TYPE="3proxy"
          echo "microsocks安装失败，已安装备选的3proxy"
        fi
      fi
    elif [ "${RECOMMENDED_KERNEL}" = "3proxy" ]; then
      echo "VPS配置适中，优先安装轻量级的3proxy..."
      if try_install_3proxy; then
        if command -v 3proxy >/dev/null 2>&1; then
          BIN_TYPE="3proxy"
          echo "已安装 3proxy"
        fi
      elif try_install_microsocks; then
        if command -v microsocks >/dev/null 2>&1; then
          BIN_TYPE="microsocks"
          echo "3proxy安装失败，已安装备选的microsocks"
        fi
      fi
    else
      echo "VPS配置良好，优先安装功能完善的ss5..."
      if try_install_ss5; then
        if command -v ss5 >/dev/null 2>&1; then
          BIN_TYPE="ss5"
          echo "已安装 ss5"
        fi
      elif try_install_3proxy; then
        if command -v 3proxy >/dev/null 2>&1; then
          BIN_TYPE="3proxy"
          echo "ss5安装失败，已安装备选的3proxy"
        fi
      elif try_install_microsocks; then
        if command -v microsocks >/dev/null 2>&1; then
          BIN_TYPE="microsocks"
          echo "ss5和3proxy安装失败，已安装备选的microsocks"
        fi
      fi
    fi
  fi

  # 如果所有尝试都失败，使用singbox作为备用
  if [ -z "${BIN_TYPE}" ]; then
    echo "尝试下载备用的sing-box作为SOCKS5实现..."
    if download_singbox; then
      BIN_TYPE="singbox"
      echo "使用下载的备用 sing-box（已保存到 ${SINGBOX_BIN}）"
    else
      echo -e "${RED}未能安装或下载任何 socks5 实现。请手动安装 microsocks/3proxy/ss5，或检查网络。${RESET}"
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
    echo "5) 检测环境"
    echo "6) 系统优化"
    echo "7) 退出"
    read -r -p "请选择 (1-7): " opt < /dev/tty || opt="7"
    case "${opt}" in
      1) install_flow ;;
      2) modify_flow ;;
      3) uninstall_flow ;;
      4) status_flow ;;
      5) check_environment ;;
      6) optimize_system ;;
      7) echo "退出。"; exit 0 ;;
      *) echo "无效选项。" ;;
    esac
  done
}

# 检查脚本是否以root权限运行
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误: 此脚本需要root权限运行${RESET}"
    echo "请使用sudo或以root用户身份运行此脚本"
    exit 1
  fi
}

# 主程序入口
main() {
  # 显示欢迎信息
  echo -e "${GREEN}欢迎使用SOCKS5代理管理脚本${RESET}"
  echo -e "${GREEN}此脚本支持LXC、KVM和NAT VPS等常用系统环境${RESET}"
  
  # 检查root权限
  check_root
  
  # 初始化工作目录和配置
  ensure_workdir
  load_meta
  
  # 显示主菜单
  main_menu
}

# 执行主程序
main
