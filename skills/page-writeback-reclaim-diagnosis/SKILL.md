# 页缓存 / 脏页回写 / 内存回收诊断 Skill

## 重要原则

1. **只读诊断**：本 skill 仅进行信息收集和分析诊断，**不执行任何修复命令**，只给出修复建议
2. **修复风险提示**：所有修复建议必须标注风险等级（高/中/低）和回滚方案
3. **禁止自动修复**：绝对禁止自动执行任何修复命令（包括内核参数变更、swap 操作、进程内存限制等）
4. **双轨分析**：采用**现场指标 + 内核回收语义双轨**，必须同时采集 `/proc/vmstat`/`/proc/meminfo` 的瞬时指标和 `tracepoint`/`perf` 的回收事件

---

## 文件结构

```
page-writeback-reclaim-diagnosis/
├── SKILL.md                                   # 诊断流程文档（本文）
├── scripts/
│   ├── collect_mem_reclaim_info.sh            # 【基线】全量信息采集脚本
│   ├── branch_A_dirty_writeback.sh            # 分支A：脏页回写异常（dirty_ratio、throttle）
│   ├── branch_B_reclaim_pressure.sh           # 分支B：kswapd / direct reclaim 高 CPU
│   ├── branch_C_page_cache_thrash.sh          # 分支C：page cache 反复回收抖动
│   ├── branch_D_wb_io_backpressure.sh         # 分支D：慢设备拖垮回写（IO 背压）
│   ├── branch_E_min_free_kbytes.sh            # 分支E：min_free_kbytes 不足
│   ├── branch_F_mmap_writeback.sh             # 分支F：mmap writeback 停顿
│   ├── branch_G_vfs_cache_pressure.sh         # 分支G：vfs_cache_pressure 误配
│   └── branch_H_mixed.sh                      # 分支H：混合/复杂场景
└── references/
    ├── reclaim_commands.md                    # 内存回收诊断命令速查
    ├── fault_patterns.md                      # 回收/回写故障模式目录
    └── kernel_tuning_params.md                # 关键内核参数速查
```

---

## 双轨分析模型

页缓存/脏页回写/内存回收诊断采用**现场指标 + 内核回收语义双轨**模型：

```
┌─────────────────────────────────────────────────────────────────────┐
│                    双轨分析模型                                       │
│                                                                     │
│   Track-1: 现场指标（瞬时快照）                                       │
│   ┌──────────────────────────────────────────────────────────────┐  │
│   │ /proc/vmstat — pgscan, pgsteal, pgfault, nr_dirty,           │  │
│   │                nr_writeback, nr_pageout, workingset_refault   │  │
│   │ /proc/meminfo — MemFree, Cached, Dirty, Writeback,           │  │
│   │                 Shmem, Slab, SReclaimable, KReclaimable      │  │
│   │ /proc/zoneinfo — free, min, low, high, spanned, present      │  │
│   │ /sys/devices/virtual/bdi/*/stats — 回写统计                   │  │
│   └──────────────────────────────────────────────────────────────┘  │
│                    ↓                                                │
│   Track-2: 内核回收语义（事件溯源）                                    │
│   ┌──────────────────────────────────────────────────────────────┐  │
│   │ tracepoint: mm_vmscan_* — kswapd/direct reclaim 扫描事件      │  │
│   │ tracepoint: writeback_* — 回写生命周期的每个阶段                │  │
│   │ tracepoint: filemap_* — page cache 映射/回写                  │  │
│   │ perf 采样 — kswapd CPU 火焰图                                  │  │
│   │ 内核日志 — 直接回收告警、OOM 触发                                 │  │
│   └──────────────────────────────────────────────────────────────┘  │
│                    ↓                                                │
│            ↓                         ↓                              │
│      指标异常判断              事件链路分析                             │
│            ↓                         ↓                              │
│          ┌─────────────────────────────────┐                        │
│          │   交叉验证 → 根因收敛            │                        │
│          └─────────────────────────────────┘                        │
└─────────────────────────────────────────────────────────────────────┘
```

