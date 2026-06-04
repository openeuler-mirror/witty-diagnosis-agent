# 🔴 malloc Arena 膨胀诊断报告 (Branch B3)

> **报告编号**: BAIZE-RCA-20260604-ARE003
> **故障级别**: P1 (严重)
> **报告时间**: 2026-06-04 02:05 UTC
> **诊断来源**: Kuafu 全分支诊断报告 (`kuafu_full_test_report_20260604.md`)
> **当前状态**: 🔴 处理中

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | 进程 PID 57 (fault_arena_expand) glibc malloc arena 膨胀 |
| 影响范围 | 容器 memleak-test 内 PID 57 进程，已消耗 198MB RSS / 225MB VmData |
| 故障时段 | 2026-06-04 01:55 ~ 至今 (持续中) |
| 根本原因 | 单线程进程通过反复调用 `malloc()` 大量分配内存，触发 glibc 创建 4 个 ~49MB 的 malloc arena，导致 VmData 膨胀至 225MB |
| 是否恢复 | ❌ 未恢复 |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 |
|------|------|------|
| 高置信 | 🟢 | 根因已明确，反事实验证全通过，排除所有替代假设 |
| 中置信 | 🟡 | 根因基本确认，但有 1-2 个维度依赖推断 |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 |

---

## 二、根因速览

**根本原因**：`fault_arena_expand` 进程在单线程下通过 `malloc()` 反复分配大块内存。glibc 的 malloc 实现为减少锁竞争会创建多个 arena（`M_ARENA_MAX` 默认值为 8 倍 CPU 核数），但单线程场景下本无需多个 arena。由于分配模式触发了 arena 创建逻辑，glibc 使用 `mmap()` 分配了 4 个 ~49MB 的匿名映射作为 arena 的 subheap，加上其他小分配共形成 **38 个匿名 mmap 区域**，导致 VmData 膨胀至 225MB、RSS 达 198MB。

### 故障因果链

```
fault_arena_expand 启动（PID 57，单线程）
    └─► malloc(large_size) 反复调用
        └─► glibc 检测到当前 arena 锁竞争（或分配模式触发多 arena 策略）
            └─► 创建新的 malloc arena（每个 arena 通过 mmap 分配约 49MB 匿名映射）
                └─► 共创建 4 个大型 arena（4 x ~49MB）
                └─► + 34 个小匿名 mmap 区域 = 38 个 total
                    └─► VmData 膨胀至 230,700 kB (~225 MB)
                    └─► VmRSS 膨胀至 198,400 kB (~194 MB)
                    └─► Anonymous 页 = 197,840 kB
                        └─► 内存严重浪费，OOM 风险升高
```

### 事故时间线

| 时间点 (UTC) | 事件 | 证据来源 |
|-------------|------|---------|
| 2026-06-04 01:55 | 容器启动，PID 57 (fault_arena_expand) 运行 | `process_baseline.csv` |
| 2026-06-04 01:57 | 基线采集：VmRSS=198,400 kB, VmData=230,700 kB | `pmap_57.txt`, `arena_trend_57.csv` |
| 2026-06-04 01:57 | pmap 检测到 38 个匿名 mmap 区域，4 个 ~49MB | `pmap_57.txt` 分析 |
| 2026-06-04 01:58 | Kuafu 完成 Arena 膨胀分支诊断确认 | `kuafu_full_test_report_20260604.md` |
| 至今 | 4 个 ~49MB arena 持续驻留，VmData=225MB | 持续监控中 |

---

## 三、排查过程

### 3.1 初始现象

- **进程信息**: PID 57, `fault_arena_expand`, 单线程
- **RSS 极高**: 198,400 kB (~194 MB)
- **VmData >> VmRSS**: VmData=230,700 kB (~225 MB) > VmRSS=198,400 kB，表明部分内存已分配但未驻留（swapped 或未触页）
- **匿名 mmap 数量**: 38 个匿名映射区域
- **匿名页总量**: 197,840 kB（占 RSS 99.7%）
- **大型匿名区域分布**: 4 个 ~49MB 区域，特征高度符合 glibc malloc arena subheap

### 3.2 假设驱动排查

