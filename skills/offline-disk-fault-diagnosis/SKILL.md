---
name: offline-disk-fault-diagnosis
description: 通过分析服务器的【系统级离线日志】——iBMC/SEL 带外日志（磁盘在位/热插拔/错误事件）、OS 系统日志（dmesg、syslog、messages）、InfoCollect 采集日志（SMART 信息/RAID 卡日志/性能数据）——诊断离线磁盘硬件、RAID 控制器及存储链路故障，做多源时序对齐与物理级根因溯源。当用户提供 ibmc_logs / messages（dmesg、syslog）/ infocollect_logs 等服务器日志包，或询问 RAID 掉盘降级（Offline/Degraded）、I/O 超时阻塞（Timeout/Blocked）、SAS/SATA/NVMe 链路不稳定（PHY Reset/ICRC）、物理槽位异常、磁盘巡检/SMART 告警、以及文件系统因底层存储故障切只读（Read-only）需要从 OS+iBMC 日志反查底层根因时，调用本技能。本技能以系统级日志为分析主体；其中希捷 FARM 底层日志（farmlog）仅作为可选的 Step 5 收敛环节。**若用户只提供希捷 FARM 底层日志（farmlog / openSeaChest .json / 华为 disktool .txt，按 IP 目录组织），而无 OS/iBMC/InfoCollect 系统日志，应改用 `seagate-farm-disktool-health-analysis` 技能。**
---

# 离线磁盘故障诊断

本技能通过分析从服务器收集的标准日志文件，重点诊断离线磁盘及存储子系统物理/链路级故障。

## 技能目录结构

本技能的目录结构如下，包含诊断脚本、参考资料和文档：

```text
offline-disk-fault-diagnosis/
├── SKILL.md                          # 本技能的主文档
├── scripts/                          # 诊断脚本目录
│   ├── diagnose_summary.py           # Step 0: 故障日志采集脚本
│   ├── diagnose_ibmc.py              # Step 2: iBMC日志分析脚本
│   ├── diagnose_infocollect.py       # Step 2: InfoCollect/磁盘专项分析脚本
│   ├── diagnose_messages.py          # Step 2: OS消息日志分析脚本
│   ├── diagnose_health_rules.py      # Step 3: 健康度评估与规则匹配脚本
│   └── analyze_farm.py               # Step 5（可选）: FARM 底层日志分析脚本（json 优先/txt 兜底）
└── references/                       # 参考资料目录
    ├── DISK_fault_scenarios.md       # 磁盘故障场景分类表
    ├── DISK_scenario_analysis.md     # 磁盘故障场景专项分析指南
    ├── disk_health_rules.md          # 硬盘健康度评估规则（SAS/SATA 硬故障 + 存活概率）
    ├── infocollect_guide.md          # InfoCollect诊断指南
    ├── messages.md                   # OS消息日志分析指南
    ├── huawei_ibmc.md                # 华为iBMC分析指南
    ├── h3c_ibmc.md                   # H3C iBMC分析指南
    ├── Inspur_ibmc.md                # Inspur iBMC分析指南
    ├── farm_analysis.md              # FARM 底层诊断指南（单快照 · 8 类故障部位）
    └── farm_field_reference.md       # FARM 字段与指标参考字典（json↔txt↔SMART 三方映射）
```

## 输入日志目录结构与对应诊断脚本

以 `/path/to/logs/xxxx` 为例，标准的服务器日志收集包通常具有以下层级结构。本技能提供了针对性的脚本来分析不同层级的日志。

> **注意**：在实际场景中，用户提供的日志包可能不完整，可能仅包含以下三种目录中的一种或多种。请根据实际存在的日志类型灵活选择对应的分析脚本。

```text
<日志根目录> (例如: 10.120.6.76)
├── ibmc_logs/                  # iBMC 硬件带外管理日志
│   └── (磁盘在位/热插拔/错误事件) -> 使用 scripts/diagnose_ibmc.py
├── infocollect_logs/           # 系统信息收集工具生成的分类日志
│   └── (SMART信息/RAID卡日志/性能数据) -> 使用 scripts/diagnose_infocollect.py
├── messages/                   # 操作系统层面的系统日志
│   └── (dmesg, syslog, messages) -> 使用 scripts/diagnose_messages.py
└── farmlog/                    # FARM 底层日志目录 (可选)
    └── (<SN>_FARM_<时间戳>_<IP>_<设备名>.json [openSeaChest, 优先], <SN>_FARM_disktool_<时间戳>_<IP>_<设备名>.txt [华为 disktool, 兜底]) -> 使用 scripts/analyze_farm.py
```

