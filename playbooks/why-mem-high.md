# Why Memory High — 内存分析综合排查手册

> 版本: v1.0 | 适用: Linux 系统 (CentOS/EulerOS/Ubuntu)

## 总览

当系统或进程内存占用异常偏高时，按本手册分步排查。涵盖 5 类场景：

1. 内存泄漏追踪（堆快照对比 + 增长趋势分析）
2. 内存碎片化检测（分配大小分布、Slab 利用率）
3. 大对象分配热点识别（> 阈值对象的分配路径追踪）
4. NUMA 不亲和检测（跨 NUMA 访问开销分析）
5. False sharing 模式识别（缓存行竞争检测）

---

## 第一节：初始信息收集

```bash
# 系统级内存概览
free -h
cat /proc/meminfo | head -30
vmstat -s

# 进程级 TOP 内存使用者
ps aux --sort=-%mem | head -20

# Slab 使用概览
slabtop -s c -o | head -30
cat /proc/slabinfo | head -5

# 页面信息
cat /proc/zoneinfo | grep -E "Node|active|inactive|free|dirty|writeback"

# NUMA 信息
numactl --hardware 2>/dev/null || echo "numactl not installed"
numastat 2>/dev/null || echo "numastat not available"
```

---

## 第二节：内存泄漏追踪

### 2.1 症状识别

| 信号 | 指示 |
|------|------|
| RSS 持续增长不回落 | 用户态泄漏 |
| `SUnreclaim` 持续增长 | Slab 泄漏 |
| `VmallocUsed` 持续增长 | vmalloc 泄漏 |
| Memcg 计数 > 进程 RSS 总和 | memcg 泄漏 |

### 2.2 堆快照对比（基线 vs 当前）

```bash
# 基线快照（怀疑异常时记录）
# /proc/[pid]/smaps 详细解析
PID=<target_pid>
cat /proc/$PID/status | grep -E "VmRSS|VmSize|VmPeak"
grep -E "^[0-9a-f]+\-" /proc/$PID/maps | awk '{print $NF}' | sort | uniq -c | sort -rn

# Heap 段增长
grep "\[heap\]" /proc/$PID/smaps
cat /proc/$PID/smaps | grep -A 10 "\[heap\]" | grep -E "Size|Rss|Pss|Anon"

# Anonymous 页增长 (匿名映射为堆/栈/bss)
cat /proc/$PID/status | grep Vm
grep -E "anonymous|stack|heap" /proc/$PID/smaps 2>/dev/null

# mmap 文件备份的匿名页
grep "Anonymous:" /proc/$PID/status
```

### 2.3 增长趋势分析

```bash
# 间隔采样 (每 10 秒记录 RSS)
for i in {1..6}; do
  echo "$(date +%H:%M:%S) $(ps -p $PID -o rss= --no-headers 2>/dev/null || echo 0)"
  sleep 10
done

# 带 GC 语言 (Java/Python/Go) 额外检查
# Java: jstat -gcutil $PID 10000 6
# Python: gc.get_objects() via debugger
# Go: runtime.ReadMemStats() via pprof
```

### 2.4 泄漏根因定位

```bash
# 用户态: valgrind massif
valgrind --tool=massif --pages-as-heap=yes ./program
ms_print massif.out.* | head -80

# 内核态: kmemleak
echo scan > /sys/kernel/debug/kmemleak
cat /sys/kernel/debug/kmemleak | head -100

# Slab 泄漏详情
for cache in $(cat /proc/slabinfo | awk 'NR>2 {print $1}'); do
  active=$(grep "^$cache " /proc/slabinfo | awk '{print $2}')
  limit=$(grep "^$cache " /proc/slabinfo | awk '{print $4}')
  if [ "$active" -gt "$limit" ] 2>/dev/null; then
    echo "$cache: active=$active limit=$limit (OVER)"
  fi
done
```

---

## 第三节：内存碎片化检测

### 3.1 外部碎片检测

```bash
# 页块信息 (外部碎片 = MAX_ORDER 不可用连续页)
cat /proc/buddyinfo
# 分析: 如果最高 order 的 free pages 接近 0 且低 order 大量碎片, 则碎片化严重

# 碎片指数计算 (简化版)
# 从 buddyinfo 提取
# 碎片率 ≈ 1 - (最大连续块大小 / 总空闲内存)
# > 30% 认为碎片化严重
```

### 3.2 分配大小分布

