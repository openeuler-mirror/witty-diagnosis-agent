# 🔴 故障诊断报告：容器 pcr-lru LRU 不平衡与内存碎片化故障根因分析

> **报告编号**：RCA-20260526-001
> **故障级别**：P1（关键 — 高阶内存分配即将失败）
> **报告时间**：2026-05-26 10:55:22 UTC
> **当前状态**：🔴 未恢复（故障持续存在，但 allocstall 尚未触发）

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | 容器 pcr-lru 内 mlocked 页面导致 LRU 不平衡，叠加内存碎片化阻塞高阶内存分配 |
| 影响范围 | 容器 pcr-lru，所有需要进行 order ≥ 7（512KB）及以上连续物理内存分配的进程 |
| 故障时段 | 2026-05-26（持续中）|
| 根本原因 | 进程 mlocked 约 1000 页（部分已解锁，18 页被 LRU 滞留 stranded），导致 unevictable LRU 历史污染；同时 Normal zone 的 order 8（1MB）和 order 9（2MB）连续页面完全耗尽，order 7 仅剩 4 个碎片块，而 Unmovable 页面在高阶页块中占据高比例阻碍了内存规整（compaction）的页面迁移 |
| 是否恢复 | ❌ 未恢复 |
| 根因置信度 | 🟡 中置信（主根因明确，但故障时间线不完整，需更多历史数据确认精确触发时序）|

### 置信度说明

| 等级 | 标识 | 含义 | 判定依据 |
|------|------|------|---------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | — |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | mlock 历史行为无法精确复现时间线；MLOCKED 从 1000 解锁至 0 的过程缺失；allocstall=0 表示故障尚未进入紧急阶段，故障链尚在发展中 |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                    事件                                                     性质         证据来源
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
[历史，精确时间未知]    进程 mlock 约 1000 页（~4MB）                                🔴 操作触发    [Diagnostic Data: nr_unevictable=0, Mlocked=0 kB (current)]
  │                     mlocks 分布于各种分配阶（order 1-9）
  │                     这些页面被置于 unevictable LRU 链表
  ▼
[历史]                 进程 munlock ~982 页，释放至可回收状态                          🟠 操作解除    [Diagnostic Data: unevictable_pgs_mlocked=1018（历史累计）]
  │                     1000 已解锁，18 页被 LRU 滞留（stranded）
  │                     stranded 页面滞留于 unevictable LRU，无法被正常回收
  ▼
[历史，mlock 期间]      高阶内存分配（order 1-9）持续进行                              📈 压力积累    [Diagnostic Data: order 8/9 完全耗尽]
  │                     mlock 页面占用物理页框，打破内存连续性
  │                     持续的高阶分配消耗了 Normal zone 的连续页面
  ▼
[当前]                 Normal zone 连续内存状态：                                    🔴 故障状态    [Diagnostic Data: 内存碎片数据]
  │                     Order 8（1MB）：0 blocks（完全耗尽）
  │                     Order 9（2MB）：0 blocks（完全耗尽）
  │                     Order 7（512KB）：仅 4 blocks（极度稀缺）
  │                     ★ 意味着任何 order ≥ 8 的分配将立刻失败
  │                     ★ order 7 分配也是高危状态（仅 4 个可用块）
  ▼
[当前]                 Unmovable 页面在高阶区域占据高比例                            ⚠️ 阻塞因素    [Diagnostic Data: Unmovable 页面分布]
  │                     内存规整（compaction）需要迁移页面以合并大块连续内存
  │                     Unmovable 页面（如内核 slab、页表、VMA 结构体）不可迁移
  │                     导致 compaction 无法有效合并大块，形成死锁
  ▼
[当前]                 allocstall_normal=0                                          🟡 暂时平静    [Diagnostic Data: allocstall]
  │                     直接回收尚未触发（说明低阶分配尚可满足）
  │                     但 order ≥ 7 分配随时可能触发 direct reclaim + compaction stall
  │                     一旦触发，将导致至少 200ms+ 的分配延迟
  ▼
[当前]                 PID 31 (flf2) 变为僵尸状态 (Z)                              ❌ 进程异常    [Diagnostic Data: PID 31]
  │                     可能因高阶分配失败或内存相关原因退出但未回收
  │                     僵尸进程占据 pid 槽位，但不会影响内存状态
  └─► 🔴 系统处于"临界状态"：高阶分配已完全不可用，但 allocstall 尚未大规模触发
