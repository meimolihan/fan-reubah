#!/usr/bin/env bash
#
# fan-reubah - 通用文件转换与图像处理 安装脚本
# 将构建产物（bin/fan-reubah 或仓库根目录 ./fan-reubah）安装为 systemd 服务，
# 并把前端模板/静态资源部署到应用目录。可重复执行（升级 = 覆盖二进制并重启服务）。
#
# Usage:
#   交互式安装（将提示端口与应用目录）:
#     bash scripts/install.sh
#   参数静默安装（-p 端口 / -a 应用目录 / -b 二进制源）:
#     bash scripts/install.sh -p 8081 -a /var/lib/fan-reubah -b ./bin/fan-reubah
#     bash scripts/install.sh -y

set -euo pipefail

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

# ================== customize me ==================
APP_NAME="fan-reubah"
DEFAULT_PORT=8081
DEFAULT_APP_DIR="/var/lib/${APP_NAME}"
BIN_PATH="/usr/local/bin/${APP_NAME}"
RECORD_FILE="/etc/${APP_NAME}.conf"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" && pwd)"

# 远程 curl|bash 执行时 BASH_SOURCE[0] 为空，SCRIPT_DIR 退化引用为当前目录；
# 若恰在仓库内运行，据此定位仓库根，使二进制/前端产物走本地而非远端下载。
REPO_ROOT=""
for _c in "${SCRIPT_DIR}/.." "$(pwd)" "$(dirname "$(pwd)")"; do
  if [ -d "${_c}/templates" ] && [ -d "${_c}/static" ] && [ -f "${_c}/templates/package.json" ]; then
    REPO_ROOT="${_c}"
    break
  fi
done

DEFAULT_BIN_SRC="${REPO_ROOT:-${SCRIPT_DIR}/..}/bin/${APP_NAME}"

# 经 curl|bash 远程执行且不在仓库内时 REPO_ROOT 为空，本地构建产物无法定位，
# 直接跳转远端 Release 下载（二进制 + 前端资产包），不再误判目录为本地产物。
resolve_local_src() {
  local candidates=(
    "${REPO_ROOT:-}/$1"
    "${SCRIPT_DIR:-}/../$1"
    "$(pwd)/$1"
  )
  for c in "${candidates[@]}"; do
    if [ -f "${c}" ]; then
      printf '%s' "${c}"
      return 0
    fi
  done
  return 1
}
# ==================================================

FRONTEND_SRC="${REPO_ROOT:-}"

PORT=""
APP_DIR=""
BIN_SRC=""
BIN_SRC_EXPLICIT=0
INSTALL_YES=0

# ---- bootstrap: support `bash -c "$(curl ...)" -p ... -a ... -b ...` ----
case "$0" in
  -*) set -- "$0" "$@" ;;
esac
# `bash -c "$(...)" -- -p ...` 形式中 $0 为 "--"，丢弃以对齐 `bash -s --` 语义
[ "${1:-}" = "--" ] && shift

