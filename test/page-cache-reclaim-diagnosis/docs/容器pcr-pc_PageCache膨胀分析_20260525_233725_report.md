# 🔴 故障诊断报告：容器 pcr-pc Page Cache 过度膨胀分析

> **报告编号**：RCA-20260525-001
> **故障级别**：P2（中等风险）
> **报告时间**：2026-05-25 23:37:25 UTC
> **当前状态**：🟡 观察中（当前无内存压力，但存在多处隐患）

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | 容器 pcr-pc Page Cache 过度膨胀至 8.7GB（54.6% MemTotal），99% 为冷缓存 |
| 影响范围 | 容器 pcr-pc（Docker 容器，运行于 WSL2 VM），宿主机可能因无 cgroup 限制受影响 |
| 故障时段 | 2026-05-25 15:13 UTC（容器启动）～ 持续观察中 |
| 根本原因 | **三个大文件（4GB+2GB+2GB）被顺序读取触发内核 Page Cache 填充，同时容器无 cgroup 内存限制，且 vfs_cache_pressure=100（默认值）未主动回收冷缓存** |
| 是否恢复 | ✅ 当前已部分恢复（Cached 从 8.7GB 回落至 5.9GB），但根本原因未消除 |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|----------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | fincore 确认 3 个大文件占缓存 98%，Active/Inactive=1:100，PSI=0 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线与故障传导链路

```text
时间（UTC）               事件                                                      性质          溯源路径
──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-05-25 ~15:13        容器 pcr-pc 启动（PID 1: sleep 3600）                          🟢 启动       [T1: 6.容器基本状态]
    │
    ▼
2026-05-25 ~(未知)       测试文件创建：/tmp/pagecache_test (4GB) / pc2 (2GB) / pc3 (2GB)   📝 操作触发   [T1: 4.1 大文件缓存占用]
    │                     并被顺序读取
    ▼
2026-05-25 ~(未知)       Page Cache 膨胀至峰值 8.7GB（Cached/MemTotal=54.6%）              🔴 指标告警   [用户原始报告]
    │                     内核将文件页缓存至 Page Cache
    │                     Inactive(file) 占比 99%+（一次读取后从未再访问）
    ▼
2026-05-25 ~(未知)       fault_reclaim_s 进程两次被宿主机 OOM killer 杀死                  🔴 宿主机OOM  [T3: 3.2 宿主机 OOM 事件]
    │                     虚拟地址空间 6.25TB，页表开销 6.1GB（异常！）
    │                     间隔约 5 分钟，可能反复拉起
    │                     （此事件与 Page Cache 膨胀的关联性待确认）
    ▼
2026-05-25 23:37         Kuafu 诊断执行：
                           - Cached 回落至 5.9GB（36.9% MemTotal）
                           - PSI 所有窗口 = 0.00
                           - mem.pressure = 0
                           - kswapd 水线触发仅 22/4 次（历史累计）
                           - Memory.current = 5.66GB（97.3% 为 Page Cache）                 🟡 观察中     [T1/T2/T3]
                           - 无 cgroup OOM 事件
                           - 无内存压力
```

### 故障因果链

```text
外部操作：三个大文件被顺序读取（/tmp/pagecache_test 4GB + pc2 2GB + pc3 2GB）
    │
    ├─► 内核 Page Cache 填充机制自动缓存文件页面
    │       │
    │       ├─► Cached 峰值达 8.7GB（占 MemTotal 54.6%）
    │       │       │
    │       │       ├─► fincore 确认 3 文件占缓存 98%（~5.5GB / 5.9GB）
    │       │       │
    │       │       └─► Active(file)=58MB / Inactive(file)=5,847MB（1:100）
    │       │               └─► 全部为冷缓存，缺乏 locality
    │       │
    │       └─► 容器无 cgroup 内存限制（memory.max = max）
    │               └─► Page Cache 无上限约束，可无限增长至宿主机内存耗尽
    │
    ├─► 内核回收机制未主动介入
    │       │
    │       ├─► vfs_cache_pressure=100（默认值）→ 对 dentry/inode 无偏向回收
    │       ├─► swappiness=60（默认值）→ Page Cache 与匿名页回收优先级相当
    │       └─► MemAvailable=14.4GB → 内核判定无回收必要
    │
    └─► 宿主机 OOM（fault_reclaim_s 进程）[需进一步调查]
            │
            ├─► 虚拟内存 6.25TB，RSS 8.4GB
            ├─► 页表开销异常 6.1GB（正常应为 ~8MB）
            └─► 与 Page Cache 膨胀可能独立，但共享同一宿主机内存资源
```

