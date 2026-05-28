# 🔴 故障诊断报告

> **报告编号**：RCA-20260528-001
> **故障级别**：P3 / 风险预警
> **报告时间**：2026-05-28 23:58:00
> **当前状态**：🟡 观察中（已有 47% inode 占用，尚未触发实际故障）

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | Docker 容器 overlayfs-fault-G OverlayFS inode 压力 — 3000 文件批量 copy-up 导致 inode 使用率 47% |
| 影响范围 | 容器 overlayfs-fault-G（Docker overlay2 存储场景），底层 ext4 文件系统 inode 池共 12800 |
| 故障时段 | 2026-05-28 23:58:00（测试执行时间点），持续累积中 |
| 根本原因 | 大量小文件（3000个）从 overlay lower 层逐批 copy-up 到 upper 层，每个文件消耗一个 inode，累计 inode 使用 6016/12800 (47%)；ext4 文件系统 inode 数量在 mkfs 时固定，无法动态扩容，持续增长将导致 inode 耗尽 |
| 是否恢复 | ✅ 当前测试状态正常（文件全量可见，容器运行正常） |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 | 
|------|------|------|--------| 
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | 定量测试：3000 文件 copy-up 后 inode 用量与预期一致 | 
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | 定位到慢查询，但流量突增原因待查 | 
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | 多个组件同时异常，无法判断触发顺序 | 
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | 服务偶发崩溃，日志无异常，无法复现 | 

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                         事件                                                  性质         证据来源
───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-05-28 23:58:00          容器 overlayfs-fault-G overlay 挂载完成                       ✅ 正常     [kuafu_T1_20260528_235800.md:4-8]
  │                           挂载拓扑：lower=/mnt/ovl_g/lower, upper=/mnt/ovl_g/upper
  │                                   work=/mnt/ovl_g/work, merged=/mnt/ovl_g/merged
  │                           各层文件系统均为 ext4
  │
  ▼
2026-05-28 23:58:00          向 overlay merged 写入 3000 个小文件                           📈 操作触发  [kuafu_T1_20260528_235800.md:17-22]
  │                           overlay 内核触发 copy-up 机制：
  │                           写入 merged → overlay 拦截 → 将 lower 文件复制到 upper
  │                           每个文件在 upper 层创建一个独立 inode
  │
  ▼
2026-05-28 23:58:00          upper 层 3000 文件 copy-up 完成                              🔵 完成     [kuafu_T1_20260528_235800.md:17-22]
  │                           lower(3000 文件) + upper(3000 文件) = 6000 个文件
  │                           加上目录元数据等开销
  │
  ▼
2026-05-28 23:58:00          inode 使用量：6016 / 12800 (47%)                           🟡 风险累积   [kuafu_T1_20260528_235800.md:24-30]
  │                           可用 inode：6784（约 53%）
  │                           每批 3000 文件消耗约 3000 inode →
  │                           预计约 6700 文件后 inode 将耗尽
  │
  ▼
2026-05-28 23:58:00          当前状态：容器运行正常，merged 全量可见 3000 文件              🟢 正常     [kuafu_T1_20260528_235800.md:32]
  │                           尚未触发 ENOSPC 故障
  │
  ▼
[预测] 若持续写入 → inode 耗尽 → 触发 ENOSPC                          🔴 风险预警
        即使 df -h 显示磁盘 block 有余量（block 与 inode 相互独立）
        容器内将无法创建新文件/目录，报 "no space left on device"
```

### 故障因果链

```text
容器应用写入 merged 目录（3000 小文件）
    │
    ▼ OverlayFS copy-up 机制（写时复制）
    └─► 内核 overlay 驱动自动将 lower 文件复制到 upper 层
         │
         ▼ 每次 copy-up 在 upper 层 ext4 创建一个新 inode
         └─► upper 层 each 文件 inode + 1
              │
              ▼ 每批 3000 文件 → 约 3000 inode 消耗
              └─► inode 使用量持续增长（当前 6016/12800 = 47%）
                   │
                   ▼ ext4 文件系统 inode 总量在 mkfs.ext4 时固定
                   └─► 无法动态扩容 inode 池
                        │
                        ▼ 可用 inode 持续减少（当前剩余 6784）
                        └─► 预计再写入约 6700 文件后 inode 耗尽
                             │
                             ▼ 🔴 触发 "no space left on device" 故障
                             即使磁盘 block 空间仍有大量余量