| 分析维度 | Track-1 现场指标 | Track-2 内核回收语义 |
|---------|------------------------|---------------------------|
| 内存回收压力 | `pgscan_kswapd` / `pgscan_direct` | `mm_vmscan_kswapd_wake` / `mm_vmscan_direct_reclaim_start` |
| 脏页回写 | `nr_dirty` / `nr_writeback` / `Dirty` / `Writeback` | `writeback_start` / `writeback_written` / `balance_dirty_pages` |
| Page cache 抖动 | `workingset_refault` / `workingset_activate` | `mm_filemap_map_pages` / `mm_filemap_delete_entry` |
| 回写拥塞 | `BDI` stats: `wb_throttled` / `wb_dirty` / `wb_dirty_limit` | `balance_dirty_pages` wait events |

---

## 故障模式分类

| 代码 | 故障模式 | 典型症状 | 关联参数 |
|------|---------|---------|---------|
| **A** | 脏页回写异常 | 业务写延迟飚高、无写入速度、D 状态进程在 `balance_dirty_pages` 等待 | `dirty_ratio`, `dirty_background_ratio`, `dirty_expire_centisecs` |
| **B** | kswapd / direct reclaim 高 CPU | kswapd 占满 CPU、系统 CPU 用量的 `si` 或 `sy` 异常高、内存分配延迟 | `min_free_kbytes`, `watermark_scale_factor`, `vfs_cache_pressure` |
| **C** | Page cache 反复回收抖动 | `workingset_refault` 高速增长、系统磁盘 IO 大量读但命中率低、load 高但 CPU 空闲 | `page-cluster`, `swappiness`, `vfs_cache_pressure` |
| **D** | 慢设备拖垮回写（IO 背压） | 单个慢盘导致全局 dirty 限速、BDI dirty 大量堆积、写回 IOPS 远低于吞吐预期 | 设备 IO 队列、BDI 限流 |
| **E** | min_free_kbytes 不足 | allocation failure 告警、直接回收频率高、pgscan_direct 远大于 pgscan_kswapd | `min_free_kbytes`, `watermark_scale_factor` |
| **F** | mmap writeback 停顿 | mmap 写入大量脏页后进程 D 状态卡在 `msync` / `page_mkwrite` / `fput` | `dirty_ratio`, 文件系统回调 |
| **G** | vfs_cache_pressure 误配 | dentry/inode 缓存快速回收→反复重造→CPU 飙升、内存充足但 slab 回收激进 | `vfs_cache_pressure` |
| **H** | 混合/复杂场景 | 同时出现多个以上故障模式 | 多个参数 |

---

## 诊断流程

### 阶段一：信息采集与场景识别

#### 步骤 1：时间窗口确认

根据用户描述计算故障时间窗口，**必须输出绝对时间**：

| 用户描述 | 时间窗口设定 |
|---------|-------------|
| 明确时间点 | `[故障时间 - 5分钟, 故障时间 + 持续时间 + 5分钟]` |
| "刚才/刚刚" | `[当前时间 - 30分钟, 当前时间]` |
| "间歇性/偶尔" | `[当前时间 - 2小时, 当前时间]` |
| 无法确定 | `[当前时间 - 1小时, 当前时间]` |

时间格式：`YYYY-MM-DD HH:MM:SS`

#### 步骤 2：执行基线信息采集

运行基线采集脚本：

```bash
bash scripts/collect_mem_reclaim_info.sh
```

脚本输出按区块组织，包括：
- **Section A** — 系统概要（kernel、发行版、内存总量、CPU 数、swap 总量）
- **Section B** — `/proc/meminfo` 完整快照（重点关注 Dirty、Writeback、Cached、Shmem、KReclaimable）
- **Section C** — `/proc/vmstat` 增量 vs 累计指标（pgfault、pgscan、pgsteal、nr_dirty、workingset_*）
- **Section D** — `/proc/zoneinfo`（各 zone 的水位状态、free/min/low/high 差异）
- **Section E** — BDI 逐设备回写统计（nr_dirty_this_bf、nr_writeback_this_bf、bdi_dirty_limit 等）
- **Section F** — 内核回写参数（dirty_ratio、dirty_background_ratio、dirty_expire_centisecs 等）
- **Section G** — 回收参数（min_free_kbytes、watermark_scale_factor、vfs_cache_pressure、swappiness）
- **Section H** — kswapd / reclaim CPU 使用率
- **Section I** — D 状态进程及 wchan（`balance_dirty_pages`、`wait_on_page_writeback`、`pageout` 等）
- **Section J** — 内核日志（OOM、allocation failure、blocked task 相关）

执行原则：所有命令超时时间 10s，vmstat 采集需至少 2 次采样（间隔 5s）获得增量趋势。

