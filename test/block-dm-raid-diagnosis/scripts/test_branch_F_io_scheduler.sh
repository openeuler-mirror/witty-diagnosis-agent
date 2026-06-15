#!/bin/bash
# Branch F: IO 调度器异常 — 切换调度器 + 压力测试
# WSL 注入脚本
set -e

echo "=========================================="
echo " Block-dm-raid Branch F: IO 调度器异常"
echo "=========================================="

# 查看当前调度器
echo "=== 当前 IO 调度器 ==="
for d in /sys/block/[svdmn]d*; do
  [ -f "$d/queue/scheduler" ] && echo "$(basename $d): $(cat $d/queue/scheduler)"
done

# 切换到 none (WSL 默认可能没有其他调度器)
SCH=$(cat /sys/block/sda/queue/scheduler 2>/dev/null | grep -oP '\[.*?\]' | tr -d '[]')
echo "当前调度器: $SCH"

# 如果有 mq-deadline 或 bfq, 切换过去
if grep -q "mq-deadline" /sys/block/sda/queue/scheduler 2>/dev/null; then
  echo "=== 切换至 mq-deadline ==="
  echo mq-deadline | sudo tee /sys/block/sda/queue/scheduler > /dev/null
  echo "当前: $(cat /sys/block/sda/queue/scheduler)"
elif grep -q "bfq" /sys/block/sda/queue/scheduler 2>/dev/null; then
  echo "=== 切换至 bfq ==="
  echo bfq | sudo tee /sys/block/sda/queue/scheduler > /dev/null
fi

# 压力测试
echo "=== IO 压力 + 调度器切换 ==="
sudo fio --name=sched_test --ioengine=libaio --iodepth=128 \
  --rw=randread --bs=4k --size=1G --numjobs=4 --direct=1 \
  --filename=/tmp/sched_test_file --runtime=30 --output=/tmp/bdm_F_fio.txt &
FIO_PID=$!

sleep 5
echo "=== 运行时切换调度器 ==="
echo none | sudo tee /sys/block/sda/queue/scheduler > /dev/null 2>/dev/null || true
sleep 3
echo mq-deadline | sudo tee /sys/block/sda/queue/scheduler > /dev/null 2>/dev/null || true

wait $FIO_PID
echo "=== 完成 ==="
cat /sys/block/sda/queue/scheduler
rm -f /tmp/sched_test_file
