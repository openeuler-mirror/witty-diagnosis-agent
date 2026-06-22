#!/usr/bin/env bash
# 真实 opencode 路径 live 冒烟：TASK_DRIVER=opencode，实际拉起 opencode 驱动 xuanyuan 全链路。
# 不依赖 mock。验证：opencode 进程拉起 + 会话建立 + xuanyuan 真实叙述流 + 报告采集。
set -u
ROOT="/opt/src/witty-diagnosis-agent/src/opencode/web/server"
cd "$ROOT" || exit 1
source ~/.nvm/nvm.sh >/dev/null 2>&1; nvm use 22 >/dev/null 2>&1

TMP="$(mktemp -d)"
JAR="$TMP/cookies.txt"
SSE="$TMP/sse.txt"
PORT=$((8800 + RANDOM % 150))
# 起前先清掉该端口上的任何残留监听，避免误连孤儿 server
fuser -k "${PORT}/tcp" 2>/dev/null || true
PID=""
cleanup(){ [ -n "$PID" ] && kill "$PID" 2>/dev/null; pkill -f "opencode.*serve" 2>/dev/null; }
trap cleanup EXIT

# 造一份离线日志（offline 创建会校验路径存在）
LOGDIR="$TMP/disk_logs"; mkdir -p "$LOGDIR"
cat > "$LOGDIR/kernel.log" <<'EOF'
2026-06-21T19:30:01 kernel: sd 0:0:0:0: [sda] tag#12 timeout
2026-06-21T19:30:02 kernel: blk_update_request: I/O error, dev sda, sector 1048576
2026-06-21T19:30:03 kernel: EXT4-fs error (device sda1): ext4_find_entry: reading directory lblock 0
2026-06-21T19:30:05 smartd[812]: Device: /dev/sda, 8 Currently unreadable (pending) sectors
2026-06-21T19:31:00 systemd: data.mount: Mount process exited, code=exited status=32
EOF

TASK_DRIVER=opencode \
  TASK_OPENCODE_BIN=/root/.nvm/versions/node/v22.17.1/bin/opencode \
  TASK_OPENCODE_HOME_BASE="$TMP/task-homes" \
  TASK_OC_DEBUG_EVENTS="$TMP/events.log" \
  SCHEDULER_MAX_CONCURRENT=1 \
  PORT="$PORT" DB_SQLITE_PATH="$TMP/task.db" UPLOAD_DIR="$TMP/uploads" \
  CONVERSATION_ENABLED=false LOG_LEVEL=info \
  node --import tsx src/index.ts >"$TMP/server.log" 2>&1 &
PID=$!
echo "server pid=$PID port=$PORT tmp=$TMP"

for i in $(seq 1 60); do curl -fs "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1 && break; sleep 0.25; done
curl -fs "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1 || { echo "FAIL server 启动"; cat "$TMP/server.log"; kill $PID; exit 1; }
echo "server up."

curl -fs -X POST "http://127.0.0.1:$PORT/api/auth/login" -H 'Content-Type: application/json' \
  -d '{"username":"ops.zhang"}' -c "$JAR" >/dev/null

BODY=$(printf '{"title":"服务器磁盘出现故障，帮我分析下根因","faultTime":"2026-06-21 19:30","mode":"offline","logPath":"%s"}' "$LOGDIR")
TID=$(curl -fs -X POST "http://127.0.0.1:$PORT/api/tasks" -H 'Content-Type: application/json' -d "$BODY" -b "$JAR" \
  | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')
echo "taskId=$TID"
[ -n "$TID" ] || { echo "FAIL 创建任务"; cat "$TMP/server.log"; kill $PID; exit 1; }

curl -Ns "http://127.0.0.1:$PORT/api/tasks/$TID/stream" -b "$JAR" >"$SSE" 2>/dev/null &
SSE_PID=$!

# 最长等 8 分钟或直到 done
for i in $(seq 1 96); do
  grep -q '"type":"done"' "$SSE" && break
  sleep 5
done
kill $SSE_PID 2>/dev/null

echo "==================== 任务详情（持久化日志，含真实叙述） ===================="
curl -fs "http://127.0.0.1:$PORT/api/tasks/$TID" -b "$JAR" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const t=JSON.parse(s);console.log("status:",t.status,"stage:",t.currentStage,"progress:",t.progress);console.log("failReason:",t.failReason);console.log("--- logs ("+t.logs.length+") ---");for(const l of t.logs)console.log(l.time,l.text)})'

echo "==================== 报告 ===================="
curl -fs "http://127.0.0.1:$PORT/api/tasks/$TID/report" -b "$JAR" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const r=JSON.parse(s);console.log("kind:",r.kind,"| meta:",JSON.stringify(r.meta||{}));console.log("html length:",(r.html||"").length)}catch(e){console.log("no report:",s.slice(0,200))}})'

echo "==================== server.log 末尾（错误排查） ===================="
tail -30 "$TMP/server.log"

kill $PID 2>/dev/null
echo "DONE. tmp=$TMP (保留以便排查)"
