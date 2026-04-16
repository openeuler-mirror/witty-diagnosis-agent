---
name: offline-file-system-fault-diagnosis
description: 通过分析服务器离线日志（iBMC、OS Messages、InfoCollect）诊断 Linux 文件系统（EXT4/XFS）逻辑损坏、挂载异常及存储关联性故障并定位根因。当用户提供日志并询问文件系统只读（Read-only）、挂载失败（Mount Failure）、元数据损毁（Metadata Corruption）、空间/Inode 耗尽、I/O 错误引发的逻辑一致性问题，以及需要针对文件系统进行异常溯源时，调用本技能。
---

# 离线文件系统故障诊断

本技能通过分析从服务器收集的标准日志文件，帮助诊断 Linux 文件系统（EXT4/XFS）及底层存储子系统故障。

## 技能目录结构

本技能的目录结构如下，包含诊断脚本、参考资料和文档：

```text
offline-file-system-fault-diagnosis/
├── SKILL.md                          # 本技能的主文档
├── scripts/                          # 诊断脚本目录
│   ├── diagnose_summary.py           # Step 0: 故障日志采集脚本
│   ├── diagnose_ibmc.py              # Step 2: iBMC日志分析脚本
│   ├── diagnose_infocollect.py       # Step 2: InfoCollect/磁盘与文件系统专项分析脚本
│   └── diagnose_messages.py          # Step 2: OS消息日志分析脚本
└── references/                       # 参考资料目录
    ├── FS_fault_scenarios.md         # 文件系统故障场景分类
    ├── FS_scenario_analysis.md       # 文件系统故障场景专项分析指南
    ├── infocollect_guide.md          # InfoCollect诊断指南
    ├── messages.md                   # OS消息日志分析指南
    ├── huawei_ibmc.md                # 华为iBMC分析指南
    ├── h3c_ibmc.md                   # H3C iBMC分析指南
    └── Inspur_ibmc.md                # Inspur iBMC分析指南
```

## 输入日志目录结构与对应诊断脚本

以 `/path/to/logs/xxxx` 为例，标准的服务器日志收集包通常具有以下层级结构。本技能提供了针对性的脚本来分析不同层级的日志。

> **注意**：在实际场景中，用户提供的日志包可能不完整，可能仅包含以下三种目录中的一种或多种。请根据实际存在的日志类型灵活选择对应的分析脚本。

```text
<日志根目录> (例如: 10.120.6.76)
├── ibmc_logs/                  # iBMC 硬件带外管理日志
│   └── (硬件报错/槽位告警) -> 使用 scripts/diagnose_ibmc.py
├── infocollect_logs/           # 系统信息收集工具生成的分类日志
│   └── (SMART信息/文件系统位图/分区表) -> 使用 scripts/diagnose_infocollect.py
└── messages/                   # 操作系统层面的系统日志
    └── (dmesg, syslog, messages) -> 使用 scripts/diagnose_messages.py
```

## ⚠️ 强制执行流程

**必须严格按以下顺序执行，禁止跳过或乱序：**

```
Step 0 (故障日志采集) → Step 1 (场景分类) → Step 2 (深入分析) → Step 3 (根因校验) → Step 4 (界面输出分析报告)
```

**执行规则：**
1. **顺序强制**：必须完成当前步骤并验证通过后，才能进入下一步
2. **场景分支**：Step 1 输出场景标签后，Step 2 必须针对性收集相关证据
3. **数据校验**：Step 3 必须通过证据矩阵校验后才能得出最终结论
4. **文件适配**：日志文件不全时自动降级分析策略，但必须至少有一个日志文件
5. **专注文件系统**：分析过程应聚焦文件系统元数据（Metadata）、日志（Journal）及空间分配逻辑，厘清逻辑损毁与底层 I/O 异常的因果链。

**每步完成标志：**
- Step 0：输出日志文件时间范围、文件统计、错误关键词概览
- Step 1：确定故障场景（如 FS_CORRUPTION 等）
- Step 2：输出底层物理/元数据层级的精准定位、传导链及初步根因
- Step 3：输出根因证据校验表、原生日志证据及置信度定性
- Step 4：在界面上按固定结构输出最终的分析报告（**严禁生成独立文件**）

---

## 分析流程总览