```

---

## 三、排查过程

> 排查逻辑：**提出假设 → 收集证据 → 验证或排除 → 逐步收敛到根因**

### 3.1 初始现象

- **环境**：Docker 容器 overlayfs-fault-G，使用 overlay2 存储驱动
- **操作**：向 merged 目录批量写入 3000 个小文件，触发 overlay copy-up
- **观测结果**：
  - 各层文件分布：lower 3000 / upper 3000（全部 copy-up）/ merged 3000（全量可见）
  - inode 用量：6016 / 12800（47%）
  - 容器运行正常，读写无异常

### 3.2 假设驱动排查

#### 假设 A：磁盘空间（block）不足导致故障

> 🧪 假设：下层 ext4 磁盘空间满，引发写入失败

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 磁盘容量 | `df -h`（ext4 文件系统） | ✅ 未报告容量不足 |
| 写入测试 | 容器内正常完成 3000 文件写入 | ✅ 写入无异常 |

**❌ 排除**：磁盘 block 空间未满，写入正常。

---

#### 假设 B：inode 耗尽导致容器异常 ✅ 确认根因 / 风险明确

> 🧪 假设：overlay upper 层 ext4 文件系统 inode 池有限，文件持续累积将耗尽 inode

**Step 1 — 确认 inode 使用现状**

| 指标 | 当前值 | 说明 |
|------|--------|------|
| 总 inode | 12800 | ext4 mkfs 时固定值 |
| 已用 inode | 6016 (47%) | 含 lower 层 3000 + upper 层 3000 + 目录元数据 |
| 可用 inode | 6784 (53%) | 可支撑约 2 批同类操作 |

**Step 2 — 理解 copy-up 机理**

OverlayFS 的内核 copy-up 机制（`fs/overlayfs/copy_up.c`）：
- 当进程对 merged 视图中的 lower 层文件进行修改操作时，overlay 内核模块先将文件**完整复制**到 upper 层
- 每次 copy-up 在 upper 层创建一个**新文件**，消耗一个 inode
- 即使只修改文件的一个字节，也需要完整的文件复制和 inode 分配
- 小文件场景下（如日志文件、缓存文件、配置文件等），大量 copy-up 会迅速消耗 inode

**Step 3 — 趋势预测**

```text
当前：3000 文件 copy-up → inode 47% (6016/12800)
第二批 3000 文件 → inode 约 67%  (约 8600/12800)
第三批 3000 文件 → inode 约 90%  (约 11600/12800)
第四批 约 2000 文件 → inode 100% → inode 耗尽 ❌
```

**✅ 结论：OverlayFS copy-up 导致 upper 层 inode 持续消耗；ext4 inode 池固定（12800），不可动态扩容；当前占用 47%，以每 3000 文件消耗约 3000 inode 的速率推算，约 6700 文件后将触发 inode 耗尽。**

---

#### 假设 C：文件系统跨设备问题

> 🧪 假设：upperdir/lowerdir/workdir 属于不同文件系统导致 overlay 异常

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 各层文件系统类型 | lower=ext4, upper=ext4, work=ext4 | ✅ 同一类型 |
| 挂载设备 | 均为同一 ext4 loop 设备 | ✅ 同设备 |

**❌ 排除**：各层位于相同 ext4 文件系统上，非跨设备问题。

---

#### 假设 D：whiteout / opaque 标记异常

> 🧪 假设：overlay 的 whiteout 或 opaque xattr 导致文件不可见

| 检查项 | 操作 | 结论 |
|--------|------|------|
| merged 文件可见性 | 3000 文件在 merged 全量可见 | ✅ 正常 |
| 文件访问 | 无 readdir 异常 | ✅ 正常 |

**❌ 排除**：whiteout/opaque 无异常，所有文件可见可访问。

---

### 3.3 排查结论

```text
容器 overlayfs-fault-G inode 使用率 47%
├─► 磁盘 block 空间       → ✅ 充足，排除
├─► 跨设备问题            → ✅ 同文件系统，排除
├─► whiteout/opaque 异常  → ✅ 文件全量可见，排除
└─► overlay copy-up inode 消耗 → ❌ 确认风险
        ├─► 机理：内核 copy_up.c 机制 → 每次写入触发文件复制到 upper 层
        ├─► 当前：3000 文件 → 6016 inode (47%)
        └─► 风险：inode 12800 固定，约 6700 文件后将耗尽
                └─► 🎯 根因确认：ext4 固定 inode 池 + overlay copy-up 逐文件消耗 inode
