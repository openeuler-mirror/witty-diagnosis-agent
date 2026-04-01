---
name: offline-power-fault-diagnosis
description: 通过分析服务器离线日志（iBMC、OS Messages、InfoCollect）诊断 EulerOS 电源故障并定位根本原因。适用场景：用户提供日志文件并询问电源掉电、电源模块故障、电压异常、冗余失效、电源过载等问题的原因或修复方案；用户要求进行电源日志分析、故障溯源、根因定位或生成诊断报告时。
---

# 离线电源故障诊断

本技能通过分析从服务器收集的标准日志文件，帮助诊断 EulerOS 电源故障。

## 技能目录结构

本技能的目录结构如下，包含诊断脚本、参考资料和文档：

```text
offline-power-fault-diagnosis/
├── SKILL.md                          # 本技能的主文档
├── scripts/                          # 诊断脚本目录
│   ├── diagnose_summary.py           # Step 0: 故障日志采集脚本
│   ├── diagnose_ibmc.py              # Step 2: iBMC日志分析脚本
│   ├── diagnose_infocollect.py       # Step 2: InfoCollect日志分析脚本
│   ├── diagnose_messages.py          # Step 2: OS消息日志分析脚本
│   ├── diagnose_power.py             # Step 1 & 2 & 3: 电源专项分析、场景分类与交叉验证脚本
│   └── generate_report.sh            # Step 4: 报告生成脚本
└── references/                       # 参考资料目录
    ├── Power_fault_scenarios.md      # 电源故障场景分类
    ├── Power_scenario_analysis.md    # 电源故障场景专项分析指南
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
│   └── (电源状态/电压/错误事件) -> 使用 scripts/diagnose_ibmc.py
├── infocollect_logs/           # 系统信息收集工具生成的分类日志
│   └── (功耗数据/电压采集/热状态) -> 使用 scripts/diagnose_infocollect.py
└── messages/                   # 操作系统层面的系统日志
    └── (dmesg, syslog, messages) -> 使用 scripts/diagnose_messages.py
```

## ⚠️ 强制执行流程

**必须严格按以下顺序执行，禁止跳过或乱序：**

```
Step 0 (故障日志采集) → Step 1 (场景分类) → Step 2 (深入分析) → Step 3 (根因校验) → Step 4 (生成报告)
```

**执行规则：**
1. **顺序强制**：必须完成当前步骤并验证通过后，才能进入下一步
2. **场景分支**：Step 1 输出场景标签后，Step 2 必须执行对应的专项分析脚本
3. **数据校验**：Step 3 必须通过证据矩阵校验后才能生成最终报告
4. **文件适配**：日志文件不全时自动降级分析策略，但必须至少有一个日志文件

**每步完成标志：**
- Step 0：输出日志文件时间范围、文件统计、错误关键词概览
- Step 1：确定故障场景（如 POWER_LOSS 等）
- Step 2：输出物理级精准定位、传导链及初步根因
- Step 3：输出根因证据校验表、原生日志证据及置信度定性
- Step 4：生成完整的诊断报告文件（.md）

---

## 分析流程总览

| **Step 0** 故障日志采集 | 全量扫描日志目录并识别关键报错 | `python3 scripts/diagnose_summary.py <log_dir> -o` |
| **Step 1** 场景分类 | 判定现象并确定故障场景类型 | `python3 scripts/diagnose_power.py <log_dir>` (自动执行) |
| **Step 2** 深入分析 | 构建起止 T0 的传导链并执行专项诊断 | `python3 scripts/diagnose_power.py <log_dir> --hardware` |
| **Step 3** 根因校验 | 交叉质询证据链，执行证据双向校验 | `python3 scripts/diagnose_power.py <log_dir>` (自动执行校验逻辑) |
| **Step 4** 生成报告 | 汇总证据链与确认根因，生成诊断报告 | `bash scripts/generate_report.sh` |

---

## Step 0：故障日志采集

### 全量扫描（宏观分析）

**目标**：快速扫描所有日志文件，识别异常模块和关键报错，建立故障全景视图。

