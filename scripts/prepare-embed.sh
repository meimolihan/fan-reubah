#!/usr/bin/env bash
#
# fan-reubah - 生成内嵌资源（go:embed）
# 将前端模板/静态资源与编译好的 vtracer 引擎写入 internal/assets/web|engine，
# 使 `go build` 产出自包含的"单文件"二进制：页面 + SVG 矢量引擎全部内置其中，
# 部署时不再需要 assets 包或额外安装 vtracer。
#
# Usage:
#   bash scripts/prepare-embed.sh

set -euo pipefail
cd "$(dirname "$0")/.."

info() { echo -e "\033[32m>>> $*\033[0m"; }
warn() { echo -e "\033[33m!!! $*\033[0m"; }
error() { echo -e "\033[31mERROR: $*\033[0m" >&2; exit 1; }

EMBED_WEB="internal/assets/web"
EMBED_ENGINE="internal/assets/engine"

ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64|amd64) GOARCH="amd64" ;;
  aarch64|arm64) GOARCH="arm64" ;;
  *) error "不支持的架构: ${ARCH}" ;;
esac

# ---- 1) 前端资源（templates + static），排除 node_modules ----
info "复制前端资源到 ${EMBED_WEB}"
rm -rf "${EMBED_WEB}/templates" "${EMBED_WEB}/static"
mkdir -p "${EMBED_WEB}"
tar --exclude='templates/node_modules' -cf - templates | tar -xf - -C "${EMBED_WEB}"
cp -rf static "${EMBED_WEB}/static"

if [ ! -f "${EMBED_WEB}/static/css/styles.css" ] || [ ! -d "${EMBED_WEB}/static/js" ]; then
  warn "static/css|js 无构建产物（可先 cd templates && npm run build），嵌入式前端将不完整。"
fi

# ---- 2) vtracer SVG 矢量引擎 ----
VTRACER_SRC=""
for c in \
  "${EMBED_ENGINE}/vtracer_linux_${GOARCH}" \
  "vtracer/target/release/vtracer"; do
  if [ -x "${c}" ] && [ -s "${c}" ]; then VTRACER_SRC="${c}"; break; fi
done

if [ -z "${VTRACER_SRC}" ] && [ -d "vtracer" ] && command -v cargo >/dev/null 2>&1; then
  info "未找到 vtracer 引擎，尝试 cargo 编译...（cd vtracer && cargo build --release -p vtracer-cli）"
  (cd vtracer && cargo build --release -p vtracer-cli) || error "vtracer 编译失败"
  VTRACER_SRC="vtracer/target/release/vtracer"
fi

if [ -n "${VTRACER_SRC}" ] && [ -x "${VTRACER_SRC}" ] && [ -s "${VTRACER_SRC}" ]; then
  mkdir -p "${EMBED_ENGINE}"
  cp -f "${VTRACER_SRC}" "${EMBED_ENGINE}/vtracer_linux_${GOARCH}"
  chmod 755 "${EMBED_ENGINE}/vtracer_linux_${GOARCH}"
  info "已内嵌 vtracer 引擎（${GOARCH}）→ ${EMBED_ENGINE}/vtracer_linux_${GOARCH}"
else
  warn "未找到/无法编译 vtracer，SVG 矢量转换不会被内嵌（其他功能不受影响）。"
fi

info "完成。现在执行 go build，产出的二进制将自包含页面与引擎。"