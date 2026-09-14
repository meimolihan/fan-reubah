#!/usr/bin/env bash
#
# fan-reubah - 通用文件转换与图像处理 卸载脚本
# 停止并移除 systemd 服务 / 后台进程，删除二进制、应用目录与安装记录，并关闭防火墙端口。
#
# Usage: bash scripts/uninstall.sh [-y] [--purge|--keep-appdir] [-q]

set -e

APP_NAME="fan-reubah"
BIN_PATH="/usr/local/bin/${APP_NAME}"
DEFAULT_APP_DIR="/opt/${APP_NAME}"
DEFAULT_PORT=8081
RECORD_FILE="/etc/${APP_NAME}.conf"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"

# ================== terminal colors ==================
list_color_init() {
    export gl_hui=$'\033[38;5;59m'
    export gl_hong=$'\033[38;5;9m'
    export gl_lv=$'\033[38;5;10m'
    export gl_huang=$'\033[38;5;11m'
    export gl_lan=$'\033[38;5;32m'
    export gl_bai=$'\033[38;5;15m'
    export gl_zi=$'\033[38;5;13m'
    export gl_bufan=$'\033[38;5;14m'
    export reset=$'\033[0m'
}
list_color_init

sep_line() {
  printf '%s' "$gl_bufan"
  printf '—%.0s' {1..32}
  printf '%s\n' "$reset"
}

section() {
  printf "  %s %s\n" "${gl_zi}▶${reset}" "$1"
}

ok() {
  printf "  %s %s\n" "${gl_lv}>>>${reset}" "$1"
}

skip() {
  printf "  %s %s\n" "${gl_hui}--${reset}" "$1"
}

__warn_box_width() {
    local s=$1 i c cp width=0
    local len=${#s}
    for ((i = 0; i < len; i++)); do
        c=${s:i:1}
        printf -v cp '%d' "'$c" 2>/dev/null || cp=63
        if (( (cp>=0x1100 && cp<=0x115F) || (cp>=0x2E80 && cp<=0x303E) || \
              (cp>=0x3041 && cp<=0x33FF) || (cp>=0x3400 && cp<=0x4DBF) || \
              (cp>=0x4E00 && cp<=0x9FFF) || (cp>=0xA000 && cp<=0xA4CF) || \
              (cp>=0xAC00 && cp<=0xD7A3) || (cp>=0xF900 && cp<=0xFAFF) || \
              (cp>=0xFE30 && cp<=0xFE6F) || (cp>=0xFF00 && cp<=0xFF60) || \
              (cp>=0x1F300 && cp<=0x1F64F) )); then
                width=$((width + 2))
            else
                width=$((width + 1))
            fi
    done
    printf '%d' "$width"
}

warn_box() {
    local gl_bai=$'\033[38;5;15m'   # 白色（内容）
    local gl_zi=$'\033[38;5;13m'    # 洋红（边框）
    local reset=$'\033[0m'

    local pad=1
    if [[ $1 =~ ^[0-9]+$ ]]; then
        pad=$1
        shift
    fi
    local lines=("$@")
    local max=0 l w
    for l in "${lines[@]}"; do
        w=$(__warn_box_width "$l")
        (( w > max )) && max=$w
    done
    local W=$max
    (( W < 1 )) && W=1
    local bar
    printf -v bar '%*s' "$W" ''
    bar=${bar// /─}
    printf '%s╭%s╮%s\n' "$gl_zi" "$bar" "$reset"
    for ((i = 0; i < pad; i++)); do
        printf '%s│%*s│%s\n' "$gl_zi" "$W" "" "$reset"
    done
    for l in "${lines[@]}"; do
        w=$(__warn_box_width "$l")
        printf '%s│%s%s%s%*s%s│%s\n' \
            "$gl_zi" "$gl_bai" "$l" "$reset" \
            $((W - w)) "" "$gl_zi" "$reset"
    done
    for ((i = 0; i < pad; i++)); do
        printf '%s│%*s│%s\n' "$gl_zi" "$W" "" "$reset"
    done
    printf '%s╰%s╯%s\n' "$gl_zi" "$bar" "$reset"
}

error() { printf "  %s %s\n" "${gl_hong}[错误]${reset}" "$1" >&2; exit 1; }
[ "$(id -u)" != "0" ] && error "请以 root 身份运行（sudo bash scripts/uninstall.sh）"

UNINSTALL_YES=0
DELETE_APPDIR=0
KEEP_APPDIR=0
QUIET=0

usage() {
  printf '%s\n' \
    "用法: bash scripts/uninstall.sh [选项]" \
    "" \
    "选项:" \
    "  -y, --yes        免确认，自动同意卸载" \
    "      --purge      卸载时同时删除应用目录（模板与静态资源）" \
    "      --keep-appdir 卸载时保留应用目录" \
    "  -q, --quiet      静默模式，仅输出关键信息" \
    "  -h, --help       显示帮助" \
    "" \
    "示例:" \
    "  bash scripts/uninstall.sh -y               免确认卸载，保留应用目录" \
    "  bash scripts/uninstall.sh -y --purge       免确认卸载，并删除应用目录"
  exit 0
}

# ---- bootstrap: support `bash -c "$(curl ...)" -y --purge` ----
case "$0" in
  -*) set -- "$0" "$@" ;;
esac

while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes) UNINSTALL_YES=1; shift ;;
    --purge|--delete-appdir) DELETE_APPDIR=1; shift ;;
    --keep-appdir) KEEP_APPDIR=1; shift ;;
    -q|--quiet) QUIET=1; shift ;;
    -h|--help) usage ;;
    *) error "未知参数: $1，使用 -h 查看帮助" ;;
  esac
