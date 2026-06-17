---
name: block-dm-raid-diagnosis
description: >
  块设备 / Device-Mapper / 软 RAID / LVM / multipath 诊断技能。
  覆盖 LVM 层(thin pool 满、PV/VG/LV 缺失、snapshot 溢出)、
  md 软 RAID 降级/重建/mismatch、multipath 路径失效/抖动与 failover、
  块设备 IO 错误传播(EIO)、IO 调度器(mq-deadline/bfq)异常、
  request queue 卡死、设备只读切换等场景。
  采用"块层 → DM/MD 映射栈 → 物理设备"自上而下定位。
  当用户提到磁盘 IO 慢、设备只读、RAID 降级、LVM 异常、multipath 路径失效、
  IO 错误、dmesg I/O error、D 状态进程堆积、文件系统卡死怀疑块设备问题时，
  必须使用本技能。
---

# 块设备 / DM / 软 RAID / LVM / Multipath 诊断 Skill

## 重要原则

1. **只读诊断**：本 skill 仅进行信息收集和分析诊断，**不执行任何修复命令**，只给出修复建议
2. **修复风险提示**：所有修复建议必须标注风险等级（高/中/低）和回滚方案
3. **禁止自动修复**：绝对禁止自动执行任何修复命令（包括 mdadm 操作、dmsetup 命令、LVM 变更等）
4. **层层递进**：采用**三堆栈下钻模型**（块层 L1 → DM/MD 映射栈 L2 → 物理设备 L3），必须逐层收敛

---

## 文件结构

```
block-dm-raid-diagnosis/
├── SKILL.md                           # 诊断流程文档（本文）
├── scripts/
│   ├── collect_blk_info.sh            # 【基线】全量信息采集脚本
│   ├── branch_A_block_layer.sh        # 分支A：块层/IO 调度器/请求队列
│   ├── branch_B_dm_stack.sh           # 分支B：Device-Mapper 映射栈
│   ├── branch_C_md_raid.sh            # 分支C：md 软 RAID（降级/重建/mismatch）
│   ├── branch_D_lvm.sh                # 分支D：LVM（PV/VG/LV/thin/snapshot）
│   ├── branch_E_multipath.sh          # 分支E：multipath（路径失效/failover）
│   ├── branch_F_io_scheduler.sh       # 分支F：IO 调度器异常/队列卡死
│   └── branch_H_mixed.sh              # 分支H：混合/复杂故障
└── references/
    ├── block_commands.md              # 块设备诊断命令速查
    └── fault_patterns.md              # 块设备故障模式目录
```

---

## 三堆栈下钻模型

块设备诊断采用**三堆栈下钻模型**，从应用/文件系统视角逐层深入物理设备：

```
┌─────────────────────────────────────────────────────────────────┐
│                    三堆栈下钻分析模型                              │
│                                                                 │
│   L1: 块层                  /sys/block/*/stat, iostat, blktrace  │
│       ├─ 判断是否块层 IO 异常？                                    │
│       ├─ IO 调度器(mq-deadline/bfq) 是否正常？                     │
│       └─ request queue 是否有卡死/冻结？                          │
│                                                                 │
│   L2: DM/MD 映射栈         dmsetup, mdadm, lvm, multipath -ll    │
│       ├─ DM 设备表是否正确？                                      │
│       ├─ md RAID 是否降级/重建中？                                 │
│       ├─ LVM PV/VG/LV 状态是否正常？                              │
│       └─ multipath 路径是否冗余？                                  │
│                                                                 │
│   L3: 物理设备             smartctl, /sys/block/*/device/, dmesg  │
│       ├─ 磁盘是否健康？                                            │
│       ├─ 是否有硬件错误/链路问题？                                   │
│       └─ 是否有 EIO 传播？                                         │
│                                                                 │
│            ↓                                   ↓                 │
│      基线采集(collect_blk_info.sh) → 分支决策 → 分支模块 → 根因    │
└─────────────────────────────────────────────────────────────────┘
```