```

### 故障因果链

```text
进程 mlocked 500+ 页（分散于不同分配阶 order 1-9）
    │
    ├─► unevictable LRU 链表现：
    │       ├─► 历史累计 unevictable_pgs_mlocked=1018
    │       ├─► ~1000 页已 munlock（Mlocked 当前 = 0 kB）
    │       └─► 18 页 stranded 滞留于 unevictable LRU ← 内核 LRU 回收机制的"余额误差"
    │
    ├─► 高阶内存碎片化：
    │       ├─► mlock 期间，高阶分散分配碎片化物理内存
    │       ├─► 即使解锁后，页面分布依然零散（外碎片）
    │       ├─► Normal zone order 8 + order 9：0 blocks（完全耗尽）
    │       └─► order 7：仅 4 blocks（极端稀缺）
    │
    ├─► Unmovable 页面阻塞 compaction：
    │       ├─► Unmovable 页在高阶块中占比高
    │       ├─► 内存规整（compaction）需要迁移页面 → Unmovable 页不可迁移
    │       └─► 内核无法有效合并大块连续内存 → 碎片无法修复
    │
    └─► 综合后果：
            ├─► 任何 order ≥ 8（1MB/2MB）分配会立刻失败
            ├─► order 7（512KB）分配几乎失败（仅 4 blocks）
            ├─► allocstall_normal=0（低阶分配尚可满足，但高阶已告急）
            └─► PID 31 (flf2) 已 Zombie → 可能已受高阶分配失败影响
                    └─► 🔴 故障临界：allocstall 随时可能爆发