```bash
# Slab 分配大小分布
slabtop -s c -o | awk 'NR>2 {print $2, $3, $4, $5}' | sort -n -k1 | head -30

# 页分配分布
cat /proc/pagetypeinfo | grep -E "Node|DMA|Normal" | head -20

# 用户态分配大小 (需要 strace 或 perf)
# strace -e trace=brk,mmap -p $PID -o /tmp/alloc.log
# awk '{sum+=$NF} END {print "total alloc:", sum}' /tmp/alloc.log
```

### 3.3 Slab 利用率分析

```bash
# 查看 Slab 整体利用率
echo "Slab 利用率:"
awk 'NR>2 {a+=$2*$3; u+=$3*$4} END {printf "%.1f%% (%d/%d KB)\n", u/a*100, u/1024, a/1024}' /proc/slabinfo

# 查找利用率低的缓存 (分配了但未使用)
cat /proc/slabinfo | awk 'NR>2 {if ($3>0 && $4/$3 < 0.3) print $1, $2, $3, $4, $3-$4}' | sort -k5 -rn | head -20
```

### 3.4 碎片化等级判定

| 碎片率 | 等级 | 建议 |
|--------|------|------|
| < 10% | 正常 | 无需处理 |
| 10% ~ 30% | 轻度 | 监控趋势 |
| > 30% | 严重 | 触发碎片整理 |
| > 50% | 危急 | 需重启或迁移 |

---

## 第四节：大对象分配热点识别

### 4.1 默认阈值的配置

```bash
# 默认阈值: 1MB (可配置)
THRESHOLD=${THRESHOLD:-1048576}  # 字节
```

### 4.2 大对象检测

```bash
# /proc/pid/maps 中查找大块映射
grep -E "^\s*[0-9a-f]+[-\s]" /proc/$PID/maps | \
  awk '{
    split($1, addr, "-");
    size = strtonum("0x" addr[2]) - strtonum("0x" addr[1]);
    if (size > 1048576) print size/1024/1024 " MB", $0;
  }' | sort -rn | head -20

# THP (透明大页) 使用
grep "AnonHugePages:" /proc/$PID/smaps 2>/dev/null | awk '{s+=$2} END {print "THP:", s, "KB"}'
```

### 4.3 分配路径追踪

```bash
# 使用 ftrace 追踪大页分配
echo function_graph > /sys/kernel/debug/tracing/current_tracer
echo __alloc_pages_nodemask > /sys/kernel/debug/tracing/set_ftrace_filter
echo 1 > /sys/kernel/debug/tracing/tracing_on
sleep 5
echo 0 > /sys/kernel/debug/tracing/tracing_on
cat /sys/kernel/debug/tracing/trace > /tmp/large_alloc_trace.log

# 使用 perf 追踪大对象分配 (需要调试符号)
perf record -e syscalls:sys_enter_brk -p $PID --sleep 10
perf script > /tmp/brk_trace.log
```

### 4.4 大对象分类

| 大小范围 | 典型场景 | 处理建议 |
|----------|----------|---------|
| 1MB ~ 10MB | 缓存、内存池 | 检查缓存策略 |
| 10MB ~ 100MB | 大文件映射、堆扩展 | 检查 mmap 使用 |
| > 100MB | 共享内存、大数组 | 检查共享内存配置 |

---

## 第五节：NUMA 不亲和检测

### 5.1 NUMA 配置检查

```bash
# 硬件拓扑
numactl --hardware
lscpu | grep -E "NUMA|Socket|Core"

# 当前策略
numactl --show
cat /sys/devices/system/node/has_normal_memory

# 进程绑定
taskset -pc $PID 2>/dev/null
cat /proc/$PID/numa_maps | head -20
```

### 5.2 跨 NUMA 访问检测

```bash
# 跨节点内存访问比例
numastat -p $PID 2>/dev/null || cat /proc/$PID/numa_maps | \
  awk '{for(i=1;i<=NF;i++) if($i ~ /^N[0-9]=/) {split($i,a,"="); node[a[1]]+=a[2]}} END {for(n in node) print n, node[n]}'

# 本地访问率计算
# 理想值: local_alloc ≈ total_alloc (接近 100%)
# /proc/vmstat 中的 numa_hit / numa_foreign
awk '{if($1=="numa_hit") h=$2; if($1=="numa_foreign") f=$2} END {printf "本地访问率: %.1f%%\n", (h/(h+f))*100}' /proc/vmstat
```

### 5.3 节点内存均衡度

```bash
# 各节点内存使用
for node in /sys/devices/system/node/node*/meminfo; do
  node_name=$(echo $node | grep -oP 'node\d+')
  total=$(grep "MemTotal" $node | awk '{print $2}')
  free=$(grep "MemFree" $node | awk '{print $2}')
  used=$((total-free))
  echo "$node_name: total=${total}KB used=${used}KB ($((used*100/total))%)"
done
```