---

## 三、排查过程

### 3.1 初始现象

- **用户报告指标**：Cached = 8,726,280 kB（8.3GB，54.6% of MemTotal）
- **容器状态**：pcr-pc，PID 1 为 `sleep 3600`（空闲容器），System Load = 0.01
- **影响**：Page Cache 占比超过 MemTotal 一半，引发对内存压力和 OOM 风险的担忧

---

### 3.2 假设驱动排查

#### 假设 D1：大文件读取导致 Page Cache 增长 ✅ 确认根因

> 🧪 **假设**：容器内 `/tmp/` 下的大文件被顺序读取，触发了内核的 Page Cache 填充机制，导致缓存膨胀

| 检查项 | 操作（基于真实诊断数据） | 结论 |
|--------|------------------------|------|
| Page Cache 总量确认 | `cat /proc/meminfo` → Cached=5,906,152 kB（诊断时值） | ✅ 确认 Cached 占 MemTotal 36.9%（峰值 54.6%） |
| 大文件缓存定位 | `fincore` 扫描 `/tmp/pagecache_test`(4GB)、`pc2`(2GB)、`pc3`(2GB) | ✅ 3 文件缓存合计 ~5.5GB，占当前 Cached 的 **98%** |
| 页面冷热状态 | Active(file)=58,356 kB / Inactive(file)=5,847,208 kB，比值 **1:100** | ✅ 99%+ 为冷缓存，仅被读取一次未被再次访问 |
| 幽灵文件检测 | `lsof +L1` 检查已删除但被 fd 持有的文件 | ✅ 无输出，不存在 deleted-but-open 问题 |
| Shmem 异常检测 | Shmem=2,700 kB（仅 2.6MB） | ✅ 排除共享内存占用问题 |

**✅ 结论：三个测试文件的读取行为直接导致 Page Cache 膨胀。fincore 证实 98% 的缓存被这 3 个文件占据，属于典型的大文件顺序读取缓存场景。**

---

#### 假设 D2：vfs_cache_pressure 设置过小导致缓存不回收 ❌ 排除

> 🧪 **假设**：`vm.vfs_cache_pressure` 值偏低导致内核不愿意回收 dentry/inode 缓存

| 检查项 | 操作（基于真实诊断数据） | 结论 |
|--------|------------------------|------|
| 当前值确认 | `sysctl vm.vfs_cache_pressure` → **100**（默认值） | ✅ 为系统默认值，无异常调优 |
| dentry 缓存量 | dentry slab = 34,146 obj × 192B = ~6.4 MB | ✅ 极低，无膨胀 |
| ext4_inode 缓存量 | ext4_inode_cache = 3,309 obj × 1168B = ~3.7 MB | ✅ 极低，无膨胀 |
| Slab 总占比 | Slab/MemTotal = 304MB / 15.99GB = **1.90%** | ✅ 无异常 |

**❌ 排除：vfs_cache_pressure=100 为默认值，且 dentry/inode 用量极低，不存在因该参数导致缓存不回收的问题。该假设不能解释 Page Cache 膨胀现象。**

---

#### 假设 D3：shmem/tmpfs 过度使用导致内存占用 ❌ 排除

> 🧪 **假设**：共享内存（shmem）或 tmpfs 文件系统过度使用导致内存占用

| 检查项 | 操作（基于真实诊断数据） | 结论 |
|--------|------------------------|------|
| Shmem 值确认 | `/proc/meminfo` → Shmem=2,700 kB（~2.6MB） | ✅ 极小，忽略不计 |
| tmpfs 挂载检查 | `df -h` → tmpfs 64M, shm 64M 均未使用 | ✅ 无 tmpfs 溢出 |
| cgroup file_mapped | cgroup memory.stat → file_mapped=32,768 bytes | ✅ 映射文件页极少 |

**❌ 排除：Shmem 仅 2.6MB，tmpfs 挂载点无使用，共享内存和 tmpfs 对内存占用几乎无贡献。**

---

#### 假设 D4：应用 mmap 映射未释放导致缓存残留 ❌ 排除

> 🧪 **假设**：应用程序通过 `mmap()` 映射大文件后未 `munmap()`，导致缓存页面被锁定

| 检查项 | 操作（基于真实诊断数据） | 结论 |
|--------|------------------------|------|
| Mapped 值确认 | `/proc/meminfo` → Mapped=128,772 kB（~126MB） | ✅ 仅 126MB，远小于 5.9GB |
| 进程 RSS 检查 | `ps aux` → PID 1 仅 RSS=1,536 kB | ✅ 唯一进程几乎无内存占用 |
| 幽灵文件检测 | `lsof +L1` → 无输出 | ✅ 无进程持有已删除文件的映射 |

