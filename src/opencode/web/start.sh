#!/usr/bin/env bash
# 本地/单机一键安装与启动（FR-016 / 02 §1.2 D-006）。
# 步骤：装依赖 → knex migrate（建库+建表，幂等）→ 启动后端 + 前端。
# 默认 SQLite，数据文件 ~/.witty-diagnosis-agent/database/witty.db（BC-011）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$HERE/server"
FRONTEND_DIR="$HERE/frontend"

echo "==> [1/4] 安装后端依赖"
cd "$SERVER_DIR"
[ -f .env ] || cp .env.example .env
npm install

echo "==> [2/4] 初始化数据库（migrate，幂等）"
npx knex migrate:latest --knexfile knexfile.cjs

echo "==> [3/4] 启动后端（后台）"
npm run start &
SERVER_PID=$!
echo "    后端 PID=$SERVER_PID"

# 等待健康检查
PORT="${PORT:-8787}"
echo "    等待 /api/health ..."
for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${PORT}/api/health" >/dev/null 2>&1; then
    echo "    后端就绪：http://127.0.0.1:${PORT}/api/health"
    break
  fi
  sleep 1
done

echo "==> [4/4] 启动前端开发服务器"
cd "$FRONTEND_DIR"
npm install
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT
npm run dev