#### 步骤 3：场景识别与分支决策

根据基线采集结果选择分支：

```
基线信息评估
  │
  ├─ Track-1 脏页指标异常
  │   ├─ nr_dirty >> dirty_limit × 0.7         → 分支A: 脏页回写异常
  │   ├─ nr_writeback 持续 > 0 且无下降趋势    → 分支A + 分支D
  │   └─ D 状态进程卡在 balance_dirty_pages     → 分支A
  │
  ├─ Track-1 回收指标异常
  │   ├─ pgscan_direct 持续 > 0                → 分支B: reclaim 压力
  │   ├─ pgscan_kswapd >> pgscan_direct        → 分支B
  │   ├─ workingset_refault 高速增长            → 分支C: page cache 抖动
  │   ├─ MemFree < min(watermark[low])          → 分支E: min_free_kbytes 不足
  │   └─ slab/SReclaimable 低但 vfs_cache 高     → 分支G: vfs_cache_pressure
  │
  ├─ Track-2 回写事件异常
  │   ├─ BDI writeback > BDI dirty_limit × 0.9  → 分支D: IO 背压
  │   ├─ writeback_delay 高                     → 分支D
  │   └─ BDI wb_throttled 计数高                → 分支D
  │
  ├─ Track-2 mmap 相关
  │   ├─ page_mkwrite 卡顿 / fput writeback 慢  → 分支F: mmap writeback
  │   └─ msync 大量块在等待                     → 分支F
  │
  └─ 混合现象或以上分支无法覆盖                   → 分支H: 混合/复杂故障
```

若基线输出推荐多个分支，需逐个执行并按优先级排序（回写异常 > 回收压力 > 参数误配）。

---

### 阶段二：逐层深入分析

#### 分支A：脏页回写异常

```bash
bash scripts/branch_A_dirty_writeback.sh
```

**分析要点：**

1. **脏页总量与阈值关系**（Section B、C）
   - `Dirty` vs `dirty_ratio` × `MemTotal` → 是否接近或超过阈值
   - `nr_dirty` vs `dirty_background_ratio` → 后台回写是否已触发
   - `dirty_expire_centisecs` → 脏页最长驻留时间（默认 3000cs=30s），若频繁超时说明回写速度跟不上

2. **写回聚合状态**（Section E）
   - `nr_writeback`：当前正在回写的页数
   - `nr_dirty_this_bf`：当前 bdi 的脏页数
   - 各 BDI 的 `bdi_dirty_limit`：每个设备的脏页上限

3. **平衡脏页（balance_dirty_pages）节流**
   - 检查 D 状态进程 wchan 是否为 `balance_dirty_pages`
   - 检查 `/proc/pid/stack` 是否显示 `wb_wait_for_completion` 或 `balance_dirty_pages_ratelimited_flush`
   - 判断节流程度：进程是否大面积进入 D 状态

| 参数 | 默认值 | 过小的影响 | 过大的影响 |
|------|-------|-----------|-----------|
| `dirty_ratio` | 20% | 过早触发全进程同步回写 | 脏页过多 → 回写风暴 |
| `dirty_background_ratio` | 10% | 频繁后台回写 | 脏页堆积 → 业务写阻塞 |
| `dirty_expire_centisecs` | 3000 | 频繁回写短寿脏页 | 脏页长期驻留 → 故障恢复慢 |
| `dirty_writeback_centisecs` | 500 | 回写线程唤醒频繁 | 脏页响应延迟 |

**故障模式判别：**

| 条件 | 诊断结论 |
|------|---------|
| `Dirty > dirty_ratio × MemTotal` 且大量 D 状态进程 | 全局 dirty 限制触发同步回写 |
| `Dirty < dirty_background_ratio × MemTotal` 但 `nr_dirty >> nr_writeback` | 后台回写不足或回写线程卡住 |
| `nr_writeback` 持续 > 0 且 5s 内无下降 | 回写 IO 卡住（见分支D） |
| `dirty_expire_centisecs` 内脏页未回写完 | 回写吞吐低于脏页产生速率 |

---

#### 分支B：kswapd / direct reclaim 高 CPU

```bash
bash scripts/branch_B_reclaim_pressure.sh
```

**分析要点：**

