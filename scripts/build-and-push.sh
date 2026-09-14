#!/bin/bash
#
# fan-reubah - 构建并发布脚本
# 构建前端产物与 Go 二进制，提交版本号、打 tag，并可选创建 GitHub Release。
#
# Usage:
#   TAG(必填) 形如 v1.0.0; --yes 免交互
#     bash scripts/build-and-push.sh v1.0.0 --yes
set -euo pipefail

info() { echo -e "\033[32m>>> $*\033[0m"; }
warn() { echo -e "\033[33m!!! $*\033[0m"; }
error() { echo -e "\033[31mERROR: $*\033[0m"; exit 1; }

YES_MODE=0
TAG=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes) YES_MODE=1; shift ;;
        *) TAG="$1"; shift ;;
    esac
done

[[ -z "${TAG}" ]] && error "缺少TAG参数，示例: $0 v1.0.0 --yes"

cd "$(dirname "$0")/.."
TARGET_VER="${TAG#v}"

GH_REPO=""
REMOTE_URL=$(git remote get-url origin 2>/dev/null || true)
if [[ "${REMOTE_URL}" == *github.com* ]]; then
    GH_REPO=$(echo "${REMOTE_URL}" | sed -E 's#.*github\.com[:/]([^/]+/[^/.]+)(\.git)?$#\1#')
fi

command -v go >/dev/null 2>&1 || error "未找到 go，请先安装并加入 PATH（如 export PATH=\$PATH:/usr/local/go/bin）"
command -v npm >/dev/null 2>&1 || error "未找到 npm/node，请先安装 Node.js"
command -v gcc >/dev/null 2>&1 || error "未找到 gcc，fan-reubah 依赖 cgo（libwebp/libheif）"
command -v pkg-config >/dev/null 2>&1 || error "未找到 pkg-config"
pkg-config --exists libwebp 2>/dev/null || warn "缺少 libwebp 开发库，编译可能失败（Debian/Ubuntu: apt install libwebp-dev）"
pkg-config --exists libheif 2>/dev/null || warn "缺少 libheif 开发库，编译可能失败（Debian/Ubuntu: apt install libheif-dev）"

# ===================== 重复Tag/Release自动清理 =====================
info "检查远端是否存在 Release ${TAG}"
if gh release view "${TAG}" ${GH_REPO:+-R "$GH_REPO"} >/dev/null 2>&1; then
    warn "发现已存在Release ${TAG}，准备删除Release并清理tag"
    gh release delete "${TAG}" -y --cleanup-tag ${GH_REPO:+-R "$GH_REPO"}
fi

info "清理本地&远端Git tag: ${TAG}"
git tag -d "${TAG}" 2>/dev/null || true
git push origin --delete "${TAG}" 2>/dev/null || true

# ===================== 版本号 bump =====================
info "执行版本号更新 ${TARGET_VER}"

sed_i_arg() {
    if sed --version 2>&1 | grep -q GNU; then echo ""
    elif sed --version 2>&1 | grep -q busybox; then echo ""
    else echo "''"
    fi
}

SED_I=$(sed_i_arg)
BUMP_FILE="templates/package.json"
[[ -f "${BUMP_FILE}" ]] || error "缺失文件 ${BUMP_FILE}"

if [[ "${SED_I}" == "''" ]]; then
    sed -i '' "s/^  \"version\": \".*\",\$/  \"version\": \"${TARGET_VER}\",/" "${BUMP_FILE}"
else
    sed -i "s/^  \"version\": \".*\",\$/  \"version\": \"${TARGET_VER}\",/" "${BUMP_FILE}"
fi

info "版本号确认:"
grep -n '"version"' "${BUMP_FILE}"

# ===================== 构建 =====================
info "构建前端生产包"
(cd templates && { npm ci --no-audit --no-fund || npm install --no-audit --no-fund; } && CI=true npm run build)

COMMIT_SHA=$(git rev-parse --short HEAD)
info "构建后端 fan-reubah v${TARGET_VER} (commit ${COMMIT_SHA})"
mkdir -p bin
CGO_ENABLED=1 go build \
    -buildvcs=false \
    -ldflags="-s -w" \
    -o bin/fan-reubah ./cmd/server

REL_ARCH=""
case "$(uname -m)" in
  x86_64|amd64) REL_ARCH="amd64" ;;
  aarch64|arm64) REL_ARCH="arm64" ;;
  *) REL_ARCH="$(uname -m)" ;;
esac
info "生成Release资产 bin/fan-reubah_linux_${REL_ARCH}"
cp ./bin/fan-reubah "./bin/fan-reubah_linux_${REL_ARCH}"
file ./bin/fan-reubah
ls -lh ./bin/fan-reubah

info "构建 SVG 矢量转换引擎 vtracer-cli（release）"
if command -v cargo >/dev/null 2>&1 && [ -d vtracer ]; then
    (cd vtracer && cargo build --release -p vtracer-cli)
    cp ./vtracer/target/release/vtracer "./bin/vtracer_linux_${REL_ARCH}"
    file ./bin/vtracer_linux_${REL_ARCH}
    ls -lh ./bin/vtracer_linux_${REL_ARCH}
else
    warn "未找到 cargo 或缺少 vtracer 源码，跳过 vtracer 构建（SVG 矢量转换功能将不可用）"
fi

info "打包前端资产 bin/fan-reubah-assets.tar.gz（templates + static）"
tar -czf ./bin/fan-reubah-assets.tar.gz \
    --exclude='templates/node_modules' \
    templates static
ls -lh ./bin/fan-reubah-assets.tar.gz

# ===================== Git 提交 & Tag =====================
info "提交版本变更"
git add templates/package.json templates/package-lock.json
git commit -m "chore: bump version to ${TARGET_VER}" || info "无版本文件变更，跳过提交"
git push origin main

git tag "${TAG}"
git push origin "${TAG}"

# ===================== GitHub Release =====================
if command -v gh >/dev/null 2>&1; then
    info "检测到 gh cli，准备处理 GitHub Release ${TAG}"
    ans="n"
    if [[ ${YES_MODE} -eq 1 ]]; then
        ans="y"
    else
        read -p "确认创建Release ${TAG} ? [y/N] " ans
    fi

    if [[ "${ans}" =~ ^[yY]$ ]]; then
        info "新建 Release ${TAG}"
        gh release create "${TAG}" \
            "./bin/fan-reubah_linux_${REL_ARCH}" \
            "./bin/vtracer_linux_${REL_ARCH}" \
            "./bin/fan-reubah-assets.tar.gz" \
            -R "${GH_REPO}" \
            --title "Release ${TAG}" \
            --generate-notes
        info "✅ GitHub Release 处理完成"
    else
        warn "跳过Release创建"
    fi
else
    warn "未找到 gh cli：仅推送git tag，不会生成网页端GitHub Release"
    warn "安装：apt install gh && gh auth login"
fi

info "✅ 发布流程全部完成 ${TAG}"
info "远程一键安装：curl -fsSL https://raw.githubusercontent.com/meimolihan/fan-reubah/main/scripts/install.sh | bash -s -- -p 8081"