| 层级 | 分析内容 | 核心命令 | 典型发现 |
|------|---------|---------|---------|
| **L1** | 块层 IO 性能与队列 | `iostat -x`, `cat /sys/block/*/stat` | %util=100%, await>50ms, IO 在 D 状态堆积 |
| **L2** | DM/MD 映射栈 | `dmsetup table`, `mdadm -D`, `lvs -a`, `multipath -ll` | RAID 降级、thin pool 100%、路径失效 |
| **L3** | 物理磁盘健康 | `smartctl -a`, `cat /sys/block/*/device/model` | SMART 错误、EIO、linkreset 计数高 |

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
bash scripts/collect_blk_info.sh
```

脚本输出按区块组织，包括：
- **Section A** — 系统概要（kernel、发行版、内存、mount）
- **Section B** — 块设备列表（lsblk 拓扑）
- **Section C** — IO 性能统计（iostat -x）
- **Section D** — 块设备队列参数（scheduler、nr_requests、rq_affinity）
- **Section E** — DM 设备（dmsetup ls、dmsetup table、dmsetup status）
- **Section F** — md RAID 状态（/proc/mdstat、mdadm -D）
- **Section G** — LVM 状态（pvs、vgs、lvs、lvs -a）
- **Section H** — multipath 状态（multipath -ll）
- **Section I** — 内核日志（dmesg 块/SCSI/dm/md 相关）
- **Section J** — D 状态进程检查

执行原则：所有命令超时时间 5s，避免被挂起 IO 阻塞。

#### 步骤 3：场景识别与分支决策

根据基线采集结果选择分支：

```
基线信息评估
  │
  ├─ L1 块层异常
  │   ├─ %util=100% 且 await>50ms                  → 分支A: 块层 IO 瓶颈
  │   ├─ 调度器非预期切换/参数异常                    → 分支F: IO 调度器异常
  │   └─ D 状态进程大量堆积且关联块设备                → 分支A + 上游分支
  │
  ├─ L2 映射栈异常
  │   ├─ dmsetup 表不完整 / DM 设备 missing          → 分支B: DM 映射栈
  │   ├─ /proc/mdstat 显示 [UU_] 或 [___]            → 分支C: md 软 RAID
  │   ├─ LVS 显示 thin pool 100% / snapshot overflow → 分支D: LVM
  │   ├─ PV missing / VG incomplete / LV inactive     → 分支D: LVM
  │   └─ multipath 路径 failed/undef/ghost            → 分支E: multipath
  │
  ├─ L3 物理设备异常
  │   ├─ dmesg 显示 I/O error / Buffer I/O error     → 分支A + L3 检查
  │   ├─ smartctl 显示 Reallocated_Sector_Ct > 0     → L3 物理磁盘诊断
  │   └─ 设备只读切换 (remounting read-only)          → 分支A + L3
  │
  └─ 混合现象或以上分支无法覆盖                       → 分支H: 混合/复杂故障
```

若基线输出推荐多个分支，须按 L1 → L2 → L3 顺序全部执行。

---

### 阶段二：逐层深入分析

#### L1: 块层分析（对应 分支A + 分支F）

##### IO 性能瓶颈（分支A）

```bash
bash scripts/branch_A_block_layer.sh [device]
```

**分析要点：**

1. **IO 吞吐量**（Section C）
   - `r/s`、`w/s`：IOPS 是否符合预期
   - `rkB/s`、`wkB/s`：吞吐量是否正常
   - `%util`：是否持续 100%（IO 瓶颈信号）
   - `await`：平均 IO 响应时间（正常 <10ms，异常 >50ms）

2. **请求队列**（Section D）
   - `nr_requests`：队列深度是否合理
   - `rq_affinity`：CPU 亲和性设置
   - 队列是否被冻结（`/sys/block/*/queue/state`）

3. **IO 错误传播**
   - 块设备是否进入只读状态（`/sys/block/*/ro`）
   - dmesg 中是否有 I/O error 直接对应的设备路径

| 指标 | 正常值 | 异常值 | 诊断结论 |
|-----|-------|-------|---------|
| %util | <70% | >90% | IO 瓶颈 |
| await | <10ms | >50ms | IO 响应慢 |
| 队列深度 | 设备特定 | 持续满队列 | 请求排队 |
| D 状态进程 | 0-1个 | 多个 | IO 等待严重 |

##### IO 调度器异常（分支F）

```bash
bash scripts/branch_F_io_scheduler.sh [device]
```

**分析要点：**

1. **调度器类型**：当前使用的调度器（mq-deadline/bfq/kyber/none）
2. **调度器参数**：
   - mq-deadline：`read_expire`、`write_expire`、`fifo_batch`
   - bfq：`weight_low_bound`、`weight_high_bound`、`timeout_sync`
3. **调度器切换历史**：是否有非预期切换
4. **写星号现象**：bfq 下是否有写请求被长时间饿死

#### L2: DM/md/LVM/multipath 映射栈分析

##### DM 映射栈（分支B）

```bash
bash scripts/branch_B_dm_stack.sh
```

**分析要点：**

1. **DM 设备拓扑**：`dmsetup ls --tree` 展示设备依赖关系
2. **DM table 检查**：每个 DM 设备的映射表是否正确
3. **DM status 检查**：thin pool 数据/元数据使用率
4. **DM 错误计数**：`dmsetup status` 中的 error 计数

##### md 软 RAID（分支C）

```bash
bash scripts/branch_C_md_raid.sh [md_device]
```

**分析要点：**

1. **RAID 级别与状态**：/proc/mdstat 中的 [UU_] 标记
   - `[UU]`：2 盘正常
   - `[U_]`：1 盘失效（降级）
   - `[___]`：完全失效
2. **重建进度**：`resync=` / `recovery=` 百分比
3. **mismatch_cnt**：`/sys/block/mdX/md/mismatch_cnt` 数据一致性计数
4. **磁盘事件计数**：每个成员的 `events` 计数器是否一致

```text
mdX : active raid5 sdb1[0] sdc1[1] sdd1[3]
      [U_U]  → RAID5 降级，一块盘丢失
      resync=42.5% → 正在重建