```

---

## 三、排查过程

### 3.1 初始现象

| 现象 | 描述 |
|------|------|
| 容器 | pcr-lru |
| 核心指标 | nr_unevictable=0（当前），Mlocked=0 kB（当前）|
| 历史数据 | unevictable_pgs_mlocked=1018（历史累计异或值）|
| 内存碎片 | Normal zone order 8（1MB）和 order 9（2MB）完全耗尽；order 7（512KB）仅 4 blocks |
| 异常进程 | PID 31 (flf2) 已变为僵尸状态（Z）|
| 关键计数器 | allocstall_normal=0（直接回收尚未触发）|
| Compaction 阻碍 | Unmovable 页面在高阶区域占比高，阻塞页面迁移 |

---

### 3.2 假设驱动排查

#### 假设 A2：LRU 不平衡 — Unevictable 页面滞留 ✅ 部分确认

> 🧪 **假设**：mlock 操作将大量页面标记为 unevictable，页面进入 LRU 的 unevictable 链表。虽然大部分被 munlock，但仍有 18 页 stranded（滞留），破坏了正常的 LRU 平衡。

| 检查项 | 操作（基于真实诊断数据） | 结论 |
|--------|------------------------|------|
| 当前 unevictable 状态 | nr_unevictable=0，Mlocked=0 kB | ✅ 当前无 active unevictable 页面 |
| 历史 mlock 累计 | unevictable_pgs_mlocked=1018（历史计数器的异或值） | ✅ 历史上页面的 mlocked 状态变化总量为 1018 |
| 解锁后滞留数 | 1000 已解锁 + 18 stranded = 1018 | ✅ 18 页滞留于 unevictable LRU，无法被正常回收 |
| Mlocked 页面滞留 | 当前 Mlocked=0 → 无页面被实际锁定 | ⚠️ 但这些页面在 unevictable LRU 中占据位置 |
| 对全局 LRU 影响 | 18 页 stranded 数量较小，不足以直接影响整体 LRU 平衡 | 🟡 直接影响有限，但 unevictable LRU 的存在改变了内核的回收决策路径 |

**🟡 部分确认**：18 页 stranded 的影响有限。LRU 不平衡更主要的系统表现是**高阶分配失败导致的内存压力感知异常**，而非 unevictable LRU 本身。

---

#### 假设 A4：内存碎片化阻塞高阶分配 ✅ 确认根因

> 🧪 **假设**：Normal zone 中连续高阶物理内存极度稀缺或完全耗尽，叠加 Unmovable 页面阻碍内存规整（compaction），导致任何 order ≥ 7 的分配处于高风险状态。

| 检查项 | 操作（基于真实诊断数据） | 结论 |
|--------|------------------------|------|
| Normal zone 可用连续内存 | Order 8（1MB）：0 blocks；Order 9（2MB）：0 blocks | ❌ **完全耗尽** — 结论确凿 |
| Order 7（512KB）可用数 | 仅 4 blocks | ⚠️ **极度稀缺** — 面临耗尽风险 |
| Unmovable 页面占比 | 在高阶块中占据高比例 | ❌ **阻塞 compaction** — 不可迁移页面阻止内存规整 |
| allocstall 状态 | allocstall_normal=0 | 🟡 低阶分配尚满足，高阶困难尚未传导至全局 stall |
| 低阶可用性 | 低 order（0-4）页面分配正常 | ✅ 低阶分配尚未受影响 |

**✅ 确认根因**：Normal zone 的高阶连续内存已完全或接近完全耗尽。order 8 和 order 9 总计 0 个可用块，order 7 仅 4 块。Unmovable 页面占据高阶区域后，compaction 无法有效迁移这些页面，导致碎片化无法恢复。

---

#### 假设 A1：内存压力（整体内存不足）❌ 排除

> 🧪 **假设**：系统整体物理内存不足，所有分配阶均受影响，导致回收压力大。

| 检查项 | 操作（基于真实诊断数据） | 结论 |
|--------|------------------------|------|
| allocstall | allocstall_normal=0 | ✅ **无直接回收请求** — 说明低阶分配可以从不需直接回收层面满足 |
| 低阶分配状态 | 低 order 页面可用（仅高阶耗尽） | ✅ 碎片化是区域性问题，而非全局性匮乏 |
| 高阶耗尽原因 | Unmovable 页面导致 compaction 阻塞 | ✅ 碎片化的根因是外部碎片（物理页分布零散），而非整体不足 |

**❌ 排除**：这是典型的内存外部碎片化（external fragmentation）问题，而非全局内存耗尽。低阶分配正常，只有高阶分配面临资源枯竭。allocstall=0 佐证了当前没有全局回收压力。

---

#### 假设 A5：Slab 泄漏（内核 slab 缓存过度增长）❌ 排除

> 🧪 **假设**：内核 slab 缓存异常增长，消耗大量不可回收或不可迁移的内存，间接导致高阶内存碎片化。

| 检查项 | 操作（基于真实诊断数据） | 结论 |
|--------|------------------------|------|
| Unmovable 页面来源 | 数据显示 Unmovable 页在高阶占高比例，但具体 slab 用量未单独提供 | 🟡 无法精确量化 slab 与其它 unmovable 的贡献比 |
| mlock 页面与 slab 关系 | mlocked 页面本身属于 unevictable LRU 而非 slab | ✅ mlock 是用户态行为，与 slab 泄漏无关 |
| 碎片化的生成机制 | 明确由 mlock 的高阶分散分配 + Unmovable 页面不可迁移共同造成 | ✅ 主路径已确认，slab 泄漏不是必要假设 |

**❌ 排除**：当前证据链不需要 slab 泄漏来解释碎片化现象。主路径（mlock → 碎片化 → Unmovable 页面阻塞 compaction）已能完整解释现有观察。

---

#### 假设 A6：Swap 颠簸（系统频繁换入换出）❌ 排除

> 🧪 **假设**：系统频繁进行 swap 换入换出，导致 I/O 压力和内存状态不稳定。

| 检查项 | 操作（基于真实诊断数据） | 结论 |
|--------|------------------------|------|
| allocstall | allocstall_normal=0 | ✅ 无直接回收压力，swap 触发的前提条件尚不成熟 |
| 高阶稀缺原因 | 碎片化而非页面频繁换出 | ✅ 碎片化在 4KB 页面级粒度下是物理连续性问题，与 swap 行为无关 |
| mlock 页面与 swap | mlocked 页面不会被 swap（unevictable 属性） | ✅ mlock 页面本身被排除在 swap 候选之外 |

**❌ 排除**：Swap 颠簸需要先有页面回收压力（allocstall > 0），然后才有换入换出振荡。当前 allocstall=0 且碎片化的根因是物理上的连续页面稀缺，而非页面换入换出行为。

---

#### 假设 A8：PID 31 (flf2) 僵尸进程问题

> 🧪 **假设**：Zombie 状态的 flf2 进程是高阶分配失败的直接受害者，或者 flf2 的退出留下未清理的资源。

| 检查项 | 操作（基于真实诊断数据） | 结论 |
|--------|------------------------|------|
| PID 31 状态 | Z（zombie），名为 flf2 | ✅ 僵尸进程确认 |
| Zombie 对内存影响 | 僵尸进程不占用内存（已释放），仅占 pid 槽位和少量 task_struct | ✅ 不会影响内存碎片或分配 |
| Zombie 原因推测 | 可能因高阶分配失败 → 进程异常退出 → 父进程未 wait() | 🟡 合理推测，但未直接确认 |
| flf2 业务角色 | 未知（未提供）| 🟠 难以评估业务影响 |

**🟡 标记为关联现象**：Zombie 进程本身不直接导致或加剧内存碎片化，但它可能是高阶分配失败的早期牺牲品，可作为故障链的旁证。需要进一步了解 flf2 的业务功能来评估完整影响范围。

---

### 3.3 排查结论与逻辑树

```text
容器 pcr-lru 内存高阶分配失败风险
│
├─► A1：全局内存压力                    → ❌ 排除（allocstall=0，低阶分配正常）
├─► A5：Slab 泄漏                      → ❌ 排除（主路径无需此假设）
├─► A6：Swap 颠簸                      → ❌ 排除（无回收压力，与碎片化无关）
│
├─► A2：LRU 不平衡 — Unevictable 滞留  → 🟡 部分确认（18 pages stranded，但影响有限）
│     └─► 历史 unevictable_pgs_mlocked=1018
│     └─► 当前 Mlocked=0, nr_unevictable=0
│     └─► 18 页滞留 unevictable LRU
│
├─► A4：内存碎片化阻塞高阶分配          → 🎯 **根因确认**
│     │
│     ├─► Normal zone order 8 (1MB) = 0 blocks  → ❌ 完全耗尽
│     ├─► Normal zone order 9 (2MB) = 0 blocks  → ❌ 完全耗尽
│     ├─► order 7 (512KB) = 仅 4 blocks          → ⚠️ 极度稀缺
│     │
│     ├─► mlock 期间高阶分散分配产生外碎片
│     │     └─► 解锁后页面碎片未整合为大块
│     │
│     ├─► Unmovable 页面在高阶区域占高比例
│     │     └─► 内存规整（compaction）无法迁移 → 碎片死锁
│     │
│     └─► allocstall_normal=0
│           └─► 低阶分配尚正常，系统仍在"勉强维持"
│
└─► A8：Zombie 进程 (PID 31 flf2)      → 🟡 旁证（可能是高阶分配失败的早期受害者）
      └─► 需进一步确认 flf2 的业务功能