## ⚠️ 强制执行流程

**必须严格按以下顺序执行，禁止跳过或乱序：**

```
Step 0 (故障日志采集) → Step 1 (场景分类) → Step 2 (深入分析) → Step 3 (健康度评估与规则匹配) → Step 4 (根因反思与证据双向校验) → [Step 5 (FARM底层诊断，可选)] → Step 6 (界面输出分析报告)
```

**执行规则：**
1. **顺序强制**：必须完成当前步骤并验证通过后，才能进入下一步
2. **场景分支**：Step 1 输出场景标签后，Step 2 必须针对性收集相关证据
3. **数据校验**：Step 4 必须通过证据矩阵校验后才能得出最终结论
4. **文件适配**：日志文件不全时自动降级分析策略，但必须至少有一个日志文件
5. **专注存储**：分析过程应锁定存储链路及介质，排查文件系统只读等现象的底层诱因。

**每步完成标志：**
- Step 0：输出日志文件时间范围、文件统计、错误关键词概览
- Step 1：确定故障场景（如 DISK_HARDWARE_FAILURE 等）
- Step 2：输出物理级精准定位、传导链及初步根因
- Step 3：输出每块涉事磁盘的基础元数据、判定结论及标准化对象
- Step 4：输出根因证据校验表、原生日志证据及置信度定性
- Step 5（可选）：输出 FARM 逐磁头分析表、8 类故障部位评级与处置建议
- Step 6：在界面上按固定结构输出最终的分析报告（**严禁生成独立文件**）

---

## 分析流程总览

| **步骤** | **阶段目标** | **主要工具/方法** |
| :--- | :--- | :--- |
| **Step 0** 故障日志采集 | 全量/定点扫描日志目录并识别关键报错 | `diagnose_summary.py <log_dir> [-k/-d/-s]` |
| **Step 1** 场景分类 | 判定现象并确定故障场景类型 | 根据 Step 0 采集结果进行场景匹配 |
| **Step 2** 深入分析 | 构建起止 T0 的传导链并执行诊断 | 使用 `diagnose_ibmc.py/diagnose_infocollect.py/diagnose_messages.py` 获取多维证据 |
| **Step 3** 健康度评估与规则匹配 | 对每块涉事磁盘按 SAS/SATA 规则集做客观判定与存活概率计算 | `diagnose_health_rules.py <log_dir> [--format md/json/table]` 配合 [disk_health_rules.md](references/disk_health_rules.md) |
| **Step 4** 根因反思与证据双向校验 | 交叉质询证据链，执行证据双向校验（含 E4 规则一致性） | 对比 iBMC/内核/系统日志的一致性 + 规则评估结果，防止结论发散 |
| **Step 5** FARM 底层深度诊断（可选） | 将故障收敛至磁头/盘面级别，定界 8 类故障部位 | `analyze_farm.py <log_dir>/farmlog`（json 优先/txt 兜底），结合 `farm_analysis.md` / `farm_field_reference.md` 判读 |
| **Step 6** 界面输出分析报告 | 汇总证据链与确认根因，在界面直接输出报告内容 | 结构化输出：结论 + 故障链条 + 规则评估 + 根因 + 修复建议 |

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

> 📖 **参考详见**：[磁盘故障场景分类](references/DISK_fault_scenarios.md)

| 场景标签 | 中文描述 | 主要特征 |
| :--- | :--- | :--- |
| `DISK_HARDWARE_FAILURE` | 磁盘硬件故障 | SMART 阈值超限、UNC/UF 坏道 (MEDIUM ERROR)、WP 写保护报错、磁盘离线 |
| `DISK_IO_PERFORMANCE` | I/O 性能问题 | I/O 延迟高、落盘缓慢 (Await 激增)、块请求堆积、SCSI 指令超时 |
| `DISK_RAID_ERROR` | RAID/控制器故障 | RAID 掉盘、控制器 Cache 故障、电池/超级电容告警、阵列降级 |
| `DISK_LINK_ISSUE` | 链路/背板故障 | 频繁 SAS 链路重置 (PHY Reset)、ICRC/ABRT 接口错误、链路及背板供电不稳定 |
| `STORAGE_INDUCED_FS_ERROR` | 存储诱发的文件系统故障 | 底层 I/O 错误引发文件系统 Remount Read-only（注：纯逻辑 FS 损坏属文件系统技能范畴） |
| `DISK_SYSTEM_CONFIG` | 系统/配置与兼容性限制 | 盘符漂移 (Drift)、磁盘不支持特定指令 (Illegal Request)、磁盘挂载数量过载 |

