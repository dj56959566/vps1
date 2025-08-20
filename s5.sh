#!/usr/bin/env bash
#
# 简洁版 socks5 管理脚本（只保留 socks5 功能 + 卸载）
# 介绍信息显示 djkyc
#
# 用法：
#   ./s5_manager.sh            # 进入交互菜单
#   ./s5_manager.sh install    # 交互式配置并安装启动
#   ./s5_manager.sh start      # 启动（需已存在 config）
#   ./s5_manager.sh stop       # 停止
#   ./s5_manager.sh uninstall  # 停止并删除所有文件
#
set -o errexit
set -o nounset
set -o pipefail

# 输出颜色
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
RESET="\e[0m"

# 头信息
echo -e "${GREEN}
  ____   ___   ____ _  ______ ____  
 / ___| / _ \\ / ___| |/ / ___| ___|  
 \\___ \\| | | | |   | ' /\\___ \\___ \\ 
  ___) | |_| | |___| . \\ ___) |__) |           不要直连
 |____/ \\___/ \\____|_|\\_\\____/____/            没有售后   
 djkyc
${RESET}"

# 环境和路径
USER="$(whoami)"
HOME_DIR="${HOME:-/root}"
FILE_PATH="${HOME_DIR}/.s5"
S5_BIN="${FILE_PATH}/s5"
CONFIG_JSON="${FILE_PATH}/config.json"
META_FILE="${FILE_PATH}/meta"   # 存储端口/用户/密码用于展示
PID_FILE="${FILE_PATH}/s5.pid"

# 原始二进制下载地址（保持原脚本来源）
S5_DOWNLOAD_URL="https://github.com/eooce/test/releases/download/freebsd/web"

# 需要的命令
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo -e "${RED}缺少命令：$1，请先安装。${RESET}"; exit 1; }
}
require_cmd curl
require_cmd pgrep
require_cmd pkill

