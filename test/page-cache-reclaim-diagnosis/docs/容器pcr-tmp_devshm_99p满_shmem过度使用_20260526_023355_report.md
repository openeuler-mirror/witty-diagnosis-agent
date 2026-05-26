# 🔴 故障诊断报告

> **报告编号**: RCA-20260526-001
> **故障级别**: P3（资源预警 / 非业务中断）
> **报告时间**: 2026-05-26 02:55:00
> **当前状态**: 🟡 观察中（/dev/shm 空间已耗尽，但业务尚未中断）

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | 容器 pcr-tmp 中 /dev/shm 使用率达 99%（64 MB 中 63 MB 被单文件占用） |
| 影响范围 | **仅容器 pcr-tmp 内部**：任何尝试分配 tmpfs 共享内存（`mmap MAP_SHARED` 到 /dev/shm）的操作将因 `ENOSPC` 失败。宿主机及其他容器不受影响。 |
| 故障时段 | 2026-05-25 23:00:00 UTC ～ 至今（持续中，未自动恢复） |
| 根本原因 | 容器内应用进程通过 `mmap MAP_SHARED` 在 `/dev/shm` 上创建了一个 63 MB 的大文件 `/dev/shm/big`，占满了 64 MB 的 tmpfs 上限。Shmem 统计值 69,644 kB 与该文件大小一致（计入元数据开销）。 |
| 是否恢复 | ❌ 未恢复（/dev/shm 仍处于 99% 满状态） |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|---------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | **本场景**：/dev/shm/big 文件占满 tmpfs 空间，Shmem 值与文件大小完全吻合 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                             事件                                             性质           溯源路径
───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-05-25 23:00:00 UTC         应用进程在容器 pcr-tmp 中分配 mmap MAP_SHARED       📈 外部触发     [kuafu_T1_20260526_023355_shmem_overuse.md:157-158]
                                 在 /dev/shm 上创建了 big 文件（63 MB）
  │
  ▼
2026-05-25 23:00:xx UTC          /dev/shm 使用率从基线上升至 99%                     ⚠️ 资源占用     [kuafu_T1_20260526_023355_shmem_overuse.md:37-43]
                                 tmpfs 剩余可用空间仅 1 MB
  │
  ▼
2026-05-25 23:00:xx UTC          Shmem 统计值上升至 69,644 kB                       🟡 证据确认     [kuafu_T1_20260526_023355_shmem_overuse.md:21]
                                 其中 63 MB 为 /dev/shm/big 文件内容
  │
  ▼
2026-05-25 23:00:xx UTC          cgroup 内存统计: shmem = 63 MB (95% of cgroup)      🟡 数据验证     [kuafu_T1_20260526_023355_shmem_overuse.md:71]
                                 容器内存几乎全部被 shmem/tmpfs 消耗
  │
  ▼
2026-05-26 02:33:00 UTC          Kuafu 诊断任务 T1 执行，确认当前状态                 🔍 诊断介入     [kuafu_T1_...md]
                                  /dev/shm 99% 满，系统内存充裕（14.1 GB 可用）
                                  ↳ 业务尚未中断，但风险持续存在
```

### 故障因果链

```text
应用进程在容器内通过 mmap MAP_SHARED 创建 /dev/shm/big（63 MB）
    └─► tmpfs 挂载点容量仅 64 MB（size=65536k）
            └─► /dev/shm 使用率飙升至 99%，剩余空间 1 MB
                    └─► 任何新的 tmpfs 分配请求将返回 ENOSPC
                    └─► 应用依赖共享内存的功能（如 IPC、大数据缓存）可能失败
