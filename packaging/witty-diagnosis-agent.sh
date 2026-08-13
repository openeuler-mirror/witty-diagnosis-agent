#!/bin/sh
# /usr/bin/witty-diagnosis-agent —— CLI 包装脚本
#
# 真正的入口是 /usr/lib/witty-diagnosis-agent/dist/cli.js。这里用绝对路径
# 显式 exec，而不是给 cli.js 做软链接：软链接场景下 import.meta.url 可能解析
# 到链接自身，干扰 shared/paths.ts 里 packageRootDir() 的「向上找 package.json」
# 逻辑，进而导致 skills 目录定位失败。
#
# "$@" 原样透传用户参数（install / doctor / --language zh ...）。

set -e

WITTY_LIBDIR="/usr/lib/witty-diagnosis-agent"
WITTY_ENTRY="${WITTY_LIBDIR}/dist/cli.js"

if [ ! -f "${WITTY_ENTRY}" ]; then
  echo "witty-diagnosis-agent: 未找到入口 ${WITTY_ENTRY}" >&2
  echo "  安装可能不完整，请尝试重新安装：dnf reinstall witty-diagnosis-agent" >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "witty-diagnosis-agent: 未找到 node，请先安装 Node.js >= 20" >&2
  exit 1
fi

exec node "${WITTY_ENTRY}" "$@"