**❌ 排除：Mapped 内存仅 126MB，容器内仅运行 `sleep 3600`，不存在 mmap 未释放的情况。Page Cache 的增长来源是常规文件读取（read() 系统调用），而非 mmap 映射。**

---

#### 假设 D5：内核回收行为异常导致 Page Cache 未被正常回收 ❌ 排除

> 🧪 **假设**：内核 LRU 回收机制异常或内存碎片导致无法有效回收 Page Cache

| 检查项 | 操作（基于真实诊断数据） | 结论 |
|--------|------------------------|------|
| PSI 压力检查 | PSI some/full avg10/60/300 = **0.00** | ✅ 当前无任何内存压力感知 |
| kswapd 水线触发 | kswapd_high_wmark_hit_quickly=22, low=4（历史累计） | ✅ 极低触发频率 |
| 直接回收历史 | pgscan_direct=2,445,150 / pgsteal_direct=349,083（效率14.3%） | ✅ 历史存在轻度直接回收，但当前无活动 |
| 文件页回收效率 | pgscan_file=532,215 / pgsteal_file=310,295（效率**58.3%**） | ✅ 文件页回收效率良好 |
| cgroup memory.pressure | some avg10=0.00, full avg10=0.00 | ✅ Cgroup 级也无压力 |
| MemAvailable | MemAvailable=15,062,352 kB（**94.2%** 可用） | ✅ 系统判定内存充裕 |
| 内存压缩活动 | compact_migrate_scanned=21.6亿 | ⚠️ 碎片整理活动频繁但非阻塞 |

**❌ 排除：内核回收行为正常。PSI=0、MemAvailable=14.4GB 表明内核认为当前无需回收 Page Cache。历史上文件页回收效率 58.3% 表现良好。检查到的内存压缩扫描频繁（21亿+）值得关注，但未导致实际回收阻滞。内核没有"错误地"保留 Page Cache，而是根据 LRU 算法和可用内存水位线的正常行为。**

---

### 3.3 排查结论与逻辑树

```text
Page Cache 膨胀至 8.7GB (54.6% MemTotal)
│
├─► D1：大文件读取导致缓存增长 → ✅ 确认（fincore 确证 3 文件占 98%）
│     └─► /tmp/pagecache_test (4GB) + pc2 (2GB) + pc3 (2GB)
│           └─► 顺序 read() → 内核 Page Cache 自动填充
│                 └─► Inactive(file) 占 99%+ → 仅读一次，未被再次访问
│
├─► D2：vfs_cache_pressure 太小 → ❌ 排除（v=100 默认值，dentry/inode 极少）
├─► D3：shmem/tmpfs 过度使用 → ❌ 排除（shmem=2.6MB，tmpfs 未使用）
├─► D4：mmap 映射未释放 → ❌ 排除（Mapped=126MB，仅 sleep 进程）
│
└─► D5：内核回收行为异常 → ❌ 排除（PSI=0，文件页回收效率 58.3%）
      │
      ├─► 但发现了间接风险：
      │     ├─► 容器无 cgroup memory 限制（memory.max = max）
      │     ├─► 宿主机 fault_reclaim_s 进程 2 次 OOM（页表 6.1GB 异常）
      │     └─► compact_migrate_scanned 极高（21亿+）
      │
      └─► 🎯 **根本原因：三个大文件的读取操作 + 未设置 cgroup 内存限制**
```

---

## 四、排除假设汇总

| 假设编号 | 假设内容 | 排除状态 | 排除依据 |
|---------|---------|---------|---------|
| D1 | 大文件读取导致 Page Cache 增长 | ✅ **确认为根因** | fincore 确证 3 文件占缓存 98%，峰值 8.7GB |
| D2 | vfs_cache_pressure 设置过小 | ❌ 排除 | 默认值 100，dentry/inode 用量极低 |
| D3 | shmem/tmpfs 过度使用 | ❌ 排除 | Shmem=2.6MB，tmpfs 未使用 |
| D4 | 应用 mmap 映射未释放 | ❌ 排除 | Mapped=126MB，容器仅运行 sleep |
| D5 | 内核回收行为异常 | ❌ 排除 | PSI=0，MemAvailable=14.4GB，文件页回收效率 58.3% |

---

## 五、风险等级与置信度评估

### 风险矩阵

