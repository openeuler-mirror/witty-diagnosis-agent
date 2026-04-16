---
name: offline-CPU-fault-diagnosis
description: 通过分析服务器离线日志（iBMC、OS Messages、InfoCollect）诊断 CPU 硬件、温度、微码及互连总线故障并定位物理级根因。当用户提供日志并询问 CPU 过热（Overheating）、降频（Throttling）、MCE 硬件错误、缓存错误（Cache Error）、UPI/QPI 链路不稳定，以及当系统因内核 Panic 或 Soft Lockup 需要进行底层 CPU 相关根因溯源时，调用本技能。
---

# 离线 CPU 故障诊断

本技能通过分析从服务器收集的标准日志文件，重点诊断离线 CPU 及相关子系统物理/链路级故障。

## 技能目录结构

本技能的目录结构如下，包含诊断脚本、参考资料和文档：

```text
offline-CPU-fault-diagnosis/
├── SKILL.md                          # 本技能的主文档
├── scripts/                          # 诊断脚本目录
│   ├── diagnose_summary.py           # Step 0: 故障日志采集脚本
│   ├── diagnose_ibmc.py              # Step 2: iBMC日志分析脚本
│   ├── diagnose_infocollect.py       # Step 2: InfoCollect日志分析脚本
│   ├── diagnose_messages.py          # Step 2: OS消息日志分析脚本
│   └── diagnose_cpu.py               # Step 2: CPU专项分析脚本
└── references/                       # 参考资料目录
    ├── CPU_fault_scenarios.md        # CPU故障场景分类
    ├── CPU_scenario_analysis.md      # CPU故障场景专项分析指南
    ├── infocollect_guide.md          # InfoCollect诊断指南
    ├── messages.md                   # OS消息日志分析指南
    ├── huawei_ibmc.md                # 华为iBMC分析指南
    ├── h3c_ibmc.md                   # H3C iBMC分析指南
    └── Inspur_ibmc.md                # Inspur iBMC分析指南
```

## 输入日志目录结构与对应诊断脚本

以 `/path/to/logs/xxxx` 为例，标准的服务器日志收集包通常具有以下层级结构。本技能提供了针对性的脚本来分析不同层级的日志。

> **注意**：在实际场景中，用户提供的日志包可能不完整，请根据实际存在的日志类型灵活选择对应的分析脚本。

```text
<日志根目录> (例如: 10.120.6.76)
├── ibmc_logs/                  # iBMC 硬件带外管理日志
│   └── (CPU温度/电压/错误事件) -> 使用 scripts/diagnose_ibmc.py
├── infocollect_logs/           # 系统信息收集工具生成的分类日志
│   └── (CPU信息/温度/性能数据) -> 使用 scripts/diagnose_infocollect.py
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
5. **专注根因**：分析过程应锁定物理部件及链路，排查系统异常的底层诱因。

**每步完成标志：**
- Step 0：输出日志文件时间范围、文件统计、错误关键词概览
- Step 1：确定故障场景（如 CPU_HARDWARE_FAILURE 等）
- Step 2：输出物理级精准定位、传导链及初步根因
- Step 3：输出根因证据校验表、原生日志证据及置信度定性
- Step 4：在界面上按固定结构输出最终的分析报告（**严禁生成独立文件**）

---

## 分析流程总览

| **步骤** | **阶段目标** | **主要工具/方法** |
| :--- | :--- | :--- |
| **Step 0** 故障日志采集 | 全量/定点扫描日志目录并识别关键报错 | `diagnose_summary.py <log_dir> [-k/-d/-s]` |
| **Step 1** 场景分类 | 判定现象并确定故障场景类型 | 根据 Step 0 采集结果进行场景匹配 |
| **Step 2** 深入分析 | 构建起止 T0 的传导链并执行诊断 | 使用 `diagnose_ibmc.py/diagnose_infocollect.py/diagnose_messages.py/diagnose_cpu.py` 获取多维证据 |
| **Step 3** 根因校验 | 交叉质询证据链，执行证据双向校验 | 对比 iBMC/内核/系统日志的一致性，防止结论发散 |
| **Step 4** 界面输出分析报告 | 汇总证据链与确认根因，在界面直接输出报告内容 | 结构化输出：结论 + 故障链条 + 修复建议 |

---

## Step 0：故障日志采集

### 全量扫描（宏观分析）

**目标**：快速扫描所有日志文件，识别 CPU 及子系统的异常，建立故障全景视图。当存在特定报错或时间范围时，利用参数进行第一轮初步精确定位。

**执行命令**（根据场景选择）：
```bash
# 场景 1：无明确过滤条件（默认全量扫描）
python3 scripts/diagnose_summary.py <log_dir>