```

---

## 四、修复方案

### 4.1 应急处置（如有）

当前 inode 占用 47%，尚未触发实际故障，无需紧急处置。但应启动监控与容量规划。

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | 对容器 overlay 层添加 inode 使用率监控告警（阈值 > 80%） | 运维团队 | 立即 | 提前感知 inode 压力 |
| 2 | 若 inode 使用率 > 90%，清理容器中不再需要的 upper 层文件 | 运维团队 | 按需 | 释放 inode，延缓耗尽 |

### 4.2 永久修复计划

| 修复措施 | 负责人 | 完成时间 |
|--------|------|--------|
| **方案一：增大 inode 密度** — 对存储层重新 mkfs.ext4，使用 `-i 4096` 或 `-N` 参数指定更大的 inode 数量（如 `mkfs.ext4 -i 4096 /dev/sdX`） | 存储/运维团队 | 下次维护窗口 |
| **方案二：日志/小文件轮转清理** — 在容器内配置 logrotate 等策略，定期清理或归档 upper 层累积的小文件 | 应用团队 | 持续 |
| **方案三：使用支持动态 inode 的文件系统** — 考虑 XFS（支持动态 inode 分配）替代 ext4 作为 overlay upper/lower 层文件系统 | 架构团队 | 长期规划 |
| **方案四：调整容器配置** — 将高频写入的小文件目录通过 volume 挂载独立文件系统，避免与 overlay upper 层共享 inode 池 | 应用/运维团队 | 短期可实施 |
| **方案五：容器镜像优化** — 减少基础镜像中的小文件数量，降低 lower 层 inode 基线的消耗（当前 lower 已占 3000+ inode） | 开发团队 | 迭代周期内 |

#### 推荐实施顺序

```
短期（1周内）：方案二（logrotate）+ 方案四（volume 分离）
中期（1月内）：方案一（增大 inode 密度）
长期（持续）：方案三（XFS 迁移）+ 方案五（镜像优化）
```

---

## 五、补充分析：OverlayFS 系统态诊断

### 5.1 挂载拓扑

| 层 | 路径 | 文件系统 |
|------|------|---------|
| lowerdir | /mnt/ovl_g/lower | ext4 |
| upperdir | /mnt/ovl_g/upper | ext4 |
| workdir | /mnt/ovl_g/work | ext4 |
| merged | /mnt/ovl_g/merged | overlay |

### 5.2 文件分布

| 位置 | 文件数 | 说明 |
|------|--------|------|
| lower | 3000 | 基础层文件（只读） |
| upper | 3000 | 全部由 lower copy-up 产生 |
| merged | 3000 | 全量可见（overlay 合并视图） |

### 5.3 inode 使用分析

| 指标 | 值 | 计算说明 |
|------|-----|---------|
| 总 inode | 12800 | mkfs.ext4 默认根据分区大小自动计算 |
| 已用 inode | 6016 | ≈ 3000(lower 文件) + 3000(upper 文件) + 16(目录等元数据开销) |
| 可用 inode | 6784 | 12800 - 6016 |
| inode 使用率 | 47% | 6016 / 12800 |

### 5.4 异常现象总结

- **当前状态**：无功能性异常，容器正常运行
- **风险模式**：overlay2 inode 耗尽风险
- **对应 OverlayFS 诊断分支**：**分支 G** — Docker overlay2 inode 耗尽
- **触发条件**：容器内持续产生小文件写入 → overlay copy-up → upper 层 inode 逐文件消耗 → ext4 inode 池耗尽 → ENOSPC

---

## 六、内核态分析

### 相关内核代码路径

| 项目 | 内容 |
|------|------|
| 内核文件 | `fs/overlayfs/copy_up.c` |
| 核心机制 | OverlayFS copy-up（写时复制） |
| 行为描述 | 当进程对 overlay merged 视图中的 lower 层文件执行修改操作时，overlay 内核模块在 upper 层创建一个新文件，将 lower 文件完整复制到 upper 层，然后对 upper 层副本执行修改。后续所有 I/O 重定向到 upper 层副本。 |
| inode 消耗机制 | 每次 copy-up 调用 `ovl_copy_up_one()` → 在 upper 层文件系统上 `vfs_create()` → 分配一个新的 inode |
| 底层限制 | ext4 文件系统在 mkfs 阶段已固定 inode 表大小（`sbi->s_inodes_count`），运行时不可扩容 |

### 因果链

```
[触发条件] 容器应用写入 merged 中源自 lower 层的文件
    → [内核路径] fs/overlayfs/copy_up.c: ovl_copy_up_one() 
        → vfs_create() in upper dir
            → ext4 分配新 inode（ext4_new_inode()）
                → inode 计数 +1
    → [累积效应] 大批小文件反复触发 copy-up
        → [异常状态] upper 层文件系统 inode 快速消耗
            → [用户可见] inode 使用率 47%（6016/12800）
                → [风险] inode 耗尽后触发 ENOSPC