| 风险维度 | 评分 | 说明 |
|---------|------|------|
| Page Cache 膨胀 | 🟡 中 | 当前回落至 5.9GB（36.9%），但无限制保护 |
| cgroup 内存限制缺失 | 🔴 **高** | memory.max = max，容器可耗尽宿主机全部内存 |
| 宿主机 OOM 历史 | 🔴 **高** | fault_reclaim_s 两次被 OOM killer 杀死，页表异常 |
| 当前内存压力 | 🟢 低 | PSI=0，MemAvailable=14.4GB（94.2%） |
| 回收效率 | 🟢 低 | 文件页回收效率 58.3%，Inactive(file) 随时可回收 |
| Slab 膨胀 | 🟢 低 | Slab/MemTotal=1.90%，dentry/inode 无膨胀 |
| Swap 风险 | 🟢 低 | Swap 使用 207MB（4.9%），swap.current=0 |
| 内存碎片化 | 🟡 中 | compact_migrate_scanned=21.6亿，碎片整理活跃 |
| **综合风险** | **🟡 P2（中等风险）** | 当前无紧迫压力，但无限制保护和宿主机 OOM 历史构成潜在威胁 |

### 根因置信度评估

| 根因候选 | 支持证据（正向） | 反对证据（反向） | 置信度 |
|---------|---------------|---------------|--------|
| **D1：大文件读取 → Page Cache 膨胀** | fincore 确证 98% 缓存来自 3 文件；Active/Inactive=1:100（冷缓存）；PSI=0 排除回收异常 | Cached 已从 8.7GB 回落至 5.9GB，说明部分缓存已被回收 | 🟢 **高置信** |
| **cgroup 无限制** | memory.max=max, HostConfig.Memory=0；cgroup OOM 为 0 但这是双刃剑 | 当前 MemAvailable 充裕，限制缺失未直接导致故障 | 🟢 **高置信**（是独立风险因素） |

---

## 六、修复方案

### 6.1 应急处置（可选）

| 步骤 | 操作 | 执行人 | 预期效果 |
|------|------|--------|---------|
| 1 | `rm /tmp/pagecache_test /tmp/pc2 /tmp/pc3` 删除测试文件 | 系统管理员 | 内核自动回收对应的 Page Cache |
| 2 | 确认文件创建来源 | 系统管理员 | 防止文件被重复创建和缓存 |

### 6.2 永久修复计划

| 优先级 | 修复措施 | 说明 | 执行人 |
|--------|---------|------|--------|
| **P0** | **为容器设置 cgroup 内存限制** | `docker update --memory=<合理上限> pcr-pc`，建议根据业务实际需求设置（如 8GB~12GB），防止 Page Cache 无限制增长 | 系统管理员 |
| **P0** | **排查 `fault_reclaim_s` 进程异常** | 该进程虚拟内存 6.25TB，页表 6.1GB 极不正常，可能为测试进程或存在内存泄漏/映射异常。分析其源代码或启动参数 | SRE/开发团队 |
| **P1** | **设置 Memory Reservation（软限制）** | `--memory-reservation=<值>` 确保宿主机内存紧张时优先回收此容器的 Page Cache | 系统管理员 |
| **P1** | **确认测试文件的业务归属** | 排查 `/tmp/pagecache_test`、`pc2`、`pc3` 的创建源（应用、测试脚本、或恶意行为） | 系统管理员 |
| **P2** | **监控 Page Cache 趋势** | 设置告警：当 Cached/MemTotal > 50% 时告警，监控 Inactive(file) 占比变化 | 监控团队 |
| **P2** | **监控 `fault_reclaim_s` 进程状态** | 确保该进程不再触发 OOM，若为测试进程应清理或限制其内存 | 监控团队 |
| **P3** | **使用 cgroup memory.current 替换 docker stats 监控** | docker stats 显示的 171.7MB 与实际 5.66GB 差异巨大，应改用 cgroup memory.current 获取真实内存占用 | 监控团队 |

### 6.3 可选调优（非紧急）

以下调优参数在当前状态下**非必需**，但可作为预防性优化：

| 参数 | 当前值 | 建议值 | 说明 |
|------|--------|--------|------|
| `vm.swappiness` | 60 | 30 | 降低内核倾向回收匿名页的权重，在内存紧张时更优先回收 Page Cache |
| `vm.vfs_cache_pressure` | 100 | 200 | 在 dentry/inode 缓存高时偏向回收，当前场景需求不高 |
| cgroup memory.max | max | 根据业务设定 | **最关键的防护措施** |

---

*报告由 witty-diagnosis-agent / Baize (Phase 1.4) 自动生成*
*数据来源：Kuafu T1 (pagecache_growth), T2 (reclaim_pressure), T3 (cgroup_memory)*
*生成时间：2026-05-25 23:37:25 UTC*