### 场景辅助分析与根因假设

确定场景标签后，**必须参考专项分析指南**进行候选根因的初步验证：

> 🔍 **专项分析指南**：[磁盘故障场景专项分析指南](references/DISK_scenario_analysis.md)

| 场景标签 | 候选根因假设（需在 Step 2 中验证） |
| :--- | :--- |
| `DISK_HARDWARE_FAILURE` | ① 磁盘物理损坏引发大量坏道 ② 磁盘固件 Bug 导致逻辑死锁/写保护 ③ No Medium/介质丢失 — *此场景下 Step 3 必执行规则评估* |
| `DISK_IO_PERFORMANCE` | ① 磁盘老化导致写缓存落盘缓慢 ② 业务压力超过 IOPS 限制 ③ RAID 背景扫描任务 — *此场景下 Step 3 仍须执行规则评估* |
| `DISK_RAID_ERROR` | ① RAID 卡缓存校验错误 ② 电池能量耗尽导致写策略回退 — *此场景下 Step 3 仍须执行规则评估* |
| `DISK_LINK_ISSUE` | ① SAS 线缆接触不良触发 PHY Reset ② 磁盘背板电气特性不稳定 ③ HBA 接口 CRC 错误 — *此场景下 Step 3 仍须执行规则评估（排除链路问题掩盖介质问题）* |
| `STORAGE_INDUCED_FS_ERROR` | ① 底层介质/链路持续 I/O 错误触发内核安全机制 ② 存储日志写入失败导致日志提交异常 — *此场景下 Step 3 仍须执行规则评估* |
| `DISK_SYSTEM_CONFIG` | ① 挂载未采用 UUID 导致漂移 ② 下发指令与磁盘固件不兼容 ③ 数量超过 HBA/内核上限 — *此场景下 Step 3 仍须执行规则评估* |

> ⚠️ **强制要求**：在进入 Step 2 深入分析前，应先通过 [DISK_scenario_analysis.md](references/DISK_scenario_analysis.md) 了解对应场景的分析路径与关键证据点。分析结束后，必须对上述候选根因方案逐一标注：✅ 已证实 / ❌ 已排除 / ❓ 证据不足。
>
> ⚠️ **Step 3 强制范围**：无论 Step 1 判定为何种场景，Step 3 健康度评估都必须对涉事磁盘执行 [disk_health_rules.md](references/disk_health_rules.md) 全量规则比对。唯一例外是 Step 2 完全无法锚定任何物理磁盘对象（仅有控制器/背板级故障）时，Step 3 输出"无涉事磁盘对象，规则评估不适用"声明。

**Step 1 完成标志：**
1. ✅ 确定主要故障场景标签（从上述类型中选择）
2. ✅ 记录故障现象与关键证据
3. ✅ 为 Step 2 深入分析提供明确的故障场景方向

---
## Step 2：深入分析

根据 Step 1 的场景分类结果，必须**首先完成时序关联与故障传导链重建**，然后再通过多源脚本收集证据，最终给出精确的物理坐标定位。

### 2.1 时序关联与传导链重建 (核心理论框架)

**目标**：通过多源日志的时间戳对齐，重建故障发生的完整时间轴，厘清事件的先后顺序与因果链，为根因定位提供时序证据。

#### 2.1.1 确定磁盘故障零点 (T0)

故障零点（T0）是时序分析的基准锚点，定义为**最早可观测到异常的时间戳**。确定优先级（由高到低）：

| 优先级 | 来源 | 说明 |
|----|----|----|
| **P1** | 硬件错误日志（iBMC / SEL） | 底层致命报错（如 Drive Fault, Hot Plug Removal），时间点最准确。 |
| **P2** | 内核感知层（`dmesg` / `messages`） | 最早出现的 SCSI Error、I/O Error 或 Device Reset。 |
| **P3** | 系统调度层（`syslog` / `messages`） | 系统级重试、文件系统切只读或 OOM 相关 IO 阻塞。 |
| **P4** | 应用感知层 | 业务响应超时、数据库写入失败等应用级异常，通常滞后较大。 |

