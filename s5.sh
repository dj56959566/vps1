#!/usr/bin/env bash
#
# 简化版：仅保留 socks5 功能并增加卸载功能
# 介绍信息显示 djkyc
#

set -o errexit
set -o nounset
set -o pipefail

# 颜色
GREEN="\e[32m"
RESET="\e[0m"
RED="\e[31m"
YELLOW="\e[33m"

echo -e "${GREEN}
  ____   ___   ____ _  ______ ____  
 / ___| / _ \\ / ___| |/ / ___| ___|  
 \\___ \\| | | | |   | ' /\\___ \\___ \\ 
  ___) | |_| | |___| . \\ ___) |__) |           不要直连
 |____/ \\___/ \\____|_|\\_\\____/____/            没有售后   
 djkyc
${RESET}"

# 环境路径（优先使用 HOME）
USER="$(whoami)"
HOME_DIR="${HOME:-/root}"
FILE_PATH="${HOME_DIR}/.s5"
S5_BIN="${FILE_PATH}/s5"
CONFIG_JSON="${FILE_PATH}/config.json"
PID_FILE="${FILE_PATH}/s5.pid"

# 下载链接（保持原脚本中的来源）
S5_DOWNLOAD_URL="https://github.com/eooce/test/releases/download/freebsd/web"

# 检查必要命令
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo -e "${RED}缺少命令：$1，请先安装。${RESET}"; exit 1; }
}

require_cmd curl
require_cmd pgrep
require_cmd pkill

# 生成 socks5 配置
socks5_config() {
  mkdir -p "${FILE_PATH}"
  chmod 700 "${FILE_PATH}"

  read -rp "请输入 socks5 端口号: " SOCKS5_PORT
  # 简单校验端口为数字且范围合适
  if ! [[ "${SOCKS5_PORT}" =~ ^[0-9]+$ ]] || [ "${SOCKS5_PORT}" -lt 1 ] || [ "${SOCKS5_PORT}" -gt 65535 ]; then
    echo -e "${RED}端口输入无效。${RESET}"
    exit 1
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

  # 写入 config.json（权限 600）
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
  echo "配置已写入：${CONFIG_JSON}"
}

# 下载并安装 socks5 二进制
install_socks5_bin() {
  if [ ! -f "${S5_BIN}" ]; then
    echo "正在下载 socks5 程序..."
    curl -L -sS -o "${S5_BIN}" "${S5_DOWNLOAD_URL}" || { echo -e "${RED}下载失败${RESET}"; exit 1; }
  else
    read -rp "s5 程序已存在，是否重新下载覆盖？(Y/N 回车N): " downsocks5
    downsocks5="${downsocks5^^}"
    if [ "${downsocks5}" == "Y" ]; then
      if [ -f "${PID_FILE}" ]; then
        if ps -p "$(cat "${PID_FILE}")" >/dev/null 2>&1; then
          echo "检测到 s5 正在运行，已尝试停止..."
          pkill -x "s5" || true
          sleep 1
        fi
      fi
      curl -L -sS -o "${S5_BIN}" "${S5_DOWNLOAD_URL}" || { echo -e "${RED}下载失败${RESET}"; exit 1; }
    else
      echo "使用已存在的 s5 程序"
    fi
  fi

  chmod 700 "${S5_BIN}"
  echo "s5 程序已安装或存在：${S5_BIN}"
}

