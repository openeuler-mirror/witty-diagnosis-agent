# 常见 Swap / Thrashing 问题模式速查

> 本文件配合 SKILL.md 第三节"内核语义分析"使用。
> 按故障类型索引，每种模式给出：现象特征、内核行为、根因定位策略。

---

## 一、Swap 空间耗尽

### 模式1：物理 swap 分区/文件被完全写满

**现象特征**：
- `free -h`：SwapUsed ≈ SwapTotal
- `vmstat 1`：si 极低或为 0（无法 swap in），so 可能为 0 或很小
- 进程可能开始 OOM，或系统进入 direct reclaim 死循环
- dmesg 可能有 "allocation failure" 或 "Out of memory"

**内核行为**：
- `get_swap_page()` 返回失败（swap 槽位耗尽）
- 匿名页无法换出 → shrink_lruvec() 只回收文件页
- 文件页被大量回收 → page cache 缩小 → 再次访问需要磁盘 I/O → 性能下降

**根因定位策略**：
1. 确认 swap 总量：`swapon --show` / `cat /proc/swaps`
2. 确认 swap 占用率：`free -h` / `cat /proc/meminfo`
3. 找出 swap 高占用 TOP 进程
4. 检查是否有内存泄漏（进程 RSS 持续增长）
5. 检查 `vm.overcommit` 是否设置为 1（总是 overcommit）
6. 检查 cgroup `memory.limit_in_bytes` 和 `memory.memsw.limit_in_bytes`

### 模式2：Swap 空间不足但内存充足（不当配置）

**现象特征**：
- 大量空闲内存（MemAvailable 充足）
- Swap 已用满
- 系统性能尚可，偶尔抖动

**根因定位策略**：
1. 检查 swappiness：`sysctl vm.swappiness`
2. 检查 dirty_ratio：如果脏页比例大，匿名页被挤出
3. 检查是否有进程通过 `mlockall()`/`mlock()` 锁定大量内存（不可回收）
4. 检查 cgroup `memory.memsw.limit_in_bytes` < `memory.limit_in_bytes` 是否太小

---

## 二、Swap Thrashing（内存抖动）

### 模式3：高频 swap in/out 循环

**现象特征**：
- `vmstat 1`：si 和 so 同时 > 1000 pages/s（highly active swapping）
- CPU iowait 高（swap in 需要磁盘读）
- CPU si（软中断）也可能升高
- 系统响应极慢，进程大量 D 状态
- `sar -W`：swapin/s 和 swapout/s 持续高位

**内核行为**：
- 内存压力大 → kswapd/direct reclaim 频繁唤醒
- 匿名页被 swap out → 进程访问该页 → 缺页异常 → swap in
- 内存压力仍在 → 刚才换入的页又被 swap out
- 形成 **swap in → use → swap out → swap in → ...** 的死循环

**检测指标（Thrashing 判定标准）**：

| 指标 | 阈值 | 严重级别 |
|------|------|---------|
| si + so 速率 | > 1000 pages/s 持续 10+ 秒 | 🔴 严重 thrashing |
| si + so 速率 | > 500 pages/s 持续 30+ 秒 | 🟡 中度 thrashing |
| pgmajfault/s | > 100/s | 🟡 大量主缺页 |
| CPU iowait | > 30% | 🔴 IO 成为瓶颈 |
| allocation stall | > 0 (任何非零) | 🟡 内存分配阻塞 |

**根因定位策略**：
1. **最常见根因**：**工作集大小 > 物理内存**（总的内存需求超过 RAM 容量）
   - 运行了太多/太大进程
   - 进程内存泄漏，RSS 持续增长最终超过 RAM
   - 验证：统计所有进程 RSS ≈ RAM → 就是工作集过大
2. **次常见根因**：**内存碎片导致高水位线焦虑**
   - 即使内存有余，高 order 分配失败触发 reclaim
   - 验证：检查 `/proc/buddyinfo` 碎片情况
3. **少见根因**：**NUMA 失衡**
   - 一个节点在 thrashing 其他节点空闲
   - 验证：`numastat -p <PID>`

**Thrashing vs 正常 Swap 的区分**：

| 特征 | 正常 swap | Thrashing |
|------|---------|-----------|
| si : so | 通常 so > si（累积换出） | si ≈ so（频繁换入换出） |
| CPU iowait | 正常或略高 | 显著升高（50%+） |
| 系统响应 | 基本正常 | 严重变慢、卡顿 |
| vmstat procs r | 运行队列正常 | r 列可能很高（进程挤在内存中） |
| 活跃 swap 趋势 | 缓慢增长 | 忽高忽低交替 |