1. **回收来源分布**（Section C）
   - `pgscan_kswapd` vs `pgscan_direct`：哪一方主导回收
   - `pgsteal_kswapd` / `pgsteal_direct`：实际回收页数
   - `pgscan_direct_throttle`：因内存不足直接回收被限流的次数

2. **kswapd CPU 使用率**（Section H）
   - `perf top -p kswapd0` 查看热点
   - 火焰图确认：`shrink_node` / `shrink_lruvec` / `shrink_page_list` 的占比
   - `compact_node` / `compact_zone` 是否占用过高

3. **回收效率**
   - `pgscan / pgsteal` 比值 → 接近 1 为高效率回收，远大于 1 为扫描大量页但回收很少（内存碎片或 page cache 频繁访问）
   - `pgsteal / pgscan` < 0.8 说明回收效率低，存在大量不可回收页
   - `pgrefill` / `pgsteal` 比值 → refill 远大于 steal 说明回收不稳定

4. **回收压力等级判定**

| 指标组合 | 严重程度 | 说明 |
|---------|---------|------|
| `pgscan_direct = 0`，`pgscan_kswapd 少量` | 🟢 正常 | kswapd 后台回收足够 |
| `pgscan_direct 偶发`，`pgscan_kswapd 持续` | 🟡 轻度 | 偶尔直接回收，kswapd 在后台工作 |
| `pgscan_direct 持续 > 0`，`pgscan_kswapd 高` | 🟠 中度 | 分配路径已经进入直接回收 |
| `pgscan_direct_throttle > 0`，`MemFree < watermark[min]` | 🔴 严重 | 直接回收被限流，分配延迟严重 |

---

#### 分支C：Page cache 反复回收抖动

```bash
bash scripts/branch_C_page_cache_thrash.sh
```

**分析要点：**

1. **workingset_refault 检测**（Section C 核心指标）
   - `workingset_refault`：page cache 页被回收后又被重新访问的次数
   - `workingset_activate`：被 refault 后激活的页数
   - `workingset_restore`：被 refault 后恢复的非活跃页
   - 如果 `workingset_refault` 在短时间内大幅增长（>1000/s），说明页面正在剧烈抖动

2. **refault 距离分析**
   - 利用 `file_workset` 和 `workingset_refault` 计算 refault 距离
   - refault 距离 > inactvie_list 大小 → 回收过度
   - refault 距离 < active_list 大小 → 活跃页被错误回收

3. **cache 命中率推断**
   - `pgfault`（缺页中断总数） > `pgmajfault`（主要缺页中断）× 100 → 大部分缺页是 minor fault（cache 命中）
   - `pgmajfault` / `pgfault` > 0.1 → 主要缺页占比高，cache 命中率低
   - `major fault` 频繁意味着每次访问都需要从磁盘读入

| 症状 | refault 增长率 | 诊断 |
|------|---------------|------|
| 应用时延抖动，CPU 空闲 | `workingset_refault` 快速增长 | Page cache 抖动 |
| `pgmajfault`/`pgfault` > 10% | 伴随高 `pswpin` | 物理内存不足 × IO 瓶颈 |
| 释放缓存后立刻故障恢复 | 无 refault | 有其它原因吸收内存 |

---

#### 分支D：慢设备拖垮回写（IO 背压）

```bash
bash scripts/branch_D_wb_io_backpressure.sh [device]
```

**分析要点：**

1. **BDI 逐设备回写统计**（Section E）
   - `nr_dirty_this_bf`：该 BDI 上的脏页数，若远高于其它 BDI → 该设备上脏页堆积
   - `nr_writeback_this_bf`：正在回写的页数，若持续 > 0 且不下降 → 回写卡住
   - `bdi_dirty_limit`：该 BDI 的 dirty 上限，是否已被占满
   - `wb_throttled` 计数：进程在该 BDI 上被限流的次数

2. **单设备 IO 性能**
   - 检查 BDI 对应块设备的 IO 性能（iostat -x）
   - %util 是否为 100%、await 是否 > 50ms、是否有多设备但仅某个慢
   - `/sys/block/*/inflight` 是否有大量 IO 未完成

3. **全局 vs 局部 dirty 限流**
   - 如果 `nr_dirty` < `dirty_background_ratio` 但 `nr_dirty_this_bf` 远高于 `bdi_dirty_limit` → 单设备背压
   - 如果 `nr_dirty` > `dirty_ratio` → 全局限流

**故障模式：**