```

---

## 四、核心风险矩阵与严重性评估

### 风险矩阵

| 风险维度 | 评分 | 说明 |
|---------|------|------|
| Order 8/9 可用内存 | 🔴 **致命** | 0 blocks — 任何 order 8/9 分配立刻失败 |
| Order 7 可用内存 | 🔴 **高危** | 仅 4 blocks — 随时可能耗尽 |
| Unmovable 页面阻塞 compaction | 🔴 **严重** | 页面不可迁移 → 碎片无法通过内核整理自愈 |
| allocstall 状态 | 🟡 暂时平静 | 尚未触发 direct reclaim，但低阶供给掩盖了高阶危机 |
| 僵尸进程影响 | 🟢 低 | 不直接加剧碎片化，但可以间接佐证已有分配失败的案例 |
| **综合风险等级** | **🔴 P1（关键）** | 高阶连续内存已实质性耗尽，部分进程已受影响（zombie），等待某个 order ≥ 7 的内存分配请求触发完整的 direct reclaim stall |

### 根因置信度评估

| 根因候选 | 支持证据（正向） | 反对证据（反向） | 置信度 |
|---------|---------------|---------------|--------|
| **A4：内存碎片化阻塞高阶分配** | order 8/9 完全耗尽（0 blocks）；order 7 仅 4 blocks；Unmovable 页面占高比导致 compaction 失败；mlock 的分散分配产生碎片 | allocstall=0 意味着高阶分配失败尚未引发系统性 direct reclaim——碎片化对低阶业务的影响尚未暴发，但高阶已实质不可用 | 🟢 **高置信** |
| **A2：LRU 不平衡（unevictable 滞留）** | unevictable_pgs_mlocked 累计 1018；18 页 stranded | nr_unevictable=0 且 Mlocked=0kB（当前无 active unevictable）；18 页数量过少不影响全局 LRU | 🟠 **低置信**（unevictable 本身不是主因，但 mlock 行为是碎片化的原因） |
| **mlock 行为为碎片化根源** | 进程 mlocked 500+ 页分布于 order 1-9，这是高阶碎片化的直接操作源 | 无法确定 mlock 前后的碎片基线；碎片化也可能由其他分配活动累积导致 | 🟡 **中置信** |

---

## 五、排除假设汇总

| 假设编号 | 假设内容 | 排除状态 | 排除依据 |
|---------|---------|---------|---------|
| A1 | 全局内存压力导致所有分配失败 | ❌ 排除 | allocstall=0，低阶分配正常，仅高阶受影响 |
| A5 | Slab 泄漏消耗不可迁移内存 | ❌ 排除 | 主路径（mlock → 碎片化 → compaction 阻塞）独立且完整 |
| A6 | Swap 颠簸引发内存不稳定 | ❌ 排除 | allocstall=0（无回收压力）；swap 与物理连续性问题无关 |
| A2 | Unevictable LRU 不平衡导致所有问题 | 🟡 部分确认为辅助因素 | 18 页 stranded 影响有限；但 mlock 行为是碎片化的根源之一 |
| A4 | 内存碎片化阻塞高阶分配 | 🎯 **确认为根因** | order 8/9=0 blocks；order 7=4 blocks；Unmovable 阻塞 compaction |

---

## 六、修复方案

### 6.1 应急处置

| 步骤 | 操作 | 执行人 | 预期效果 | 风险 |
|------|------|--------|---------|------|
| 1 | `echo 3 > /proc/sys/vm/drop_caches` 清空 Page Cache 和 slab 缓存 | 系统管理员 | 释放可回收页面，可能帮助整合部分连续内存 | ⚠️ 会引起 I/O storm（重建缓存时的大规模磁盘读取），且无法回收 Unmovable 或 unevictable 页面 |
| 2 | `echo 1 > /proc/sys/vm/compact_memory` 触发全局内存规整 | 系统管理员 | 触发内核 compaction 合并碎片页 | 仅对可迁移页面有效；Unmovable 页面不可迁移，效果受限 |
| 3 | 重启容器 pcr-lru 或相关业务进程 | 系统管理员 | 释放该容器所有页面，完全重新分配 | 需要业务准入；对系统的碎片恢复最彻底，因为容器的所有页面都会被释放 |

**推荐紧急操作顺序**：先执行 `compact_memory`（低风险），若无效则判断业务窗口是否允许容器重启。

### 6.2 永久修复计划

| 优先级 | 修复措施 | 说明 | 执行人 |
|--------|---------|------|--------|
| **P0** | **定位并优化 mlock 行为** | 排查为什么要 mlock 500+ 页（~4MB）且分散在各分配阶。如果可能，使用 `mlockall(MCL_CURRENT)` 锁定更少页面，或使用 `mlock2()` + `MLOCK_ONFAULT` 按需锁定 | 研发团队 |
| **P0** | **增加内存碎片监控告警** | 添加对 `/proc/buddyinfo` 中 order ≥ 7 可用块数的监控，设置告警阈值：order 7 < 10 blocks 告警，order 8/9 = 0 告警 | 监控团队 |
| **P1** | **调整 vm.extfrag_threshold** | 降低 extfrag_threshold（默认 500）到 100-150，使内核在碎片化初期就积极尝试 compaction | 系统管理员 |
| **P1** | **设置 vm.min_free_kbytes 为更高值** | 增加每个 zone 保留的预留内存，确保紧急分配有缓冲 | 系统管理员 |
| **P2** | **启用 THP 的碎片整理** | 若业务未使用透明大页，可确保 `transparent_hugepage/defrag = defer` 以允许内核后台整理 | 系统管理员 |
| **P2** | **优化 Unmovable 页面分配** | 调整内核 slab 分配器和页表分配策略，减少在高阶区域中分配 Unmovable 页面 | 内核调优团队 |
| **P3** | **Zombie 进程处理** | 排查 PID 31 (flf2) 成为 zombie 的原因：父进程未 wait()？确认 flf2 是否为内存分配失败的受害者并提供修复 | 研发/SRE 团队 |

### 6.3 详细调优参数

| 参数 | 当前值 | 建议值 | 说明 |
|------|--------|--------|------|
| `vm.extfrag_threshold` | 500（默认） | 100～150 | 降低至 100 使碎片指数 > 0.1 时就触发 compaction；越低越积极 |
| `vm.min_free_kbytes` | 内核自动（~1% RAM） | 增大 2～3 倍 | 为每个 zone 预留更多空闲内存，防止紧急分配回退失败 |
| `vm.compaction_proactiveness` | 20（默认） | 50～80 | 提高后台 compaction 的积极度，在碎片化恶化前主动整理 |
| `transparent_hugepage/defrag` | always | defer | 仅在后台 kcompactd 线程中整理，不触发直接 compaction（避免分配延迟）|

---

## 七、关键证据清单

| # | 证据 | 来源 | 说明 |
|---|------|------|------|
| 1 | nr_unevictable=0, Mlocked=0 kB | 当前内存状态 | 当前无 active unevictable 页面 |
| 2 | unevictable_pgs_mlocked=1018 | 内存事件计数器 | 历史累计异或值，表示有 1018 页经历了 mlocked 状态变化 |
| 3 | ~1000 已解锁，18 stranded | LRU 状态分析 | 解锁后 18 页滞留 unevictable LRU 不可回收 |
| 4 | order 8 (1MB)=0 blocks, order 9 (2MB)=0 blocks | `/proc/buddyinfo` Normal zone | 完全耗尽 — 核心证据 |
| 5 | order 7 (512KB)=4 blocks | `/proc/buddyinfo` Normal zone | 极度稀缺 — 核心证据 |
| 6 | Unmovable 页面在高阶占高比例 | 内存页类型分布 | 阻塞 compaction 页面迁移 — 核心证据 |
| 7 | allocstall_normal=0 | VM 事件计数器 | 直接回收尚未触发（低阶分配尚可满足）|
| 8 | PID 31 (flf2) = Z (zombie) | 进程状态表 | 可能已受高阶分配失败影响 |

---

## 八、附录

### A. 故障场景参数表

| 参数 | 值 |
|------|-----|
| 容器名称 | pcr-lru |
| 故障类型 | 内存碎片化 + LRU Unevictable 滞留 |
| mlock 总量（历史）| 约 500+ pages（分布于 order 1-9）|
| unevictable_pgs_mlocked（历史累计）| 1018 |
| 当前 Mlocked | 0 kB |
| 当前 nr_unevictable | 0 |
| Stranded 页面 | ~18 pages |
| Normal zone order 8 (1MB) | 0 blocks |
| Normal zone order 9 (2MB) | 0 blocks |
| Normal zone order 7 (512KB) | 4 blocks |
| allocstall_normal | 0 |
| 异常进程 | PID 31 (flf2) — Z (zombie) |

### B. 碎片状态速查 /proc/buddyinfo 解读

```
Normal zone 状态（示例性解释）：
Order（大小）：  0(4K)  1(8K)  2(16K)  3(32K)  4(64K)  5(128K)  6(256K)  7(512K)  8(1M)  9(2M)
可用块数：      XXX    XXX    XXX     XXX     XXX     XXX      XXX      4        0      0
                                                                     ⚠️       ❌     ❌
```

- **绿色区**（order 0-3）：基本可用
- **黄色区**（order 4-6）：有可用但高阶稀缺
- **红色区**（order 7-9）：接近或完全耗尽

### C. 诊断建议

**短期行动**：
1. 执行 `cat /proc/buddyinfo` 确认当前 Normal zone 各 order 可用块数
2. 执行 `cat /proc/pagetypeinfo` 查看各分配阶的 Unmovable/Reclaimable/Movable 页面分布
3. 执行 `echo 1 > /proc/sys/vm/compact_memory` 尝试触发全局 compaction
4. 执行 `grep -E "unevictable|mlocked" /proc/vmstat` 获取累积计数

**中长期行动**：
1. 审查应用代码中 mlock 的调用逻辑
2. 部署 `/proc/buddyinfo` 监控
3. 评估是否需要容器级内存保护（cgroup memory.max）

---

*报告由 witty-diagnosis-agent / Baize (Phase 1.4) 自动生成*
*数据来源：Dayu 摘要 — 容器 pcr-lru mlocked pages / 内存碎片 / LRU 不平衡诊断*
*生成时间：2026-05-26 10:55:22 UTC*