# ---- parse command-line args (silent install) ----
while [ "$#" -gt 0 ]; do
  case "$1" in
    -p|--port)
      shift
      [ -n "${1:-}" ] || error "缺少 -p/--port 的值"
      PORT="$1"
      ;;
    -a|--appdir)
      shift
      [ -n "${1:-}" ] || error "缺少 -a/--appdir 的值"
      APP_DIR="$1"
      ;;
    -b|--bin)
      shift
      [ -n "${1:-}" ] || error "缺少 -b/--bin 的值"
      BIN_SRC="$1"
      BIN_SRC_EXPLICIT=1
      ;;
    -y|--yes)
      INSTALL_YES=1
      ;;
    -h|--help)
      printf "%s\n" "${gl_lan}fan-reubah${reset} - ${gl_bai}通用文件转换与图像处理 安装脚本${reset}"
      printf "  %-13s %s\n" "${gl_bai}用法:${reset}" "bash scripts/install.sh [-p PORT] [-a APP_DIR] [-b BIN] [-y]"
      printf "  %-13s %s\n" "${gl_bai}-p, --port${reset}" "监听端口（默认 ${gl_lan}${DEFAULT_PORT}${reset}）"
      printf "  %-13s %s\n" "${gl_bai}-a, --appdir${reset}" "应用部署目录（模板/静态资源，默认 ${gl_lan}${DEFAULT_APP_DIR}${reset}）"
      printf "  %-13s %s\n" "${gl_bai}-b, --bin${reset}" "二进制源路径（默认 ${gl_lan}${DEFAULT_BIN_SRC}${reset}）"
      printf "  %-13s %s\n" "${gl_bai}-y, --yes${reset}" "免交互，未指定项全部使用默认值"
      printf "  %-13s %s\n" "${gl_bai}-h, --help${reset}" "显示本帮助"
      printf "%s\n" "${gl_hui}指定任意参数即进入静默安装；不带参数则为交互式安装。${reset}"
      printf "%s\n" "${gl_hui}未指定 -b 且本地无构建产物时，自动从 GitHub Release 下载对应架构二进制。${reset}"
      exit 0
      ;;
    *)
      error "未知参数: $1（使用 -h 查看帮助）"
      ;;
  esac
  shift
done

# ---- read previous install record to prefill defaults (reinstall/upgrade) ----
read_record() {
  [ -f "${RECORD_FILE}" ] || return 0
  while IFS='=' read -r KEY VALUE; do
    KEY=$(printf '%s' "$KEY" | tr -d ' ')
    VALUE=$(printf '%s' "$VALUE" | tr -d '\r')
    case "$KEY" in
      BIN_PATH) [ -n "$VALUE" ] && BIN_PATH="$VALUE" ;;
      PORT) [ -n "$VALUE" ] && [ -z "$PORT" ] && PORT="$VALUE" ;;
      APP_DIR) [ -n "$VALUE" ] && [ -z "$APP_DIR" ] && APP_DIR="$VALUE" ;;
    esac
  done < "${RECORD_FILE}"
  return 0
}

# ---- firewall: automatically open the listen port ----
FW_OPENED="n"
open_firewall_port() {
  local PORT="$1"
  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    if ! firewall-cmd --query-port="${PORT}/tcp" >/dev/null 2>&1; then
      firewall-cmd --permanent --add-port="${PORT}/tcp" >/dev/null 2>&1 || true
      firewall-cmd --reload >/dev/null 2>&1 || true
    fi
    ok "已通过 ${gl_bai}firewalld${reset} 开放端口 ${gl_lan}${PORT}/tcp${reset}"
    FW_OPENED="y"
    return 0
  fi

  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    if ! ufw status 2>/dev/null | grep -q "${PORT}/tcp"; then
      ufw allow "${PORT}/tcp" >/dev/null 2>&1 || true
    fi
    ok "已通过 ${gl_bai}ufw${reset} 开放端口 ${gl_lan}${PORT}/tcp${reset}"
    FW_OPENED="y"
    return 0
  fi

  if command -v iptables >/dev/null 2>&1; then
    if iptables -C INPUT -p tcp --dport "${PORT}" -j ACCEPT >/dev/null 2>&1; then
      ok "端口 ${gl_lan}${PORT}/tcp${reset} 已在 iptables 中放行"
      FW_OPENED="y"
      return 0
    fi
    if iptables -L INPUT -n 2>/dev/null | grep -qE 'policy (DROP|REJECT)|REJECT|DROP'; then
      if iptables -I INPUT -p tcp --dport "${PORT}" -j ACCEPT >/dev/null 2>&1; then
        ok "已通过 ${gl_bai}iptables${reset} 开放端口 ${gl_lan}${PORT}/tcp${reset}"
        FW_OPENED="y"
        return 0
      fi
    fi
  fi
  printf "  %s %s\n" "${gl_huang}[提示]${reset}" "未检测到活跃的防火墙（firewalld/ufw/iptables），跳过端口开放。"
}

