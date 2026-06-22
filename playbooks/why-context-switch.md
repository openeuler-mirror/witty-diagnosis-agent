# Why Context Switch — 并发/并行问题综合排查手册

> 版本: v1.0 | 适用: Linux 系统 (CentOS/EulerOS/Ubuntu)

## 总览

当系统出现性能瓶颈、响应延迟、CPU 利用率不足等问题时，按本手册分步排查。涵盖 5 类场景：

1. 线程池饱和检测（队列积压、拒绝率分析）
2. Work stealing 不均衡分析（任务分布偏差检测）
3. 任务队列积压分析（生产消费速率差分析）
4. 并行度不足识别（可用核心未充分利用检测）
5. Cache coherence 开销分析（缓存一致性流量检测）

---

## 第一节：初始信息收集

```bash
# 系统级并发概览
ps -eo pid,tid,comm,psr,%cpu | sort -k4 -n | tail -30
top -b -n1 -H | head -40

# 上下文切换
cat /proc/stat | grep ctxt
vmstat 1 5

# CPU 运行队列
cat /proc/loadavg
sar -q 1 3 2>/dev/null

# 运行线程数
ps -eo pid | wc -l
cat /sys/devices/system/cpu/online
```

---

## 第二节：线程池饱和检测

### 2.1 症状识别

| 信号 | 指示 |
|------|------|
| 线程池任务队列持续增长 | 消费速度 < 生产速度 |
| 任务拒绝率 > 0 | 线程池已满且队列已满 |
| 活跃线程数 = 最大线程数 | 线程池资源耗尽 |

### 2.2 检测方法

```bash
# Java 线程池 (需要通过 JMX 或 jstack 分析)
jstack <pid> | grep -E "pool-|ThreadPool|ForkJoin" | head -20

# 分析线程状态分布
jstack <pid> | grep "java.lang.Thread.State" | sort | uniq -c | sort -rn

# 通用线程数监控
THREAD_COUNT=$(ls /proc/<pid>/task 2>/dev/null | wc -l)
MAX_TASKS=$(cat /proc/sys/kernel/threads-max)
echo "Threads: $THREAD_COUNT / $MAX_TASKS"

# 线程状态分布
for state in R S D T Z X; do
  count=$(ps -eo stat | grep -c "^$state" 2>/dev/null || echo 0)
  echo "State $state: $count"
done
```

### 2.3 判定标准

| 指标 | 正常 | 警告 | 严重 |
|------|------|------|------|
| 线程池使用率 | < 60% | 60-85% | > 85% |
| 队列积压趋势 | 稳定或下降 | 缓慢增长 | 持续快速增长 |
| 任务拒绝率 | 0% | < 1% | > 1% |

---

## 第三节：Work Stealing 不均衡分析

### 3.1 检测方法

```bash
# 各 CPU 利用率分布
mpstat -P ALL 1 3 | grep -v "CPU\|all" | awk '{print $3, $NF"%"}'

# 各 CPU 运行队列长度
for cpu in /sys/devices/system/cpu/cpu*/; do
  cpu_name=$(basename $cpu)
  queue=$(cat $cpu/run_queue 2>/dev/null || echo "N/A")
  echo "$cpu_name: queue=$queue"
done

# 软中断分布
cat /proc/softirqs | head -10

# 硬中断分布
cat /proc/interrupts | head -5
```

### 3.2 偏差计算

```bash
# CPU 利用率标准差（衡量不均衡度）
mpstat -P ALL 1 1 | tail -n +4 | awk '{
  sum+=$NF; vals[NR]=$NF
} END {
  avg=sum/NR
  for(v in vals) sqdiff+=((vals[v]-avg)^2)
  stddev=sqrt(sqdiff/NR)
  printf "平均利用率: %.1f%%\n标准差: %.1f%%\n不均衡系数: %.2f\n", avg, stddev, stddev/avg
}'
```

### 3.3 判定标准

| 不均衡系数 | 等级 | 建议 |
|-----------|------|------|
| < 0.2 | 均衡 | 正常 |
| 0.2 ~ 0.5 | 轻度不均衡 | 检查中断亲和性 |
| > 0.5 | 严重不均衡 | 需调整绑核策略 |

---

## 第四节：任务队列积压分析

### 4.1 生产消费速率分析

```bash
# 使用 perf 统计 syscall 频率 (模拟生产/消费速率)
perf stat -e syscalls:sys_enter_write,syscalls:sys_enter_read -p <pid> --sleep 10 2>&1

# 网络队列积压
netstat -tn | wc -l
ss -tn | wc -l
ip -s link | grep -E "TX|RX" | head -10

# disk 队列
cat /sys/block/*/queue/nr_requests 2>/dev/null | head -5
iostat -x 1 3 | tail -20
```

