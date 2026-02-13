#!/bin/bash
# Usage: ./start_monitor.sh <target> <duration_seconds>
# Example: ./start_monitor.sh hkidsd 30

TARGET=$1
DURATION=$2

# 1. 智能解析 PID
if [[ "$TARGET" =~ ^[0-9]+$ ]]; then
    PID=$TARGET
else
    PID=$(pidof "$TARGET" | awk '{print $1}')
fi

if [ -z "$PID" ]; then
    echo "ERROR: Process '$TARGET' not found."
    exit 1
fi

# 清理旧日志
LOG_RSS="/tmp/agent_rss.log"
LOG_STRACE="/tmp/agent_strace.log"
rm -f $LOG_RSS $LOG_STRACE

# 2. 启动 pidstat (后台运行，非阻塞)
# 使用 setsid 确保它脱离当前 shell 会话
nohup pidstat -r 1 "$DURATION" -p "$PID" > $LOG_RSS 2>&1 &

# 3. 启动 strace (后台运行，非阻塞)
# 使用 timeout 控制时长，setsid 确保脱离
nohup timeout -s SIGINT "${DURATION}s" strace -p "$PID" -f -tt -s 200 \
  -e trace=memory \
  -o $LOG_STRACE > /dev/null 2>&1 &

# 4. 立刻返回状态给 Agent
echo "SUCCESS"
echo "PID=$PID"
echo "DURATION=${DURATION}s"
echo "LOG_RSS=$LOG_RSS"
echo "LOG_STRACE=$LOG_STRACE"
echo "MESSAGE=Monitoring started in background. Please inject fault now."