### 模式4：透明大页（THP）触发的假性 Thrashing

**现象特征**：
- si/so 间歇性爆发（非持续）
- 爆发时伴随 kswapd/kcompactd CPU 突增
- 系统平时正常，但周期性出现卡顿

**根因**：透明大页的 khugepaged 在进行大页折叠（promotion）时，需要连续物理内存，触发 compaction（内存压缩），compaction 可能唤醒 kswapd 进行页回收，导致短时 swap 活动。

**验证**：
```bash
cat /sys/kernel/mm/transparent_hugepage/enabled  # 检查是否启用
cat /proc/vmstat | grep compact_stall  # compaction stall 计数
```

---

## 三、Swappiness 配置不当

### 模式5：Swappiness 过高（default 60 可能太高）

**现象特征**：
- 有足够文件页缓存可回收时，内核仍然 swap out 匿名页
- Swap 被用满，但 page cache 很大
- 系统整体性能低于预期

**内核行为**：
- `shrink_lruvec()` 中，匿名页扫描比例 = swappiness / (swappiness + 200)
- swappiness=60 时，匿名页扫描比例 = 60/260 ≈ 23%（仍然不低）
- 若 page cache 充足（大量文件读缓存），理论上不应 swap out 匿名页

**根因定位策略**：
1. 检查 swappiness：`sysctl vm.swappiness`
2. 检查 page cache 是否实际可回收：`cat /proc/meminfo` 的 Cached/Dirty
3. 如果 Cached 大但 Dirty 也大 → 脏页无法回收 → 被迫 swap out
4. 检查 dirty_ratio / dirty_background_ratio

**推荐值**：
| 场景 | 推荐 swappiness | 说明 |
|------|----------------|------|
| 桌面/通用 | 60 | 默认值，均衡策略 |
| 数据库服务器 | 10–20 | 优先保留文件缓存，减少 swap |
| Java 应用服务器 | 10–30 | 避免 GC 停顿受 swap 影响 |
| 高 IO 压力 | 1–20 | 减少 IO 竞争 |
| 实时/延迟敏感 | 1 | 最小化 swap 导致的延迟抖动 |
| SSD 作为 swap | 30–60 | 平衡 SSD 寿命与性能 |
| 内存充足 > 64GB | 1–10 | swap 几乎不需要 |

### 模式6：Swappiness=0 但仍出现 Swap

**现象特征**：
- swappiness=0 已设置
- 仍然看到 si/so 活动（虽然较少）
- 管理员困惑"明明设置了不用 swap"

**根因**：
- swappiness=0 只是"强烈倾向不用 swap"，不是"禁止 swap"
- 在以下情况内核仍然会 swap out：
  - 内存压力大且**文件页不足或不可回收**（大量 dirty 页）
  - 水位线低于 **min** 时，启动 direct reclaim，匿名页和文件页都回收
  - NUMA 节点内存失衡时
- **cgroup 内的 `memory.swappiness=0` 才能真正禁止该 cgroup 内的 swap**（因为 cgroup 级别的 swap 控制是独立实现的）

---

## 四、Swap 文件/分区损坏

### 模式7：Swap 设备 I/O 错误

**现象特征**：
- dmesg 含 "I/O error" + swap 设备名
- si/so 强烈波动（一会儿高一会儿为 0）
- 系统不稳定，随机出现 "swap_info_get" 相关告警
- 进程可能 segfault（尝试读损坏的 swap 槽位）

**内核行为**：
- swap_readpage() 从损坏区域读取失败 → 返回 `-EIO`
- swap 槽位标记为坏页
- 内核可能尝试从内存中恢复（如果有页的原始副本）

**根因定位策略**：
1. `dmesg | grep -E "swap|I/O error|sd[a-z]"` 找 I/O 错误
2. `smartctl -a /dev/sdX` 检查磁盘健康状态
3. `badblocks -v /dev/sdX_partition` 检查坏块
4. 对于 swap 文件：检查文件系统完整性

### 模式8：Swap 文件元数据损坏（swap 文件场景）

**现象特征**：
- `swapon` 报错：`swapon: swapfile has holes`
- `swapon` 报错：`swapon: swapon failed: Invalid argument`
- 内核无法激活 swap 文件
- 系统启动后 swap 未启用

**根因**：
- swap 文件必须是**连续存储**的（非文件系统碎片化就是不能有 hole）
- 文件系统 resize 或 CoW（btrfs/xfs）可能破坏连续性
- Btrfs 不支持 swap 文件（除非 NODATACOW）

**验证**：
```bash
ls -lh /path/swapfile  # 检查文件大小
filefrag -v /path/swapfile  # 检查文件碎片
# 期望：1 extent（连续），不超过 1 个 extent 块
```