done

[ "$QUIET" = "1" ] && {
  sep_line() { :; }
  section() { :; }
  ok() { :; }
  skip() { :; }
}

read_config() {
  [ -f "$RECORD_FILE" ] || return 0
  while IFS='=' read -r KEY VALUE; do
    KEY=$(printf '%s' "$KEY" | tr -d ' ')
    VALUE=$(printf '%s' "$VALUE" | tr -d '\r')
    case "$KEY" in
      BIN_PATH) [ -n "$VALUE" ] && BIN_PATH="$VALUE" ;;
      PORT) [ -n "$VALUE" ] && PORT="$VALUE" ;;
      APP_DIR) [ -n "$VALUE" ] && APP_DIR="$VALUE" ;;
    esac
  done < "$RECORD_FILE"
  return 0
}

find_app_pids() {
  local d pid exe
  for d in /proc/[0-9]*; do
    [ -d "$d" ] || continue
    pid="${d#/proc/}"
    [ "$pid" = "$$" ] && continue
    exe=$(readlink "$d/exe" 2>/dev/null) || continue
    [ "$(basename "$exe")" = "${APP_NAME}" ] || continue
    echo "$pid"
  done
}

close_firewall_port() {
  local PORT="$1"
  [ -z "$PORT" ] && return 0

  # 1. firewalld
  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --remove-port="${PORT}/tcp" >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
    ok "已通过 ${gl_bai}firewalld${reset} 关闭端口 ${gl_lan}${PORT}/tcp${reset}"
  # 2. ufw
  elif command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw delete allow "${PORT}/tcp" >/dev/null 2>&1 || true
    ok "已通过 ${gl_bai}ufw${reset} 关闭端口 ${gl_lan}${PORT}/tcp${reset}"
  # 3. iptables
  elif command -v iptables >/dev/null 2>&1; then
    if iptables -D INPUT -p tcp --dport "${PORT}" -j ACCEPT >/dev/null 2>&1; then
      ok "已通过 ${gl_bai}iptables${reset} 关闭端口 ${gl_lan}${PORT}/tcp${reset}"
    fi
  fi
}

[ "$QUIET" = "1" ] || warn_box 0  '     Fan Reubah 文件转换 · 卸载    '
sep_line
section "卸载确认"
if [ "$UNINSTALL_YES" = "1" ]; then
  ok "开始卸载 ${APP_NAME} ${gl_hong}.${gl_huang}.${gl_lv}.${reset}"