| **步骤** | **阶段目标** | **主要工具/方法** |
| :--- | :--- | :--- |
| **Step 0** 故障日志采集 | 全量扫描日志目录并识别关键报错 | `python3 scripts/diagnose_summary.py <log_dir>` |
| **Step 1** 场景分类 | 判定现象并确定故障场景类型 | 根据 Step 0 结果参考 [FS_fault_scenarios.md](references/FS_fault_scenarios.md) 匹配 |
| **Step 2** 深入分析 | 构建起止 T0 的传导链并执行专项诊断 | 参考 [FS_scenario_analysis.md](references/FS_scenario_analysis.md) 获取多维证据 |
| **Step 3** 根因校验 | 交叉质询证据链，执行证据双向校验 | 对比 iBMC/内核/系统日志的一致性，防止结论发散 |
| **Step 4** 界面输出分析报告 | 汇总证据链与确认根因，在界面直接输出报告内容 | 结构化输出：结论 + 故障链条 + 修复建议 |

---

## Step 0：故障日志采集

### 全量扫描（宏观分析）

**目标**：快速扫描所有日志文件，识别磁盘及存储子系统的异常，建立故障全景视图。当存在特定报错或时间范围时，利用参数进行第一轮初步精确定位。

**执行命令**（根据场景选择）：
```bash
# 场景 1：无明确过滤条件（默认全量扫描）
python3 scripts/diagnose_summary.py <log_dir>

# 场景 2：用户提供故障关键词时
python3 scripts/diagnose_summary.py <log_dir> -k "disk_fail" "slot0"

# 场景 3：用户提供故障发生时间/日期时
python3 scripts/diagnose_summary.py <log_dir> -d "Mar 16"
python3 scripts/diagnose_summary.py <log_dir> -s "2026-03-10 08:00:00" -e "2026-03-10 12:00:00"
```

### 精细定位（微观分析）

**目标**：在优先使用上述带有参数的扫描命令锁定范围的基础上，结合全量扫描结果，辅以 `grep` / `less` 等文件操作命令查看更细节的原始日志上下文。

> **注意：使用脚本时，可优先执行 `--help` 参数，了解脚本多维度过滤用法。**

---
## Step 1：场景分类

根据 Step 0 采集的日志概览，分析故障现象并确定故障场景类型。

### 场景分类概述

根据 Step 0 采集的日志概览，分析故障现象并从以下标准场景中确定故障场景类型。

> 📖 **参考详见**：[文件系统故障场景分类](references/FS_fault_scenarios.md)

| 场景标签 | 中文描述 | 主要特征 |
| :--- | :--- | :--- |
| `FS_CORRUPTION` | 文件系统损毁 | `EXT4-fs error`、`XFS: Metadata corruption`、`fsck` 报错、位图/校验和不一致 |
| `FS_MOUNT_ERROR` | 逻辑挂载异常 | `Mount failed`、`Structure needs cleaning`、UUID 变更、`/etc/fstab` 配置冲突 |
| `FS_IO_ERROR` | 内核 I/O 报错 | `Buffer I/O error`、`I/O error`、`Device error` (引发 FS 切只读的核心诱因) |
| `FS_SPACE_ISSUE` | 空间/索引耗尽 | `No space left on device`、`Inode exhausted`、大文件残留、配额 (Quota) 限制 |
| `STORAGE_INDUCED_FS_ERR` | 存储诱发的 FS 故障 | 底层磁盘/RAID 硬件故障（如 Drive Fault/Media Error）直接导致的文件系统不可用 |
| `FS_PERMISSION_CONFIG` | 权限与系统配置问题 | `Permission denied`、SELinux 阻断、ACL 异常、挂载参数 (Mount Options) 冲突 |

### 场景辅助分析与根因假设

确定场景标签后，**必须参考专项分析指南**进行候选根因的初步验证：

> 🔍 **专项分析指南**：[文件系统故障场景专项分析指南](references/FS_scenario_analysis.md)

| 场景标签 | 候选根因假设（需在 Step 2 中验证） |
| :--- | :--- |
| `FS_CORRUPTION` | ① 异常断电导致元数据未落盘 ② 磁盘物理坏道损毁关键元数据 ③ 内核/驱动 Bug 导致的逻辑破坏 |
| `FS_MOUNT_ERROR` | ① 文件系统超级块 (Superblock) 损坏 ② 挂载点目录被占用或存在依赖冲突 |
| `FS_IO_ERROR` | ① 磁盘介质老化/损坏 ② SAS 链路抖动触发超时重试 ③ RAID 卡缓存故障 |
| `FS_SPACE_ISSUE` | ① 隐藏进程占用已删除的大文件句柄 ② 小文件过多耗尽 Inode ③ 磁盘配额已满 |
| `STORAGE_INDUCED_FS_ERR` | ① 磁盘硬件物理失效 (Offline) ② RAID 阵列降级或崩溃 ③ 存储链路徹底中断 |
| `FS_PERMISSION_CONFIG` | ① 运维操作导致 ACL 被误改 ② 只读模式挂载 (RO) 保护 ③ 容器/虚拟化命名空间隔离 |

