#!/bin/bash
#
# fan-reubah - 发布脚本（触发 GitHub Actions 自动构建）
# 不在本地编译任何产物：仅更新版本号、推送代码并打 v 开头 tag。
# 推送 tag 后由 .github/workflows/release.yml 自动完成全部编译与发布：
#   amd64/arm64 的 fan-reubah + vtracer 二进制、前端资产打包、创建 GitHub Release。
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

# ===================== 重复Tag/Release自动清理 =====================
info "检查远端是否存在 Release ${TAG}"
if command -v gh >/dev/null 2>&1 && gh release view "${TAG}" ${GH_REPO:+-R "$GH_REPO"} >/dev/null 2>&1; then
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

# ===================== Git 提交 & Tag =====================
info "提交版本变更"
git add templates/package.json templates/package-lock.json
git commit -m "chore: bump version to ${TARGET_VER}" || info "无版本文件变更，跳过提交"
git push origin main

git tag "${TAG}"
git push origin "${TAG}"

# ===================== 交由 CI 自动构建发布 =====================
info "✅ 已推送 tag ${TAG}，GitHub Actions 将自动完成编译与 Release 创建"

# 自动捕获刚触发的 CI run 并实时跟踪（gh 可用时）
if command -v gh >/dev/null 2>&1; then
    info "等待 GitHub Actions 捕获本次构建..."
    EXPECT_SHA="$(git rev-parse "${TAG}")"
    RUN_ID=""
    for _ in {1..30}; do
        RUN_ID="$(gh run list --workflow=release.yml --branch "${TAG}" --event push --limit 5 \
            --json databaseId,headSha,status \
            --jq '.[] | select(.headSha == "'"${EXPECT_SHA}"'") | .databaseId' 2>/dev/null | head -1 || true)"
        [ -n "${RUN_ID}" ] && break
        sleep 5
    done

    if [ -n "${RUN_ID}" ]; then
        info "已捕获 CI 运行 #${RUN_ID}，开始实时跟踪（Ctrl+C 退出后构建会在后台继续）"
        if gh run watch "${RUN_ID}" --exit-status; then
            info "🎉 CI 构建成功，查看发布结果: gh release view ${TAG}"
        else
            error "CI 构建失败，查看日志: gh run view ${RUN_ID} --log-failed"
        fi
    else
        warn "150 秒内未捕获到 CI 运行（发布流程可能尚未触发），请手动查看: gh run list --workflow=release.yml"
    fi
else
    warn "未找到 gh cli，跳过 CI 自动跟踪（可手动: gh run list --workflow=release.yml）"
fi

info "查看发布结果: gh release view ${TAG}"
info "远程一键安装：curl -fsSL https://raw.githubusercontent.com/meimolihan/fan-reubah/main/scripts/install.sh | bash -s -- -p 8081"