else
  while :; do
    read -r -p "${gl_huang}卸载将停止并移除 ${APP_NAME} 服务与程序，是否继续？${gl_bai}[y/N]${reset}: " CONFIRM
    case "$CONFIRM" in
      y|Y|yes|YES)
        ok "开始卸载 ${APP_NAME} ${gl_hong}.${gl_huang}.${gl_lv}.${reset}"
        break
        ;;
      n|N|no|NO|"")
        printf "  %s\n" "${gl_huang}已取消卸载。${reset}"
        exit 0
        ;;
      *)
        printf "  %s\n" "${gl_huang}输入无效，请输入 y 或 n。${reset}"
        ;;
    esac
  done
fi

PORT="$DEFAULT_PORT"
APP_DIR=""
read_config
[ -z "$APP_DIR" ] && APP_DIR="$DEFAULT_APP_DIR"

sep_line
section "停止服务"
if command -v systemctl >/dev/null 2>&1 && [ -f "$SERVICE_FILE" ]; then
  ok "正在停止并移除 systemd 服务 ${gl_bai}${APP_NAME} ${gl_hong}.${gl_huang}.${gl_lv}.${reset}"
  systemctl stop "${APP_NAME}" 2>/dev/null || true
  systemctl disable "${APP_NAME}" 2>/dev/null || true
  rm -f "$SERVICE_FILE"
  systemctl daemon-reload 2>/dev/null || true
else
  skip "未发现 systemd 服务，跳过。"
fi

sep_line
section "停止进程"
PIDS=$(find_app_pids)
if [ -n "$PIDS" ]; then
  ok "正在停止 ${APP_NAME} 进程: ${gl_bai}$PIDS ${gl_hong}.${gl_huang}.${gl_lv}.${reset}"
  for PID in $PIDS; do
    [ -d "/proc/$PID" ] || continue
    kill "$PID" 2>/dev/null || true
  done
  sleep 1
  for PID in $PIDS; do
    [ -d "/proc/$PID" ] || continue
    kill -9 "$PID" 2>/dev/null || true
  done
else
  skip "未发现运行中的 ${APP_NAME} 进程，跳过。"
fi

sep_line
section "删除二进制"
if [ -f "${BIN_PATH}" ]; then
  rm -f "${BIN_PATH}"
  ok "已删除二进制文件 ${gl_bai}${BIN_PATH}${reset}"
else
  skip "未找到二进制文件 ${gl_bai}${BIN_PATH}${reset}，跳过。"
fi

sep_line
section "删除应用目录"
if [ -n "$APP_DIR" ] && [ -d "$APP_DIR" ]; then
  ok "检测到应用目录: ${gl_bai}${APP_DIR}${reset}"
  if [ "$KEEP_APPDIR" = "1" ]; then
    skip "已保留应用目录 ${gl_bai}${APP_DIR}${reset}"
  elif [ "$DELETE_APPDIR" = "1" ]; then
    rm -rf "$APP_DIR"
    ok "已删除应用目录 ${gl_bai}${APP_DIR}${reset}"
  elif [ -t 0 ]; then
    read -r -p "${gl_huang}是否删除应用目录 ${APP_DIR}？（模板与静态资源）${gl_bai}[Y/n]${reset}: " DEL_APP
    case "$DEL_APP" in
      n|N|no|NO)
        skip "已保留应用目录 ${gl_bai}${APP_DIR}${reset}"
        ;;
      *)
        rm -rf "$APP_DIR"
        ok "已删除应用目录 ${gl_bai}${APP_DIR}${reset}"
        ;;
    esac
  else
    skip "非交互模式下默认保留应用目录 ${gl_bai}${APP_DIR}${reset}"
  fi
else
  skip "未找到应用目录，跳过。"
fi

sep_line
section "删除安装记录"
rm -f "$RECORD_FILE"
ok "已删除安装记录"

sep_line
section "关闭防火墙"
close_firewall_port "$PORT"

sep_line
printf "  %s\n" "${gl_lv}✔ ${APP_NAME} 已卸载完成${reset}"
printf "  %s\n" "${gl_hui}如需重新安装，请再次运行 scripts/install.sh 安装脚本。${reset}"
sep_line