> ⚠️ **强制要求**：在进入 Step 2 深入分析前，应先通过 [FS_scenario_analysis.md](references/FS_scenario_analysis.md) 了解对应场景的分析路径。分析结束后，必须对上述候选根因方案逐一标注：✅ 已证实 / ❌ 已排除 / ❓ 证据不足。

**Step 1 完成标志：**
1. ✅ 确定主要故障场景标签（从上述类型中选择）
2. ✅ 记录故障现象与关键证据
3. ✅ 为 Step 2 深入分析提供明确的故障场景方向

---
## Step 2：深入分析

根据 Step 1 的场景分类结果，必须**首先完成时序关联与故障传导链重建**，然后再通过多源脚本收集证据，最终给出精确的物理/逻辑坐标定位。

### 2.1 时序关联与传导链重建 (核心理论框架)

**目标**：通过多源日志的时间戳对齐，重建故障发生的完整时间轴，厘清事件的先后顺序与因果链，为根因定位提供时序证据。

#### 2.1.1 确定文件系统故障零点 (T0)

故障零点（T0）是时序分析的基准锚点，定义为**最早可观测到异常的时间戳**。确定优先级（由高到低）：

| 优先级 | 来源 | 说明 |
|----|----|----|
| **P1** | 硬件错误日志（iBMC / SEL） | 底层物理故障时间点最准确（如 Power Loss, Drive Fault）。 |
| **P2** | 内核感知层（`dmesg` / `messages`） | 最早出现的 I/O Error 或 EXT4/XFS Metadata Error。 |
| **P3** | 系统调度层（`syslog` / `messages`） | systemd 挂载失败、服务启动超时或 OOM 触发。 |
| **P4** | 应用感知层 | 数据库由于 IO 缓慢产生的报错，通常滞后于内核层。 |

#### 2.1.2 多维日志对齐与时间轴矩阵

以 T0 为基准，构建事件序列矩阵。
*示例：因异常断电导致文件系统损坏的时间轴*
```text
T0-2m   ├─ [iBMC SEL]    记录 `Power Loss` 外部供电失效告警。
T0      ├─ [iBMC SEL]    系统由于过温或供电不足触发强制下电。
T0+1m   ├─ [OS restart]  系统重启，内核加载存储驱动并尝试挂载根分区之外的文件系统。
T0+1.5m ├─ [OS dmesg]    `EXT4-fs (sdb1): error loading journal` → 标定为致命故障节点 T0'。
T0+2m   ├─ [OS messages] `Failed to mount /data: Structure needs cleaning`。
```

#### 2.1.3 文件系统故障传导链推断 (示例)

结合对齐的时间轴矩阵，运用以下规则推导故障传导链方向：
- **规则一：自下而上（硬件/介质诱发）**
  - *传导链*：磁盘物理坏道 (T0) → 触发底层 I/O Error → 文件系统元数据读取失败 (Corruption) → 触发内核安全保护并 `Remount read-only`。
- **规则二：逻辑向应用传导（配置/空间诱发）**
  - *传导链*：日志异常膨胀 (T0) → 触发 `No space left` → 元数据/日志提交失败 → 导致应用数据库死锁或服务退出。

> ⚠️ **精确定位强制要求**：在文件系统诊断中，**严禁仅使用“文件系统损坏”这类含糊结论。**
> 必须给出明确的“逻辑-物理”映射定位，例如：
> - ✅ 正确结论：`Mount Point: /data (Device: /dev/sdb1) -> Slot 3 -> EXT4 Metadata Corruption -> Block 98304`。
> - ❌ 错误结论：`由于 I/O 错误导致挂载失败` 或 `磁盘损坏`。

#### 2.1.4 存储数据流拓扑梳理

在推断故障传导链的同时，必须梳理受影响的存储数据拓扑网络（即从用户业务层直达物理磁盘层的映射关系），以便确认底层/文件系统异常最终影响的业务挂载点。明确映射关系：
- 挂载点，即用户入口（例如 `/data/vols/vol13/phenix_data`） → 文件系统类型（例如 `ext4`/`xfs`） → 对应的分区或 LVM 逻辑卷（例如直接分区块设备 或 `/dev/mapper/xxx`） → 发生告警/故障的真实底层物理磁盘设备（例如 `/dev/sda`）。