> ⚠️ **时钟偏差处理**：多节点场景下，需留意 iBMC 时间与 OS 时间（NTP）是否存在时钟偏移。多源对齐时需留意并修正该偏差量。

#### 2.1.2 多维日志对齐与时间轴矩阵

以 T0 为基准，将 iBMC 传感器告警、dmesg 报错、RAID 卡日志和 OS 系统日志统一映射到绝对时间轴上，构建**事件序列矩阵**。
*示例：因底板/背板供电异常导致磁盘掉盘与文件系统只读的时间轴*
```text
T0-5m   ├─ [iBMC SEL]    检测到背板（Backplane）供电电压出现瞬间短幅跌落告警。
T0-1m   ├─ [OS dmesg]    `mpt3sas_cm0: log_info(0x31110d01): originator(PL)...` (频繁出现 SAS 链路重置)。
T0-30s  ├─ [OS iostat]   底层块设备 I/O await 严重阻塞，请求大量堆积，应用层感知死锁。
T0      ├─ [iBMC SEL]    记录 `Drive 8 Fault` 拔出或离线错误 → 标定为致命故障节点 T0。
T0+1m   ├─ [OS messages] 存储写入失败重试达到内核阈值，文件系统触发内核安全保护并触发 `Remount read-only`。
```

#### 2.1.3 磁盘故障传导链推断 (示例)

结合对齐的时间轴矩阵，运用以下规则推导故障传导链方向：
- **规则一：层级自下而上（硬件损坏主导）**
  - *传导链*：磁盘物理损坏 (T0) → 触发底层报错 (SMI/NMI) → 操作系统驱动报错 (I/O Error) → 文件系统切只读。
- **规则二：环境向硬件传导（链路/压力主导）**
  - *传导链*：业务高负载 (T0) → 触发链路重置 (SAS Reset) → RAID 卡性能下降 → 最终应用超时。

> ⚠️ **精确定位强制要求**：在磁盘诊断中，**严禁仅使用“磁盘故障”这类含糊结论。**
> 必须通过证据追踪到细粒度的三维物理坐标定位，例如：
> - ✅ 正确结论：`Slot 4 (Disk Index: 8) -> Media Error -> Reallocated Sectors Exceeded`。
> - ❌ 错误结论：`发生 I/O 错误` 或仅仅说是 `磁盘 sdb 损坏`。

#### 2.1.4 存储数据流拓扑梳理

在推断故障传导链的同时，必须梳理受影响的存储数据拓扑网络（即从用户业务层直达物理磁盘层的映射关系），以便确认底层硬件异常最终影响的业务定损边界。明确逆向映射：
- 挂载点，即用户入口（例如 `/data/vols/vol13/phenix_data`） → 文件系统类型（例如 `ext4`/`xfs`） → 对应的分区或 LVM 逻辑卷（例如直接分区块设备 或 `/dev/mapper/xxx`） → 发生告警/故障的真实底层物理磁盘设备（例如 `/dev/sda`）。

---

### 2.2 日志脚本分析执行 (执行工具动作)

#### 2.2.1 通用分析流程

通用分析流程适用于所有磁盘故障场景，提供基础的日志提取与数据分析能力：

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
1. **磁盘硬件故障**：重点查看 SMART 中的 `Reallocated_Sector_Ct` 和 `Standard_Health_Status`。
2. **I/O 性能问题**：重点查看 `iostat` 中的 `await` 和 `util%`。
3. **RAID故障**：重点查看 `sasraidlog` 中的 `Logical Drive Status` 和 `Battery/Capacitor` 状态。

#### 2.2.3 分析执行原则

1. **场景优先原则**：当故障现象明确匹配某个场景时，优先针对该场景取证。
2. **组合使用原则**：必须同时使用带外（iBMC）和带内（OS）脚本进行相互验证。
3. **逐步深入原则**：从宏观概览开始，逐步根据时序对齐结果深入特定日志行。

**Step 2 完成标志**：
1. ✅ 输出故障零点 T0 的精确时间戳及其所依托的具体日志行。
2. ✅ 梳理出以 T0 为基准的结构化事件序列矩阵与至少 3 步的确定故障传导链。
3. ✅ 给出精确到物理部件（例如 Slot ID / Disk Index）的细粒度定位结果。
4. ✅ 收集脚本产出的相关原生日志片段作为强有力的支撑证据。
5. ✅ 成功梳理出底层设备故障直达业务挂载点的**重点存储数据流拓扑映射关系**。