---

## 五、Swap on SSD 磨损

### 模式9：SSD 因频繁 swap 导致加速磨损

**现象特征**：
- SSD 寿命快速下降（smartctl 查看 Wear_Leveling_Count）
- swap 设备写入量巨大（`iostat -x` 查看 w/s 和 wkB/s）
- SSD 写入放大（随机 4K 写入比顺序写入更差）

**检测**：
```bash
smartctl -a /dev/sdX | grep -E "Wear_Leveling|Total_LBAs_Written|Percentage Used"
cat /sys/block/sdX/stat | awk '{print "写入次数:", $2, "写入扇区:", $7, "IO等待ms:", $10}'
```

**评估**：
| SSD 类型 | DWPD (Drive Writes Per Day) | 256GB 每日可写 | 4K 随机写入(~0.4JOB) 寿命 |
|---------|---------------------------|---------------|--------------------------|
| 消费级 TLC | 0.1–0.3 | ~50GB | 若 swap 写入 50GB/天 → 约 5 年 |
| 企业级 TLC | 1–3 | ~500GB | 若 swap 写入 50GB/天 → 长寿命 |
| Optane | 30–60 | ~15TB | swap 写入几乎不影响寿命 |

**根因定位策略**：
1. 确认 swap 确实在 SSD 上：`swapon --show` 查看设备路径
2. 量化 swap 写入量：`iostat -x 1` / `atop -d`
3. 评估 swap 写入对 SSD 寿命的影响

---

## 六、kswapd CPU 占用过高

### 模式10：kswapd 持续高 CPU 但内存未耗尽

**现象特征**：
- `top` 显示 kswapd0 CPU > 30% 长时间持续
- 内存 `MemAvailable` 仍有较多空闲
- 系统负载不高但 response time 增加

**内核行为**：
- kswapd 被频繁唤醒，检查水位线发现未达目标
- **无效扫描**（扫描大量页面但回收很少）：pgscan >> pgsteal
- 典型原因：
  1. **LRU 链表上有大量不可回收页**
     - 脏页（Dirty）正在回写
     - unevictable 页（mlock）
     - 正在写回的页
  2. **内存碎片化**：需要 high-order 页但 free_list 碎片化
  3. **水位线设置过高**：`min_free_kbytes` 过大

**根因定位策略**：
1. 检查 pgscan/pgsteal 比率：`cat /proc/vmstat | grep -E "pgscan|pgsteal"`
   - 如 pgscan >> pgsteal → 无效扫描
2. 检查当前脏页：`cat /proc/meminfo | grep Dirty`
   - Dirty 高且 Writeback 持续 → 回写瓶颈
3. 检查 per-CPU 页缓存是否不足：`cat /proc/meminfo | grep "percpu"`
4. 检查内存碎片：`cat /proc/buddyinfo`
5. 检查 watermark：`cat /proc/zoneinfo | grep -A50 "Node 0, zone"`

### 模式11：内存碎片化导致 kswapd 频繁工作

**现象特征**：
- kswapd 高频唤醒但每次工作时间短
- `compaction_stall` 计数持续增长
- `pgscan_direct` > 0（direct reclaim 被触发）
- `allocstall` 计数增长

**根因**：
- 高 order（连续大块）分配频繁失败
- 内核尝试 compaction（压缩内存）但失败
- 为满足 high-order 分配，kswapd 持续回收页面试图合并空闲区域

**验证**：
```bash
cat /proc/buddyinfo  # 看各个 order 的空闲块分布
cat /proc/vmstat | grep -E "compact_|allocstall"
# compaction 相关的计数增长说明碎片化
```

---

## 七、zswap/zram 配置异常

### 模式12：zswap 压缩率极低

**现象特征**：
- zswap 使用了大量内存但压缩比接近 1:1
- `frontswap` 存储效率低下
- 压缩解压 CPU 负载增加

**检测**：
```bash
cat /sys/kernel/debug/zswap/pool_total_size    # zswap 占用的总内存
cat /sys/kernel/debug/zswap/stored_pages        # 存储的页数
cat /sys/kernel/debug/zswap/comp_pages          # 压缩后页数
# 压缩率 = comp_pages / stored_pages（越低越好）
cat /sys/kernel/debug/zswap/reject_compress_poor  # 因压缩率低而被拒绝
```

**根因定位**：
- 页面已在 zram 中被压缩过（双重压缩浪费）
- 使用 zswap 但压缩算法不适合（lzo 在某些场景不如 zstd）
- 数据本身不可压缩（已加密数据/压缩后的媒体数据）

### 模式13：zram 内存占用过高