# 场景 2：用户提供故障关键词时
python3 scripts/diagnose_summary.py <log_dir> -k "thermal" "CATERR"

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

> 📖 **参考详见**：[CPU 故障场景分类](references/CPU_fault_scenarios.md)

| 场景标签 | 中文描述 | 主要特征 |
| :--- | :--- | :--- |
| `CPU_HARDWARE_FAILURE` | CPU 硬件故障 | iBMC SEL 报告 CPU 硬件错误、UCE 引发 MCE (机器检查异常) |
| `CPU_OVERHEATING` | CPU 过热 | CPU 温度持续超过安全阈值 (Thermal Trip)、降频告警 |
| `CPU_MICROCODE_ERROR` | CPU 微码/内核 Bug | 微码版本不匹配、CPU 内部死锁导致的 Soft Lockup |
| `CPU_CACHE_ERROR` | CPU 缓存错误 | L1/L2/L3 缓存 ECC 错误、缓存一致性错误告警 |
| `CPU_FREQUENCY_THROTTLING` | CPU 频率调节 | CPU 频率被持续限制、电源管理问题导致性能下降 |
| `CPU_INTERCONNECT_ERROR` | CPU 互连错误 | QPI/UPI 总线错误、CPU 间通信物理损坏 |
| `CPU_VOLTAGE_REGULATION` | CPU 电压调节 | VRM 故障、CPU 供电异常 (Power Fault) |

### 场景辅助分析与根因假设

确定场景标签后，**必须参考专项分析指南**进行候选根因的初步验证：

> 🔍 **专项分析指南**：[CPU 故障场景专项分析指南](references/CPU_scenario_analysis.md)

| 场景标签 | 候选根因假设（需在 Step 2 中验证） |
| :--- | :--- |
| `CPU_HARDWARE_FAILURE` | ① CPU 物理损引发 MCE 导致 Panic 宕机 ② CPU 插座接触不良 ③ 主板总线故障 |
| `CPU_OVERHEATING` | ① 散热器硅脂干涸/安装不当 ② 风扇异常导致积热 ③ 环境温度严重超标 |
| `CPU_MICROCODE_ERROR` | ① 触发特定微码指令集缺陷 ② BIOS/UEFI 固件版本不兼容 |
| `CPU_CACHE_ERROR` | ① 高频 CE 错误触发阈值 ② 缓存控制器物理损坏 |
| `CPU_FREQUENCY_THROTTLING` | ① 电源策略配置回退 ② 温度过高触发热限制 |
| `CPU_INTERCONNECT_ERROR` | ① UPI 链路物理链路中断 ② CPU 针脚弯曲导致的电气特性异常 |
| `CPU_VOLTAGE_REGULATION` | ① VRM 模块硬件老化 ② 电源供应模块不稳 |

> ⚠️ **强制要求**：在进入 Step 2 深入分析前，应先通过 [CPU_scenario_analysis.md](references/CPU_scenario_analysis.md) 了解对应场景的分析路径与关键证据点。分析结束后，必须对上述候选根因方案逐一标注：✅ 已证实 / ❌ 已排除 / ❓ 证据不足。

**Step 1 完成标志：**
1. ✅ 确定主要故障场景标签（从上述类型中选择）
2. ✅ 记录故障现象与关键证据
3. ✅ 为 Step 2 深入分析提供明确的故障场景方向

---
## Step 2：深入分析

根据 Step 1 的场景分类结果，必须**首先完成时序关联与故障传导链重建**，然后再通过多源脚本收集证据，最终给出精确的物理坐标定位。

### 2.1 时序关联与传导链重建 (核心理论框架)

**目标**：通过多源日志的时间戳对齐，重建故障发生的完整时间轴，厘清事件的先后顺序与因果链，为根因定位提供时序证据。

#### 2.1.1 确定 CPU 故障零点 (T0)

故障零点（T0）是时序分析的基准锚点，定义为**最早可观测到异常的时间戳**。确定优先级（由高到低）：