---
## Step 3：健康度评估与规则匹配（客观硬指标判定）

**目标**：基于客观规则集对 Step 2 识别到的涉事磁盘进行评估，作为硬指标侧验证。

### 3.1 评估对象锚定

从 Step 2 的结果中提取涉事磁盘清单，逐盘抽取以下要素：

| 字段 | 来源 | 缺失时表现 |
| :--- | :--- | :--- |
| `卷_id`（卷标识） | `diskmap.txt` / `mount` / `lsblk` | **必填**；输出缺失原因说明 |
| `SCSI 磁盘设备`（盘符） | smartctl / dmesg / phy_info | 输出缺失原因说明 |
| `物理槽位` | iBMC SEL / sasraidlog | 输出缺失原因说明 |
| `接口类型` | SAS / SATA / NVMe | `"Unknown"` 或原因说明 |
| `型号` / `序列号` | smartctl 信息段 | 输出缺失原因说明 |
| `容量` | smartctl User Capacity | 输出缺失原因说明 |
| `通电时间` | SMART ID 9 或 Accumulated time | 输出缺失原因说明 |

> ⚠️ **`卷_id` 要求**：若无映射证据，应在 `"分析原因"` 中提示补充信息，**严禁伪造**。

### 3.2 规则判定与存活概率计算

**执行逻辑规范**：
> 📖 **判定标准详情参考**：[硬盘健康度评估技术规范](references/disk_health_rules.md)

1.  **规则比对**：根据规范 §2 (SAS) 或 §3 (SATA) 执行全量规则逐条比对。
2.  **存活概率**：若未命中硬故障规则，按规范 §4 计算偏离程度及半年存活概率。
3.  **处置等级**：按规范 §5 确定 `"是否已更换"` 和 `"是否可修复"` 布尔值。
4.  **NVMe 降级**：NVMe 盘不适用当前规则集，输出“无法评估”声明，并推荐 `nvme-cli` 命令。

**执行命令**：
```bash
# 默认输出 Markdown 表格视图（含规则命中详情）
python3 scripts/diagnose_health_rules.py <log_dir> --format md

# 输出 JSON
python3 scripts/diagnose_health_rules.py <log_dir> --format json

# 默认 table 输出（仅显示命中项）
python3 scripts/diagnose_health_rules.py <log_dir>

# 显示所有规则行（含未命中）
python3 scripts/diagnose_health_rules.py <log_dir> --include-passed
```

### 3.3 数据缺失与异常声明

- **模型补全机制**：若自动化脚本未能成功提取关键元数据（如 `"物理槽位"`、`"序列号"`、`"卷_id"` 等），模型必须尝试使用 `grep` / `less` 等文件操作命令深入检索原始日志上下文（如 iBMC SEL、`sasraidlog.txt` 等），力求最大限度补全标准化诊断对象。
- **数据冲突与时效纠错**：
  - **最新原则**：若脚本产出与模型自动检索结果不一致（如因盘符漂移导致的名称变更），模型必须以最接近故障时刻（T0）且逻辑闭环的证据为准，确保数据“最新且真实”。
  - **修正逻辑**：若模型纠正了脚本的错误输出（如识别出脚本解析了过时的旧配置），必须在 `分析原因` 中记录纠错依据。
- 任何无法索取的字段，应在对应字段位置输出具体的缺失原因说明字符串（如"日志缺失无法定位"），严禁输出 `null` 或占位符，严禁编造。

### 3.4 标准化诊断对象（Step 3 最终落地形式）

每块涉事磁盘必须输出符合以下 **13 字段** 结构的标准化诊断对象，并以 `"磁盘列表"` 数组形式聚合到报告级两个字段（`"故障服务器IP"` / `"分析日期"`）下：