**现象特征**：
- zram 占用了大量系统内存（/sys/block/zram0/mm_stat 显示 mem_used 大）
- 使用 zram 后系统内存更紧张了

**根因**：
- zram 本身从系统内存分配，**zram 太大反而吃掉了可用内存**
- 典型配置错误：`zram 大小 = RAM * 2`（这是 swap 概念，zram 不需要两倍）

**检测**：
```bash
zramctl
# 对比 zram 使用的内存（mem_used）与分配的 zram 设备大小（disksize）
# mem_used 应当远小于 disksize（因为压缩）
```

**推荐配置**：
```bash
# zram 大小建议为 25%-50% 的 RAM（不是 swap 方式的 2x）
# 轻负载：25% RAM
# 重负载：50% RAM
# zram 太大 → 压占内存 → 触发更多 swap → 恶性循环
```

### 模式14：zswap reject 太多

**现象特征**：
- `reject_reclaim_fail` 持续增长：zswap 在内存压力下无法释放空间
- `reject_compress_poor` 持续增长：压缩率过低被拒绝
- `reject_alloc_fail` 持续增长：内存不够分配压缩页池

**检测**：
```bash
cat /sys/kernel/debug/zswap/reject_reclaim_fail
cat /sys/kernel/debug/zswap/reject_compress_poor
cat /sys/kernel/debug/zswap/reject_alloc_fail
```

**根因定位**：
| Reject 类型 | 含义 | 常见原因 |
|-----------|------|---------|
| reject_reclaim_fail | zswap 在内存压力下无法回收页面 | zswap 池太小或内存压力过大 |
| reject_compress_poor | 页压缩率太低，拒绝存储 | 数据无法压缩 |
| reject_alloc_fail | 无法分配压缩页所需内存 | 系统内存不足 |

---

## 八、内存 cgroup 限制导致的 Swap 异常

### 模式15：cgroup memory.max 过小

**现象特征**：
- cgroup 内进程频繁 OOM，但主机内存充足
- cgroup 内发生大量 swap（memory.swappiness 控制松）
- cgroup `memory.pressure_level` 持续为 "critical"

**检测**：
```bash
cat /sys/fs/cgroup/<path>/memory.current
cat /sys/fs/cgroup/<path>/memory.max
cat /sys/fs/cgroup/<path>/memory.swap.current
cat /sys/fs/cgroup/<path>/memory.pressure_level
```

### 模式16：memory.swap.max 过小

**现象特征**：
- cgroup 内内存+swap 总使用接近上限
- cgroup 内进程直接 OOM（没有 swap 缓冲）
- 但主机整体内存 + swap 仍有富余

---

## 九、多因素混合故障

### 模式17：Cgroup + Dirty 页 + Swap 三重故障

**现象特征**：
- cgroup 限制了内存但未限制 swap
- 大量 dirty 页在 cgroup 内积累
- 文件页无法回收 → 被迫 swap out 匿名页 → 性能下降
- swap 被填满 → cgroup OOM

**根因链**：
```
cgroup memory.max 过小
  → 大量 dirty 页占据 cgroup 内 memory
  → 可回收文件页不足
  → 被迫 swap out 匿名页
  → cgroup 内 swap 耗尽
  → OOM kill
```

**排查路径**：
1. 检查 cgroup memory.stat：rss vs cache vs swap
2. 检查 dirty_ratio/dirty_background_ratio 是否在 cgroup 级别生效
3. 考虑设置 cgroup memory.swap.max 作为硬上限

---

## 十、搜索通用工具命令

```bash
# 查找高 swap 占用进程
for f in /proc/[0-9]*/status; do
  awk '/^VmSwap|^Name|^Pid/{printf "%s ", $2} END{print ""}' "$f" 2>/dev/null
done | sort -k3 -rn | head -20

# 查找内存泄漏可疑进程（RSS 持续增长）
ps -eo pid,comm,rss,%mem --sort=-%mem | head -20

# 查看内存分配延迟
dmesg | grep -E "page allocation failure|allocation failure" | tail -10

# 查看 OOM score 最高的进程
for f in /proc/[0-9]*/oom_score; do
  pid=$(basename $(dirname "$f"))
  name=$(cat /proc/$pid/comm 2>/dev/null)
  score=$(cat "$f" 2>/dev/null)
  [ -n "$score" ] && echo "$pid $name $score"
done 2>/dev/null | sort -k3 -rn | head -20

# 查看 kswapd 的 perf 热点
perf top -k1 | grep -E "kswapd|shrink|reclaim|swap|page"

# 查看内存压缩情况
cat /proc/vmstat | grep -E "compact|stall|fail"