---

### 2.2 日志脚本分析执行 (执行工具动作)

#### 2.2.1 通用分析流程

```bash
# iBMC 日志分析（硬件层）
python3 scripts/diagnose_ibmc.py <log_dir>

# InfoCollect 日志分析（系统信息层）
python3 scripts/diagnose_infocollect.py <log_dir>

# OS Messages 日志分析（操作系统层）
python3 scripts/diagnose_messages.py <log_dir>
```

> **注意：使用脚本时，可优先执行 `--help` 参数，了解脚本多维度过滤用法。**

#### 2.2.2 按场景专项分析

当 Step 1 确定故障场景后，优先分析对应的关键指标：
1. **文件系统损坏**：重点查看 `dmesg` 中的元数据校验错误及 `infocollect` 中的文件系统位图信息。
2. **磁盘硬件故障**：重点查看 SMART 中的 `Reallocated_Sector_Ct`。
3. **空间/索引耗尽**：重点查看 `df -i` 和 `df -h` 的各项指标。

**Step 2 完成标志**：
1. ✅ 输出故障零点 T0 的精确时间戳及其所依托的具体日志行。
2. ✅ 梳理出以 T0 为基准的结构化事件序列矩阵与至少 3 步的确定故障传导链。
3. ✅ 给出精确到设备文件名（/dev/sdX）和物理槽位（Slot ID）的定位结果。
4. ✅ 收集脚本产出的相关原生日志片段作为强有力的支撑证据。
5. ✅ 成功梳理出底层设备故障/逻辑盘直达业务挂载点的**重点存储数据流拓扑映射关系**。

---
## Step 3：根因反思与证据双向校验 (Cross-Examination Rules)

**目标**：对 Step 2 输出的“初步传导链与定位结果”进行“交叉质询”，确保结论 100% 由底层日志支撑。

### 3.1 交叉质询铁律 (Cross-Examination Rules)

1. **孤证不立原则**：任何涉及 I/O 错误引起的文件系统问题，必须同时在内核日志（dmesg）和存储层（SMART/RAID 卡日志/iBMC）找到独立证据。
2. **逻辑闭环原则**：从 T0 到最终故障结果，传导链不允许出现逻辑断层。例如：判定为“由于坏道导致”，则必须找到对应的物理扇区重映射记录。
3. **互斥排异原则**：判定为文件系统自身损坏前，必须排除外部因素（如链路抖动、驱动版本 Bug 或人为 rm -rf）。

### 3.2 强制：根因证据校验表 (Evidence Validation Matrix)

在确认最终结论前，强制要求进行证据校验：

| 校验维度 | 校验标准要求 | 强制证据格式（分析打样要求） |
| :--- | :--- | :--- |
| **E1: 时序连续性** | 底层报错 (I/O/Power) 是否早于或同步于文件系统报错？ | `[✅/❌ 结果]` + `时序对齐说明` + `[绝对路径 : 行号/行号范围]` + `原生日志片段` |
| **E2: 逻辑-物理同一性** | 报错的设备节点 (/dev/sdX) 与物理槽位 (Slot Y) 是否指向同一单元？ | `[✅/❌ 结果]` + `设备与槽位映射日志梳理` + `[绝对路径 : 行号/行号范围]` + `原生日志片段` |
| **E3: 现象排他性** | 是否排除了系统 OOM、网络挂载延迟或人为误删等非存储因素？ | `[✅/❌ 结果]` + `主动排异日志及逻辑说明` + `[绝对路径 : 行号/行号范围]` + `原生日志片段` |

### 3.3 结论防发散拦截机制 (Anti-Hallucination Mechanism)

*   **断链阻断**：若无法从日志中找到证明因果传导的片段，强制触发流程拦截，回溯重新收集。
*   **降级处分**：若确实缺乏某一层关键日志，必须在报告中声明为**“疑似故障 (Suspected)”**并标注证据断层位置。
*   **严禁用词限制**：在证据链未能满足完全闭环标准前，**严禁**使用“肯定”、“必然”等决定性断言。

