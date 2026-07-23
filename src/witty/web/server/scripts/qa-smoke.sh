#!/usr/bin/env bash
# QA 模块端到端冒烟（T101/T106 验证）：capabilities 开关 + 单轮问答 SSE 主链路。
set -u
ROOT="/opt/src/witty-diagnosis-agent/src/witty/web/server"
cd "$ROOT" || exit 1

TMP="$(mktemp -d)"
JAR="$TMP/cookies.txt"
SSE="$TMP/sse.txt"
PASS=0; FAIL=0
ok(){ echo "PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }

start_server(){ # $1=port $2=enabled
  CONVERSATION_ENABLED="$2" LIGHTRAG_MOCK=true PORT="$1" \
    DB_SQLITE_PATH="$TMP/qa-$1.db" QA_OPENCODE_HOME="$TMP/qa-home-$1" LOG_LEVEL=warn \
    node --import tsx src/index.ts >"$TMP/server-$1.log" 2>&1 &
  echo $!
}
wait_up(){ for i in $(seq 1 40); do curl -fs "http://127.0.0.1:$1/api/health" >/dev/null 2>&1 && return 0; sleep 0.25; done; return 1; }

echo "=== 场景 A：CONVERSATION_ENABLED=true ==="
PID_A=$(start_server 8799 true)
if ! wait_up 8799; then no "server(enabled) 启动"; cat "$TMP/server-8799.log"; kill $PID_A 2>/dev/null; exit 1; fi
ok "server(enabled) 启动"

CAP=$(curl -fs http://127.0.0.1:8799/api/capabilities)
echo "  capabilities=$CAP"
[ "$CAP" = '{"qa":true}' ] && ok "capabilities=true" || no "capabilities=true (got $CAP)"

curl -fs -X POST http://127.0.0.1:8799/api/auth/login -H 'Content-Type: application/json' \
  -d '{"username":"smoke"}' -c "$JAR" >/dev/null && ok "登录" || no "登录"

SID=$(curl -fs -X POST http://127.0.0.1:8799/api/qa/sessions -H 'Content-Type: application/json' \
  -d '{}' -b "$JAR" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
[ -n "$SID" ] && ok "创建会话 ($SID)" || no "创建会话"

# 先订阅 SSE，再发消息
curl -Ns "http://127.0.0.1:8799/api/qa/sessions/$SID/stream" -b "$JAR" >"$SSE" 2>/dev/null &
SSE_PID=$!
sleep 0.6

HTTP=$(curl -s -o "$TMP/msg.json" -w '%{http_code}' -X POST "http://127.0.0.1:8799/api/qa/sessions/$SID/messages" \
  -H 'Content-Type: application/json' -d '{"text":"firewalld reload 后容器断网怎么恢复"}' -b "$JAR")
echo "  POST messages -> HTTP $HTTP $(cat "$TMP/msg.json")"
[ "$HTTP" = "202" ] && ok "发消息 202" || no "发消息 202 (got $HTTP)"

# 立即二次提交应 409（single-flight）
HTTP2=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:8799/api/qa/sessions/$SID/messages" \
  -H 'Content-Type: application/json' -d '{"text":"再问一句"}' -b "$JAR")
[ "$HTTP2" = "409" ] && ok "并发同会话二次提交 409" || no "single-flight 409 (got $HTTP2)"

# 空白问题 400
HTTP3=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:8799/api/qa/sessions/$SID/messages" \
  -H 'Content-Type: application/json' -d '{"text":"   "}' -b "$JAR")
[ "$HTTP3" = "400" ] && ok "空白问题 400" || no "空白问题 400 (got $HTTP3)"

sleep 4  # 等待流式完成
kill $SSE_PID 2>/dev/null
for ev in qa_snapshot qa_trace_start qa_trace qa_evidence qa_token qa_done; do
  grep -q "\"type\":\"$ev\"" "$SSE" && ok "SSE 收到 $ev" || no "SSE 缺 $ev"
done
grep -q '"sourceCount":3' "$SSE" && ok "trace 命中 3 处来源" || echo "  (sourceCount 非3，内容供参考)"
echo "  --- SSE 末尾 ---"; tail -c 400 "$SSE"; echo

# 越权：另一个用户访问该会话应 404
curl -fs -X POST http://127.0.0.1:8799/api/auth/login -H 'Content-Type: application/json' \
  -d '{"username":"intruder"}' -c "$TMP/jar2.txt" >/dev/null
HTTP4=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:8799/api/qa/sessions/$SID" -b "$TMP/jar2.txt")
[ "$HTTP4" = "404" ] && ok "越权访问他人会话 404" || no "越权 404 (got $HTTP4)"

kill $PID_A 2>/dev/null

echo; echo "=== 场景 B：CONVERSATION_ENABLED 未设（false） ==="
PID_B=$(start_server 8798 false)
if ! wait_up 8798; then no "server(disabled) 启动"; cat "$TMP/server-8798.log"; kill $PID_B 2>/dev/null; exit 1; fi
CAPB=$(curl -fs http://127.0.0.1:8798/api/capabilities)
[ "$CAPB" = '{"qa":false}' ] && ok "capabilities=false" || no "capabilities=false (got $CAPB)"
curl -fs -X POST http://127.0.0.1:8798/api/auth/login -H 'Content-Type: application/json' -d '{"username":"smoke"}' -c "$TMP/jar3.txt" >/dev/null
HTTP5=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8798/api/qa/sessions -b "$TMP/jar3.txt")
[ "$HTTP5" = "404" ] && ok "未启用时 /api/qa/* 404" || no "未启用 404 (got $HTTP5)"
kill $PID_B 2>/dev/null

echo; echo "===== 结果：PASS=$PASS FAIL=$FAIL ====="
rm -rf "$TMP"
[ "$FAIL" -eq 0 ]