```jsonc
{
  "故障服务器IP": "10.78.26.27",              // 报告级，从 log_dir 路径解析或 --ip 参数
  "分析日期": "YYYY-MM-DD",
  "磁盘列表": [
    {
      "卷_id": "vol13",
      "物理槽位": "Slot 4",
      "SCSI 磁盘设备": "/dev/sdx",
      "硬盘型号": "ST20000NM007D-3DJ103",
      "序列号": "ZVT6MK9K",
      "接口类型": "SATA",                     // "SAS" | "SATA" | "NVMe" | "Unknown"
      "容量": "20.0 TB",
      "通电时长小时": 16502,
      "是否已更换": "否",                     // 见规范 §5.1
      "是否可修复": "是",                     // 见规范 §5.2
      "半年存活概率": 0.933,                  // 见规范 §4
      "命中故障规则": [],                     // 命中规则 ID 及简述
      "分析原因": ["未命中任何故障规则"]        // 命中规则、退化指标的自然语言原因列表
    }
  ]
}
```

**字段规约**：
- `"是否已更换"` / `"是否可修复"`：NVMe 或数据严重缺失时，在对应字段输出具体原因说明（如"NVMe 盘不适用此规则"或"缺少关键 SMART 记录无法判定"）。
- `"分析原因"`：至少包含一条自然语言原因。

**Step 3 完成标志**：
1. ✅ 列出涉事磁盘清单及基础元数据。
2. ✅ 完成基于规范的全量规则比对与概率计算。
3. ✅ 输出 13 字段标准化诊断对象（Card 或 JSON 视图）。

---
## Step 4：根因反思与证据双向校验 (Cross-Examination Rules)

**目标**：对 Step 2 输出的“初步传导链与定位结果”、Step 3 输出的"客观规则评估结果"进行"交叉质询"，确保得出的最终结论 100% 由底层日志支撑。

### 4.1 交叉质询铁律 (Cross-Examination Rules)

1. **孤证不立原则**：任何物理级磁盘故障（如磁盘坏道），绝对不能仅凭系统层的一个报错（如 I/O Error）就下断言。**必须**同时找到硬件层（如 SMART 或 iBMC SEL）的第二独立证据源支撑。Step 3 的硬故障规则命中本身已是客观证据，但仍须配合 Step 2 时序传导链验证其与本次故障的因果关联（避免"长期亚健康盘背锅，实际故障在链路"）。
2. **逻辑闭环原则**：从 T0 到最终业务故障结果，传导链不允许出现跳跃。例如：`链路重启`不能直接等同于`驱动器彻底故障`，除非伴随连续的硬件离线记录。
3. **互斥排异原则**：如果判定故障是磁盘 A 损坏，则必须验证同背板/同通道的其他磁盘是否正常，以排除共性故障（如背板供电）。

### 4.2 强制：根因证据校验表 (Evidence Validation Matrix)

在确认最终结论前，强制要求进行证据校验：

| 校验维度 | 校验标准要求 | 强制证据格式（分析打样要求） |
| :--- | :--- | :--- |
| **E1: 时序连续性** | 硬件告警时间是否早于或同步于系统层报错？ | `[✅/❌ 结果]` + `时序对齐说明` + `[绝对路径 : 行号/行号范围]` + `原生日志片段` |
| **E2: 物理同一性** | 各级日志指控的逻辑盘符（sdX）与物理槽位（Slot Y）是否对应？ | `[✅/❌ 结果]` + `盘符与槽位映射日志梳理` + `[绝对路径 : 行号/行号范围]` + `原生日志片段` |
| **E3: 现象排他性** | 是否排除了 RAID 重建或巡检等预定后台任务的干扰？ | `[✅/❌ 结果]` + `RAID 卡状态及任务日志排除说明` + `[绝对路径 : 行号/行号范围]` + `原生日志片段` |
| **E4: 客观规则一致性** | Step 3 规则命中结论是否与 Step 2 的因果链推断一致？若不一致（如命中硬故障规则但 §2 推断为链路问题），是否在结论中说明并采取更保守的处置策略？ | `[✅/❌ 结果]` + `规则命中与因果链对照说明` + 指向 Step 3 §3.4 标准化诊断对象（具体到对应 `"磁盘列表"` 项）的引用 + `原生日志片段` |

### 4.3 结论防发散拦截机制 (Anti-Hallucination Mechanism)

*   **断链阻断**：若无法从日志中找到证明因果传导的片段，强制触发流程拦截，回溯重新收集。
*   **降级处分**：若确实缺乏某一层关键日志（如无 iBMC），必须在报告中声明为**"疑似故障 (Suspected)"**并标注证据断层位置。
*   **严禁用词限制**：在证据链未能满足完全闭环标准前，**严禁**使用"肯定"、"必然"、"磁盘绝对已坏"等决定性断言。