ASSETS_TGZ_URL="https://github.com/meimolihan/fan-reubah/releases/latest/download/fan-reubah-assets.tar.gz"

download_frontend_assets() {
  local tmp
  tmp="$(mktemp -d)"
  ok "本地无前端产物，从 GitHub Release 下载前端资产..."
  curl -fsSL "${ASSETS_TGZ_URL}" -o "${tmp}/assets.tar.gz" \
    || error "前端资产包下载失败（${ASSETS_TGZ_URL}），请先用 scripts/build-and-push.sh 完整发布"
  tar -xzf "${tmp}/assets.tar.gz" -C "${tmp}" \
    || error "前端资产包解压失败"
  [ -d "${tmp}/templates" ] && [ -d "${tmp}/static" ] \
    || error "前端资产包缺少 templates/static 目录"
  FRONTEND_SRC="${tmp}"
}

ensure_frontend() {
  # 前端编译产物（static/css 与 static/js）缺失时：
  #   仓库内 -> 用 npm 构建；远程 -> 从 Release 下载资产包
  local missing=0
  [ -d "${FRONTEND_SRC}/static/css" ] || missing=1
  [ -d "${FRONTEND_SRC}/static/js" ] || missing=1

  if [ "${missing}" = "1" ]; then
    if [ -n "${FRONTEND_SRC:-}" ] && [ -f "${FRONTEND_SRC}/templates/package.json" ] && command -v npm >/dev/null 2>&1; then
      ok "检测到前端编译产物缺失，尝试构建前端..."
      (cd "${FRONTEND_SRC}/templates" && { npm ci --no-audit --no-fund >/dev/null 2>&1 || npm install --no-audit --no-fund >/dev/null 2>&1; } && npm run build >/dev/null)
      { [ -d "${FRONTEND_SRC}/static/css" ] && [ -d "${FRONTEND_SRC}/static/js" ]; } \
        || error "前端构建失败，请先运行 scripts/build-and-push.sh 或在安装前完成构建"
    else
      download_frontend_assets
    fi
  fi
}

[ "$(id -u)" != "0" ] && error "请以 root 身份运行（例如 sudo bash scripts/install.sh）"

read_record

warn_box 0  '     Fan Reubah 文件转换 · 安装    '

sep_line
section "安装信息"
printf "  %-14s %s\n" "${gl_lan}系统${reset}" "$(uname -s) $(uname -m)"
printf "  %-14s %s\n" "${gl_lan}程序${reset}" "${gl_bai}${APP_NAME}${reset}"
sep_line

# ---- silent install detection ----
SILENT="n"
if [ -n "${PORT}" ]; then
  case "${PORT}" in
    ''|*[!0-9]*) error "PORT 无效（需为 1‑65535 的数字）: ${PORT}" ;;
    *) [ "${PORT}" -ge 1 ] && [ "${PORT}" -le 65535 ] || error "PORT 超出范围（1‑65535）: ${PORT}" ;;
  esac
  SILENT="y"