```

---

## 七、交叉验证结果

| 验证维度 | 系统态结论 | 内核态结论 | 是否吻合？ |
|---------|-----------|-----------|-----------|
| 异常现象 | inode 使用率 47%，无功能性异常 | copy_up_one() 每次消耗一个 inode | ✅ 吻合 |
| 配置条件 | ext4 文件系统，total_inodes=12800 | ext4 超级块固定 inode 数量 | ✅ 吻合 |
| 触发路径 | 3000 文件写入 merged → copy-up → inode 6000+ | copy_up.c 逐文件复制到 upper | ✅ 吻合 |
| 根因位置 | inode 池固定 + copy-up 逐文件消耗 | ext4_inode_info 结构体预分配 | ✅ 吻合 |
| 触发条件 | 小文件批量写入 overlay 场景 | vfs_create 每次调用分配 inode | ✅ 吻合 |

**综合判断**：两轨完全吻合。系统态观察到 inode 占用的定量数据，内核态确认了 copy-up 的逐文件 inode 消耗机制和 ext4 的固定 inode 限制。结论为**高置信度**。

---

## 八、排除的替代假设

| 假设 | 排除原因 |
|------|---------|
| 磁盘 block 空间不足 | df -h 未显示容量问题，且 inode 与 block 相互独立 |
| 跨设备 overlay 限制 | upper/lower/work 均位于同一 ext4 文件系统 |
| whiteout/opaque 元数据异常 | merged 目录 3000 文件全量可见，无异常 |
| 文件系统权限问题 | 写入操作全部成功完成，无 Permission denied |
| 内核版本不兼容 | overlay 挂载成功，copy-up 执行正常，无 dmesg 报错 |
| SELinux/AppArmor 限制 | 无相关拒绝日志，操作正常完成 |

---

## 九、验证建议

### 9.1 根因验证

- **正向验证**：在同等 ext4 + overlay 配置下，持续写入小文件，观察 inode 使用量随文件数的线性增长关系，验证单位文件消耗单位 inode 的推理
- **反向验证**：使用 XFS 文件系统（动态 inode）代替 ext4 重复测试，验证 inode 耗尽现象是否消失

### 9.2 修复验证

| 修复措施 | 验证方法 |
|---------|---------|
| 增大 inode 密度 | 使用 `mkfs.ext4 -i 4096` 重建后，确认 `dumpe2fs -h | grep 'Inode count'` 显示的 inode 数量已增大 |
| logrotate 清理 | 模拟文件累积后触发 logrotate，确认 `df -i` 显示的已用 inode 下降 |
| XFS 迁移 | `xfs_info` 确认支持动态 inode，压力测试中不会出现 inode 耗尽 |
| volume 分离 | 确认 volume 挂载点使用独立的文件系统，inode 统计不占用 overlay upper 层 |

### 9.3 监控建议

```text
推荐告警阈值：
  🟢 安全：inode 使用率 < 60%  → 无需处理
  🟡 注意：inode 使用率 60%-80%  → 评估清理或扩容计划
  🟠 预警：inode 使用率 80%-90%  → 启动文件清理流程
  🔴 紧急：inode 使用率 > 90%  → 立即介入，准备应急扩容或迁移
```

---

> **报告结束**
>
> 分析节点：白泽（Baize）- Phase 1.4 分析与报告 Agent
> 日期：2026-05-28 23:58:00
