#!/usr/bin/env bash
# 启动后端 + 前端服务（需先执行 init.sh 完成环境初始化）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$HERE/server"
FRONTEND_DIR="$HERE/frontend"

# ---------- 前置检查 ----------


# 检查后端依赖是否已安装（tsx 二进制是否存在）
if [ ! -f "$SERVER_DIR/node_modules/.bin/tsx" ]; then
  echo "    ⚠ 未检测到后端依赖（缺少 tsx），请先执行: bash init.sh"
  exit 1
fi
if [ ! -f "$SERVER_DIR/.env" ]; then
  echo "    ⚠ 未检测到 .env 配置文件，请先执行: bash init.sh"
  exit 1
fi

# ---------- 清理旧进程 ----------

PORT="${PORT:-8787}"

# 尝试 ss + lsof 双方式查找占用端口的 PID（ss -p 可能需要 root）
OLD_PID="$(ss -tlnp 2>/dev/null | grep ":${PORT} " | grep -oP 'pid=\K\d+' || true)"
if [ -z "$OLD_PID" ]; then
  OLD_PID="$(lsof -ti:"$PORT" 2>/dev/null || true)"
fi
if [ -n "$OLD_PID" ]; then
  echo "    端口 ${PORT} 已被 PID=$OLD_PID 占用，正在关闭..."
  kill "$OLD_PID" 2>/dev/null || true
  sleep 1
fi

# ---------- 启动后端 ----------

echo "==> [1/2] 启动后端（后台）"
cd "$SERVER_DIR"
npm run start &
SERVER_PID=$!
echo "    后端 PID=$SERVER_PID"

# ---------- 等待健康检查 ----------

echo "    等待 /api/health ..."
HEALTH_OK=false
FIRST_FAIL=""
LAST_FAIL=""
for i in $(seq 1 60); do
  # 检查后端进程是否还活着
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "    ⚠ 后端进程已异常退出"
    echo "    查看后端输出以获取详细错误信息"
    exit 1
  fi

  OUTPUT="$(curl -fsS "http://127.0.0.1:${PORT}/api/health" 2>&1)" && {
    HEALTH_OK=true
    echo "    后端就绪：http://127.0.0.1:${PORT}/api/health"
    break
  } || {
    [ -z "$FIRST_FAIL" ] && FIRST_FAIL="$OUTPUT"
    LAST_FAIL="$OUTPUT"
  }
  sleep 1
done

if [ "$HEALTH_OK" = false ]; then
  echo "    ⚠ 后端启动失败"
  echo "    首次错误：$FIRST_FAIL"
  echo "    最后错误：$LAST_FAIL"
  exit 1
fi

# ---------- 启动前端 ----------

echo "==> [2/2] 启动前端开发服务器"
cd "$FRONTEND_DIR"

trap 'kill $SERVER_PID 2>/dev/null || true' EXIT
npm run dev
