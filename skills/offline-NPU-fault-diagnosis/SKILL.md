---
name: offline-NPU-fault-diagnosis
description: 通过分析服务器离线日志（iBMC、OS Messages、InfoCollect）诊断 NPU（神经网络处理器）及其关联的 PCIe 链路、驱动固件及内存故障。当用户提供日志并询问 NPU 掉卡、HBM 故障、AER 链路错误、驱动加载失败、Acl Error 及温度过高保护时，调用本技能。
---

# 离线 NPU 故障诊断

本技能通过分析从服务器收集的标准日志文件，重点诊断 NPU（如华为昇腾 Ascend 系列）及其关联通信链路、固件与存储（HBM）子系统的故障。

## 技能目录结构

本技能的目录结构如下，包含诊断脚本、参考资料和文档：

```text
offline-NPU-fault-diagnosis/
├── SKILL.md                          # 本技能的主文档
├── scripts/                          # 诊断脚本目录
│   ├── diagnose_summary.py           # Step 0: 故障日志采集脚本
│   ├── diagnose_ibmc.py              # Step 2: iBMC日志分析脚本
│   ├── diagnose_infocollect.py       # Step 2: InfoCollect专项分析脚本
│   └── diagnose_messages.py          # Step 2: OS消息日志分析脚本
└── references/                       # 参考资料目录
    ├── NPU_fault_scenarios.md        # NPU 故障场景分类表
    ├── NPU_scenario_analysis.md      # NPU 故障场景专项分析指南
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
│   └── (PCIe/硬件故障/过温报警) -> 使用 scripts/diagnose_ibmc.py
├── infocollect_logs/           # 系统信息收集工具生成的分类日志
│   └── (npu-smi/固件信息/环境数据) -> 使用 scripts/diagnose_infocollect.py
└── messages/                   # 操作系统层面的系统日志
    └── (dmesg, syslog, ascend日志) -> 使用 scripts/diagnose_messages.py
```

## ⚠️ 强制执行流程

**必须严格按以下顺序执行，禁止跳过或乱序：**

```
Step 0 (故障日志采集) → Step 1 (场景分类) → Step 2 (深入分析) → Step 3 (根因校验) → Step 4 (界面输出分析报告)
```

**执行规则：**
1. **顺序强制**：必须完成当前步骤并验证通过后，才能进入下一步。
2. **场景分支**：Step 1 输出场景标签后，Step 2 必须针对性收集相关证据。
3. **数据校验**：Step 3 必须通过证据矩阵校验后才能得出最终结论。
4. **文件适配**：日志文件不全时自动降级分析策略，但必须至少有一个日志文件。
5. **专注 NPU**：分析过程应锁定 NPU 计算单元、HBM 显存、PCIe 拓扑及相关驱动栈。

**每步完成标志：**
- Step 0：输出日志文件时间范围、文件统计、错误关键词（Acl Error, HBM, ECC, PCIe AER等）概览。
- Step 1：确定故障场景（如 NPU_HARDWARE_FAILURE 等）。
- Step 2：输出物理级精准定位（NPU ID / PCIe Slot）、传导链及初步根因。
- Step 3：输出根因证据校验表、原生日志证据及置信度定性。
- Step 4：在界面上按固定结构输出最终的分析报告（**严禁生成独立文件**）。

---

## 分析流程总览

| **步骤** | **阶段目标** | **主要工具/方法** |
| :--- | :--- | :--- |
| **Step 0** 故障日志采集 | 全量/定点扫描日志目录并识别关键报错 | `diagnose_summary.py <log_dir> [-k/-d/-s]` |
| **Step 1** 场景分类 | 判定现象并确定故障场景类型 | 根据 Step 0 采集结果进行场景匹配 |
| **Step 2** 深入分析 | 构建起止 T0 的传导链并执行诊断 | 使用 `diagnose_ibmc.py/diagnose_infocollect.py/diagnose_messages.py` 获取多维证据 |
| **Step 3** 根因校验 | 交叉质询证据链，执行证据双向校验 | 对比 iBMC/内核/系统日志的一致性，防止结论发散 |
| **Step 4** 界面输出分析报告 | 汇总证据链与确认根因，在界面直接输出报告内容 | 结构化输出：结论 + 故障链条 + 修复建议 |