### 4.2 速率差计算

```bash
# 采样两次，计算生产消费速率差
BEFORE=$(cat /proc/<pid>/io | grep "write_bytes" | awk '{print $2}')
sleep 10
AFTER=$(cat /proc/<pid>/io | grep "write_bytes" | awk '{print $2}')
RATE=$(( (AFTER - BEFORE) / 10 ))
echo "生产速率: $RATE bytes/s"
```

---

## 第五节：并行度不足识别

### 5.1 检测方法

```bash
# CPU 利用率 vs 可用核心
CPU_CORES=$(nproc)
CPU_IDLE=$(top -b -n1 | grep "%Cpu" | awk '{print $8}')
CPU_USED=$((100 - ${CPU_IDLE%.*}))
echo "可用核心: $CPU_CORES, CPU使用率: $CPU_USED%"
echo "并行利用率: $((CPU_USED * 100 / (CPU_CORES * 100)))%"

# 运行队列 vs 核心数
LOAD=$(cat /proc/loadavg | awk '{print $1}')
echo "运行队列长度: $LOAD (核心数: $CPU_CORES)"

# 并行度判定
if [ $(echo "$LOAD < $CPU_CORES * 0.5" | bc -l 2>/dev/null) -eq 1 ]; then
  echo "⚠ 并行度不足: 运行队列 (${LOAD}) < 核心数 (${CPU_CORES}) 的一半"
fi
```

### 5.2 判定标准

| 条件 | 判定 |
|------|------|
| CPU 利用率 < 50% + 负载 < 核心数 | 并行度不足 |
| CPU 利用率 > 80% + 负载 > 核心数*2 | CPU 饱和 |
| GPU 利用率低 + CPU 利用率低 | 应用瓶颈不在计算 |

---

## 第六节：Cache Coherence 开销分析

### 6.1 检测方法

```bash
# 需要 perf 支持 (Linux 4.10+)
perf stat -e cache-misses,cache-references,LLC-loads,LLC-stores -a --sleep 5 2>&1

# 缓存一致性流量 (特定硬件)
perf stat -e rff03,rff01 -a --sleep 5 2>&1 || echo "HW counters not available"

# snoop 流量 (Intel)
perf list | grep -i "snoop\|coheren\|HITM" 2>/dev/null | head -10
```

### 6.2 判定标准

| 指标 | 正常 | 警告 | 严重 |
|------|------|------|------|
| cache miss rate | < 5% | 5-15% | > 15% |
| LLC load miss | < 10% | 10-30% | > 30% |
| snoop/HITM 占比 | < 1% | 1-5% | > 5% |

---

## 综合分析流程

```
用户报 "并发性能差"
      │
      ▼
初始信息收集 (ps, vmstat, loadavg)
      │
      ├── 线程池满/任务拒绝? ──→ 线程池饱和检测 (第二节)
      │                              ├── 线程状态分布
      │                              ├── 队列积压趋势
      │                              └── 拒绝率分析
      │
      ├── CPU利用率不均衡? ──→ Work stealing 不均衡 (第三节)
      │                              ├── 各CPU利用率
      │                              ├── 软硬中断分布
      │                              └── 不均衡系数
      │
      ├── 队列增长? ──→ 任务队列积压分析 (第四节)
      │                        ├── 生产消费速率
      │                        ├── 网络/磁盘队列
      │                        └── 速率差判定
      │
      ├── CPU用不满? ──→ 并行度不足识别 (第五节)
      │                        ├── 利用率 vs 核心数
      │                        ├── 运行队列分析
      │                        └── 负载判定
      │
      └── 多核扩展差? ──→ Cache coherence 开销 (第六节)
                             ├── cache miss率
                             ├── LLC miss率
                             └── snoop/HITM 占比
```

## 配套脚本

| 脚本 | 对应章节 | 功能 |
|------|---------|------|
| `diagnose_thread_pool.sh` | 第二节 | 线程池饱和检测 |
| `diagnose_work_stealing.sh` | 第三节 | Work stealing 不均衡分析 |
| `diagnose_task_queue.sh` | 第四节 | 任务队列积压分析 |
| `diagnose_parallelism.sh` | 第五节 | 并行度不足识别 |
| `diagnose_cache_coherence.sh` | 第六节 | Cache coherence 开销分析 |