start_socks5() {
  if [ ! -f "${S5_BIN}" ] || [ ! -f "${CONFIG_JSON}" ]; then
    echo -e "${YELLOW}缺少可执行文件或配置，请先安装/配置。${RESET}"
    return 1
  fi

  # 先尝试停止可能已存在的进程
  if [ -f "${PID_FILE}" ]; then
    pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
    if [ -n "${pid}" ] && ps -p "${pid}" >/dev/null 2>&1; then
      echo "检测到 s5 进程（PID: ${pid}），将先停止它..."
      pkill -x "s5" || true
      sleep 1
    fi
  fi

  nohup "${S5_BIN}" -c "${CONFIG_JSON}" >/dev/null 2>&1 &
  s5_pid=$!
  echo "${s5_pid}" > "${PID_FILE}"
  sleep 2

  if ps -p "${s5_pid}" >/dev/null 2>&1; then
    echo -e "${GREEN}s5 已启动，PID=${s5_pid}${RESET}"
    # 尝试通过代理查询外网 IP
    SOCKS5_PORT=$(jq -r '.inbounds[0].port' "${CONFIG_JSON}" 2>/dev/null || true)
    SOCKS5_USER=$(jq -r '.inbounds[0].settings.accounts[0].user' "${CONFIG_JSON}" 2>/dev/null || true)
    SOCKS5_PASS=$(jq -r '.inbounds[0].settings.accounts[0].pass' "${CONFIG_JSON}" 2>/dev/null || true)

    # 如果系统没有 jq，使用 fallback 提示
    if ! command -v jq >/dev/null 2>&1; then
      echo -e "${YELLOW}注意：未安装 jq，无法读取配置中的用户名/端口用于连通性检测。将跳过公网 IP 检查。${RESET}"
      echo "可使用 socks5 地址：socks://${SOCKS5_USER}:${SOCKS5_PASS}@127.0.0.1:${SOCKS5_PORT}"
      return 0
    fi

    CURL_OUTPUT="$(curl -s 4.ipw.cn --socks5 "${SOCKS5_USER}:${SOCKS5_PASS}@127.0.0.1:${SOCKS5_PORT}" || true)"
    if [[ "${CURL_OUTPUT}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "代理创建成功，外网返回 IP: ${CURL_OUTPUT}"
      SERV_DOMAIN="${CURL_OUTPUT}"
    else
      echo -e "${YELLOW}通过代理检查公网 IP 失败，可能不可达或系统缺少 jq。${RESET}"
      SERV_DOMAIN="127.0.0.1"
    fi

    echo "socks URL: socks://${SOCKS5_USER}:${SOCKS5_PASS}@${SERV_DOMAIN}:${SOCKS5_PORT}"
  else
    echo -e "${RED}s5 启动失败，请检查日志与配置。${RESET}"
    return 1
  fi
}

stop_socks5() {
  if [ -f "${PID_FILE}" ]; then
    pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
    if [ -n "${pid}" ] && ps -p "${pid}" >/dev/null 2>&1; then
      pkill -x "s5" || true
      sleep 1
      if ! ps -p "${pid}" >/dev/null 2>&1; then
        echo "s5 (PID ${pid}) 已停止。"
        rm -f "${PID_FILE}"
        return 0
      fi
    else
      echo "未检测到运行的 s5 进程，正在清理 PID 文件。"
      rm -f "${PID_FILE}" || true
      return 0
    fi
  else
    # 尝试通过进程名停止
    if pgrep -x "s5" >/dev/null 2>&1; then
      pkill -x "s5" || true
      echo "已尝试通过进程名停止 s5。"
      sleep 1
      return 0
    fi
    echo "未检测到 s5 运行。"
  fi
}

uninstall_socks5() {
  echo -e "${YELLOW}注意：卸载将停止 s5 并删除目录：${FILE_PATH}。此操作不可恢复。${RESET}"
  read -rp "确认卸载并删除所有文件？(请输入 Y 以确认): " confirm
  confirm="${confirm^^}"
  if [ "${confirm}" != "Y" ]; then
    echo "已取消卸载。"
    return 0
  fi

  stop_socks5 || true

  # 删除文件和目录
  if [ -d "${FILE_PATH}" ]; then
    rm -rf "${FILE_PATH}" && echo "已删除目录 ${FILE_PATH}"
  else
    echo "目录 ${FILE_PATH} 不存在，跳过删除。"
  fi

  echo "卸载完成。"
}

# 主菜单（简洁）
show_menu() {
  echo
  echo "请选择操作："
  echo "1) 安装/配置并启动 socks5"
  echo "2) 停止 socks5"
  echo "3) 卸载 socks5（停止并删除文件）"
  echo "4) 退出"
  read -rp "请选择 (1-4): " opt
  case "${opt}" in
    1)
      socks5_config
      install_socks5_bin
      start_socks5
      ;;
    2)
      stop_socks5
      ;;
    3)
      uninstall_socks5
      ;;
    4)
      echo "退出。"
      exit 0
      ;;
    *)
      echo "无效选项。"
      ;;
  esac
}

# 如果传入参数 non-interactive：install / uninstall
if [ "$#" -gt 0 ]; then
  case "$1" in
    install)
      socks5_config
      install_socks5_bin
      start_socks5
      exit 0
      ;;
    uninstall)
      uninstall_socks5
      exit 0
      ;;
    stop)
      stop_socks5
      exit 0
      ;;
    *)
      echo "未知参数。支持：install | stop | uninstall"
      exit 1
      ;;
  esac
fi

# 交互循环
while true; do
  show_menu
done