**Step 4 完成标志**：
1. ✅ 结构化地产出《根因证据校验表》中每一项（E1/E2/E3/E4）的自查结论。
2. ✅ 每个通过项均附带 Trace 日志中的 Timestamp、Text 以及其明确的 [绝对路径 : 行号/行号范围]。
3. ✅ 输出与之等位置信度（已证实 / 高度疑似 / 多重原因交织）的严谨研判方向。
4. ✅ E4 维度明确给出规则评估结论与因果链推断的一致性判断（一致 / 部分一致 / 冲突）；冲突时采取更保守的处置策略。

---
## Step 5：FARM 底层深度诊断 (可选环节)

**触发条件**（须**同时满足**）：
1. 在前置步骤中已经识别出是某物理磁盘存在问题；
2. 当前的日志包内有 `farmlog/` 目录，其中含以该 SN 命名的 FARM 日志（json 优先/txt 兜底）。

**目标**：不再局限于"哪块盘坏了"，而是探究**"这块盘的内部哪里坏了"**，将其归类至 8 类部位（如：纯粹个别磁头退化、马达供电异常等）。

> [!IMPORTANT]
> **FARM 是单帧快照，没有 `poh` 时间序列。严禁套用"旧→新趋势/活跃增长 vs 暂稳"这类趋势话术。** 活跃度改用 **`Reallocated Candidate Sectors`（候选坏道数）** 近似：候选 > 0 = 退化进行中，候选 = 0 = 暂稳。

### 5.1 运行分析引擎
```bash
# 默认 json 优先、txt 兜底（推荐）
python3 scripts/analyze_farm.py <log_dir>/farmlog

# 只用 json / 强制只用 txt（测试降级路径）
python3 scripts/analyze_farm.py <log_dir>/farmlog --source json
python3 scripts/analyze_farm.py <log_dir>/farmlog --source txt
```

> [!WARNING]
> **先确认数据源是 json 还是 txt！** json（openSeaChest）字段最全，能做逐头定位、逐头不可恢复读、Flash LED/Depop 判定；txt（华为 disktool）仅约 40% 字段，第 2/7 类及逐头明细会降级，故障常只能判到"整盘介质退化（未定位到磁头）"。报告"数据源"列已标注，结论关键时应索取该盘 json 重新分析。

### 5.2 结合指南定界病因
依据以上输出结果并参考指南进行专业判读：
> 📖 [FARM 底层诊断指南](references/farm_analysis.md)
> 📖 [FARM 字段与指标参考字典](references/farm_field_reference.md)

**重点关注**：
1. **种群相对法**：对比同一硬盘内的不同磁头，挑出 `FAFH`（飞高 clearance delta）离群、`MRR`=0xFFFF（磁头开路）或 `H2SAT` 信号劣化的"离群磁头"。
2. **候选数活跃度**（替代 SM2 的趋势判断）：用 `Reallocated Candidate`（整盘或逐头）判定退化进行中（>0）还是暂稳（=0）。
3. **整盘↔逐头对账**：用逐头重分配数把整盘坏道定位到具体磁头；逐头全 0 而整盘很大时，诚实标注"无法定位到磁头"。
4. **FAFH 谨慎**：飞高 clearance delta 逐头校准差异天然大，单独离群只算"关注"，须与同头坏道共振才升级为"退化"。
5. **组合研判**：第 1 类（重分配/坏扇区）+ 第 2 类（不可恢复读）同时非零时，故障概率升至约 76%——最优先备份换盘。

**Step 5 完成标志**：
1. ✅ 输出 FARM 逐磁头分析表（重分配/候选/不可恢复读/FAFH(O/M/I)/MRR/离群标记），标注离群磁头及数据源覆盖度。
2. ✅ 给出 8 类故障部位评级（如：磁头退化 / 整盘介质退化 / 接口异常 / 固件硬件级失效等）及其置信度。
3. ✅ 用候选数判定活跃度（退化进行中 / 暂稳），输出处置建议，并将 FARM 诊断结论整合至 Step 6 的报告中。

---
## Step 6：界面输出分析报告

汇总 Step 0～5 的所有分析结果（若执行了 Step 5 FARM 诊断，须将其逐磁头结论、8 类部位评级与候选数活跃度并入报告），直接在当前对话界面输出结构化的诊断报告。**禁止生成任何额外的文档或报告文件。**

### 6.1 报告结构 (五大章节)