---

## Step 0：故障日志采集

### 全量扫描（宏观分析）

**目标**：快速扫描所有日志文件，识别 NPU 子系统的异常，建立故障全景视图。当存在特定报错或时间范围时，利用参数进行第一轮初步精确定位。

**执行命令**（根据场景选择）：
```bash
# 场景 1：无明确过滤条件（默认全量扫描）
python3 scripts/diagnose_summary.py <log_dir>

# 场景 2：用户提供故障关键词时
python3 scripts/diagnose_summary.py <log_dir> -k "npu" "pcie" "aer" "ecc"

# 场景 3：用户提供故障发生时间/日期时
python3 scripts/diagnose_summary.py <log_dir> -d "Mar 16"
python3 scripts/diagnose_summary.py <log_dir> -s "2026-03-10 08:00:00" -e "2026-03-10 12:00:00"
```

### 精细定位（微观分析）

**目标**：在优先使用上述带有参数的扫描命令锁定范围的基础上，结合全量扫描结果，辅以 `grep` / `less` 等文件操作命令查看更细节的原始日志上下文。尤其关注 `dmesg` 中的 Ascend/NPU 内核报错栈。

> **注意：使用脚本时，可优先执行 `--help` 参数，了解脚本多维度过滤用法。**

---
## Step 1：场景分类

根据 Step 0 采集的日志概览，分析故障现象并确定故障场景类型。

### 场景分类概述

根据 Step 0 采集的日志概览，分析故障现象并从以下标准场景中确定故障场景类型。

> 📖 **参考详见**：[NPU 故障场景分类](references/NPU_fault_scenarios.md)

| 场景标签 | 中文描述 | 主要特征 |
| :--- | :--- | :--- |
| `NPU_HARDWARE_FAILURE` | NPU 核心硬件故障 | NPU 芯片损坏、不可恢复的物理级缺陷、设备处于 Offline 状态 |
| `NPU_PCIE_LINK_ISSUE` | PCIe 链路与拓扑故障 | AER 报错、PCIe 训练失败、NPU 设备 Missing、链路重置 |
| `NPU_DRIVER_SW_STACK` | 驱动与软件栈报错 | CANN 与 Driver 不匹配、`Acl Error`、驱动加载失败、调度崩溃 |
| `NPU_HBM_PERFORMANCE` | HBM 与显存故障 | ECC 未修正/可修正错误频繁、显存访问超时、带宽受限 |
| `NPU_THERMAL_POWER` | 热电与功耗异常 | iBMC 过温保护（Thermal Throttling）、电源供给异常、电涌掉卡 |

### 场景辅助分析与根因假设

确定场景标签后，**必须参考专项分析指南**进行候选根因的初步验证：

> 🔍 **专项分析指南**：[NPU 故障场景专项分析指南](references/NPU_scenario_analysis.md)

| 场景标签 | 候选根因假设（需在 Step 2 中验证） |
| :--- | :--- |
| `NPU_HARDWARE_FAILURE` | ① NPU 核心计算单元损坏 ② 固件死锁或崩溃触发不可逆离线 |
| `NPU_PCIE_LINK_ISSUE` | ① PCIe Riser 卡或主板槽位虚接 ② CPU 侧 PCIe 控制器异常 |
| `NPU_DRIVER_SW_STACK` | ① 内核版本与驱动不兼容导致 Panic ② 应用越权访问导致设备失联 |
| `NPU_HBM_PERFORMANCE` | ① 显存颗粒物理损坏引发大量 Uncorrectable ECC ② 持续高负载引发纠错瓶颈 |
| `NPU_THERMAL_POWER` | ① 风扇故障或风道堵塞引发高温限频/降级 ② 插槽供电不足导致瞬时断电 |

