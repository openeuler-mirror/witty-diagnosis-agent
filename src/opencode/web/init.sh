#!/usr/bin/env bash
# 环境初始化：装依赖 + 建库建表（幂等）
# 独立于启动脚本，只需执行一次，或依赖更新时重跑。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$HERE/server"
FRONTEND_DIR="$HERE/frontend"

# ---------- 系统依赖检查 ----------

if command -v ansible &>/dev/null; then
  echo "    ✅ Ansible 已安装"
else
  echo "    ⚠ 未检测到 Ansible，在线诊断需要此工具"
  echo "    安装命令：sudo apt-get install ansible"
  echo "    或参考：https://docs.ansible.com/ansible/latest/installation_guide/"
  echo "    （如果仅使用离线诊断模式，可忽略此提示）"
fi

if command -v sshpass &>/dev/null; then
  echo "    ✅ sshpass 已安装"
else
  echo "    ⚠ 未检测到 sshpass，在线诊断连通性测试需要此工具"
  echo "    安装命令：sudo apt-get install sshpass"
  echo "    （如果仅使用离线诊断模式，可忽略此提示）"
fi

echo "==> [1/3] 安装后端依赖"
cd "$SERVER_DIR"
[ -f .env ] || cp .env.example .env
npm install

echo "==> [2/3] 安装前端依赖"
cd "$FRONTEND_DIR"
npm install

echo "==> [3/3] 初始化数据库（migrate，幂等）"
cd "$SERVER_DIR"
npx knex migrate:latest --knexfile knexfile.cjs

echo "✅ 环境初始化完成"
