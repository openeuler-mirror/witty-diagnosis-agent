---
name: X-diagnosis-io
description: |
  专业的 Linux 存储与文件系统在线故障诊断 skill。该 skill 严格限制使用 X-diagnosis 工具栈中的 4 种核心 IO 诊断工具（xd_iolatency, xd_scsiiocount, xd_scsiiotrace, xd_ext4fsstat）进行精准探测。
---

# 在线存储与文件系统故障诊断

本技能旨在利用 Agent 自动化在目标故障主机上实时执行 X-diagnosis IO 工具栈，采用“时延切片、指令追踪、文件级审计”的手段，精准定位块设备与文件系统的内核级性能瓶颈与异常。

## 技能目录结构

本技能包含在线诊断引导脚本与深度参考资料，结构如下：

```text
X-diagnosis-io/
├── SKILL.md                           # 本技能的主文档与流程规范
├── scripts/
│   └── show_location_index.sh         # [Step 1] 快速问题定位索引 (仅含 xd IO 工具)
└── references/
    └── xdiagnosis_reference.md        # [手册] 4 种 xd IO/FS 工具详细说明
```

## ⚠️ 强制执行流程

**必须严格按以下顺序执行，禁止跳过或乱序：**

```
Step 0 (现象确认) → Step 1 (索引对标) → Step 2 (深入交互探测) → Step 3 (证据校验) → Step 4 (输出报告)
```

**执行规则：**
1. **顺序强制**：必须完成当前步骤并验证通过后，才能进入下一步。
2. **“先确认，后探测”**：在进行深度探测前，必须通过标准 OS 命令确认故障现象，防止盲目执行。
3. **XD 工具受限**：诊断时仅允许使用 `xdiagnosis_reference.md` 中列出的 4 种 `xd` 工具，严禁使用其他未说明的复杂诊断工具。
4. **不留冗余**：分析结果展示在回复流中即可，**严禁在目标服务器生成独立分析文件残留**。

---

## 分析流程总览

| **Step** | **阶段目标** | **主要工具/方法** |
| :--- | :--- | :--- |
| **Step 0** | 故障现象初步确认 | `iostat`, `df -h`, `lsblk`, `dmesg`, `mount` |
| **Step 1** | **场景对标与工具匹配** | 执行 `bash scripts/show_location_index.sh` 匹配诊断工具 |
| **Step 2** | **内核深度专项探测** | 运行选定的 `xd_*` 工具进行时序与因果分析 |
| **Step 3** | 三重交叉质询 | 对比 `xd_*` 证据与标准 OS 计数器（如 `iostat` %util） |
| **Step 4** | 结构化诊断报告输出 | 按固定格式输出，核心证据需引用 `xd_*` 结果 |

---

## Step 0：故障现象初步确认

**目标**：通过基础 OS 命令快速锁定故障表现，为 Step 1 的工具匹配提供依据。

**常用命令示例**：
- **负载确认**：`iostat -xz 1 5` (查看 %util, await, svctm)
- **空间与挂载核查**：`df -h`, `mount | grep ext4`
- **内核报错核查**：`dmesg -T | tail -n 50` (寻找 I/O error, SCSI timeout)
- **分区布局**：`lsblk`

---

## Step 1：场景对标与工具匹配

**执行动作**：
执行以下脚本以获取当前故障场景对应的推荐 `xd` 工具：
```bash
bash scripts/show_location_index.sh
```

**匹配决策树简述**：
- **IO 响应慢/卡顿** → `xd_iolatency`
- **SCSI 报错/只读** → `xd_scsiiotrace`
- **写放大/高频命令** → `xd_scsiiocount`
- **文件级写入量统计** → `xd_ext4fsstat`

---

## Step 2：深度交互分析与证据获取

Agent **必须**根据 Step 1 选定的方向，通过专项工具进行深度分析。

**执行动作**：
1. **查阅手册**：必须查阅 `references/xdiagnosis_reference.md` 确定工具参数。
2. **场景探测**：执行 `xd_*` 工具并捕获关键输出（如各阶段耗时分布、SCSI 返回码、Top 写入文件）。

**核心框架：IO 传导链重建**
- **路径溯源**：描述 IO 从应用层下发到物理介质的完整链路，找出耗时异常的切片（如 G2I 还是 D2C）。
- **因果关联**：如“SCSI 命令超时导致文件系统触发保护机制变为只读”。

---

## Step 3：根因反思与交叉校验

### 3.1 交叉质询铁律
1. **统计印证**：`xd_iolatency` 的结论必须与 `iostat` 的 `await` 趋势一致。
2. **资源联动**：排除内存回收（Direct Reclaim）或系统负载对 IO 提交延迟的影响。

### 3.2 证据校验表 (Evidence Validation Matrix)
| 维度 | 校验标准 | 强制证据 |
| :--- | :--- | :--- |
| **E1: 链路定界** | 延迟是发生在 OS 内部还是硬件？ | `xd_iolatency (I2D vs D2C)` |
| **E2: 范围一致** | 报错磁盘是否为业务受损对应的分区？ | `lsblk & mount 对应关系` |
| **E3: 结果解析** | SCSI 错误码是否指向硬件故障？ | `xd_scsiiotrace -p 解析结果` |

---

## Step 4：输出结构化诊断报告

**报告结构要求如下：**

1. **Executive Summary**：故障时间、定性结论（如：磁盘硬件亚健康、应用异常高频写入）。
2. **Fault Chains**：
   - **IO 处理链**：各阶段耗时占比。
   - **传播链**：从底层错误到上层业务报错的演进过程。
3. **Technical Evidences**：**必须引用 `xd_*` 关键输出**，并配合 E1-E3 校验结果。
4. **Recommendations**：调整 IO 调度算法、更换磁盘或优化业务写入模式。

**诊断完备性检查清单：**
- [ ] 是否确认了故障磁盘与挂载点的对应关系？
- [ ] 是否包含 `xd_*` 核心证据（如 IO 阶段耗时分布）？
- [ ] 是否解析了 SCSI 错误码的具体含义？
- [ ] **是否无任何本地诊断文件残留？**
