#!/usr/bin/env bash
#
# build-rpm.sh —— 一键构建 witty-diagnosis-agent RPM 包
#
# 用法：
#   bash packaging/build-rpm.sh              # 联网构建（默认）
#   bash packaging/build-rpm.sh --vendor      # 离线构建（先备好 node_modules）
#   bash packaging/build-rpm.sh --nodeps      # 跳过构建期依赖检查
#
# 多个开关可组合，例如：bash packaging/build-rpm.sh --vendor --nodeps
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
NODEPS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --vendor) USE_VENDOR=1 ;;
    --nodeps) NODEPS=1 ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) fail "未知参数：$1（可用：--vendor / --nodeps / --help）" ;;
  esac
  shift
done

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
                   bash packaging/build-rpm.sh'
      产物会直接出现在项目下的 rpm-out/（容器内已写入挂载目录）。"
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

# spec 默认不声明 BuildRequires: nodejs/npm，构建期依赖以上面的实际检查为准
# （node/npm 常来自 NodeSource / nvm，不在 rpm 数据库内）。
# 因此这里无需自动 --nodeps；仅在用户显式传入时透传。
if ! rpm -q nodejs >/dev/null 2>&1; then
  warn "Node.js $(node -v) 未被 rpm 管理（NodeSource / nvm 安装），属正常情况。"
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
  # node_modules 必须按任意层级排除，不能只写 './node_modules'：
  # src/witty/web/{frontend,server}/ 下各有一份被 git 忽略的依赖目录（合计
  # 约 164M，且含原生模块编译产物）。只排顶层会把它们打进源码包，
  # 使 SRPM 从几 M 膨胀到 160M+。
  tar czf ~/rpmbuild/SOURCES/"${NAME}-${VERSION}.tar.gz" \
    --transform "s,^\.,${NAME}-${VERSION}," \
    --exclude='./.git' \
    --exclude='node_modules' \
    --exclude='./dist' \
    --exclude='./rpm-out' \
    --exclude='.DS_Store' \
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

if [ "${NODEPS}" -eq 1 ]; then
  RPMBUILD_ARGS+=(--nodeps)
fi

# --- 构建 ---
info "开始 rpmbuild（首次构建需下载 npm 依赖，请耐心等待）"
rpmbuild -ba "${RPMBUILD_ARGS[@]}" ~/rpmbuild/SPECS/"${NAME}.spec"

# --- 收集产物到项目目录 ---
# rpmbuild 只认 ~/rpmbuild 作为工作区，构建完再拷回项目下的 rpm-out/，
# 免去使用者跨目录翻找。rpm-out/ 已在 .gitignore 中排除。
OUT_DIR="${PROJECT_DIR}/rpm-out"
info "收集产物 → ${OUT_DIR}/"
# 先清掉同名旧产物，避免上一次构建的包残留造成误装
rm -f "${OUT_DIR}"/"${NAME}"-*.rpm
mkdir -p "${OUT_DIR}"
find ~/rpmbuild/RPMS -name "${NAME}-${VERSION}*.rpm" -exec cp -f {} "${OUT_DIR}"/ \;
find ~/rpmbuild/SRPMS -name "${NAME}-${VERSION}*.rpm" -exec cp -f {} "${OUT_DIR}"/ \;

RPM_FILE="$(find "${OUT_DIR}" -name "${NAME}-${VERSION}*.noarch.rpm" | head -1)"
[ -n "${RPM_FILE}" ] || fail "未找到构建产物，rpmbuild 可能未成功"

# --- 输出结果 ---
echo ""
info "构建完成，产物："
ls -lh "${OUT_DIR}"/"${NAME}"-*.rpm
echo ""
echo -e "${BOLD}安装命令：${NC}"
echo "  sudo dnf install ${RPM_FILE}"
echo ""
echo -e "${BOLD}安装后每个用户需执行一次（不要用 sudo）：${NC}"
echo "  witty-diagnosis-agent install"
