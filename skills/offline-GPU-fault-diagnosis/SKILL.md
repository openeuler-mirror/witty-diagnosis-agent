---
name: offline-GPU-fault-diagnosis
description: 通过分析服务器离线日志（iBMC、OS Messages、InfoCollect）诊断离线 GPU 硬件故障、驱动异常、显存 ECC 错误及 PCIe 链路问题。当用户提供日志并询问 GPU 掉卡（Fallen off the bus）、XID 错误、显存不可纠正错误（Uncorrectable ECC）、GPU 维度过温或性能下降需要进行根因溯源时，调用本技能。
---

# 离线 GPU 故障诊断

本技能通过分析从服务器收集的标准日志文件，重点诊断离线 GPU 及其子系统在软件驱动与硬件物理层面的故障。

## 技能目录结构

本技能的目录结构如下，包含诊断脚本、参考资料和文档：

```text
offline-GPU-fault-diagnosis/
├── SKILL.md                          # 本技能的主文档
├── scripts/                          # 诊断脚本目录
│   ├── diagnose_summary.py           # Step 0: 故障日志采集脚本
│   ├── diagnose_ibmc.py              # Step 2: iBMC日志分析脚本
│   ├── diagnose_infocollect.py       # Step 2: InfoCollect (nvidia-smi) 分析脚本
│   └── diagnose_messages.py          # Step 2: OS消息日志分析脚本
└── references/                       # 参考资料目录
    ├── GPU_fault_scenarios.md        # GPU 故障场景分类表
    ├── GPU_scenario_analysis.md      # GPU 故障场景专项分析指南
    ├── XID_error_codes.md            # NVIDIA XID 错误代码快速参考
    ├── infocollect_guide.md          # InfoCollect 诊断指南
    ├── messages.md                   # OS 消息日志分析指南
    ├── huawei_ibmc.md                # 华为 iBMC 分析指南
    ├── h3c_ibmc.md                   # H3C iBMC 分析指南
    └── Inspur_ibmc.md                # Inspur iBMC 分析指南
```

## 输入日志目录结构与对应诊断脚本

以 `/path/to/logs/xxxx` 为例，标准的服务器日志收集包通常具有以下层级结构。本技能提供了针对性的脚本来分析不同层级的日志。

> **注意**：在实际场景中，用户提供的日志包可能不完整，可能仅包含以下三种目录中的一种或多种。请根据实际存在的日志类型灵活选择对应的分析脚本。

```text
<日志根目录> (例如: 10.120.6.76)
├── ibmc_logs/                  # iBMC 硬件带外管理日志
│   └── (GPU 硬件故障/电压/告警事件) -> 使用 scripts/diagnose_ibmc.py
├── infocollect_logs/           # 系统信息收集工具生成的分类日志
│   └── (nvidia-smi -a 详细信息 / 拓扑数据) -> 使用 scripts/diagnose_infocollect.py
└── messages/                   # 操作系统层面的系统日志
    └── (dmesg, XID 报错, NVRM 驱动记录) -> 使用 scripts/diagnose_messages.py
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
4. **全维度覆盖**：必须涵盖软件驱动（Driver/CUDA）与硬件物理（GPU Core/Memory/PCIE）两个层面的故障排查。
5. **文件适配**：日志文件不全时自动降级分析策略，但必须至少有一个日志文件。

**每步完成标志：**
- Step 0：输出日志文件时间范围、文件统计、错误关键词概览
- Step 1：确定故障场景（如 GPU_HARDWARE_FATAL 等）及候选根因
- Step 2：输出物理级精确Bdf/Slot定位、时间传导链及初步根因
- Step 3：输出根因证据校验表、原生日志证据及置信度定性
- Step 4：在界面上按固定结构输出最终的分析报告（**严禁生成独立文件**）

---

## 分析流程总览

| **步骤** | **阶段目标** | **主要工具/方法** |
| :--- | :--- | :--- |
| **Step 0** 故障日志采集 | 全量/定点扫描日志目录并识别关键 GPU 报错 | `diagnose_summary.py <log_dir> [-k/-d/-s]` |
| **Step 1** 场景分类 | 判定现象并确定故障场景类型及推断可能根因 | 根据 Step 0 采集结果进行场景匹配和表格排查 |
| **Step 2** 深入分析 | 构建起止 T0 的传导链并执行三维精确物理定位 | 使用 `diagnose_ibmc.py/diagnose_infocollect.py/diagnose_messages.py` 获取多维证据 |
| **Step 3** 根因校验 | 交叉质询证据链，执行硬/软层面双向交叉比对 | 对比 iBMC/内核/驱动日志的互斥与一致性，防止结论发散 |
| **Step 4** 界面输出分析报告 | 汇总证据链与确认根因，在界面直接输出报告内容 | 结构化输出：结论 + 故障链条 + 修复建议 |

---

## Step 0：故障日志采集

### 全量扫描（宏观分析）

**目标**：快速扫描所有日志文件，识别 GPU 子系统的异常，建立故障全景视图。当存在特定报错或时间范围时，利用参数进行第一轮初步精确定位。

**执行命令**（根据场景选择）：
```bash
# 场景 1：无明确过滤条件（默认全量扫描）
python3 scripts/diagnose_summary.py <log_dir>