# 生成配置（交互式）
socks5_config() {
  mkdir -p "${FILE_PATH}"
  chmod 700 "${FILE_PATH}"

  read -rp "请输入 socks5 端口号: " SOCKS5_PORT
  if ! [[ "${SOCKS5_PORT}" =~ ^[0-9]+$ ]] || [ "${SOCKS5_PORT}" -lt 1 ] || [ "${SOCKS5_PORT}" -gt 65535 ]; then
    echo -e "${RED}端口输入无效。${RESET}"; return 1
  fi

  read -rp "请输入 socks5 用户名: " SOCKS5_USER
  while true; do
    read -rp "请输入 socks5 密码（不能包含 @ 和 :）: " SOCKS5_PASS
    echo
    if [[ "${SOCKS5_PASS}" == *"@"* || "${SOCKS5_PASS}" == *":"* ]]; then
      echo "密码中不能包含 @ 和 : 符号，请重新输入。"
    else
      break
    fi
  done

  cat > "${CONFIG_JSON}" <<EOF
{
  "log": {
    "access": "/dev/null",
    "error": "/dev/null",
    "loglevel": "none"
  },
  "inbounds": [
    {
      "port": ${SOCKS5_PORT},
      "protocol": "socks",
      "tag": "socks",
      "settings": {
        "auth": "password",
        "udp": false,
        "ip": "0.0.0.0",
        "userLevel": 0,
        "accounts": [
          {
            "user": "${SOCKS5_USER}",
            "pass": "${SOCKS5_PASS}"
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

  chmod 600 "${CONFIG_JSON}"
  # 保存元数据便于展示（权限 600）
  {
    echo "PORT=${SOCKS5_PORT}"
    echo "USER=${SOCKS5_USER}"
    echo "PASS=${SOCKS5_PASS}"
  } > "${META_FILE}"
  chmod 600 "${META_FILE}"

  echo "配置已写入：${CONFIG_JSON}"
}

# 下载并安装二进制（不会盲目修改已有文件，提供覆盖选项）
install_s5_bin() {
  mkdir -p "${FILE_PATH}"
  chmod 700 "${FILE_PATH}"

  if [ -f "${S5_BIN}" ]; then
    read -rp "检测到 s5 可执行文件已存在，是否覆盖下载？(Y/N 回车N): " ans
    ans="${ans^^}"
    if [ "${ans}" != "Y" ]; then
      echo "保留已存在的可执行文件。"
      chmod 700 "${S5_BIN}" || true
      return 0
    fi
    # 尝试停止正在运行的实例（若有）
    if [ -f "${PID_FILE}" ]; then
      pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
      if [ -n "${pid}" ] && ps -p "${pid}" >/dev/null 2>&1; then
        echo "检测到 s5 正在运行 (PID ${pid})，将尝试停止..."
        pkill -x "s5" || true
        sleep 1
      fi
    fi
  fi

  echo "正在下载 s5 二进制到 ${S5_BIN} ..."
  curl -L -sS -o "${S5_BIN}" "${S5_DOWNLOAD_URL}" || { echo -e "${RED}下载失败${RESET}"; return 1; }
  chmod 700 "${S5_BIN}"
  echo "下载并安装完成。"
}

# 启动 s5（将 pid 写入 PID_FILE）
start_s5() {
  if [ ! -f "${S5_BIN}" ]; then
    echo -e "${YELLOW}未找到可执行文件 ${S5_BIN}，请先安装。${RESET}"
    return 1
  fi
  if [ ! -f "${CONFIG_JSON}" ]; then
    echo -e "${YELLOW}未找到配置 ${CONFIG_JSON}，请先运行 install 或 config。${RESET}"
    return 1
  fi

  # 如果已有 pid 且进程存在，提示并退出
  if [ -f "${PID_FILE}" ]; then
    pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
    if [ -n "${pid}" ] && ps -p "${pid}" >/dev/null 2>&1; then
      echo "s5 已在运行 (PID ${pid})。"
      return 0
    else
      rm -f "${PID_FILE}" || true
    fi
  fi

  nohup "${S5_BIN}" -c "${CONFIG_JSON}" >/dev/null 2>&1 &
  s5_pid=$!
  echo "${s5_pid}" > "${PID_FILE}"
  sleep 2

  if ps -p "${s5_pid}" >/dev/null 2>&1; then
    echo -e "${GREEN}s5 已启动，PID=${s5_pid}${RESET}"
    # 尝试用 meta 文件显示 socks URL；无 meta 则显示本地地址
    if [ -f "${META_FILE}" ]; then
      # shellcheck disable=SC1090
      source "${META_FILE}"
      CURL_OUTPUT="$(curl -s --max-time 5 4.ipw.cn --socks5 "${USER}:${PASS}@127.0.0.1:${PORT}" || true)"
      if [[ "${CURL_OUTPUT}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        SERV_DOMAIN="${CURL_OUTPUT}"
      else
        SERV_DOMAIN="127.0.0.1"
      fi
      echo "socks URL: socks://${USER}:${PASS}@${SERV_DOMAIN}:${PORT}"
    else
      echo "未找到 meta 信息，socks 在本机监听，请使用 127.0.0.1:<port>"
    fi
    return 0
  else
    echo -e "${RED}s5 启动失败。${RESET}"
    return 1
  fi
}

# 停止 s5
stop_s5() {
  stopped=0
  if [ -f "${PID_FILE}" ]; then
    pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
    if [ -n "${pid}" ] && ps -p "${pid}" >/dev/null 2>&1; then
      pkill -x "s5" || true
      sleep 1
      if ! ps -p "${pid}" >/dev/null 2>&1; then
        echo "s5 (PID ${pid}) 已停止。"
        rm -f "${PID_FILE}" || true
        stopped=1
      fi
    else
      rm -f "${PID_FILE}" || true
    fi
  fi

  # 兜底：通过进程名停止
  if pgrep -x "s5" >/dev/null 2>&1; then
    pkill -x "s5" || true
    echo "通过进程名尝试停止 s5。"
    stopped=1
  fi

  if [ "${stopped}" -eq 0 ]; then
    echo "未检测到运行的 s5。"
  fi
}

# 卸载：停止并删除所有文件
uninstall_s5() {
  echo -e "${YELLOW}警告：卸载会停止 s5 并删除目录 ${FILE_PATH} 下的所有文件。此操作不可恢复。${RESET}"
  read -rp "确认卸载并删除所有文件？(请输入 Y 以确认): " confirm
  confirm="${confirm^^}"
  if [ "${confirm}" != "Y" ]; then
    echo "已取消卸载。"
    return 0
  fi

  stop_s5 || true

  if [ -d "${FILE_PATH}" ]; then
    rm -rf "${FILE_PATH}" && echo "已删除目录 ${FILE_PATH}"
  else
    echo "目录 ${FILE_PATH} 不存在，跳过删除。"
  fi
  echo "卸载完成。"
}

# 简单交互菜单
show_menu() {
  echo
  echo "选择操作："
  echo "1) 安装/配置并启动 socks5"
  echo "2) 启动 socks5"
  echo "3) 停止 socks5"
  echo "4) 卸载 socks5（停止并删除）"
  echo "5) 退出"
  read -rp "请选择 (1-5): " opt
  case "${opt}" in
    1)
      socks5_config
      install_s5_bin
      start_s5
      ;;
    2) start_s5 ;;
    3) stop_s5 ;;
    4) uninstall_s5 ;;
    5) echo "退出。"; exit 0 ;;
    *) echo "无效选项。" ;;
  esac
}

# 参数模式
if [ "$#" -gt 0 ]; then
  case "$1" in
    install)
      socks5_config
      install_s5_bin
      start_s5
      exit 0
      ;;
    start) start_s5; exit 0 ;;
    stop) stop_s5; exit 0 ;;
    uninstall) uninstall_s5; exit 0 ;;
    *)
      echo "未知参数。支持：install | start | stop | uninstall"
      exit 1
      ;;
  esac
fi

# 进入交互循环
while true; do
  show_menu
done
