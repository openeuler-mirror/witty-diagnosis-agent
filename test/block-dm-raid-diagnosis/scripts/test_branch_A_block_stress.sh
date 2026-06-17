#!/bin/bash
# Branch A: 块层 IO 压力测试 — 高 %util + D 状态进程堆积
# WSL 注入脚本
set -e

echo "=========================================="
echo " Block-dm-raid Branch A: 块层 IO 压力注入"
echo "=========================================="

# 检查工具
which fio iostat 2>/dev/null || { echo "缺少 fio/iostat"; exit 1; }

# 采集基线
echo "=== 基线 ==="
iostat -x 1 2 2>/dev/null | tail -10
echo "D state 进程: $(ps aux | grep ' D ' | grep -v grep | wc -l)"

# 注入: 4个fio写压力 + 4个fio随机读 -> 高 %util + D 状态堆积
echo "=== 启动 fio IO 压力 (8 jobs, 60s) ==="
sudo fio --name=blk_stress --ioengine=libaio --iodepth=64 \
  --rw=randrw --rwmixwrite=50 --bs=4k --size=1G \
  --numjobs=8 --direct=1 --runtime=60 \
  --filename=/tmp/blk_stress_file --output=/tmp/bdm_A_fio.txt &
FIO_PID=$!

echo "=== 监控 (每10s) ==="
for i in 1 2 3 4; do
  sleep 10
  echo "--- T$i ---"
  iostat -x 1 2 2>/dev/null | tail -8
  DCNT=$(ps aux | grep ' D ' | grep -v grep | wc -l)
  echo "D state: $DCNT"
  cat /sys/block/sda/inflight 2>/dev/null || true
done

wait $FIO_PID
echo "=== 完成 ==="
iostat -x 1 2 2>/dev/null | tail -5
echo ""
echo "=== 验证完毕 ==="
echo "执行 witty 全流程: 通知 Xuanyuan 运行此诊断"
echo "故障描述: WSL 块层 IO 压力 — fio randrw 8jobs, %util 近100%, D 状态堆积"