| 优先级 | 来源 | 说明 |
|----|----|----|
| **P1** | 硬件错误日志（iBMC / SEL） | 底层致命报错（如 CATERR, IERR, Thermal Trip），时间点最准确。 |
| **P2** | 内核感知层（`dmesg` / `mcelog`） | 最早出现的 MCE (Machine Check Exception) 或温度阈值告警。 |
| **P3** | 系统调度层（`syslog` / `messages`） | Soft Lockup、降频 (Throttling) 等系统级异常事件。 |
| **P4** | 应用感知层 | 进程崩溃、业务响应超时等应用层记录，滞后性较大。 |

#### 2.1.2 多维日志对齐与时间轴矩阵

以 T0 为基准，将 iBMC 传感器读数、dmesg 报错、微码状态和 OS 日志统一映射到绝对时间轴上，构建**事件序列矩阵**。
*示例：因散热失效导致的 CPU 热宕机时间轴*
```text
T0-30m  ├─ [InfoCollect] 环境温度与 CPU 温度传感器记录开始持续升高。
T0-5m   ├─ [iBMC SEL]    检测到 CPU 风扇转速过低或转子锁定告警。
T0-1m   ├─ [OS dmesg]    `Core temperature above threshold, cpu clock throttled` (CPU开始降频自保)。
T0      ├─ [iBMC SEL]    记录 `Thermal Trip` 硬件断电保护 → 标定为故障发生零点 T0。
```

#### 2.1.3 CPU 故障传导链推断 (示例)

结合对齐的时间轴矩阵，运用以下规则推导故障传导链方向：
- **规则一：层级自下而上（硬件损坏主导）**
  - *传导链*：主板供电/CPU 插槽物理异常 (T0) → 触发硬件报错 (SMI/NMI) → 操作系统无法处理触发 Panic → 系统重启。
- **规则二：环境向硬件传导（散热/电源主导）**
  - *传导链*：风扇/电源模块预警 (T0) → CPU 降频功耗限制 → 业务性能骤降告警 → 最终触发硬件断电保护。

> ⚠️ **精确定位强制要求**：在 CPU 诊断中，**严禁仅使用“CPU故障”这类含糊结论。**
> 必须通过证据追踪到细粒度的三维物理坐标定位，例如：
> - ✅ 正确结论：`Socket 1 -> Core 8 -> L2 Cache 读取校验失败`。
> - ❌ 错误结论：`发生 MCE 错误` 或仅仅说是 `CPU 0 损坏`。

---

### 2.2 日志脚本分析执行 (执行工具动作)

#### 2.2.1 通用分析流程

通用分析流程适用于所有 CPU 故障场景，提供基础的日志提取与数据分析能力：

```bash
# iBMC 日志分析（硬件层）
python3 scripts/diagnose_ibmc.py <log_dir>

# InfoCollect 日志分析（系统信息层）
python3 scripts/diagnose_infocollect.py <log_dir>

# OS Messages 日志分析（操作系统层）
python3 scripts/diagnose_messages.py <log_dir>

# CPU 专项分析
python3 scripts/diagnose_cpu.py <log_dir> --hardware
```

> **注意：使用脚本时，可优先执行 `--help` 参数，了解脚本多维度过滤用法。**

#### 2.2.2 按场景专项分析

当 Step 1 确定故障场景后，优先分析对应的关键指标：
1. **CPU 硬件故障**：重点分析 `mcelog` 和 iBMC 的硬件状态。
2. **CPU 过热分析**：重点查看温度曲线与风扇转速的耦合关系。
3. **互连总线分析**：重点查找 UPI/QPI 链路上的 CRC 或同步错误。

#### 2.2.3 分析执行原则

1. **场景优先原则**：当故障现象明确匹配某个场景时，优先针对该场景取证。
2. **组合使用原则**：必须同时使用带外（iBMC）和带内（OS）脚本进行相互验证。
3. **逐步深入原则**：从宏观概览开始，逐步根据时序对齐结果深入特定日志行。

**Step 2 完成标志**：
1. ✅ 输出故障零点 T0 的精确时间戳及其所依托的具体日志行。
2. ✅ 梳理出以 T0 为基准的结构化事件序列矩阵与至少 3 步的确定故障传导链。
3. ✅ 给出精确到物理部件（例如 Socket / Core）的细粒度定位结果。
4. ✅ 收集脚本产出的相关原生日志片段作为强有力的支撑证据。

---
## Step 3：根因反思与证据双向校验 (Cross-Examination Rules)

**目标**：对 Step 2 输出的“初步传导链与定位结果”进行“交叉质询”，确保得出的最终结论 100% 由底层日志支撑。

