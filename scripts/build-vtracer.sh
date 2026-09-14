#!/usr/bin/env bash
#
# fan-reubah - VTracer 编译安装脚本
# 从 vendored Rust 源码（vtracer/）编译 vtracer-cli 并安装到 /usr/local/bin。
#
# 需要 Rust 工具链（cargo + rustc）；脚本会自动探测 ~/.cargo/bin（rustup 安装路径）。
#
# Usage:
#   bash scripts/build-vtracer.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# 将 rustup 默认安装路径加入 PATH（如已存在则重复追加无害）
if [ -x "${HOME}/.cargo/bin/cargo" ] && ! command -v cargo >/dev/null 2>&1; then
  export PATH="${HOME}/.cargo/bin:${PATH}"
fi

command -v cargo >/dev/null 2>&1 || { echo "错误: cargo 未安装，请先通过 https://rustup.rs 安装 Rust 工具链"; exit 1; }
cargo --version

[ -d vtracer ] || { echo "错误: 缺少 vendored vtracer 源码（vtracer/ 目录不存在）"; exit 1; }

echo "正在编译 vtracer-cli（release）..."
(cd vtracer && cargo build --release -p vtracer-cli)

INSTALL="/usr/local/bin/vtracer"
if cp -f vtracer/target/release/vtracer "${INSTALL}" && chmod 755 "${INSTALL}"; then
  echo "✅ 已安装 vtracer 至 ${INSTALL} （$("${INSTALL}" --version 2>/dev/null || echo "ok")）"
else
  echo "⚠️  安装失败，请检查权限（sudo bash scripts/build-vtracer.sh）"
  exit 1
fi