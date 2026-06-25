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
PORT="${PORT:-8787}"
# 清理旧进程：检查端口是否已被占用
OLD_PID="$(ss -tlnp 2>/dev/null | grep ":${PORT} " | grep -oP 'pid=\K\d+' || true)"
if [ -n "$OLD_PID" ]; then
  echo "    端口 ${PORT} 已被 PID=$OLD_PID 占用，正在关闭..."
  kill "$OLD_PID" 2>/dev/null || true
  sleep 1
fi
npm run start &
SERVER_PID=$!
echo "    后端 PID=$SERVER_PID"

# 等待健康检查
echo "    等待 /api/health ..."
HEALTH_OK=false
for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${PORT}/api/health" >/dev/null 2>&1; then
    HEALTH_OK=true
    echo "    后端就绪：http://127.0.0.1:${PORT}/api/health"
    break
  fi
  sleep 1
done
if [ "$HEALTH_OK" = false ]; then
  echo "    ⚠ 后端启动失败（端口 ${PORT} 无法监听或健康检查超时），请检查日志"
fi
echo "==> [4/4] 启动前端开发服务器"
cd "$FRONTEND_DIR"
npm install
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT
npm run dev