### 3.1 交叉质询铁律 (Cross-Examination Rules)

1. **孤证不立原则**：任何物理级 CPU 故障（如 CPU 损坏），绝对不能仅凭系统层的一个报错（如 OS Panic）就下断言。**必须**同时找到硬件层（如 iBMC SEL）或内核底层（如 MCE 寄存器）的第二独立证据源支撑。
2. **逻辑闭环原则**：从 T0 到最终业务故障结果，传导链不允许出现跳跃。例如：`温度异常`不能直接推断导致`UPI链路故障`，除非建立能量/物理链接逻辑。
3. **互斥排异原则**：如果判定故障是 CPU 损坏，则必须验证供电模块（VRM）和总线是否异常，以排除外部环境导致的诱发性损坏。

### 3.2 强制：根因证据校验表 (Evidence Validation Matrix)

在确认最终结论前，强制要求进行证据校验：

| 校验维度 | 校验标准要求 | 强制证据格式（分析打样要求） |
| :--- | :--- | :--- |
| **E1: 时序连续性** | 硬件告警时间是否早于或同步于系统层报错？ | `[✅/❌ 结果]` + `时序对齐说明` + `原生日志片段` |
| **E2: 物理同一性** | 各级日志指控的逻辑核心 ID 与物理 Socket ID 是否对应？ | `[✅/❌ 结果]` + `逻辑 ID 到物理坐标的映射梳理` |
| **E3: 现象排他性** | 是否排除了如 OS 配置、微码已知不稳定性等软性干扰因素？ | `[✅/❌ 结果]` + `特定版本缺陷/配置排查说明` |

### 3.3 结论防发散拦截机制 (Anti-Hallucination Mechanism)

*   **断链阻断**：若无法从日志中找到证明因果传导的片段，强制触发流程拦截，回溯重新收集。
*   **降级处分**：若确实缺乏某一层关键日志（如无 iBMC），必须在报告中声明为**“疑似故障 (Suspected)”**并标注证据断层位置。
*   **严禁用词限制**：在证据链未能满足完全闭环标准前，**严禁**使用“肯定”、“必然”、“CPU 绝对已坏”等决定性断言。

**Step 3 完成标志**：
1. ✅ 结构化地产出《根因证据校验表》中每一项的自查结论。
2. ✅ 每个通过项均附带 Trace 日志中的 Timestamp 和 Text 指南。
3. ✅ 输出与之等位置信度（已证实 / 高度疑似 / 多重原因交织）的严谨研判方向。

---
## Step 4：界面输出分析报告

汇总 Step 0～3 的所有分析结果，直接在当前对话界面输出结构化的诊断结论。**禁止生成任何额外的文档或报告文件。**

**报告结构：**

1. **Executive Summary（故障摘要）** — 故障位置（Socket ID）、直接原因、后果概述
2. **Fault Chains（故障链条分析）** — **必须包含以下两级链条：**
   - **故障时间链 (Fault Time Chain)**：列出带关键节点的事件序列，**每个节点必须包含准确的时间戳**。
   - **故障传播链 (Fault Propagation Chain)**：清晰描绘因果传导路径（例如：`CPU 核心触发 UCE -> 硬中断触发内核 Panic -> 触发 IERR 指引系统重启`）。
3. **Technical Analysis & Root Cause（技术分析与根因）** — 基于多源证据链（E1/E2/E3）支撑，定位物理级根因。
4. **Recommendations（修复建议）** — 立即操作、备件更换建议及预防性检查

**诊断分析完成性检查（输出报告前必检）：**

在得出结论前，必须回答以下问题：
- [ ] 是否给出了精确的**物理 Socket/Core ID**？
- [ ] Step 1 场景假设矩阵是否已完成 ✅/❌ 标注？
- [ ] 是否排除了硬件以外的软硬件或电源干扰因素？
- [ ] **故障时间链中的每一个节点是否都有准确的时间？**
- [ ] **是否清晰勾勒并输出了故障传播链？**

---

## 参考资料

* [CPU 故障场景分类](references/CPU_fault_scenarios.md)
* [CPU 故障场景专项分析指南](references/CPU_scenario_analysis.md)
* [InfoCollect 诊断指南](references/infocollect_guide.md)
* [OS Messages 诊断指南](references/messages.md)
* [Huawei iBMC 分析](references/huawei_ibmc.md)
* [H3C iBMC 分析](references/h3c_ibmc.md)
* [Inspur iBMC 分析](references/Inspur_ibmc.md)

---