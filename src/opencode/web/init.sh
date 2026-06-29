#!/usr/bin/env bash
# 环境初始化：装依赖 + 建库建表（幂等）
# 独立于启动脚本，只需执行一次，或依赖更新时重跑。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$HERE/server"

echo "==> [1/2] 安装后端依赖"
cd "$SERVER_DIR"
[ -f .env ] || cp .env.example .env
npm install

echo "==> [2/2] 初始化数据库（migrate，幂等）"
npx knex migrate:latest --knexfile knexfile.cjs

echo "✅ 环境初始化完成"