**执行命令**：
```bash
python3 scripts/diagnose_summary.py <log_dir> -o
```

---
## Step 1：场景分类

根据 Step 0 采集的日志概览，分析故障现象并确定故障场景类型。

### 场景分类概述

电源故障主要分为以下六种场景类型：

| 场景标签 | 中文描述 | 主要特征 |
|---------|---------|----------|
| `POWER_LOSS` | 服务器掉电 | 系统意外关机、iBMC 报告 AC 丢失或电源输入丢失 |
| `POWER_MODULE_FAILURE` | 电源模块故障 | iBMC SEL 报告 PSU 故障、PSU 缺失、硬件错误 |
| `VOLTAGE_ANOMALY` | 电压异常 | iBMC 报告电压超出范围、电压传感器故障 |
| `REDUNDANCY_FAILURE` | 电源冗余失效 | PSU 冗余丢失、多路供电负载分布严重不均 |
| `OVERLOAD` | 电源过载 | 系统功耗超过 PSU 额定容量、电流过载保护 |
| `TEMPERATURE_ISSUE` | 电源过热 | PSU 内部温度过高、风扇故障导致的热过载 |

### 场景 → 根因假设矩阵

确定场景标签后，**必须从以下矩阵中选取 2~3 个候选根因假设**，并在 Step 2 中逐一验证：

| 场景标签 | 候选根因假设（需在 Step 2 中验证） |
|---------|----------------------------------|
| `POWER_LOSS` | ① 机房 PDU/市电供电中断 ② PSU 输入短路触发断路器 ③ 服务器主板供路故障 |
| `POWER_MODULE_FAILURE` | ① PSU 物理损坏（电容/MOS管） ② PSU 固件不兼容 ③ 金手指连接不良 |
| `VOLTAGE_ANOMALY` | ① 母板 VRM 模块失效 ② PSU 电源纹波过大 ③ CPU/内存电流负载异常分配 |
| `REDUNDANCY_FAILURE` | ① 冗余管理策略配置错误 ② 其中一个 PSU 假在线 ③ 电源背板故障 |
| `OVERLOAD` | ① 系统负载瞬时峰值超过上限 ② PSU 老化导致满载能力下降 ③ 外部短路伪告警 |
| `TEMPERATURE_ISSUE` | ① PSU 散热风道堵塞 ② PSU 内部风扇转子锁定故障 ③ 机柜进风温度过高 |

> ⚠️ **强制要求**：Step 2 分析结束后，必须对上述候选根因逐一标注：✅ 已证实 / ❌ 已排除 / ❓ 证据不足

---
## Step 2：深入分析

根据 Step 1 的场景分类结果，必须**首先完成时序关联与故障传导链重建**，然后再通过通用或专项脚本收集对应证据，最终给出精确的物理坐标定位。

### 2.1 时序关联与传导链重建 (核心理论框架)

#### 2.1.1 确定电源故障零点 (T0)

定义为**最早可观测到异常的时间戳**。确定优先级：
1. **P1 (硬件层)**：iBMC SEL 的 `AC Lost` / `Power Loss` / `Critical Voltage` 报错。
2. **P2 (内核层)**：`dmesg` 中的系统断电信号或电压违规警告。
3. **P3 (应用层)**：进程因为电源波动导致的直接宕机或意外重启。

#### 2.1.2 多维日志对齐与时间轴矩阵
*示例：PSU 内部风扇故障引发的热下电传导链*
```text
T0-10m  ├─ [iBMC Sensor] PSU 1 进风口温度开始持续攀升。
T0-2m   ├─ [iBMC SEL]    检测到 PSU 1 Fan Rotor Locked (转子锁定)。
T0-10s  ├─ [iBMC SEL]    PSU 1 过热保护触发 (Over-temp Trip) 并断电。
T0      ├─ [iBMC SEL]    Redundancy Lost (冗余丢失) → 标定为 T0。
```