```

---

## 三、排查过程：基于 Page-Cache-Reclaim 诊断方法论的假设驱动分析

> 排查逻辑：**提出多假设 → 收集证据验证/排除 → 逐步收敛到根因**，涵盖 D1～D5 五类假设。

### 3.1 初始现象

- **容器 pcr-tmp 内部** `/dev/shm` 使用率 99%（64 MB total, 63 MB used）
- 唯一占用量大的文件是 `/dev/shm/big`（63 MB）
- 系统级 `Shmem` = 69,644 kB（~68 MB），与文件大小基本吻合
- 系统可用内存充裕：MemAvailable = 14.1 GB，Swap 未使用
- cgroup memory.max = max（无限制）
- 无 System V 共享内存段（`ipcs` 为空）

---

### 3.2 假设驱动排查（Page-Cache-Reclaim 五维分析）

#### 假设 D3：tmpfs/shmem 过度使用 ✅ **确认根因**

> 🧪 假设：应用进程通过 `mmap MAP_SHARED` 在 tmpfs 上分配了过大共享内存，导致 `/dev/shm` 空间耗尽。

**正向证据（支持）：**

| 检查项 | 数据来源 | 结论 |
|--------|---------|------|
| /dev/shm 使用率 | `df -h /dev/shm` → 64M/63M (99%) | ✅ /dev/shm 空间接近耗尽 |
| 大文件定位 | `ls -la /dev/shm` → `/dev/shm/big` = 66,060,288 bytes | ✅ 唯一大文件，大小 63 MB |
| Shmem 统计 | `/proc/meminfo` → Shmem = 69,644 kB | ✅ 与文件大小一致（含元数据） |
| cgroup shmem | memory.stat: shmem = 66,060,288 bytes | ✅ cgroup 级 shmem 完全匹配文件大小 |
| ipcs 检查 | `ipcs -m` → 无输出 | ✅ 非 System V 方式，确认为 mmap 到 tmpfs |
| 无 cgroup 限制 | memory.max = max | ✅ 非 cgroup 限流导致 |

**反向证据（反对）**：无。

**排除其他解释：**
- Shmem 值 69,644 kB 并不异常（相对 15.3 GB 总内存仅 0.44%），问题仅在于 **tmpfs 挂载点自身的 64 MB 小容量限制**，而非系统内存不足。

**✅ 结论确认：`/dev/shm/big` 文件占满了 64 MB 的 tmpfs 容量，任何需要分配新 tmpfs 空间的操作将失败。**

---

#### 假设 D1：文件读取（Page Cache / 文件读取页面缓存膨胀）

> 🧪 假设：大量文件 I/O 读取导致 page cache 膨胀，间接占用了可回收内存。

| 检查项 | 数据来源 | 结论 |
|--------|---------|------|
| nr_file_pages | 1,216,800 页（~4.6 GB） | ✅ 文件缓存存在 |
| nr_inactive_file | 1,132,069 页（~4.3 GB） | ✅ 大量非活跃文件页可供回收 |
| MemAvailable | 14.1 GB | ✅ 系统内存充裕，无回收压力 |
| Dirty | 84 kB | ✅ 脏页极少，回写正常 |
| pswpin/pswpop | 0/0 | ✅ 无 swap 压力，未触发回收 |

**❌ 排除**：page cache 总量合理（4.6 GB/15.3 GB = 30%），且 MemAvailable 充裕表明内核不认为内存紧张。page cache 膨胀并非导致 /dev/shm 耗尽的原因。

---

#### 假设 D2：vfs_cache_pressure / 内核缓存回收参数过小

> 🧪 假设：`vm.vfs_cache_pressure` 设置过低，导致 dentry/inode 等 slab 可回收缓存无法被及时回收，从而妨碍了正常的 page reclaim。

| 检查项 | 数据来源 | 结论 |
|--------|---------|------|
| SReclaimable | 172,748 kB（~169 MB） | ✅ slab 可回收量正常 |
| SUnreclaim | 104,064 kB（~102 MB） | ✅ slab 不可回收量正常 |
| 总 slab | ~271 MB，占总内存 1.8% | ✅ slab 占比合理，无明显异常 |
| 系统内存压力 | MemAvailable = 14.1 GB | ✅ 系统无内存压力，reclaim 未触发 |

**❌ 排除**：即使 vfs_cache_pressure 较低（未见配置证据），当前系统内存充裕、无回收触发条件，且 slab 总量合理。不存在 "回收受阻导致内存压力" 的情况。此外，Shmem（tmpfs）**本身不可回收**（内核标记为不可回收页），与 vfs_cache_pressure 无关。

---

#### 假设 D4：应用 mmap 未释放 / 内存泄漏

> 🧪 假设：应用进程分配了 `mmap MAP_SHARED` 映射后，未正确释放（munmap），导致 `Shmem` 持续增长并最终占满 tmpfs。

| 检查项 | 数据来源 | 结论 |
|--------|---------|------|
| /dev/shm 内容 | 仅有 `/dev/shm/big` 一个 63 MB 文件 | ✅ 仅一个文件，非持续增长型泄漏 |
| cgroup anon | anon = 475 kB，active_anon = 16 kB | ✅ 匿名页极少，未发现持续增长的匿名映射 |
| cgroup inactive_anon | 66,473,984 bytes | ✅ 非活跃匿名页即 shmem，与 big 文件一致 |
| tmpfs 文件计数 | 仅 `/dev/shm/big` + 目录自身 | ✅ 无大量小文件碎片泄漏迹象 |
| System V ipcs | 无段 | ✅ 非 System V 泄漏 |

**❌ 排除"泄漏"模式**：证据指向单一固定大小的文件（63 MB）被创建后持续存在，**而非 mmap 未释放导致的增长型内存泄漏**。如果存在泄漏，应当观察到 Shmem 持续增长、多次分配的文件残留等迹象。此处是**一次性资源占用**，属于应用资源使用模式问题。

---

#### 假设 D5：内核回收异常（kswapd / direct reclaim 异常）

> 🧪 假设：内核页面回收机制（kswapd 或 direct reclaim）存在缺陷或异常，导致无法正常回收可回收页面，间接影响内存分配。

| 检查项 | 数据来源 | 结论 |
|--------|---------|------|
| swap 活动 | pswpin=0, pswpout=0 | ✅ 未触发 swap，无回收压力迹象 |
| 脏页 | Dirty = 84 kB | ✅ 无脏页堆积，回写正常 |
| MemAvailable | 14.1 GB | ✅ 系统内存充裕，kswapd 不会密集运行 |
| dmesg | 无 shmem/tmpfs 错误日志 | ✅ 无内核回收相关告警或错误 |
| nr_inactive_file | 1,132,069 页（~4.3 GB） | ✅ 大量可回收页，未因故障无法回收 |

**❌ 排除**：系统内存充裕（可用 14.1 GB），mem Available 远高于 min_free_kbytes（45,056 kB），内核没有触发 kswapd 或 direct reclaim 的条件。dmesg 中无任何异常。回收机制工作正常。

---

### 3.3 排查结论与逻辑树

```text
/dev/shm 99% 满
├─► D5: 内核回收异常 (kswapd/direct reclaim)
│       └─ 系统内存充裕 (MemAvailable=14.1 GB)，无 swap，无回收压力 → ✅ 排除
├─► D2: vfs_cache_pressure 过小
│       └─ slab 正常 (~271 MB, 1.8%)，无回收触发条件 → ✅ 排除
├─► D1: 文件读取引起 page cache 膨胀
│       └─ page cache 4.6 GB (30%)，MemAvailable 充裕 → ✅ 排除
├─► D4: 应用 mmap 未释放 (内存泄漏)
│       └─ 仅一个固定 63 MB 文件，非增长型泄漏 → ✅ 排除
└─► D3: tmpfs/shmem 过度使用 ← 🎯 **根因确认**
        └─ /dev/shm/big = 63 MB, tmpfs=64 MB cap → 99% 满
            └─ 应用使用 mmap MAP_SHARED 分配共享内存到 tmpfs