**Step 3 完成标志**：
1. ✅ 结构化地产出《根因证据校验表》中每一项的自查结论。
2. ✅ 每个通过项均附带 Trace 日志中的 Timestamp、Text 以及其明确的 [绝对路径 : 行号/行号范围]。
3. ✅ 输出与之等位置信度（已证实 / 高度疑似 / 逻辑推断）的严谨研判方向。

---
## Step 4：界面输出分析报告

汇总 Step 0～3 的所有分析结果，直接在当前对话界面输出结构化的诊断结论。**禁止生成任何额外的文档或报告文件。**

**报告结构：**

1. **Executive Summary（故障摘要）** — **严禁使用笼统回答，必须包含以下三要素**：
   - **具体设备或挂载点信息**（例如：明确指出具体的设备名 `/dev/sdX`、分区及文件系统挂载路径）。
   - **具体的根因故障**（例如：具体的“EXT4 元数据超级块物理损毁”或“Journal 日志加载失败”，而非宽泛的“文件系统错误”）。
   - **业务后果概述**（例如：该故障对应用层的直接影响，如“导致数据库分区无法挂载，业务启动失败”或“触发内核保护机制导致分区只读”）。
2. **Storage Data Flow（存储数据流拓扑）** — **必须呈现从业务感知层到底层故障部件的数据流向映射关系：**
   - 必须按层级包含以下上下游映射关系及路径节点名：**挂载点（用户入口，如 `/data/vols/vol13/phenix_data`） → 文件系统（如 `ext4/xfs`） → 分区/LVM逻辑卷 → 真实故障物理磁盘设备（如 `/dev/sda`）**。
3. **Fault Chains（故障链条分析）** — **必须包含以下两级链条：**
   - **故障时间链 (Fault Time Chain)**：列出带关键节点的事件序列，**每个节点必须包含准确的时间戳及对应的出处 `[绝对路径 : 行号/行号范围]`**。
   - **故障传导链 (Fault Propagation Chain)**：清晰描绘导致系统表现的因果路径（例如：`RAID卡电池失效 -> 写策略降级 -> I/O 延迟剧增 -> 文件系统由于超时被动切为 Read Only`）。
4. **Technical Analysis & Root Cause（技术分析与根因）** — 基于 Step 2 的传导链底层回溯与 Step 3 的交叉质询得出的物理级或配置级根因，并提供多源证据链（E1/E2/E3）支撑。**🔴 强制约束：针对提供证明此根因或结论对应的原生日志片段，必须强制标明其确切证据出处，格式统一为 `[绝对路径 : 行号/行号范围]`。溯源路径必须是从系统中可查找的完整绝对路径，严禁截断。**
   - ✅ 正确示例：`[/path/to/logs/ibmc_logs/maintenance/sel.log : 1024]`
   - ❌ 错误示例：`[sel.log : 1024]`（丢失路径）或 `[maintenance/sel.log : 1024]`（路径不完整）
5. **Recommendations（修复建议）** — 立即操作、备件更换建议及预防性检查


**诊断分析完成性拦截检查（不满足条件时强行熔断回溯，严禁盲目输出报告）：**

在得出结论前，核心系统（作为自我审查器）必须强制执行以下内部清单确认拦截：
- [ ] ⚠️ 关键校验 1：报告中是否已经完整包含并格式化输出了直探底部物理硬件的**挂载存储数据流映射关系结构**？
- [ ] ⚠️ 关键校验 2：所有关键证据或者日志引用的出处，是否都已经无遗漏地指明了它的**完整绝对路径（而非仅文件名或相对路径）与精准行号/行号范围**？
- [ ] 是否给出了精确的**设备名**（/dev/sdX）及对应的**物理槽位号**（Slot ID）？
- [ ] Step 1 场景假设矩阵是否已完成 ✅/❌ 标注？
- [ ] 是否排除了文件系统逻辑以外的底层硬件或存储链路干扰？
- [ ] **故障时间链中的每一个节点是否都有准确的时间和对应的溯源出处 `[绝对路径 : 行号/行号范围]`？**
- [ ] **是否清晰勾勒并输出了故障传导链？**

---

## 参考资料

* [文件系统故障场景分类](references/FS_fault_scenarios.md)
* [文件系统故障场景专项分析指南](references/FS_scenario_analysis.md)
* [InfoCollect 诊断指南](references/infocollect_guide.md)
* [OS Messages 诊断指南](references/messages.md)
* [Huawei iBMC 分析](references/huawei_ibmc.md)
* [H3C iBMC 分析](references/h3c_ibmc.md)
* [Inspur iBMC 分析](references/Inspur_ibmc.md)

---