> ⚠️ **强制要求**：在进入 Step 2 深入分析前，应先通过 [NPU_scenario_analysis.md](references/NPU_scenario_analysis.md) 了解对应场景的分析路径与关键证据点。分析结束后，必须对上述候选根因方案逐一标注：✅ 已证实 / ❌ 已排除 / ❓ 证据不足。

**Step 1 完成标志：**
1. ✅ 确定主要故障场景标签（从上述类型中选择）。
2. ✅ 记录故障现象与关键证据。
3. ✅ 为 Step 2 深入分析提供明确的故障场景方向。

---
## Step 2：深入分析

根据 Step 1 的场景分类结果，必须**首先完成时序关联与故障传导链重建**，然后再通过多源脚本收集证据，最终给出精确的物理坐标定位。

### 2.1 时序关联与传导链重建 (核心理论框架)

**目标**：通过多源日志的时间戳对齐，重建故障发生的完整时间轴，厘清事件的先后顺序与因果链，为根因定位提供时序证据。

#### 2.1.1 确定 NPU 故障零点 (T0)

故障零点（T0）是时序分析的基准锚点，定义为**最早可观测到异常的时间戳**。确定优先级（由高到低）：

| 优先级 | 来源 | 说明 |
|----|----|----|
| **P1** | 硬件错误日志（iBMC / SEL） | 底层致命报错（如 PCIe Fatal Error, Over Temperature, Hardware Failure），时间点最准确。 |
| **P2** | 内核感知层（`dmesg` / `messages`） | 最早出现的 PCIe AER (Advanced Error Reporting)、ECC Uncorrectable Error、NPU Driver 初始化失败或设备 Reset。 |
| **P3** | 驱动与组件层（`syslog` / OS 日志） | `npu-smi` 服务状态异常日志、Host 侧调度器卡死报错。 |
| **P4** | 应用感知层 | 上层训练任务崩溃、`Acl Error` 报错、算子执行超时（HCCP timeout），通常滞后较大。 |

> ⚠️ **时钟偏差处理**：多节点/集群场景下，需留意 iBMC 时间与 OS 时间（NTP）是否存在时钟偏移。多源对齐时需留意并修正该偏差量。

#### 2.1.2 多维日志对齐与时间轴矩阵

以 T0 为基准，将 iBMC 传感器告警、dmesg 报错、npu-smi 状态和应用程序报错统一映射到绝对时间轴上，构建**事件序列矩阵**。
*示例：因 HBM 物理损坏引发的业务中断传导链*
```text
T0-5m   ├─ [OS dmesg]    系统检测到个别可修正的 HBM ECC Error，系统尝试后台修正。
T0      ├─ [iBMC SEL]    上报 NPU Slot 4 `Uncorrectable ECC Memory Error` -> 致命故障零点 T0。
T0+1s   ├─ [OS dmesg]    内核捕获 NMI，NPU 驱动上报设备状态变为异常（Abnormal/Offline）。
T0+5s   ├─ [OS sys/dmesg] 正在执行的训练进程抛出 `Device Unreachable` 异常。
T0+1m   ├─ [App Log]     上层框架（如 MindSpore/PyTorch）级联报错退出（Acl Error）。
```

#### 2.1.3 NPU 故障传导链推断 (示例)

结合对齐的时间轴矩阵，运用以下规则推导故障传导链方向：
- **规则一：自底向上（硬件主导损坏）**
  - *传导链*：HBM ECC 物理击穿 (T0) → 触发 iBMC 及 dmesg 硬件报错 → NPU Driver 重置设备 → 上层应用抛出报错退出。
- **规则二：环境向硬件传导（散热/链路主导）**
  - *传导链*：机房空调故障/散热不良 → iBMC 检测 NPU Die 过温告警 (T0) → NPU 触发 Thermal Throttling 降频 → 最终导致驱动超时（Timeout）。

