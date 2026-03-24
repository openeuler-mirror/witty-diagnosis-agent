# 进程级 OOM 分析参考手册

## 适用场景
- 特定进程被 OOM killer 杀死（exit code 137）
- 特定进程内存持续增长
- 进程因内存不足崩溃（ENOMEM 错误）

---

## B1. 确认进程是否被 OOM Kill

```bash
PROC_NAME="java"   # 替换为目标进程名
FAULT_TIME="2024-01-15 14:30:00"

# 方法1：从日志确认
journalctl -k --since="$FAULT_TIME -30min" | grep -E "Killed process.*$PROC_NAME|oom.*$PROC_NAME"

# 方法2：检查退出码（进程仍在 systemd 管理下）
systemctl status $SERVICE_NAME | grep -E "exit code|signal|OOM"

# 方法3：检查进程退出原因
# exit code 137 = 128 + 9(SIGKILL) = 被 OOM killer 杀死
journalctl -u $SERVICE_NAME | grep -E "code=killed|signal=KILL"

# 方法4：检查内核日志中的完整 OOM 记录
dmesg -T | grep -B5 -A30 "Killed process.*$PROC_NAME"
```

### OOM Kill 日志完整示例
```
[Mon Jan 15 14:30:01 2024] java invoked oom-killer: gfp_mask=0x14200ca, order=0, oom_score_adj=0
[Mon Jan 15 14:30:01 2024] java cpuset=/ mems_allowed=0
[Mon Jan 15 14:30:01 2024] CPU: 3 PID: 12345 Comm: java
[Mon Jan 15 14:30:01 2024] [ pid ]   uid  tgid total_vm      rss nr_ptes nr_pmds swapents oom_score_adj name
[Mon Jan 15 14:30:01 2024] [12345]     0 12345  1048576   786432    1536       4        0             0 java
...
[Mon Jan 15 14:30:01 2024] Out of memory: Kill process 12345 (java) score 756 or sacrifice child
[Mon Jan 15 14:30:01 2024] Killed process 12345 (java) total-vm:4194304kB, anon-rss:3145728kB
```

**关键信息提取**：
- `total_vm`：进程申请的虚拟内存页数 × 4 = KB
- `rss`：实际驻留物理内存页数 × 4 = KB
- `swapents`：被换出的页数

---

## B2. 进程内存分布详细分析

### 2.1 分析 /proc/PID/smaps

```bash
PID=12345

# 汇总内存分布
cat /proc/$PID/smaps_rollup 2>/dev/null

# 按类型统计各段内存（如果 smaps_rollup 不可用）
awk '
/^[0-9a-f]/ {
    split($0, parts, " ")
    addr = parts[1]
    name = parts[NF]
    if (name == "[heap]") cur_type = "heap"
    else if (name ~ /\[stack/) cur_type = "stack"
    else if (name ~ /\.so/) cur_type = "shared_lib"
    else if (name == "") cur_type = "anonymous_mmap"
    else cur_type = "file_mmap"
}
/^Rss:/ { mem[cur_type] += $2 }
END {
    printf "%-20s %10s KB\n", "Segment", "RSS(KB)"
    printf "%-20s %10s\n", "----", "----"
    for (t in mem) printf "%-20s %10d KB  (%d MB)\n", t, mem[t], mem[t]/1024
}
' /proc/$PID/smaps 2>/dev/null
```

### 2.2 Heap 内存详细分析

```bash
# 查看 heap 段大小
grep "\[heap\]" /proc/$PID/maps

# 输出示例：
# 7f0000000000-7f0100000000 rw-p 00000000 00:00 0  [heap]
# 地址范围差即为 heap 虚拟大小
# RSS 需从 smaps 获取

# 检查 malloc 统计（如果是 glibc malloc）
# 对运行中的进程
gdb -p $PID -batch -ex "call malloc_stats()" 2>/dev/null
# 或
gdb -p $PID -batch -ex "call mallinfo()" 2>/dev/null
```

---

## B3. 内存泄漏判断方法论

### 3.1 基于时间轴的内存趋势分析

