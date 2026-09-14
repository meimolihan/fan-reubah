#!/usr/bin/env bash
#
# fan-reubah - 卸载脚本
# 停止并删除 systemd 服务、二进制（fan-reubah + vtracer）、应用目录、安装记录，
# 并撤销安装时添加的防火墙放行规则。可重复执行（重复运行只是再次清理）。
#
# Usage:
#   bash scripts/uninstall.sh [-y]
#   curl -fsSL https://raw.githubusercontent.com/meimolihan/fan-reubah/main/scripts/uninstall.sh | sudo bash -s -- -y
set -euo pipefail

gl_lv=$'\033[38;5;10m'; gl_huang=$'\033[38;5;11m'; gl_hong=$'\033[38;5;9m'
gl_bai=$'\033[38;5;15m'; gl_lan=$'\033[38;5;32m'; gl_hui=$'\033[38;5;59m'; reset=$'\033[0m'
ok()   { printf "  %s %s\n" "${gl_lv}>>>${reset}" "$1"; }
error(){ printf "  %s %s\n" "${gl_hong}[错误]${reset}" "$1" >&2; exit 1; }

APP_NAME="fan-reubah"
RECORD_FILE="/etc/${APP_NAME}.conf"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
DEFAULT_PORT=8081
DEFAULT_APP_DIR="/var/lib/${APP_NAME}"
DEFAULT_BIN="/usr/local/bin/${APP_NAME}"
VTRACER_BIN="/usr/local/bin/vtracer"

UNINSTALL_YES=0
case "$0" in
  -*) set -- "$0" "$@" ;;
esac
[ "${1:-}" = "--" ] && shift
while [ "$#" -gt 0 ]; do
  case "$1" in
    -y|--yes) UNINSTALL_YES=1 ;;
    -h|--help)
      printf "%s\n" "${gl_lan}fan-reubah${reset} - ${gl_bai}卸载脚本${reset}"
      printf "  %-13s %s\n" "${gl_bai}用法:${reset}" "bash scripts/uninstall.sh [-y]"
      printf "  %-13s %s\n" "${gl_bai}-y, --yes${reset}" "免确认直接卸载"
      exit 0 ;;
    *) error "未知参数: $1（使用 -h 查看帮助）" ;;
  esac
  shift
done

[ "$(id -u)" != "0" ] && error "请以 root 身份运行（例如 sudo bash scripts/uninstall.sh）"

# ---- 读取安装记录以还原端口/目录（未找到则用默认值）----
PORT="${DEFAULT_PORT}"; APP_DIR="${DEFAULT_APP_DIR}"; BIN_PATH="${DEFAULT_BIN}"
while IFS='=' read -r KEY VALUE; do
  KEY=$(printf '%s' "$KEY" | tr -d ' ')
  VALUE=$(printf '%s' "$VALUE" | tr -d '\r')
  case "$KEY" in
    BIN_PATH) [ -n "$VALUE" ] && BIN_PATH="$VALUE" ;;
    PORT)     [ -n "$VALUE" ] && PORT="$VALUE" ;;
    APP_DIR)  [ -n "$VALUE" ] && APP_DIR="$VALUE" ;;
  esac
done < "${RECORD_FILE}" 2>/dev/null || true

printf "  %s\n" "${gl_bai}将删除以下内容：${reset}"
printf "  %-16s %s\n" "${gl_hui}- systemd 服务${reset}" "${gl_bai}${SERVICE_FILE}${reset}"
printf "  %-16s %s\n" "${gl_hui}- 二进制${reset}"     "${gl_bai}${BIN_PATH}${reset} ${gl_bai}${VTRACER_BIN}${reset}"
printf "  %-16s %s\n" "${gl_hui}- 应用目录${reset}"   "${gl_bai}${APP_DIR}${reset}"
printf "  %-16s %s\n" "${gl_hui}- 安装记录${reset}"   "${gl_bai}${RECORD_FILE}${reset}"
printf "  %-16s %s\n" "${gl_hui}- 防火墙规则${reset}" "${gl_bai}${PORT}/tcp${reset}"

if [ "${UNINSTALL_YES}" != "1" ]; then
  read -r -p "${gl_huang}确认卸载 fan-reubah ? [y/N] ${reset}" ans
  case "${ans}" in
    y|Y) ;;
    *) printf "  %s\n" "已取消卸载。"; exit 0 ;;
  esac
fi

# ---- 停止并移除 systemd 服务 ----
if command -v systemctl >/dev/null 2>&1; then
  systemctl stop "${APP_NAME}" >/dev/null 2>&1 || true
  systemctl disable "${APP_NAME}" >/dev/null 2>&1 || true
  rm -f "${SERVICE_FILE}"
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl reset-failed "${APP_NAME}" >/dev/null 2>&1 || true
  ok "已停止并移除 systemd 服务"
fi

# ---- 删除二进制 / 应用目录 / 安装记录 ----
rm -f "${BIN_PATH}" "${VTRACER_BIN}"
rm -rf "${APP_DIR}"
rm -f "${RECORD_FILE}"
ok "已删除二进制、应用目录与安装记录"

# ---- 撤销防火墙放行规则（仅当对应防火墙存在且活跃）----
if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
  firewall-cmd --permanent --remove-port="${PORT}/tcp" >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null 2>&1 || true
  ok "已撤销 firewalld 端口 ${PORT}/tcp"
elif command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw delete allow "${PORT}/tcp" >/dev/null 2>&1 || true
  ok "已撤销 ufw 端口 ${PORT}/tcp"
elif command -v iptables >/dev/null 2>&1; then
  iptables -D INPUT -p tcp --dport "${PORT}" -j ACCEPT >/dev/null 2>&1 || true
  ok "已撤销 iptables 端口 ${PORT}/tcp"
fi

printf "  %s\n" "${gl_lv}✔ fan-reubah 已卸载完成。${reset}"
printf "  %s\n" "${gl_hui}  若不再需要，可用 apt purge 移除 libheif1 libwebp7 等系统库（请确认无其他软件依赖）。${reset}"