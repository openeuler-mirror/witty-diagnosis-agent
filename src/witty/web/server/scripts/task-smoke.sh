#!/usr/bin/env bash
# 故障运维任务端到端冒烟：新建任务 → 驱动执行（mock）→ SSE 进度/日志 → 完成 → HTML 报告。
# 验证 runner 已接入 agents/xuanyuan/driver 驱动抽象（替换原 mock 骨架），主链路打通。
set -u
ROOT="/opt/src/witty-diagnosis-agent/src/witty/web/server"
cd "$ROOT" || exit 1

TMP="$(mktemp -d)"
JAR="$TMP/cookies.txt"
SSE="$TMP/sse.txt"
PORT=8797
PASS=0; FAIL=0
ok(){ echo "PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TASK_DRIVER=mock PORT="$PORT" DB_SQLITE_PATH="$TMP/task.db" \
  UPLOAD_DIR="$TMP/uploads" LOG_LEVEL=warn \
  node --import tsx src/index.ts >"$TMP/server.log" 2>&1 &
PID=$!
for i in $(seq 1 40); do curl -fs "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1 && break; sleep 0.25; done
curl -fs "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1 && ok "server 启动" || { no "server 启动"; cat "$TMP/server.log"; kill $PID 2>/dev/null; exit 1; }

curl -fs -X POST "http://127.0.0.1:$PORT/api/auth/login" -H 'Content-Type: application/json' \
  -d '{"username":"smoke"}' -c "$JAR" >/dev/null && ok "登录" || no "登录"

# 在线任务（mock 驱动不真正 SSH；connectivityVerified=true 通过门禁）
BODY='{"title":"02:14 起 Nginx 大量返回 502，前端下单失败","faultTime":"2026-06-10 01:30","mode":"online","hostIp":"192.168.10.21","sshUser":"root","sshPassword":"s3cr3t-pass","sshPort":22,"connectivityVerified":true}'
TID=$(curl -fs -X POST "http://127.0.0.1:$PORT/api/tasks" -H 'Content-Type: application/json' -d "$BODY" -b "$JAR" \
  | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')
[ -n "$TID" ] && ok "创建任务 ($TID)" || { no "创建任务"; cat "$TMP/server.log"; kill $PID 2>/dev/null; exit 1; }

# 订阅 SSE 看执行流
curl -Ns "http://127.0.0.1:$PORT/api/tasks/$TID/stream" -b "$JAR" >"$SSE" 2>/dev/null &
SSE_PID=$!

# 等待终态（mock 全流程 ~7-8s）
for i in $(seq 1 40); do
  grep -q '"type":"done"' "$SSE" && break; sleep 0.5
done
kill $SSE_PID 2>/dev/null

for ev in snapshot progress log done; do
  grep -q "\"type\":\"$ev\"" "$SSE" && ok "SSE 收到 $ev" || no "SSE 缺 $ev"
done
grep -q '"status":"succeeded"' "$SSE" && ok "任务成功完成" || no "任务成功完成"

# 阶段流转 / 执行流：以持久化日志为准（避免 SSE 连接前丢失早期阶段的竞态）
DET="$TMP/detail.json"
curl -fs "http://127.0.0.1:$PORT/api/tasks/$TID" -b "$JAR" >"$DET"
for phase in 'fuxi-sub' 'Dayu' 'Baize' 'report_visualization'; do
  grep -q "$phase" "$DET" && ok "执行流可见: $phase" || no "执行流缺: $phase"
done
# 脱敏：SSH 密码绝不出现在事件流
grep -q 's3cr3t-pass' "$SSE" && no "脱敏失败：密码泄漏!" || ok "脱敏：密码未泄漏"

# 拉报告（HTML 内嵌）
REP="$TMP/report.json"
curl -fs "http://127.0.0.1:$PORT/api/tasks/$TID/report" -b "$JAR" >"$REP"
grep -q '"kind":"html"' "$REP" && ok "报告为 HTML 类型" || no "报告非 HTML (got $(head -c 120 "$REP"))"
grep -q '故障诊断报告' "$REP" && ok "报告含正文" || no "报告缺正文"

echo; echo "===== 结果：PASS=$PASS FAIL=$FAIL ====="
kill $PID 2>/dev/null
rm -rf "$TMP"
[ "$FAIL" -eq 0 ]