> ⚠️ **精确定位强制要求**：在 NPU 诊断中，**严禁仅得出“NPU 掉卡”或“NPU 坏了”这类含糊结论。**
> 必须通过证据追踪到细粒度的物理坐标及具体子模块定位，例如：
> - ✅ 正确结论：`PCIe Slot X (NPU ID: Y) -> HBM Uncorrectable ECC Error -> 内存颗粒物理损坏`。
> - ❌ 错误结论：`发生 Acl Error` 或仅仅说是 `NPU Offline`。

---

### 2.2 日志脚本分析执行 (执行工具动作)

#### 2.2.1 通用分析流程

通用分析流程适用于所有 NPU 故障场景，提供基础的日志提取与数据分析能力：

```bash
# iBMC 日志分析（硬件层与带外警告）
python3 scripts/diagnose_ibmc.py <log_dir>

# InfoCollect 日志分析（固件状态/NPU-SMI/环境信息）
python3 scripts/diagnose_infocollect.py <log_dir>

# OS Messages 日志分析（操作系统层与内核驱动异常）
python3 scripts/diagnose_messages.py <log_dir>
```

> **注意：使用脚本时，可优先执行 `--help` 参数，了解脚本多维度过滤用法。**

#### 2.2.2 按场景专项分析

当 Step 1 确定故障场景后，优先分析对应的关键指标：
1. **PCIe 链路故障**：重点在 `dmesg` 与 iBMC 中检索 `AER`、`PCIe training` 和 `Link reset` 相关字眼。
2. **HBM 显存故障**：重点检索 `ECC`, `Memory Error`, `HBM` 关键字。
3. **驱动与软件栈**：检查 `npu-smi info` 历史输出（如有），分析 CANN 版本与 OS Kernel log 中驱动抛出的 Panic Call Trace。

#### 2.2.3 分析执行原则

1. **场景优先原则**：当故障现象明确匹配某个场景时，优先针对该场景取证。
2. **组合使用原则**：必须同时使用带外（iBMC）和带内（OS）脚本进行相互验证。
3. **逐步深入原则**：从宏观概览开始，逐步根据时序对齐结果深入特定日志行。

**Step 2 完成标志**：
1. ✅ 输出故障零点 T0 的精确时间戳及其所依托的具体日志行。
2. ✅ 梳理出以 T0 为基准的结构化事件序列矩阵与核心故障传导链。
3. ✅ 给出精确到物理部件（例如 Slot ID / NPU ID）的细粒度定位结果。
4. ✅ 收集脚本产出的相关原生日志片段作为强有力的支撑证据。

---
## Step 3：根因反思与证据双向校验 (Cross-Examination Rules)

**目标**：对 Step 2 输出的“初步传导链与定位结果”进行“交叉质询”，确保得出的最终结论 100% 由底层日志支撑。

### 3.1 交叉质询铁律 (Cross-Examination Rules)

1. **孤证不立原则**：任何物理级 NPU 故障（如 HBM 损坏引发掉卡），绝对不能仅凭系统驱动层的一个报错（如 `Device Missing`）就下断言。**必须**同时找到硬件层（如 iBMC SEL）的独立证据源支撑（如果 iBMC 日志存在）。
2. **逻辑闭环原则**：从 T0 到最终业务故障结果，传导链不允许出现跳跃。例如：`PCIe AER 警告`不能直接等同于`NPU 核心完全烧毁`，必须考量中间的 Reset 恢复机制与日志的连续性。
3. **互斥排异原则**：如果判定故障是 PCIe Riser 卡损坏，则必须说明同一 Riser 卡上的其他 PCIe 设备（如有）的表现，以排除单 NPU 故障或共因。

### 3.2 强制：根因证据校验表 (Evidence Validation Matrix)

在确认最终结论前，强制要求进行证据校验：