```

| RAID 模式 | 降级影响 | 重建触发条件 |
|-----------|---------|------------|
| RAID0 | 完全失效 | 不可重建 |
| RAID1 | 读性能不变，写镜丢失 | 替换磁盘后自动重建 |
| RAID5 | 性能严重下降 | 替换磁盘后自动重建 |
| RAID10 | 受影响但可用 | 替换磁盘后自动重建 |

##### LVM 诊断（分支D）

```bash
bash scripts/branch_D_lvm.sh
```

**分析要点：**

1. **PV 状态**（Section G）：`pvs` 检查每个 PV 是否 active
   - `missing` 标记 → 物理卷丢失
   - `unknown device` → 设备不可访问
2. **VG 状态**：`vgs` 检查 VG 是否完整
   - `incomplete` → PV 缺失导致 VG 降级
   - `exported` → VG 被导出
3. **LV 状态**：`lvs -a` 检查每个 LV 是否 active
   - `thin pool` 数据使用率 > 80% → thin pool 满风险
   - `snapshot` 使用率 > 80% → snapshot 溢出风险
   - `activation` 状态 → LV 是否活跃

| LVM 异常 | 症状 | 关键检测命令 |
|----------|------|------------|
| PV missing | VG incomplete，LV 不可用 | `pvs`, `vgdisplay -v` |
| thin pool 满 | 写操作挂起/报错 | `lvs -a`, `dmsetup status thin-pool` |
| snapshot 溢出 | snapshot 自动失效 | `lvs -a`, `lvs -o+snap_percent` |
| LV 不活跃 | 无法挂载 | `lvchange -ay` (仅建议) |
| metadata 损毁 | VG/LV 无法识别 | `vgck`, `pvck` |

##### Multipath 诊断（分支E）

```bash
bash scripts/branch_E_multipath.sh
```

**分析要点：**

1. **路径状态**（Section H）：`multipath -ll`
   - `active/ready`：主路径正常
   - `active/faulty`：路径失效
   - `enabled`：备用路径正常
   - `undef`：路径状态未知
   - `ghost`：路径设备不存在
2. **路径抖动**：检查 `/sys/block/sdX/device/state` 是否在 running↔offline 间切换
3. **failover 事件**：dmesg 中 multipath 路径切换记录
4. **queue_if_no_path**：是否配置了 IO 排队等待路径恢复

| multipath 状态 | 含义 | 影响 |
|---------------|------|------|
| active/ready | 当前活跃路径 | 正常 |
| active/faulty | 路径已失效 | IO 错误 |
| enabled | 备用路径正常 | 冗余正常 |
| undef | 路径状态未知 | 需要排查 |
| ghost | 设备不存在 | 需检查物理连接 |

---

### 阶段三：交叉验证与结论收敛

对每条证据做对齐检查：

| 验证维度 | L1 块层 | L2 映射栈 | L3 物理层 | 是否吻合？ |
|---------|---------|-----------|----------|-----------|
| IO 错误源 | %util、await 异常 | DM/md 返回 EIO | smart/dmesg 错误 | □ 吻合 □ 不符 |
| 设备不可用 | ro 标记 | dm/md 状态异常 | 设备 missing | □ 吻合 □ 不符 |
| 性能下降 | IO 排队 | 映射层延迟 | 磁盘响应慢 | □ 吻合 □ 不符 |
| 只读切换 | ro=1 | dm 错误传播 | FS 只读重挂 | □ 吻合 □ 不符 |

**置信度收敛：**
- **高**：三层完全吻合 + 反事实验证通过
- **中**：两层吻合，一层依赖推断
- **低**：两层及以上依赖推断
- **待定**：用户态证据链完整但无法定位具体设备

---

### 阶段四：输出诊断报告

```markdown
# 块设备/DM/RAID 故障诊断报告