#### 2.1.3 电源专属故障传导链推断
- **规则一：源头掉电传导链**
  - *特征*：所有 PSU 几乎同时报告 `AC Lost`。
  - *传导链*：[外部 PDU 闪停/掉电] -> [PSU AC Lost] -> [PSU Power Loss] -> [系统断电]。
- **规则二：单机电源硬件传导链**
  - *特征*：单个 PSU 报错后系统依然运行（冗余）或由于负载增加导致另一路也下电。
  - *传导链*：[PSU 1 内部故障] -> [iBMC 记录 PSU Failure] -> [冗余丢失] -> [系统宕机（若负载超载）]。

---

### 2.2 日志脚本分析执行

```bash
# iBMC 日志分析
python3 scripts/diagnose_ibmc.py <log_dir>

# 电源综合分析（推荐）
python3 scripts/diagnose_power.py <log_dir> --hardware
```

**Step 2 完成标志**：
1. ✅ 输出故障零点 T0 的精确时间戳及其所依托的具体日志行。
2. ✅ 梳理出以 T0 为基准的结构化事件序列矩阵。
3. ✅ 给出精确到物理部件（PSU 1/2 等）的细粒度定位结果。

---
## Step 3：根因反思与证据双向校验

**目标**：交叉质询证据链，确保结论 100% 由底层日志支撑，防范发散性推断。

### 3.1 交叉质询铁律
1. **孤证不立原则**：系统报 `unexpected shutdown` 不能直接断定 PSU 坏，必须配合 iBMC 的硬件告警。
2. **逻辑闭环原则**：从 T0 到最终结果，传导链必须符合科学原理。
3. **互斥排异原则**：若判定是外部掉电，则必须证明服务器内部 PSU 无硬件自检报错。

### 3.2 强制：根因证据校验表 (Evidence Validation Matrix)

| 校验维度 | 校验标准要求 | 强制证据格式 |
| :--- | :--- | :--- |
| **E1: 时序连续性** | 掉电信号与系统关机信号是否在 5 秒窗内？ | `[✅/❌]` + 时序说明 + 日志片段 |
| **E2: 物理同一性** | 各级日志指控的槽位 (Slot 1/2) 是否一致？ | `[✅/❌]` + 槽位对应关系验证 |
| **E3: 现象排他性** | 是否排除了由于 CPU 过热导致的系统强制下电可能性？ | `[✅/❌]` + 环境温度日志干净证据 |

### 3.3 结论防发散拦截机制 (Anti-Hallucination Mechanism)

*   **断链阻断**：如果在证据校验表中存在 `[❌ 冲突]`，则视为假想无效，强制拦截。
*   **降级处分**：若缺乏 iBMC 底层支持，必须降级为“高度疑似 (Suspected)”状态。
*   **严禁用词限制**：严禁在证据不足时使用“肯定”、“必然”等断言。

---
## Step 4：生成报告

汇总 Step 0～3 的所有分析结果，生成结构化诊断报告：

```bash
bash scripts/generate_report.sh \
    --analysis /tmp/power_analysis_results.json \
    --output ./power_diagnosis_report.md
```

**根因具体性要求：**
- ❌ "电源故障"
- ✅ "PSU 2 内部风扇故障导致其在负载 400W 下运行 1 小时后触发热保护下电 (T0=2026-03-20 10:00:00)"

---

## 参考资料

* [电源故障场景分类](references/Power_fault_scenarios.md)
* [电源故障场景专项分析指南](references/Power_scenario_analysis.md)
* [InfoCollect 诊断指南](references/infocollect_guide.md)
* [OS Messages 分析](references/messages.md)
* [Huawei iBMC 分析](references/huawei_ibmc.md)
* [H3C iBMC 分析](references/h3c_ibmc.md)
* [Inspur iBMC 分析](references/Inspur_ibmc.md)

---

## 分析原则

0. **根因优先**：终点是“为什么”，而不是“发生了什么”。
1. **硬件优先**：电源问题优先排错 iBMC/SEL。
2. **证据驱动**：每个结论必须有日志数据支撑。
3. **时空对齐**：必须校正 OS 与 iBMC 的时间偏差。
4. **离线分析**：仅基于日志，不执行在线命令。