```bash
# 方法1：如果有 /proc/$PID/status 的历史监控数据
# 查看 VmRSS 随时间变化

# 方法2：实时观察（排查进行中的泄漏）
watch -n 2 'cat /proc/$PID/status | grep -E "VmRSS|VmHWM|VmSize|VmPeak"'

# 方法3：分析 atop 历史
atop -r /var/log/atop/atop_$(date +%Y%m%d -d "$FAULT_TIME") \
    -b "$FAULT_TIME" -e "$FAULT_TIME +2hours" 2>/dev/null | \
    grep "$PROC_NAME"
```

### 3.2 区分真泄漏 vs 缓存膨胀

| 特征 | 真内存泄漏 | 缓存膨胀（正常） |
|------|-----------|-----------------|
| 内存变化 | 单调递增，不回落 | 随负载波动 |
| anon-rss | 持续增大 | 相对稳定 |
| 触发条件 | 持续运行就增大 | 特定操作时增大 |
| 重启后 | 立刻开始泄漏 | 需要负载才增大 |
| Heap 段 | 持续扩张 | 相对稳定 |

### 3.3 内存泄漏类型判断

```bash
# 判断是堆泄漏还是 mmap 泄漏
# 堆泄漏：[heap] 段 RSS 持续增大
# mmap 泄漏：maps 中有大量匿名 mmap 段

# 统计匿名 mmap 段数量
grep -c "^[0-9a-f].*rw-p 00000000 00:00 0 $" /proc/$PID/maps

# mmap 段超过 1000 个且持续增加，说明存在 mmap 泄漏

# 检查文件描述符泄漏（fd 泄漏可能导致内核内存泄漏）
ls /proc/$PID/fd | wc -l
ls -la /proc/$PID/fd | awk '{print $NF}' | grep -v "^$" | sort | uniq -c | sort -rn | head
```

---

## B4. Java 进程 OOM 专项分析

Java 进程 OOM 需区分 JVM OOM 和系统 OOM：

```bash
# 检查是否有 JVM OOM（java.lang.OutOfMemoryError）
grep -r "OutOfMemoryError" /var/log/app/ 2>/dev/null | tail -20

# JVM heap dump 分析
# 如果配置了 -XX:+HeapDumpOnOutOfMemoryError
ls -lh /tmp/*.hprof 2>/dev/null || find / -name "*.hprof" -newer /tmp 2>/dev/null

# JVM 内存区域占用（需要 jmap/jstat）
jstat -gcutil $PID 2>/dev/null
jmap -heap $PID 2>/dev/null | head -50
```

**Java OOM 分类**：
| OOM 类型 | 根因 | 对应 JVM 参数 |
|----------|------|--------------|
| Java heap space | heap 不足 | -Xmx 太小或泄漏 |
| Metaspace | 类太多/动态代理 | -XX:MaxMetaspaceSize |
| GC overhead limit | GC 时间占比>98% | -XX:+UseG1GC |
| Direct buffer | NIO direct memory | -XX:MaxDirectMemorySize |
| 系统 OOM | JVM 进程被 kernel 杀 | 系统内存总量不足 |

---

## B5. 进程级分析检查清单

```
确认阶段：
□ 确认进程退出方式（被 kill -9 / OOM kill / 自行 crash）
□ 提取 OOM kill 日志（含 anon-rss / total-vm / score）
□ 确认被杀时间点与故障时间点是否吻合

内存分布分析：
□ 分析 /proc/PID/smaps 各段内存占比
□ 确认 heap / anonymous mmap / shared lib 各占多少
□ 对比正常状态与异常状态的内存分布差异

泄漏判断：
□ 是否有单调递增的内存趋势？
□ heap 段 RSS 是否持续增大？
□ 是否有大量碎片化 mmap 段？
□ fd 数量是否异常高？

根因定位：
□ 业务逻辑层面：是否有无限循环 / 无限缓存 / 对象积累？
□ 框架层面：是否有线程池 / 连接池泄漏？
□ JVM 层面（Java）：heap / metaspace / direct buffer？
□ 原生库层面：native 代码是否存在 malloc 未释放？
```
