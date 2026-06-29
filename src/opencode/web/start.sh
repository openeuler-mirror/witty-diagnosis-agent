#!/usr/bin/env bash
# 启动后端 + 前端服务（需先执行 init.sh 完成环境初始化）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$HERE/server"
FRONTEND_DIR="$HERE/frontend"

echo "==> [1/2] 启动后端（后台）"
PORT="${PORT:-8787}"
# 清理旧进程：检查端口是否已被占用
OLD_PID="$(ss -tlnp 2>/dev/null | grep ":${PORT} " | grep -oP 'pid=\K\d+' || true)"
if [ -n "$OLD_PID" ]; then
  echo "    端口 ${PORT} 已被 PID=$OLD_PID 占用，正在关闭..."
  kill "$OLD_PID" 2>/dev/null || true
  sleep 1
fi
cd "$SERVER_DIR"
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

echo "==> [2/2] 启动前端开发服务器"
cd "$FRONTEND_DIR"
npm install
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT
npm run dev