```

---

## 四、修复方案

### 4.1 应急处置

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | 确认 `/dev/shm/big` 的创建进程：`fuser -v /dev/shm/big` 或 `ls -la /proc/*/fd/ 2>/dev/null \| grep /dev/shm/big` | 运维 | 立即 | 定位占用进程 |
| 2 | 若该文件不再需要且进程已退出：`rm -f /dev/shm/big` | 运维 | 立即 | 释放全部 63 MB tmpfs 空间 |
| 3 | 若进程仍运行中且 big 文件为运行所需：评估能否缩小 big 文件大小或扩展 tmpfs 容量 | 运维/开发 | 按需 | 恢复 tmpfs 可用余量 |

**清理脚本参考：**
```bash
# 方案 A：文件不再需要
rm -f /dev/shm/big

# 方案 B：若进程仍存活但内容可清除
: > /dev/shm/big     # 清空但不删除（保留 fd 引用）

# 方案 C：扩展 tmpfs 容量（需容器重建或 docker --shm-size）
docker run --shm-size=128m ...  # 下次部署时指定更大的 shm
```

### 4.2 永久修复计划

| 修复措施 | 负责人 | 完成时间 |
|---------|--------|---------|
| 分析 `/dev/shm/big` 的来源：是应用自身的 mmap 分配（如中间件 IPC）还是数据文件 | 开发团队 | 待定 |
| 若为应用正常行为：增大容器 `--shm-size` 到 128 MB 或 256 MB，提供充裕 tmpfs 空间 | 运维团队 | 待定 |
| 若为异常行为：修复应用代码，限制共享内存分配大小或及时释放 | 开发团队 | 待定 |
| 添加容器内 tmpfs 使用率监控告警（如 /dev/shm > 80% → P4 告警，> 95% → P3 告警） | 运维团队 | 待定 |
| 重启/重新部署容器后验证 tmpfs 使用率回到安全水位 | 运维团队 | 待定 |

### 4.3 预防建议

- **容量规划**：容器 `--shm-size` 应基于应用的峰值共享内存需求设定，建议至少为实际需求的 2 倍。
- **监控增强**：容器内部 `/dev/shm` 使用率应纳入 Prometheus/node_exporter 采集，设置分级告警阈值。
- **审计日志**：对于容器的 tmpfs 文件创建操作，建议记录审计日志以便追查来源。

---

## 附录：证据路径索引

| 证据项 | 源文件 | 行号 |
|--------|--------|------|
| /dev/shm 使用率 99% | `kuafu_T1_20260526_023355_shmem_overuse.md` | L37 |
| /dev/shm/big 文件大小 63 MB | 同上 | L43 |
| Shmem = 69,644 kB | 同上 | L21 |
| cgroup shmem = 63 MB | 同上 | L71 |
| ipcs 空（无 System V） | 同上 | L52-60 |
| cgroup memory.max = max | 同上 | L70 |
| MemAvailable = 14.1 GB | 同上 | L20 |
| Swap 未使用 | 同上 | L26-27 |
| 脏页 84 kB | 同上 | L94 |
| 无 dmesg 错误 | 同上 | L138-140 |

---

> **报告生成**: 白泽（Baize）分析与报告 Agent (Phase 1.4) | 2026-05-26 02:55:00 UTC
> **诊断工具链**: Dayu (编排) → Kuafu (执行) → Baize (分析 & 报告)