| 现象 | 诊断 |
|------|------|
| `BDEV-A` 的 `nr_dirty_this_bf` >> `bdi_dirty_limit` | 慢设备 IO 背压导致全局 dirty 节流 |
| `wb_throttled` 频繁触发 | BDI 限流生效，回写被限速 |
| `Dirty` 总量不高但单设备 `nr_dirty_this_bf` 高 | 脏页集中在某慢设备 |
| 单设备 %util=100% + await>100ms + 写回慢 | 设备层瓶颈拖累上层回写 |

---

#### 分支E：min_free_kbytes 不足

```bash
bash scripts/branch_E_min_free_kbytes.sh
```

**分析要点：**

1. **水位状态**（Section D）
   - `zoneinfo` 中每个 zone 的 `free < min` → 进入直接回收
   - `free < low` → kswapd 将被唤醒
   - `free < high` → kswapd 会持续回收直到高于 high
   - 计算 `watermark[min] / pageblock_order` → 是否满足原子分配需求

2. **min_free_kbytes 合理性评估**
   - 公式：`min_free_kbytes_建议 = sqrt(MemTotal_kB) * 4`（内核经典估算）
   - 或 `建议水位 = 最大页面块(2^max_order) × pageblock_order 数`，确保原子分配总有余量
   - 对于大内存机器（>64GB），默认 min_free_kbytes（约 0.05%）可能不够

3. **页面分配失败（allocation failure）**
   - dmesg 检查 `page allocation failure`、`order:` 字段
   - 检查 `DMA/ DMA32/ Normal` 哪个 zone 不足
   - 如果 `allocation failure` 的 order 较大（>3）可能是碎片而非水位问题

| 现象 | 诊断 |
|------|------|
| `pgscan_direct > 0` + `MemFree ≈ watermark[min]` | 水位过低触发直接回收 |
| `allocation failure` at order > 3 | 可能是内存碎片 + 水位低 |
| `allocation failure` at order 0 | 物理内存严重不足，水位已失守 |

---

#### 分支F：mmap writeback 停顿

```bash
bash scripts/branch_F_mmap_writeback.sh
```

**分析要点：**

1. **D 状态进程检测**（Section I）
   - 查找 wchan 为 `page_mkwrite`、`fput->writeback`、`msync`、`munmap` 的 D 状态进程
   - 检查 `/proc/pid/stack` 确认回写路径
   - 多个进程同时在 `wait_on_page_writeback` 上等待

2. **文件映射脏页判断**
   - `pmap -x pid` 查看进程内存映射中 Dirty RSS
   - 检查 `/proc/pid/smaps` 中的匿名 vs 文件映射页统计
   - 大比例 Dirty RSS 来自文件映射 → 触发 mmap writeback 时造成停顿

3. **msync / munmap 卡顿**
   - 检查 `msync` 是否主动刷出大量 dirty page
   - `fput` 关闭 fd 时触发 writeback writeback
   - `page_mkwrite` 等待 IO 完成

| 场景 | 症状 | 诊断 |
|------|------|------|
| DB 类 mmap 应用 | 突发的 msync 延迟 | 大量脏页在 unmap 时刷出 |
| 文件 IO + mmap 混合 | 写 D 状态在 `page_mkwrite` | 页冲突（回写中再次写） |
| 大文件映射 | 关闭 fd 时进程卡顿 | `fput` 触发 writeback |

---

#### 分支G：vfs_cache_pressure 误配

```bash
bash scripts/branch_G_vfs_cache_pressure.sh
```

**分析要点：**

1. **Slab 回收状态**（Section B）
   - `SReclaimable` vs `SUnreclaim`：可回收 slab 量
   - `Dentry` / `Inode` / `dentry_cache` 占用（`/proc/slabinfo`）
   - 若 `vfs_cache_pressure = 0`：slab 完全不回收，可能导致 dentry/inode 缓存膨胀

2. **回收效果评估**
   - 执行 `slabtop -s c` 查看 dentry/inode 占用
   - 检查 `nr_dentry` / `nr_inode` 数量（`/proc/sys/fs/` 文件）
   - 如果 `SReclaimable` > 50% MemTotal 且 `vfs_cache_pressure` 低 → 缓存膨胀
   - 如果 `SReclaimable` < 5% MemTotal 但 `vfs_cache_pressure` > 200 → 回收过度