## 基本信息
- 诊断时间：
- 故障时间窗口：
- 故障设备路径：
- 严重级别：（P0/P1/P2/P3）

## 问题确认
**故障现象**：

**影响范围**：

**复现方式**：

## 三堆栈分析结论

### L1 块层结论
- IO 性能：%util / await / r/s / w/s
- 队列状态：nr_requests / scheduler / state
- 错误计数：IO errors / D 状态进程
- 判定：[正常/可疑/异常]

### L2 映射栈结论
- DM 拓扑/状态：
- md RAID 状态：
- LVM PV/VG/LV 状态：
- multipath 路径状态：
- 判定：[正常/可疑/异常]

### L3 物理层结论
- 设备健康（SMART）：
- 链路/硬件错误：
- 判定：[正常/可疑/异常]

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
2. <措施> — 风险等级：[高/中/低]

### 永久措施
1. <措施> — 风险等级：[高/中/低]

### 验证方法
- <验证方法>
```

---

## 故障模式速查表

| 故障模式 | 主要表现 | L1 指标 | L2 指标 | L3 指标 | 诊断命令 |
|---------|---------|---------|---------|---------|---------|
| 块层 IO 瓶颈 | 业务慢、D 状态进程多 | %util=100%, await>50ms | 正常 | 正常 | `iostat -x` |
| IO 调度器异常 | 写延迟高、不公平 | 调度器类型/参数异常 | 正常 | 正常 | `cat /sys/block/*/queue/scheduler` |
| DM 映射错误 | 设备不可访问 | 正常 | dmsetup 表异常 | 正常 | `dmsetup table` |
| md RAID 降级 | 性能下降 | 正常 | [U_] 标记 | 可能盘故障 | `cat /proc/mdstat` |
| LVM thin pool 满 | 写操作挂起 | IO 等待 | thin_data_percent=100% | 正常(SSD) | `lvs -a` |
| LVM snapshot 溢出 | snapshot 失效 | 正常 | snap_percent=100% | 正常 | `lvs -o+snap_percent` |
| multipath 路径失效 | IO 延迟/中断 | 正常 | 路径 faulty/undef | 可能有链路问题 | `multipath -ll` |
| 设备只读 | 写操作返回 EIO | ro=1 | 上层传播 EIO | 磁盘/FS 错误 | `cat /sys/block/*/ro` |
| 物理盘损坏 | EIO、数据丢失 | %util 异常 | 传播 EIO | SMART 错误 | `smartctl -a` |

---

## 注意事项

1. **数据安全**：所有诊断操作均为只读，不会修改系统状态
2. **性能影响**：iostat、smartctl 等命令会产生轻微负载
3. **权限要求**：大部分命令需要 root 权限
4. **超时机制**：所有采集命令应设置 5s 超时，避免被挂起 IO 阻塞
5. **修复风险**：
   - md 操作（如 mdadm --manage --remove）风险高，需严格确认磁盘
   - LVM 操作（如 lvchange）风险中，可能导致数据不可访问
   - multipath 配置变更风险高，可能导致业务中断
6. **dmesg 时效性**：内核环形缓冲区有限，早期日志可能被覆盖