### 5.4 优化建议输出

| 检测结果 | 建议 |
|----------|------|
| 本地访问率 < 70% | 使用 `numactl --membind` 绑定节点 |
| 节点内存使用偏差 > 30% | 调整 `numa_balancing` 或迁移进程 |
| 跨节点延迟 > 20% | 开启 `AutoNUMA` 或手动 pin CPU |
| 进程跨 Socket | 使用 `taskset` 绑定同一 socket 的 CPU 和内存 |

---

## 第六节：False Sharing 检测

### 6.1 症状识别

| 信号 | 指示 |
|------|------|
| 多线程性能不随核心数线性扩展 | 可能 false sharing |
| `perf stat` 显示高 cache-misses | 缓存行竞争 |
| VTune 报告 `False Sharing` 事件 | 确认 false sharing |

### 6.2 perf c2c 分析

```bash
# 需要 Linux 4.10+ 和特定硬件支持
perf c2c record -a -- sleep 10
perf c2c report --stats | head -40
perf c2c report | head -20

# 查看热点缓存行
perf c2c report -c pid,iaddr | head -30
```

### 6.3 缓存行热变量定位

```bash
# 使用 perf mem
perf mem record -a -- sleep 10
perf mem report | head -30

# 查看特定地址的缓存行竞争
# 从 perf c2c 输出中提取竞争地址
perf c2c report | grep -E "0x[0-9a-f]+" | awk '{print $1}' | head -10

# 反查变量 (需要调试符号)
# addr2line -e /path/to/binary -f -C <address>
```

### 6.4 代码级检测脚本

```bash
# 检测特定函数内的 cache miss 率
perf stat -e cache-misses,cache-references -p $PID --sleep 10 2>&1 | \
  awk '/cache-misses/ {miss=$1} /cache-references/ {ref=$1} END {printf "Cache miss rate: %.1f%%\n", miss/ref*100}'

# 如果 miss rate > 10% 且多线程, 建议检查 false sharing
```

### 6.5 修复建议

| 检测结果 | 建议 |
|----------|------|
| 确认 false sharing | 对热点变量添加 `__attribute__((aligned(64)))` 填充 |
| 疑似 false sharing | 使用 `pread`/`pwrite` 替代全局锁 |
| 结构体内存布局不当 | 重新排列字段: 读频繁字段分开到不同缓存行 |
| 原子操作频繁 | 使用 `__sync_fetch_and_add` 替代锁 |

---

## 综合分析流程

```
用户报 "内存高"
      │
      ▼
初始信息收集 (free, meminfo, slabtop, numastat)
      │
      ├── RSS 持续增长? ──→ 内存泄漏追踪 (第二节)
      │                        │
      │                        ├── 堆快照对比
      │                        ├── 增长趋势分析
      │                        └── 根因定位 (valgrind/kmemleak/slab)
      │
      ├── 碎片率高? ──→ 内存碎片化检测 (第三节)
      │                        │
      │                        ├── 外部碎片检测 (buddyinfo)
      │                        ├── 分配大小分布
      │                        └── Slab 利用率
      │
      ├── 大块分配? ──→ 大对象热点识别 (第四节)
      │                        │
      │                        ├── 映射大小扫描
      │                        ├── 分配路径追踪
      │                        └── 阈值分析 (默认 1MB)
      │
      ├── 多 NUMA 节点? ──→ NUMA 不亲和检测 (第五节)
      │                        │
      │                        ├── 跨节点访问比例
      │                        ├── 节点内存均衡
      │                        └── 优化建议
      │
      └── 多线程扩展差? ──→ False sharing 检测 (第六节)
                             │
                             ├── perf c2c 分析
                             ├── 缓存行定位
                             └── 修复建议
```

---

## 配套脚本

| 脚本 | 对应章节 | 功能 |
|------|---------|------|
| `diagnose_rss_growth.sh` | 第二节 | RSS 增长趋势分析 |
| `diagnose_anon_page.sh` | 第二节 | 匿名页泄漏诊断 |
| `diagnose_fragmentation.sh` | 第三节 | 内存碎片化检测 |
| `diagnose_large_object.sh` | 第四节 | 大对象热点识别 |
| `diagnose_numa_affinity.sh` | 第五节 | NUMA 不亲和检测 |
| `diagnose_false_sharing.sh` | 第六节 | False sharing 检测 |
| `analyze_heap_trend.py` | 第二节 | 堆增长趋势分析 |
