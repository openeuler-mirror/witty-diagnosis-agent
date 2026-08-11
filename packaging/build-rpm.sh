#!/usr/bin/env bash
#
# build-rpm.sh —— 一键构建 witty-diagnosis-agent RPM 包
#
# 用法：
#   bash packaging/build-rpm.sh              # 联网构建（默认）
#   bash packaging/build-rpm.sh --vendor      # 离线构建（先备好 node_modules）
#
# 产物：~/rpmbuild/RPMS/noarch/witty-diagnosis-agent-*.noarch.rpm

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}==>${NC} ${BOLD}$1${NC}"; }
warn()  { echo -e "${YELLOW}警告:${NC} $1"; }
fail()  { echo -e "${RED}错误:${NC} $1" >&2; exit 1; }

USE_VENDOR=0
if [ "${1:-}" = "--vendor" ]; then
  USE_VENDOR=1
fi

# --- 定位项目根目录 ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_DIR}"

# --- 平台检查 ---
if [ "$(uname -s)" != "Linux" ]; then
  fail "RPM 只能在 Linux 上构建，当前系统为 $(uname -s)。
      请在 Linux 机器/虚拟机中执行，或使用容器：
        docker run --rm -v \"\$PWD\":/src -w /src openeuler/openeuler:24.03 \\
          bash -c 'dnf install -y rpm-build rpmdevtools nodejs npm git tar && \\
                   bash packaging/build-rpm.sh && \\
                   cp -r /root/rpmbuild/RPMS/noarch /src/rpm-out'"
fi

# --- 工具检查 ---
for cmd in rpmbuild rpmdev-setuptree node npm git tar; do
  command -v "$cmd" >/dev/null 2>&1 || \
    fail "未找到 $cmd。请安装：sudo dnf install -y rpm-build rpmdevtools nodejs npm git tar"
done

NODE_MAJOR="$(node -v | sed 's/^v\([0-9]*\).*/\1/')"
if [ "${NODE_MAJOR}" -lt 20 ]; then
  fail "Node.js 版本过低（当前 $(node -v)），package.json 要求 >= 20.0.0"
fi

# --- 从 spec 读取版本号，保持单一事实来源 ---
SPEC_SRC="${SCRIPT_DIR}/witty-diagnosis-agent.spec"
[ -f "${SPEC_SRC}" ] || fail "未找到 spec 文件：${SPEC_SRC}"
VERSION="$(grep -m1 '^Version:' "${SPEC_SRC}" | awk '{print $2}')"
NAME="witty-diagnosis-agent"

info "构建 ${NAME} ${VERSION}"

# --- 准备 rpmbuild 目录树 ---
info "准备 ~/rpmbuild 目录树"
rpmdev-setuptree

# --- 打包源码 ---
info "打包源码 → ${NAME}-${VERSION}.tar.gz"
if git rev-parse --git-dir >/dev/null 2>&1 && git diff --quiet HEAD 2>/dev/null; then
  # 干净的 git 仓库：用 git archive，自动排除 .git/node_modules/dist
  git archive --format=tar.gz \
    --prefix="${NAME}-${VERSION}/" \
    -o ~/rpmbuild/SOURCES/"${NAME}-${VERSION}.tar.gz" HEAD
else
  # 有未提交改动（或非 git 仓库）：打包工作区，手工排除无关目录，
  # 保证本地调试中的改动也能进包
  warn "工作区有未提交改动，将打包当前工作区内容"
  tar czf ~/rpmbuild/SOURCES/"${NAME}-${VERSION}.tar.gz" \
    --transform "s,^\.,${NAME}-${VERSION}," \
    --exclude='./.git' \
    --exclude='./node_modules' \
    --exclude='./dist' \
    --exclude='./rpm-out' \
    --exclude='./.DS_Store' \
    .
fi

# --- 拷贝 wrapper 与 spec ---
cp "${SCRIPT_DIR}/${NAME}.sh" ~/rpmbuild/SOURCES/
cp "${SPEC_SRC}" ~/rpmbuild/SPECS/

# --- 离线模式：准备 vendor 包 ---
RPMBUILD_ARGS=()
if [ "${USE_VENDOR}" -eq 1 ]; then
  VENDOR_TARBALL=~/rpmbuild/SOURCES/"witty-node-modules-${VERSION}.tar.gz"
  if [ ! -f "${VENDOR_TARBALL}" ]; then
    info "生成 vendor 依赖包（此步需要网络，仅需一次）"
    npm ci
    tar czf "${VENDOR_TARBALL}" node_modules
  else
    info "复用已有 vendor 依赖包"
  fi
  RPMBUILD_ARGS+=(--with vendor)
fi

# --- 构建 ---
info "开始 rpmbuild（首次构建需下载 npm 依赖，请耐心等待）"
rpmbuild -ba "${RPMBUILD_ARGS[@]}" ~/rpmbuild/SPECS/"${NAME}.spec"

# --- 输出结果 ---
echo ""
info "构建完成，产物："
find ~/rpmbuild/RPMS -name "${NAME}-${VERSION}*.rpm" -exec ls -lh {} \;
find ~/rpmbuild/SRPMS -name "${NAME}-${VERSION}*.rpm" -exec ls -lh {} \;
echo ""
echo -e "${BOLD}安装命令：${NC}"
echo "  sudo dnf install \$(find ~/rpmbuild/RPMS/noarch -name '${NAME}-${VERSION}*.rpm' | head -1)"
echo ""
echo -e "${BOLD}安装后每个用户需执行一次（不要用 sudo）：${NC}"
echo "  witty-diagnosis-agent install"