#### 假设 B3: malloc arena 膨胀 ✅ 确认根因

> 🧪 假设：glibc malloc 为减少锁竞争创建了多个 arena，每个 arena 预分配大块 mmap 区域

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 匿名 mmap 数量 | `pmap -x 57 \| grep anon \| wc -l` | 38 个匿名区域 |
| 大型匿名区域分布 | `pmap -x 57 \| sort -k3 -rn \| head -10` | 4 个 ~49MB 大区域 (49,152 kB) |
| VmData vs RSS | `grep -E "VmData\|VmRSS" /proc/57/status` | VmData=230,700 > VmRSS=198,400 |
| 线程数 | `ls /proc/57/task/ \| wc -l` | 1（单线程却有多 arena） |
| arena 典型大小 | glibc 默认 arena subheap 大小 | 64-bit 系统默认 64MB，此处 ~49MB 合理 |

**✅ 结论**：单线程进程创建了 4 个 malloc arena，每个引用 ~49MB mmap 匿名区域，导致 VmData 膨胀至 225MB。38 个匿名 mmap 中 4 个大区域为 arena subheap。

#### 假设 B1: 堆内存未释放 (heap 段泄漏)

| 检查项 | 操作 | 结论 |
|--------|------|------|
| [heap] 段 RSS | `pmap -x 57 \| grep "\[heap\]"` | 非传统 heap 段增长，而是匿名 mmap |
| VmData 构成分析 | pmap 详细输出 | 匿名 mmap 占主导，非 brk() 堆 |

**❌ 排除**：增长模式为 mmap 匿名映射而非传统 brk heap。

#### 假设 B2: mmap 匿名映射未释放 (应用层 mmap)

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 区域大小分布 | pmap 排序输出 | 4 个 ~49MB 区域 + 34 个小区域 |
| 区域特征 | 大小一致、地址对齐 | 4 个大区域大小一致(~49MB)，符合 glibc arena 特征而非应用层 mmap |

**❌ 排除**：区域大小和数量特征指向 glibc 内部机制，非应用代码直接 mmap。

#### 假设 B4: 递归增长缓存

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 内存增长模式 | arena 增长为阶梯式而非线性 | 4 个 ~49MB 区域非缓存碎片模式 |

**❌ 排除**：阶梯式大块增长不符合缓存渐进膨胀特征。

#### 假设 B5: 内存池碎片化

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 碎片特征 | pmap 小区域分布 | 34 个小区域但总量远小于 4 个大区域 |

**❌ 排除**：主要内存消耗来自 4 个大 arena 而非碎片。

### 3.3 排查结论与逻辑树

```
PID 57 VmData=225MB > VmRSS=194MB，38 个匿名 mmap 区域
├─► 假设 B1: heap 段泄漏       → ❌ 非 brk heap 增长，排除
├─► 假设 B2: 应用层 mmap 泄漏  → ❌ 区域大小一致，为 glibc 内部机制，排除
├─► 假设 B3: malloc arena 膨胀 → 🎯 确认根因
│       ├─► 4 个 ~49MB 大匿名区域 = glibc arena subheap
│       ├─► 单线程却有多 arena（M_ARENA_MAX 默认策略）
│       └─► VmData > VmRSS 说明部分 arena 内存未驻留
├─► 假设 B4: 递归增长缓存     → ❌ 阶梯式非缓存增长
└─► 假设 B5: 内存池碎片化     → ❌ 大区域主导非碎片
```

---

## 四、关键证据

1. **证据1 — 匿名 mmap 计数与分布**：`pmap_57.txt` 显示 **38 个匿名 mmap 区域**，其中 **4 个 ~49,152 kB 的大区域** — 大小高度一致，这是 glibc arena 创建 `mmap()` subheap 的典型特征。
2. **证据2 — VmData >> VmRSS**：VmData=230,700 kB vs VmRSS=198,400 kB，差值约 32MB 表明部分 arena 内存已分配但尚未触页驻留（demand paging）。
3. **证据3 — 单线程多 arena**：进程仅 1 线程却拥有 4 个 arena，确认是 glibc arena 分配策略导致。
4. **证据4 — 匿名页占 RSS 99.7%**：AnonPages=197,840 kB，几乎全部 RSS 由匿名页构成，确认无文件缓存干扰。