# 场景 2：用户提供故障关键词时 (扫描 GPU 常见异常)
python3 scripts/diagnose_summary.py <log_dir> -k "XID" "NVRM" "Fallen" "ECC"

# 场景 3：用户提供故障发生时间/日期时
python3 scripts/diagnose_summary.py <log_dir> -d "Mar 16"
python3 scripts/diagnose_summary.py <log_dir> -s "2026-03-10 08:00:00" -e "2026-03-10 12:00:00"
```

### 精细定位（微观分析）

**目标**：在优先使用上述带有参数的扫描命令锁定范围的基础上，结合全量扫描结果，辅以 `grep` / `less` 等文件操作命令查看更细节的原始日志上下文。

> **注意：使用脚本时，可优先执行 `--help` 参数，了解脚本多维度过滤用法。**

---

## Step 1：场景分类

分析 Step 0 结果并确定故障场景类型。

### 场景分类概述

根据 Step 0 采集的日志概览，分析故障现象并从以下标准场景中确定故障场景类型。

> 📖 **参考详见**：[GPU 故障场景分类](references/GPU_fault_scenarios.md)

| 场景标签 | 中文描述 | 主要特征 |
| :--- | :--- | :--- |
| `GPU_HARDWARE_FATAL` | GPU 硬件致命故障 | XID 79, iBMC 记录 GPU Fault, 物理掉卡 (Fallen off the bus) |
| `GPU_DRIVER_CRASH` | 驱动与软件层故障 | NVRM Kernel Oops, API Mismatch, 驱动加载失败, XID 62 |
| `GPU_MEMORY_ECC` | 显存 ECC 错误 | XID 31, XID 48, 行重映射错误, 显存不可纠正错误 (Uncorrectable ECC > 0) |
| `GPU_THERMAL_POWER` | 散热与功耗限制 | HW Slowdown, iBMC 过温告警, 性能异常下降 |
| `GPU_PCIE_LINK` | PCIe 链路与总线异常 | Link Width Reduction, XID 61, PCIe AER Error (Advanced Error Reporting) |

### 场景辅助分析与根因假设

确定场景标签后，**必须参考专项分析指南**进行候选根因的初步验证：

> 🔍 **专项分析指南**：[GPU 故障场景专项分析指南](references/GPU_scenario_analysis.md)

| 场景标签 | 候选根因假设（需在 Step 2 中验证） |
| :--- | :--- |
| `GPU_HARDWARE_FATAL` | ① GPU 供电异常或物理元件烧毁 ② CPU Socket 端引脚异常 ③ 假掉卡(内核 OOM 或 死锁所致) |
| `GPU_DRIVER_CRASH` | ① 驱动版本与 CUDA 不兼容 ② 业务程序异常调用导致内核态 Crash ③ 后台有非法进程争抢显存 |
| `GPU_MEMORY_ECC` | ① 显存颗粒硬损伤 ② 显存频率/功耗超频导致不稳定 ③ 软链接错误可通过驱动自恢复 |
| `GPU_THERMAL_POWER` | ① 散热模组失效/风扇故障引发降频保护 ② GPU 硅脂干涸 ③ 高强度计算持续触及 TDP 上限 |
| `GPU_PCIE_LINK` | ① PCIe 线缆/Riser卡松动或老化 ② 对应的系统底板通道电气不稳定 ③ AER 报错触发安全隔离 |

> ⚠️ **强制要求**：在进入 Step 2 深入分析前，必须要明确分析方向，并对候选根因进行验证。分析结束后需逐一标注：✅ 已证实 / ❌ 已排除 / ❓ 证据不足。

**Step 1 完成标志：**
1. ✅ 确定主要故障场景标签（从上述类型中选择）
2. ✅ 记录故障现象与关键证据（如特定 XID 或现象特征）
3. ✅ 为 Step 2 深入分析提供明确的根因假设待判清单

---

## Step 2：深入分析

根据 Step 1 的场景分类结果，必须**首先完成时序关联与故障传导链重建**，然后再通过多源脚本收集证据，最终给出精确的物理坐标定位。

### 2.1 时序关联与传导链重建 (核心理论框架)

**目标**：通过多源日志的时间戳对齐，梳理 XID 与 iBMC 及系统层面告警的先后顺序，重建故障因果链。

#### 2.1.1 确定故障零点 (T0)

定义 T0 为最早发生的异常记录时间戳，确定优先级如下：

| 优先级 | 来源 | 说明 |
|----|----|----|
| **P1** | 硬件错误日志 (iBMC/SEL) | CPU DIMM CATERR、GPU 供电故障、温度超限等，由于是独立监控，最为准确。 |
| **P2** | 系统底层中断 (PCIe AER) | `dmesg` 中记录的底层 PCIe 总线报错（AER）。 |
| **P3** | GPU 驱动日志 (NVRM XID) | 驱动层抛出的首个 XID，特别是 XID 31/79/44/119 等。 |
| **P4** | 业务感知层日志 | 算力下降、CUDA 分配失败、业务进程 Crash 等滞后现象。 |

#### 2.1.2 多维日志对齐与时间轴矩阵

提取各维度日志围绕 T0 进行排布：
*示例：因底板供电不稳引发的 GPU 掉卡*
```text
T0-2m   ├─ [OS dmesg]    系统出现 PCIe AER Correctable Error (BDF 0000:ca:00.0)
T0      ├─ [iBMC SEL]    检测到底板/电源供电瞬间异常中断
T0+1s   ├─ [OS dmesg]    `NVRM: GPU at PCI:0000:ca:00: GPU-xxxx fallen off the bus.` (致命点)
T0+2s   ├─ [OS dmesg]    `NVRM: XID (PCI:0000:ca:00): 79, GPU has fallen off the bus.`
T0+30s  ├─ [App Log]     训练任务检测到 NCCL Error 与 Tensor Core 中断
```

#### 2.1.3 故障传导链推断与精确定位要求

- **规则一：硬件引发软件**
  - *传导链*：硬件层供电异常 (T0) -> 触发 PCIe 链路超时 (T0+X) -> NVRM 报 XID 79 掉卡保护 -> 业务奔溃退出。
- **规则二：软件导致伪掉卡**
  - *传导链*：主机 CPU 长期处于 `soft-lockup` 或 OOM (T0) -> 无法响应 GPU 的中断请求 -> GPU 报超时 -> XID 119。

> ⚠️ **精确定位强制要求**：诊断需精确定位，**严禁含糊**。不能仅输出 "GPU 出错"。
> 必须提供完整定位路径，例如：
> ✅ 正确定位：`Slot 3 -> BDF 0000:82:00.0 (GPU UUID: GPU-xxx) -> XID 31 -> Uncorrectable ECC`。

### 2.2 日志脚本分析执行

#### 2.2.1 通用分析流程

```bash
# iBMC 日志分析（硬件层）
python3 scripts/diagnose_ibmc.py <log_dir>