| vfs_cache_pressure 值 | 效果 |
|----------------------|------|
| 0 | 永远不回收 dentry/inode → slab 只增不减 |
| 100（默认） | 平衡回收 |
| 200 | 2 倍默认回收力度 → slab 可能过低 |
| 10000 | 极端激进回收 → 反复构造 dentry → CPU 飙升 |

---

### 阶段三：交叉验证与结论收敛

对 Track-1（现场指标）和 Track-2（事件语义）做对齐检查：

| 验证维度 | Track-1 现场指标 | Track-2 事件语义 | 是否吻合？ |
|---------|----------------|-----------------|-----------|
| 脏页回写阻塞 | Dirty > dirty_limit, nr_writeback 高 | balance_dirty_pages wait 计数 | □ 吻合 □ 不符 |
| 回收压力高 | pgscan_direct >> pgscan_kswapd, direct_throttle > 0 | vmscan direct_reclaim_start/end 大量事件 | □ 吻合 □ 不符 |
| Page cache 抖动 | workingset_refault 增长 > 1000/s | refault_distance > inactive_list | □ 吻合 □ 不符 |
| IO 背压 | 某 BDI nr_dirty_this_bf >> bdi_dirty_limit | wb_throttled 计数高 | □ 吻合 □ 不符 |
| 水位不足 | MemFree < watermark[min] | allocation failure 日志 | □ 吻合 □ 不符 |

**置信度收敛：**
- **高**：Track-1 + Track-2 完全吻合 + 反事实验证通过
- **中**：一条轨道完全吻合，另一条依赖推断
- **低**：两条轨道均依赖推断
- **待定**：用户态证据链完整但无法定位具体内核路径

---

### 阶段四：输出诊断报告

```markdown
# 页缓存/脏页回写/内存回收诊断报告

## 基本信息
- 诊断时间：
- 故障时间窗口：
- 故障现象描述：
- 严重级别：（P0/P1/P2/P3）

## 问题确认
**故障现象**：

**影响范围**：

**复现方式**：

## 双轨分析结论

### Track-1 现场指标分析
- /proc/meminfo 异常指标：
- /proc/vmstat 增量趋势：
- zoneinfo 水位状态：
- BDI 逐设备回写统计：

### Track-2 内核回收语义分析
- kswapd/direct reclaim 事件：
- 回写生命周期事件：
- refault 距离 / page cache 抖动：
- 内核日志关键条目：

## 根因定位
**根因描述**：

**置信度**：[高/中/低]

## 故障因果链
```
[根因] → [传播路径] → [用户可见症状]
```

## 排除的替代假设
- <假设X>：排除原因

## 修复建议
### 临时措施
1. <措施> — 风险等级：[高/中/低]

### 永久措施
1. <措施> — 风险等级：[高/中/低]

### 验证方法
- <验证方法>
```

---

## 故障模式速查表

| 故障模式 | 主要表现 | Track-1 指标 | Track-2 事件 | 关键参数 |
|---------|---------|-------------|-------------|---------|
| 脏页回写异常 | 写延迟飚高、D 状态在 balance_dirty_pages | Dirty > dirty_ratio, nr_writeback 持续 | balance_dirty_pages wait | dirty_ratio, dirty_background_ratio |
| kswapd 高 CPU | cpu si/sy 高、kswapd 占满核 | pgscan_kswapd 高、pgsteal/pgscan < 0.8 | mm_vmscan_kswapd_wake 频繁 | min_free_kbytes, watermark_scale_factor |
| page cache 抖动 | 时延抖动、IO 大量读 | workingset_refault 暴涨、pgmajfault 高 | refault_distance > inactive | vfs_cache_pressure, swappiness |
| IO 背压 | 单盘回写慢 | BDI nr_dirty_this_bf >> bdi_dirty_limit | wb_throttled, writeback_delay | BDI 限流参数 |
| min_free_kbytes 不足 | allocation failure | MemFree ≈ min, pgscan_direct 主导 | direct reclaim throttle | min_free_kbytes, watermark_scale_factor |
| mmap writeback | msync/munmap 卡顿 | Dirty RSS 来自文件映射高 | page_mkwrite, fput writeback | dirty_ratio, 文件系统选项 |
| vfs_cache_pressure 误配 | slab 过高或过低 | SReclaimable 异常偏高/低, dentry 多 | dentry/inode 生命周期短 | vfs_cache_pressure |
