#!/bin/bash
# Usage: ./start_gdb_trap.sh <target> <duration> <syscall> <threshold>
# Example: ./start_gdb_trap.sh hkidsd 30 mprotect 16000000

TARGET=$1
DURATION=$2
SYSCALL=$3
THRESHOLD=$4

# 1. 解析 PID
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
rm -f /tmp/agent_gdb.log

LOG_GDB="/tmp/agent_gdb.log"
SCRIPT_GDB="/tmp/agent_trap_dynamic.gdb"

# 2. 动态生成 GDB 脚本
cat <<EOF > $SCRIPT_GDB
set pagination off
set confirm off
set logging file $LOG_GDB
set logging overwrite on
set logging on

catch syscall $SYSCALL

commands
  silent
  # 动态阈值判断
  if \$rsi >= $THRESHOLD
    printf "\n[CAPTURE_SUCCESS] Syscall: $SYSCALL detected!\n"
    printf "Size: %d bytes (Threshold: $THRESHOLD)\n", \$rsi
    bt
    info proc mappings
    # 抓到后退出，结束 GDB 进程
    quit
  else
    continue
  end
end
continue
EOF

# 3. 启动 GDB (后台运行，非阻塞)
# 使用 timeout 确保即使没抓到，时间到了也会自动杀死 GDB
nohup timeout "${DURATION}s" gdb -p "$PID" -x $SCRIPT_GDB > /dev/null 2>&1 &

# 4. 立刻返回
echo "SUCCESS"
echo "PID=$PID"
echo "DURATION=${DURATION}s"
echo "TRAP=$SYSCALL >= $THRESHOLD"
echo "LOG_FILE=$LOG_GDB"
echo "MESSAGE=GDB Trap deployed in background. Please inject fault IMMEDIATELY."