# InfoCollect / nvidia-smi 静态/拓扑数据分析包含 ECC 与功耗墙
python3 scripts/diagnose_infocollect.py <log_dir>

# OS Messages / NVRM / XID 报错时序列分析
python3 scripts/diagnose_messages.py <log_dir>
```

> **注意：使用脚本时，可优先执行 `--help` 参数，结合 `-h` 了解过滤用法。由于 GPU 日志极其啰嗦，需善用关键词与时间过滤。**

#### 2.2.2 按场景专项分析

当 Step 1 确定故障场景后，优先分析对应的关键项：
1. **GPU_HARDWARE_FATAL**：必须核对 `dmesg` 中的 BDF 掉卡记录与 iBMC 的对应卡槽硬件事件。
2. **GPU_MEMORY_ECC**：深入 `nvidia-smi` 收集的信息，查阅隔离页数量、Row Remapper 等，并且关联看是否有 XID 31 / 48 / 44 等显存强相关报错。
3. **GPU_DRIVER_CRASH**：聚焦系统 `dmesg` 中是否有 Oops / Bug / NVRM 初始化报错。

**Step 2 完成标志**：
1. ✅ 输出故障零点 T0 的精确时间戳及其所依托的具体日志行。
2. ✅ 梳理出以 T0 为基准的结构化事件序列矩阵与传导链。
3. ✅ 给出精确到槽位及 BDF 的物理定位结果。
4. ✅ 收集各个视角的原生日志片段以待下一步核验。

---

## Step 3：根因反思与证据双向校验

**核心目标**：通过交叉比对规则防止单一视角的幻觉误判。

### 3.1 交叉质询铁律 (Cross-Examination Rules)

1. **孤证不立原则**：指控 GPU 硬件损坏（如 XID 79 或严重 ECC），绝对不能仅凭业务报错，必须具备系统 dmesg 日志或硬件带外 iBMC 的独立证据支撑。
2. **互斥排异原则**：如果是 OOM、CPU `soft-lockup` 或其他 OS Crash 导致了驱动未响应下发的 XID，则故障属于“系统伪掉卡”，须排查是否为主机资源枯竭而非 GPU 损坏。
3. **拓扑关联查验**：如果存在 PCIe 链路异常，必须同步检查同一 Switch 或同一 CPU Root Node 下其它 GPU 的 PCIe AER 报错，以排除上游硬件主板的公共问题。

### 3.2 强制：根因证据校验表 (Evidence Validation Matrix)

在确认结论前，必须执行校验单质询：

| 校验维度 | 校验要求 | 强制证据格式（分析打样要求） |
| :--- | :--- | :--- |
| **E1: 时序连续性** | 外围设备报警时间是否与 XID 抛出时间处于极短吻合窗口期？ | `[✅/❌]` + `时序对齐说明` + `原生日志片段` |
| **E2: 物理同一性** | 各级日志（如 OS层的 BDF `0000:ca:00.0` 和 iBMC 中的 `Slot 8`）是否物理对映同一实体？ | `[✅/❌]` + `驱动侧与带外硬件的映射证明梳理` |
| **E3: 现象排他性** | 是否完全排除了因为内存/CPU 满载带来的软死锁伪掉卡？ | `[✅/❌]` + `系统层面 dmesg CPU死锁/OOM 排除分析` |

### 3.3 结论防发散拦截机制 (Anti-Hallucination Mechanism)

*   **缺失必降级**：若证据严重缺失某一层逻辑，必须标注为**“疑似故障 (Suspected)”**，切忌生造不存在的 XID 记录。
*   **严禁无端断言**：在缺乏 T0 日志或缺失 P1 级别告警时，不要轻易给出“主板烧毁”等不可逆故障原因断言，应建议进一步现场更换验证。

**Step 3 完成标志**：
1. ✅ 结构化地产出《根因证据校验表》中每一项的自查结论。
2. ✅ 每个通过项均附带 Trace 日志中的 Timestamp 和原生 Text 证明。
3. ✅ 得出具备置信度的根因定论。

---

## Step 4：界面输出分析报告

汇总 Step 0~3 的分析成果，在界面输出结构化诊断结论。**禁止生成额外文档附加件**。

**报告结构必须包含：**

1. **Executive Summary（故障摘要）** — 涉及的物理槽位 / BDF 坐标、直接表象及结果简述。
2. **Fault Chains（故障链条分析）** — 包含以下分支：
   - **故障时间链 (Fault Time Chain)**：按精确时间列出关键异常序列。
   - **故障传播链 (Fault Propagation Chain)**：呈现因果链节点连接，如：`PCIe Link Lost -> NVRM Error -> XID 79 -> Application Abort`。
3. **Technical Analysis & Root Cause（技术分析与根因）** — 细致的根因讨论和支撑此推论的具体的多重视角证据 (对应 E1-E3 校验项)。
4. **Recommendations（修复建议）** — 例如驱动更新、下发软硬件排错动作或报修退换机验证动作。

**诊断分析完成性检查（输出报告前必检）：**

在得出结论前，必须回答以下问题：
- [ ] 是否给出了精确的 **BDF 和 Slot ID** 定位？
- [ ] Step 1 场景假设矩阵是否已完成验证标注（✅/❌）？
- [ ] 是否执行了“系统软死机导致伪掉卡”的排他性排查？
- [ ] 故障时间链中的每一个节点是否都有明确的时间回溯？

---

## 参考资料

* [GPU 场景专项分析指南](references/GPU_scenario_analysis.md)
* [XID 错误代码对照表](references/XID_error_codes.md)
* [OS Messages 诊断指南](references/messages.md)
* [Huawei iBMC 分析](references/huawei_ibmc.md)
* [H3C iBMC 分析](references/h3c_ibmc.md)
* [Inspur iBMC 分析](references/Inspur_ibmc.md)
* [InfoCollect 诊断指南](references/infocollect_guide.md)