1.  **结论 (Conclusion)**
    *   **故障摘要**：必须指明物理槽位（Slot ID）、硬盘型号、具体故障现象（如：坏道超限/链路重置）及业务后果（如：文件系统只读）。
    *   **存储数据流拓扑**：清晰呈现层级映射：`挂载点（用户入口） -> 文件系统 -> 分区/LVM -> 真实故障物理磁盘设备（/dev/sdX）`。

2.  **故障链条 (Fault Chains)**
    *   **故障时间链 (Fault Time Chain)**：按时间顺序排列的关键事件点。每个节点必须包含准确时间戳及出处 `[完整绝对路径 : 行号/行号范围]`。
    *   **故障传播链 (Fault Propagation Chain)**：物理/外部因果向系统表现的传导路径（例如：`硬盘物理损坏 -> I/O 阻塞 -> 内核触发 Device Reset -> 文件系统保护`）。

3.  **故障盘修复价值评估**
    *   **协议封装**：输出时必须使用双层协议标签包裹。若涉及多块磁盘，需分开描述：
        <!-- DOMAIN_EXT_START-->
        ## 标题： 故障盘修复价值评估 
        <!-- DOMAIN_DATA_START-->
        ### 卷_id - SCSI 磁盘设备
        1. 故障盘结论：[结论描述，含修复/更换建议及原因]
        2. 故障盘标准化诊断对象：
        ```json
        { /* 此处为 Step 3 §3.4 规定的 13 字段标准化 JSON */ }
        ```
        <!-- DOMAIN_DATA_END -->
        <!-- DOMAIN_EXT_END -->
        
    *   **诊断卡片**：逐盘呈现 Step 3 §3.4 规定的 13 字段标准化对象（Card 视图），作为底层的客观硬指标证据。
    *   **半年存活概率**：对未命中硬故障的磁盘，引用 [disk_health_rules.md](references/disk_health_rules.md) §4.1 的偏离程度明细。
    
4.  **根因 (Root Cause)**
    *   **技术分析**：结合 §3 的规则评估结果与 §2 的传导链回溯，明确指出导致本次业务故障的物理级或配置级根因。
    *   **交叉质询证据 (E1-E4)**：呈现 Step 4 的校验结果（重点说明规则评估结论与因果链推断的一致性）。
    *   **🔴 强制约束**：所有原生日志证据必须统一标注出处：`[完整绝对路径 : 行号/行号范围]`。严禁截断路径。

5.  **修复建议 (Recommendations)**
    *   **处置建议**：综合 §4 因果根因与 §3 规则评估结果给出。若规则评估建议更换（`"是否已更换"=true`），即便因果根因指向其他部件，仍须建议同步更换。
    *   **具体修复路径**：针对 `"是否可修复"=true` 的部件给出线缆更换、自检、监控等建议；针对 NVMe/缺失盘提供具体的复检命令。

### 6.2 诊断质量基线 (质量拦截要求)

在输出报告前，必须确认满足以下基线要求：
- [ ] **路径溯源**：所有证据引用均包含**完整绝对路径**与**精准行号/行号范围**。
- [ ] **时序对齐**：故障时间链中的每一个节点均有准确的时间和对应的溯源出处 `[完整绝对路径 : 行号/行号范围]`。
- [ ] **拓扑完整**：报告包含从挂载点到底层硬件的**存储数据流映射**。
- [ ] **逻辑闭环**：包含时间与传播双向链条，且根因经过 E1-E4 交叉校验。
- [ ] **规则覆盖**：对每块涉事磁盘完成了 [disk_health_rules.md](references/disk_health_rules.md) 全量规则比对，并在修复建议中闭环规则判定结论。

---

## 参考资料

* [磁盘故障场景分类](references/DISK_fault_scenarios.md)
* [磁盘故障场景专项分析指南](references/DISK_scenario_analysis.md)
* [硬盘健康度评估规则](references/disk_health_rules.md)
* [InfoCollect 诊断指南](references/infocollect_guide.md)
* [OS Messages 诊断指南](references/messages.md)
* [Huawei iBMC 分析](references/huawei_ibmc.md)
* [H3C iBMC 分析](references/h3c_ibmc.md)
* [Inspur iBMC 分析](references/Inspur_ibmc.md)
* [FARM 底层诊断指南](references/farm_analysis.md)
* [FARM 字段与指标参考字典](references/farm_field_reference.md)

---