---

## 五、反事实验证

| 维度 | 推演结果 | 实际现象 | 是否吻合 |
|------|---------|---------|---------|
| Arena 膨胀 → VmData > RSS | VmData > VmRSS，差值约 10-20% | VmData=230,700 > VmRSS=198,400 (差 14%) | ✅ 是 |
| Arena 膨胀 → 多匿名区域 | 匿名 mmap 数 >> 正常 (<10) | 38 个匿名区域（4 个 ~49MB 大区域） | ✅ 是 |
| Arena 膨胀 → 区域大小一致 | 多个区域大小接近 | 4 个区域均为 49,152 kB (±少量偏移) | ✅ 是 |
| Arena 膨胀 → 单线程场景 | 1 线程但 arena 数 > 1 | 4 个 arena / 1 线程 | ✅ 是 |

---

## 六、排除的替代假设

- **假设 B1 (Heap 段泄漏)**：排除。内存增长来自匿名 mmap 区域而非传统 `[heap]` 段，`brk()` 机制正常。
- **假设 B2 (应用层 mmap 泄漏)**：排除。4 个 ~49MB 大区域大小高度一致，对齐地址，符合 glibc arena 内部 mmap 策略特征，非应用代码直接调用。
- **假设 B4 (递归增长缓存)**：排除。内存消耗为阶梯式大块分配而非缓存渐进增长。
- **假设 B5 (内存池碎片化)**：排除。内存主要集中在大区域，非碎片积累。

---

## 七、修复建议

### 7.1 应急处置

| 步骤 | 操作 | 执行人 | 预期效果 |
|------|------|--------|---------|
| 1 | `kill -9 57` | 系统管理员 | 终止进程，释放所有内存 |
| 2 | 确认释放: `free -h` 观察可用内存回升 | 系统管理员 | 内存恢复正常 |

### 7.2 永久修复

```c
// 方案1：启动时设置 M_ARENA_MAX 环境变量限制 arena 数量
// 在启动命令前设置（推荐值：CPU 核数或 1 对于单线程）
// MALLOC_ARENA_MAX=1 ./fault_arena_expand

// 方案2：代码中使用 mallopt() 限制 arena 数量
#include <malloc.h>
mallopt(M_ARENA_MAX, 1);  // 限制最多 1 个 arena

// 修复前（故障代码模式 - 大量大块 malloc 触发多 arena）
for (int i = 0; i < iterations; i++) {
    void *p = malloc(large_size);  // 反复大块分配
    // ❌ 未释放 或 释放后 arena 不归还给 OS
}

// 修复后（考虑使用 mmap 大块或限制 arena）
mallopt(M_ARENA_MAX, 1);
// 或改用 mmap 直接管理大块内存
```

### 7.3 预防措施

1. **环境变量调优**：对于单线程或低并发服务，设置 `MALLOC_ARENA_MAX=1` 或 `MALLOC_ARENA_MAX=<CPU核数>`，避免 arena 过度创建。
2. **内存分配策略**：大块内存（>128KB）考虑直接使用 `mmap()` + `munmap()`，避免经过 glibc arena。
3. **监控指标**：监控进程 `VmData` 与 `VmRSS` 比值，若 `VmData > VmRSS * 1.2` 且匿名 mmap 数 > 20，触发 arena 膨胀告警。
4. **替代分配器**：考虑使用 `jemalloc` 或 `tcmalloc` 替代 glibc malloc，在多线程场景下有更好的 arena 管理策略。

---

## 八、附件

- 进程基线表: `process_baseline.csv` (PID 57 行: VmRSS=198,400 kB, VmData=230,700 kB)
- Arena 趋势数据: `arena_trend_57.csv`
- 进程内存映射: `pmap_57.txt` (38 个匿名区域, 4 x ~49MB)
- 系统内存快照: `meminfo_final.txt`
- 容器环境: memleak-test, Linux 6.6.87.2-microsoft-standard-WSL2
- Kuafu 全分支报告: `kuafu_full_test_report_20260604.md` (行 121-131)