fi
if [ -n "${APP_DIR}" ]; then
  [[ "${APP_DIR}" = /* ]] || error "APP_DIR 必须是绝对路径: ${APP_DIR}"
  SILENT="y"
fi
if [ -n "${BIN_SRC}" ]; then
  SILENT="y"
fi
if [ ! -t 0 ]; then
  SILENT="y"
fi

section "配置参数"
# port prompt
if [ -z "${PORT}" ]; then
  if [ "$INSTALL_YES" = "1" ] || [ ! -t 0 ]; then
    PORT="${DEFAULT_PORT}"
  else
    while :; do
      read -r -p "${gl_bai}请输入监听端口${reset} ${gl_hui}[默认: ${DEFAULT_PORT}]${reset}: " PORT
      PORT="${PORT:-$DEFAULT_PORT}"
      case "$PORT" in
        ''|*[!0-9]*) printf "  %s\n" "${gl_huang}端口无效，请重新输入。${reset}" ;;
        *)
          if [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; then break; fi
          printf "  %s\n" "${gl_huang}端口超出范围（1‑65535），请重新输入。${reset}"
          ;;
      esac
    done
  fi
else
  printf "  %-14s %s\n" "${gl_lan}监听端口${reset}" "${gl_bai}${PORT}${reset}（参数指定）"
fi
PORT="${PORT:-$DEFAULT_PORT}"

# app dir prompt
if [ -z "${APP_DIR}" ]; then
  if [ "$INSTALL_YES" = "1" ] || [ ! -t 0 ]; then
    APP_DIR="${DEFAULT_APP_DIR}"
  else
    read -r -p "${gl_bai}请输入应用部署目录${reset} ${gl_hui}[默认: ${DEFAULT_APP_DIR}]${reset}: " APP_DIR
    APP_DIR="${APP_DIR:-$DEFAULT_APP_DIR}"
  fi
else
  printf "  %-14s %s\n" "${gl_lan}应用目录${reset}" "${gl_bai}${APP_DIR}${reset}（参数指定）"
fi
APP_DIR="${APP_DIR:-$DEFAULT_APP_DIR}"

# binary source
BIN_SRC="${BIN_SRC:-$DEFAULT_BIN_SRC}"
if [ ! -f "${BIN_SRC}" ]; then
  # 经 curl|bash 远程执行：探测当前目录/仓库目录中的本地产物
  if [ "${BIN_SRC_EXPLICIT}" != "1" ]; then
    DISCOVERED_BIN="$(resolve_local_src "bin/${APP_NAME}")" || true
    if [ -n "${DISCOVERED_BIN:-}" ]; then
      ok "已从仓库目录发现本地产物 ${gl_bai}${DISCOVERED_BIN}${reset}"
      BIN_SRC="${DISCOVERED_BIN}"
    fi
  fi
fi
if [ ! -f "${BIN_SRC}" ]; then
  if [ "${BIN_SRC_EXPLICIT}" = "1" ]; then
    error "未找到二进制文件 ${BIN_SRC}（-b 显式指定）"
  fi
  # 本地无构建产物时，尝试从 GitHub Release 下载对应架构的二进制
  REL_ARCH=""
  case "$(uname -m)" in
    x86_64|amd64) REL_ARCH="amd64" ;;
    aarch64|arm64) REL_ARCH="arm64" ;;
    *) error "不支持的架构: $(uname -m)，请先本地构建（scripts/build-and-push.sh）或使用 -b 指定" ;;
  esac
  REL_URL="https://github.com/meimolihan/fan-reubah/releases/latest/download/fan-reubah_linux_${REL_ARCH}"
  ok "本地无构建产物，尝试从 GitHub Release 下载 ${gl_bai}${REL_URL}${reset}"
  TMP_BIN="$(mktemp)"
  if ! curl -fsSL "${REL_URL}" -o "${TMP_BIN}"; then
    error "下载 Release 二进制失败（${REL_URL}），请先本地构建或使用 -b 指定"
  fi
  chmod +x "${TMP_BIN}"
  BIN_SRC="${TMP_BIN}"
  ok "已从 GitHub Release 下载二进制（${gl_bai}$(du -h "${TMP_BIN}" | cut -f1)${reset}）"
fi

# 确保前端编译产物存在（本地安装时自动尝试构建）
ensure_frontend

if command -v systemctl >/dev/null 2>&1; then
  USE_SYSTEMD="y"
else
  USE_SYSTEMD="n"
  printf "  %s\n" "${gl_huang}[警告]${reset} 未检测到 systemd（容器或受限环境）。"
  printf "  %s\n" "${gl_hui}    已回退为后台运行模式，重启或崩溃后服务不会自动恢复。${reset}"
fi

sep_line
section "安装程序"
ok "正在安装 ${gl_bai}${APP_NAME}${reset} 二进制 ${gl_hong}.${gl_huang}.${gl_lv}.${gl_bai}"

cp -f "${BIN_SRC}" "${BIN_PATH}"
chmod +x "${BIN_PATH}"
ok "已安装二进制至 ${gl_bai}${BIN_PATH}${reset}"

# ---- SVG 矢量转换引擎（vtracer，可选）----
deploy_vtracer() {
  local src="$1"
  if cp -f "${src}" /usr/local/bin/vtracer && chmod +x /usr/local/bin/vtracer; then
    ok "已安装 SVG 矢量转换引擎 vtracer（${gl_bai}$(du -h /usr/local/bin/vtracer | cut -f1)${reset}）"
  fi
}
VTRACER_SRC=""
for c in \
  "${REPO_ROOT:-}/vtracer/target/release/vtracer" \
  "${REPO_ROOT:-}/bin/vtracer" \
  "${SCRIPT_DIR}/../vtracer/target/release/vtracer" \
  "$(pwd)/vtracer/target/release/vtracer" \
  "${SCRIPT_DIR}/../bin/vtracer"; do
  if [ -x "${c}" ]; then VTRACER_SRC="${c}"; break; fi
done
if [ -n "${VTRACER_SRC}" ]; then
  deploy_vtracer "${VTRACER_SRC}"
elif [ -n "${REPO_ROOT:-}" ] && [ -d "${REPO_ROOT}/vtracer" ] && command -v cargo >/dev/null 2>&1; then
  printf "  %s\n" "${gl_huang}[提示]${reset} 未找到预编译 vtracer，尝试用 cargo 编译（可能需要几分钟）..."
  if (cd "${REPO_ROOT}/vtracer" && cargo build --release -p vtracer-cli >/dev/null 2>&1); then
    deploy_vtracer "${REPO_ROOT}/vtracer/target/release/vtracer"
  else
    printf "  %s\n" "${gl_huang}[提示]${reset} vtracer 编译失败，SVG 矢量转换功能不可用（不影响其他功能）"
  fi
else
  printf "  %s\n" "${gl_huang}[提示]${reset} 未找到 vtracer，SVG 矢量转换功能不可用（不影响其他功能）。"
  printf "  %s\n" "${gl_hui}    可先运行 bash scripts/build-vtracer.sh 编译安装。${reset}"
fi

ok "正在部署应用目录 ${gl_lan}${APP_DIR}${reset}"
mkdir -p "${APP_DIR}"
if [ -n "${FRONTEND_SRC:-}" ] && [ -d "${FRONTEND_SRC}/templates" ]; then
  cp -rf "${FRONTEND_SRC}/templates" "${APP_DIR}/"
  rm -rf "${APP_DIR}/templates/node_modules"
fi
if [ -n "${FRONTEND_SRC:-}" ] && [ -d "${FRONTEND_SRC}/static" ]; then
  cp -rf "${FRONTEND_SRC}/static" "${APP_DIR}/"
fi
chmod -R a+rX "${APP_DIR}"

# ---- write install record ----
mkdir -p "$(dirname "${RECORD_FILE}")"
cat > "${RECORD_FILE}" <<EOF
# ${APP_NAME} 安装记录（由 install.sh 生成，请勿手动修改）
BIN_PATH=${BIN_PATH}
PORT=${PORT}
APP_DIR=${APP_DIR}
EOF
chmod 0644 "${RECORD_FILE}"
ok "已写入安装记录 ${gl_bai}${RECORD_FILE}${reset}"

sep_line
section "启动服务"
if [ "${USE_SYSTEMD}" = "y" ]; then
  cat > "${SERVICE_FILE}" <<UNIT
[Unit]
Description=${APP_NAME} - 通用文件转换与图像处理
After=network-online.target local-fs.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${BIN_PATH}
WorkingDirectory=${APP_DIR}
Environment=PORT=${PORT}
Environment=TZ=Asia/Shanghai
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable "${APP_NAME}" >/dev/null 2>&1 || true
  systemctl restart "${APP_NAME}"
  sleep 2
  if systemctl is-active "${APP_NAME}" >/dev/null 2>&1; then
    ok "${gl_bai}${APP_NAME}${reset} 服务已启动。"
    systemctl status "${APP_NAME}" --no-pager || true
  else
    printf "  %s\n" "${gl_hong}[错误]${reset} 服务启动失败，请检查：${gl_bai}journalctl -u ${APP_NAME} -n 50${reset}" >&2
    exit 1
  fi
else
  if command -v pgrep >/dev/null 2>&1 && pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
    printf "  %s\n" "${gl_huang}[警告]${reset} 检测到 ${APP_NAME} 进程可能已在运行"
  else
    mkdir -p "${APP_DIR}"
    nohup "${BIN_PATH}" >> "${APP_DIR}/${APP_NAME}.log" 2>&1 &
    ok "${APP_NAME} 已在后台启动，pid: ${gl_bai}$!${reset}"
  fi
fi

# 取第一个IPv4
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
[ -z "${IP}" ] && IP="<服务器IP>"

open_firewall_port "${PORT}"

if [ "${FW_OPENED}" = "y" ]; then
  FW_STATUS="${gl_lv}已开放 ${PORT}/tcp${reset}"
else
  FW_STATUS="${gl_huang}未检测到活跃防火墙，已跳过${reset}"
fi

sep_line
if [ "${USE_SYSTEMD}" = "y" ]; then
  printf "  %s\n" "${gl_lv}✔ ${APP_NAME} 安装成功！${reset}"
  printf "  %-14s %s\n" "${gl_lan}访问地址${reset}" "${gl_bai}http://${IP}:${PORT}${reset}"
  printf "  %-14s %s\n" "${gl_lan}应用目录${reset}" "${gl_bai}${APP_DIR}${reset}"
  printf "  %-14s %s\n" "${gl_lan}二进制${reset}" "${gl_bai}${BIN_PATH}${reset}"
  printf "  %-14s %s\n" "${gl_lan}防火墙状态${reset}" "$FW_STATUS"
  printf "  %-14s %s\n" "${gl_lan}运行模式${reset}" "${gl_bai}systemd 服务${reset}"
  sep_line
  printf "  %s\n" "${gl_bai}常用命令：${reset}"
  printf "    %-46s %s\n" "${gl_hui}systemctl status ${APP_NAME}${reset}" "${gl_lan}# 查看状态${reset}"
  printf "    %-46s %s\n" "${gl_hui}systemctl restart ${APP_NAME}${reset}" "${gl_lan}# 重启服务${reset}"
  printf "    %-46s %s\n" "${gl_hui}systemctl stop ${APP_NAME}${reset}" "${gl_lan}# 停止服务${reset}"
  printf "    %-46s %s\n" "${gl_hui}systemctl enable ${APP_NAME}${reset}" "${gl_lan}# 开机自启${reset}"
  printf "    %-46s %s\n" "${gl_hui}journalctl -u ${APP_NAME} -f${reset}" "${gl_lan}# 跟随日志${reset}"
  printf "    %-46s %s\n" "${gl_hui}journalctl -u ${APP_NAME} -n 50${reset}" "${gl_lan}# 最近日志${reset}"
else
  printf "  %s\n" "${gl_lv}✔ ${APP_NAME} 安装成功！${reset} ${gl_huang}（后台运行模式）${reset}"
  printf "  %-14s %s\n" "${gl_lan}访问地址${reset}" "${gl_bai}http://${IP}:${PORT}${reset}"
  printf "  %-14s %s\n" "${gl_lan}应用目录${reset}" "${gl_bai}${APP_DIR}${reset}"
  printf "  %s\n" "  ${gl_huang}注意：${reset}后台运行模式在系统重启后不会自动恢复。"
fi

sep_line