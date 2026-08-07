#!/usr/bin/env bash
# QA Phase 2 冒烟：多轮上下文 / 停止后重发 / 反馈落库 / LightRAG 降级与故障隔离。
set -u
ROOT="/opt/src/witty-diagnosis-agent/src/witty/web/server"
cd "$ROOT" || exit 1
TMP="$(mktemp -d)"; JAR="$TMP/jar"; PASS=0; FAIL=0
ok(){ echo "PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }
jval(){ sed -n "s/.*\"$2\":\"\([^\"]*\)\".*/\1/p" <<<"$1"; }

start(){ # port mockflag
  CONVERSATION_ENABLED=true LIGHTRAG_MOCK="$2" PORT="$1" DB_SQLITE_PATH="$TMP/db-$1.db" \
    QA_OPENCODE_HOME="$TMP/h-$1" LOG_LEVEL=warn node --import tsx src/index.ts >"$TMP/log-$1" 2>&1 & echo $!; }
wait_up(){ for i in $(seq 1 40); do curl -fs "http://127.0.0.1:$1/api/health">/dev/null 2>&1 && return; sleep 0.25; done; return 1; }
postmsg(){ curl -s -o "$TMP/m.json" -w '%{http_code}' -X POST "http://127.0.0.1:$1/api/qa/sessions/$2/messages" -H 'Content-Type: application/json' -d "{\"text\":\"$3\"}" -b "$JAR"; }

echo "=== 多轮 / 停止重发 / 反馈（mock=true）==="
PID=$(start 8797 true); wait_up 8797 || { no "启动"; cat "$TMP/log-8797"; exit 1; }
curl -fs -X POST http://127.0.0.1:8797/api/auth/login -H 'Content-Type: application/json' -d '{"username":"p2"}' -c "$JAR" >/dev/null
SID=$(jval "$(curl -fs -X POST http://127.0.0.1:8797/api/qa/sessions -d '{}' -H 'Content-Type: application/json' -b "$JAR")" id)
[ -n "$SID" ] && ok "创建会话" || no "创建会话"

SSE="$TMP/sse"; curl -Ns "http://127.0.0.1:8797/api/qa/sessions/$SID/stream" -b "$JAR" >"$SSE" 2>/dev/null & SSEPID=$!
sleep 0.5
# 第一轮：firewalld（命中关键词）
postmsg 8797 "$SID" "firewalld reload 后容器断网" >/dev/null
AID=$(jval "$(cat "$TMP/m.json")" assistantMessageId)
sleep 3.5
# 第二轮追问：无关键词 → 结合上文续答（多轮上下文）
H=$(postmsg 8797 "$SID" "那要怎么彻底避免这种情况")
[ "$H" = "202" ] && ok "追问 202" || no "追问 202 (got $H)"
sleep 3.5
kill $SSEPID 2>/dev/null
grep -q "结合上文" "$SSE" && ok "多轮上下文：第二轮结合上文续答" || no "多轮上下文未体现（无『结合上文』）"

# 反馈落库
HF=$(curl -s -o /dev/null -w '%{http_code}' -X PUT "http://127.0.0.1:8797/api/qa/sessions/$SID/messages/$AID/feedback" -H 'Content-Type: application/json' -d '{"feedback":"useful"}' -b "$JAR")
[ "$HF" = "200" ] && ok "PUT feedback 200" || no "feedback 200 (got $HF)"
DETAIL=$(curl -fs "http://127.0.0.1:8797/api/qa/sessions/$SID" -b "$JAR")
grep -q '"feedback":"useful"' <<<"$DETAIL" && ok "反馈落库可查" || no "反馈未落库"
# 非法反馈 400
HF2=$(curl -s -o /dev/null -w '%{http_code}' -X PUT "http://127.0.0.1:8797/api/qa/sessions/$SID/messages/$AID/feedback" -H 'Content-Type: application/json' -d '{"feedback":"x"}' -b "$JAR")
[ "$HF2" = "400" ] && ok "非法反馈 400" || no "非法反馈 400 (got $HF2)"

# 停止后重发：发起 → stop → 短暂 settle → 重发应 202（锁已释放，非 409）
postmsg 8797 "$SID" "Java 容器 Exited(137) 反复重启" >/dev/null
sleep 0.3
curl -fs -X POST "http://127.0.0.1:8797/api/qa/sessions/$SID/stop" -b "$JAR" >/dev/null && ok "stop 200" || no "stop"
sleep 0.5
HR=$(postmsg 8797 "$SID" "升级 docker 后容器全部启动失败")
[ "$HR" = "202" ] && ok "停止后重发 202（非 409）" || no "停止后重发 (got $HR)"
sleep 3
# 验证被停止的那条标记 aborted
ABORTED=$(curl -fs "http://127.0.0.1:8797/api/qa/sessions/$SID" -b "$JAR")
grep -q '"status":"aborted"' <<<"$ABORTED" && ok "被停止消息标记 aborted" || echo "  (未见 aborted，供参考)"
kill $PID 2>/dev/null

echo; echo "=== 降级与故障隔离（mock=false 且无端点）==="
PID2=$(start 8796 false); wait_up 8796 || { no "启动(降级态)"; cat "$TMP/log-8796"; exit 1; }
ok "server 启动（LightRAG 不可达不阻塞）"
curl -fs -X POST http://127.0.0.1:8796/api/auth/login -H 'Content-Type: application/json' -d '{"username":"p2"}' -c "$TMP/jar2" >/dev/null
SID2=$(jval "$(curl -fs -X POST http://127.0.0.1:8796/api/qa/sessions -d '{}' -H 'Content-Type: application/json' -b "$TMP/jar2")" id)
SSE2="$TMP/sse2"; curl -Ns "http://127.0.0.1:8796/api/qa/sessions/$SID2/stream" -b "$TMP/jar2" >"$SSE2" 2>/dev/null & SSEPID2=$!
sleep 0.5
curl -s -o /dev/null -X POST "http://127.0.0.1:8796/api/qa/sessions/$SID2/messages" -H 'Content-Type: application/json' -d '{"text":"任意问题"}' -b "$TMP/jar2"
sleep 2.5; kill $SSEPID2 2>/dev/null
grep -q '"degraded":true' "$SSE2" && ok "降级：qa_trace degraded=true（S-007）" || no "未见 degraded"
grep -q '"type":"qa_done"' "$SSE2" && ok "降级仍正常收敛 qa_done" || no "降级未收敛"
# 故障隔离：故障运维 /api/tasks 不受影响
HT=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:8796/api/tasks" -b "$TMP/jar2")
[ "$HT" = "200" ] && ok "故障运维 /api/tasks 不受影响（200）" || no "tasks 受影响 (got $HT)"
kill $PID2 2>/dev/null

echo; echo "===== 结果：PASS=$PASS FAIL=$FAIL ====="; rm -rf "$TMP"; [ "$FAIL" -eq 0 ]