| 校验维度 | 校验标准要求 | 强制证据格式（分析打样要求） |
| :--- | :--- | :--- |
| **E1: 时序连续性** | 硬件/环境级告警时间是否早于或同步于驱动与应用层崩溃时间？ | `[✅/❌ 结果]` + `时序对齐说明（含 T0）` + `原生日志片段` |
| **E2: 物理同一性** | 各级日志指控的 OS 逻辑设备（/dev/davinciX）与物理槽位（Slot Y）映射是否准确不冲突？ | `[✅/❌ 结果]` + `设备编号与槽位映射对齐说明` |
| **E3: 现象排他性** | 是否排除了宿主机 OOM Kill、手动重启引发的合法 Offline 及散热故障引发的连带表现？ | `[✅/❌ 结果]` + `环境及系统级日志排除说明` |

### 3.3 结论防发散拦截机制 (Anti-Hallucination Mechanism)

*   **断链阻断**：若无法从网络或存储日志中找到证明因果传导的片段（只有应用报错而毫无底层记录），强制触发流程拦截，回溯重新收集线索。
*   **降级处分**：若确实缺乏某一层关键日志（如缺少 iBMC，仅有 dmesg），必须在报告中声明为**“疑似故障 (Suspected)”**并标注证据断层位置。
*   **严禁用词限制**：在证据链未能满足完全闭环标准前，**严禁**使用“绝对”、“必须更换主板”等无回旋余地的决定性断言。

**Step 3 完成标志**：
1. ✅ 结构化地产出《根因证据校验表》中每一项的自查结论。
2. ✅ 每个通过项均附带 Trace 日志中的 Timestamp 和原生日志摘录。
3. ✅ 输出与之等位置信度（已证实 / 高度疑似 / 多重原因交织）的严谨研判方向。

---
## Step 4：界面输出分析报告

汇总 Step 0～3 的所有分析结果，直接在当前对话界面输出结构化的诊断结论。**禁止生成任何额外的文档或报告文件。**

**报告结构：**

1. **Executive Summary（故障摘要）** — 故障物理节点与受影响的 NPU Device ID、直接原因、后果概述。
2. **Fault Chains（故障链条分析）** — **必须包含以下两级链条：**
   - **故障时间链 (Fault Time Chain)**：列出带关键节点的事件序列，**每个节点必须包含准确的时间戳**（精确到具体时间与时区，明确标出 T0）。
   - **故障传播链 (Fault Propagation Chain)**：清晰描绘引发系统表现的物理/链路因果传导路径（例如：`风扇异常停转 -> NPU 核心触发 Overtemp 阈值 -> BMC 切断供电保护 -> 驱动上报 Device Lost`）。
3. **Technical Analysis & Root Cause（技术分析与根因）** — 基于 Step 2 的传导链回溯与 Step 3 的交叉质询，给出硬件/驱动/链路维度的实质性根因，并提供多源证据链（E1/E2/E3）强力支撑。
4. **Recommendations（修复建议）** — 例如：重新插拔 Riser 卡、更换 NPU 模组备件、修复机柜散热、升级驱动固件对应版本等。

**诊断分析完成性检查（输出报告前必检）：**

在得出结论前，必须回答以下问题：
- [ ] 是否给出了精确的**物理槽位号**（Slot ID）与 **NPU 逻辑编号**？
- [ ] Step 1 场景假设矩阵是否已完成 ✅/❌ 标注初筛？
- [ ] 在归咎于 NPU 硬件故障前，是否排除了 PCIe 主板背板及电源模块等外围元器件的问题？
- [ ] **故障时间链中的每一个节点是否都有准确的时间？**
- [ ] **是否清晰勾勒并输出了严谨的故障传播链？**

---

## 参考资料

* [InfoCollect 诊断指南](references/infocollect_guide.md)
* [OS Messages 诊断指南](references/messages.md)
* [Huawei iBMC 分析](references/huawei_ibmc.md)
* [H3C iBMC 分析](references/h3c_ibmc.md)
* [Inspur iBMC 分析](references/Inspur_ibmc.md)

---
