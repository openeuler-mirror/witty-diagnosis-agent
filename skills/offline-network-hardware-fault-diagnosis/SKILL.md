---
name: offline-network-hardware-fault-diagnosis
description: 通过分析服务器离线日志（iBMC、OS Messages、InfoCollect）诊断网络硬件故障（网卡、PCIe、链路、物理配置）并定位物理级根因。当用户提供日志并询问网卡硬件错误、PCIe 致命错误、网口 Link Down、丢包/错包/延时大、Bond 切换、网卡驱动 Panic 或固件加载失败，以及需要对网络异常进行底层物理坐标定位时，调用本技能。
---

# 离线网络硬件故障诊断

本技能通过分析从服务器收集的标准日志文件，重点诊断 Linux 网络硬件及物理链路层故障。

## 技能目录结构

本技能的目录结构如下，包含诊断脚本、参考资料和文档：

```text
offline-network-hardware-fault-diagnosis/
├── SKILL.md                          # 本技能的主文档
├── scripts/                          # 诊断脚本目录
│   ├── diagnose_summary.py           # Step 0: 故障日志采集脚本
│   ├── diagnose_ibmc.py              # Step 2: iBMC日志分析脚本
│   ├── diagnose_infocollect.py       # Step 2: InfoCollect/系统配置分析脚本
│   ├── diagnose_messages.py          # Step 2: OS消息日志分析脚本
│   └── diagnose_network.py           # Step 2: 网络专项分析脚本
└── references/                       # 参考资料目录
    ├── network_fault_scenarios.md    # 网络故障场景分类表
    ├── network_scenario_analysis.md  # 网络故障场景专项分析指南
    ├── infocollect_guide.md          # InfoCollect诊断指南
    ├── messages.md                   # OS消息日志分析指南
    ├── huawei_ibmc.md                # 华为iBMC分析指南
    ├── h3c_ibmc.md                   # H3C iBMC分析指南
    └── Inspur_ibmc.md                # Inspur iBMC分析指南
```

## 输入日志目录结构与对应诊断脚本

以 `/path/to/logs/xxxx` 为例，标准的服务器日志收集包通常具有以下层级结构。本技能提供了针对性的脚本来分析不同层级的日志。

> **注意**：在实际场景中，用户提供的日志包可能不完整，请报根据实际存在的日志类型灵活选择对应的分析脚本。

```text
<日志根目录> (例如: 10.120.6.76)
├── ibmc_logs/                  # iBMC 硬件带外管理日志
│   └── (网卡温度/插槽/硬件错误事件) -> 使用 scripts/diagnose_ibmc.py
├── infocollect_logs/           # 系统信息收集工具生成的分类日志
│   └── (网卡配置/驱动/性能数据)    -> 使用 scripts/diagnose_infocollect.py
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
2. **场景分支**：Step 1 输出场景标签后，Step 2 必须执行对应的专项或组合分析脚本
3. **数据校验**：Step 3 必须通过证据矩阵校验后才能得出最终结论
4. **文件适配**：日志文件不全时自动降级分析策略，但必须至少有一个日志文件
5. **专注硬件**：分析过程应锁定网络硬件及路径，排查链路层、驱动层及物理环境对网络稳健性的影响。

**每步完成标志：**
- Step 0：输出日志文件时间范围、文件统计、错误关键词概览
- Step 1：确定故障场景（如 NIC_HARDWARE_FAILURE 等）
- Step 2：输出物理级精准定位（如 PCIe BDF/Slot ID）、传导链及初步根因
- Step 3：输出根因证据校验表、原生日志证据及置信度定性
- Step 4：在界面上按固定结构输出最终的分析报告（**严禁生成独立文件**）

---

## 分析流程总览

| **步骤** | **阶段目标** | **主要工具/方法** |
| :--- | :--- | :--- |
| **Step 0** 故障日志采集 | 全量/定点扫描日志目录并识别关键报错 | `diagnose_summary.py <log_dir> [-k/-d/-s]` |
| **Step 1** 场景分类 | 判定现象并确定故障场景类型 | 根据 Step 0 采集结果进行场景匹配 |
| **Step 2** 深入分析 | 构建起止 T0 的传导链并执行诊断 | 使用 `diagnose_network.py` 或多维脚本组合获取多维证据 |
| **Step 3** 根因校验 | 交叉质询证据链，执行证据双向校验 | 对比 iBMC/内核/系统日志的一致性，防止结论发散 |
| **Step 4** 界面输出分析报告 | 汇总证据链与确认根因，在界面直接输出报告内容 | 结构化输出：结论 + 故障链条 + 修复建议 |

---

## Step 0：故障日志采集

### 全量扫描（宏观分析）

**目标**：快速扫描所有日志文件，识别网络硬件及驱动层异常，建立故障全景视图。

**执行命令**（根据场景选择）：
```bash
# 场景 1：无明确过滤条件（默认全量扫描）
python3 scripts/diagnose_summary.py <log_dir>

# 场景 2：用户提供故障关键词时（如网卡名、PCIe 地址）
python3 scripts/diagnose_summary.py <log_dir> -k "eth0" "0000:03:00.0"

# 场景 3：用户提供故障发生时间/日期时
python3 scripts/diagnose_summary.py <log_dir> -d "Mar 16"
python3 scripts/diagnose_summary.py <log_dir> -s "2026-03-10 08:00:00" -e "2026-03-10 12:00:00"
```

### 精细定位（微观分析）

**目标**：优先使用脚本参数锁定范围，再辅以 `grep` / `less` 等命令查看更细节的原始日志上下文。

---
## Step 1：场景分类

根据 Step 0 采集的日志概览，分析故障现象并确定故障场景类型。

### 场景分类概述

> 📖 **参考详见**：[网络故障场景分类](references/network_fault_scenarios.md)

| 场景标签 | 中文描述 | 主要特征 |
| :--- | :--- | :--- |
| `NIC_HARDWARE_FAILURE` | 网卡硬件故障 | iBMC SEL 报告硬件错误 (Fatal Error)、温度超限、网卡离线/离位 |
| `DRIVER_ISSUE` | 驱动/固件问题 | 内核 Panic (TX hang)、固件加载失败、驱动版本与内核版本不匹配 |
| `LINK_DOWN` | 物理链路故障 | 网口 Carrier Lost、物理网口不断 Up/Down (Flapping)、Bond 全员离线 |
| `PERFORMANCE_DEGRADATION` | 性能下降/丢包 | 丢包/错包率高 (CRC Error)、延时大/抖动、硬件转发瓶颈 |
| `INTERRUPT_ERROR` | 中断/调度错误 | 中断极化严重、MSI-X 配置失败、CPU 中断处理负载不均 |
| `CONFIG_ERROR` | 配置/协议错误 | IP 冲突、VLAN/MTU 不一致、udev 网卡重命名导致逻辑错乱 |

### 场景辅助分析与根因假设

确定场景后，**必须参考专项分析指南**进行候选根因验证：

> 🔍 **专项分析指南**：[网络故障场景专项分析指南](references/network_scenario_analysis.md)

| 场景标签 | 候选根因假设（需在 Step 2 中验证） |
| :--- | :--- |
| `NIC_HARDWARE_FAILURE` | ① 网卡芯片物理损坏 ② PCIe 插槽接触不良 ③ 环境温度过高导致过载保护 |
| `DRIVER_ISSUE` | ① 驱动 Bug 引起内存死锁 ② 固件(Firmware)版本过低触发逻辑挂死 |
| `LINK_DOWN` | ① 网线/光模块物理衰减导致 Rx 功率过低 ② 对端交换机端口异常 |
| `PERFORMANCE_DEGRADATION` | ① 链路 CRC 错误引发持续重传 ② PCIe 链路带宽协商不足 |
| `INTERRUPT_ERROR` | ① 中断亲和性(Affinity)未配置 ② 驱动不支持多队列接收 |
| `CONFIG_ERROR` | ① MTU 突发大包丢弃 ② ARP 探测失败引发 IP 离线 |

**Step 1 完成标志：**
1. ✅ 确定场景标签，并完成对候选根因的 ✅/❌/❓ 标注路径。
2. ✅ 记录故障现象（如：`eth0 Link Down`）与初步物理指向。

---
## Step 2：深入分析

根据 Step 1 结果，**首先完成时序关联与故障传导链重建**，再通过多源脚本及网络专项脚本收集证据。

### 2.1 时序关联与传导链重建 (核心理论框架)

#### 2.1.1 确定网络故障零点 (T0)

定义为**最早可观测到异常的时间戳**。优先级：
1. **P1**：硬件错误（iBMC/SEL） - 底层物理报错（如 PCIe Fatal）。
2. **P2**：内核感知（dmesg） - 早期 PCIe AER 错误、Tx hang。
3. **P3**：系统调度（syslog） - `Link Down`、`Carrier Lost`。
4. **P4**：应用感知 - 业务响应超时。

#### 2.1.2 多维日志对齐与时间轴矩阵 (示例)
```text
T0-5m   ├─ [InfoCollect] 统计发现 eth0 侧 CRC Error 计数开始异常增长。
T0-1m   ├─ [iBMC SEL]    检测到 PCIe 链路修正错误警告。
T0      ├─ [OS dmesg]    `ixgbe 0000:03:00.0: TX hang` → 标定故障零点 T0。
T0+1s   ├─ [OS dmesg]    `Reset adapter` 驱动尝试自愈重启物理单元。
T0+2s   ├─ [OS messages] `eth0: link down` 业务中断。
```

#### 2.1.3 网络故障传导链推断
- **硬件向上传导**：插槽不良 (Root) → PCIe AER 错误 (T0) → 驱动 Reset (Action) → 链路中断 (Result)。
- **外部向内传导**：网线衰减 (Root) → Link Flapping (T0) → OS 重复初始化端口 → 业务延时。

> ⚠️ **精确定位强制要求**：严禁仅使用“网卡故障”结论。必须精确定位至：`PCIe 0000:03:00.0 (eth0) -> SFP+ Module Rx Power Low (-15dBm)`。

---
### 2.2 日志脚本分析执行

```bash
# iBMC 分析
python3 scripts/diagnose_ibmc.py <log_dir>
# 网络专项分析 (强烈推荐)
python3 scripts/diagnose_network.py <log_dir> --hardware    # 硬件/PCIe/温度故障
python3 scripts/diagnose_network.py <log_dir> --link        # 链路/连接故障
python3 scripts/diagnose_network.py <log_dir> --performance # 性能/丢包故障
```

**Step 2 完成标志**：
1. ✅ 输出故障零点 T0 及其原生日志证据。
2. ✅ 给出物理级（BDF/Slot/Port）的细粒度定位。

---
## Step 3：根因反思与证据双向校验 (Cross-Examination Rules)

### 3.1 交叉质询铁律
1. **孤证不立**：任何物理故障（如网卡坏）不能仅凭 OS 层一个 Link Down 就下结论。必须找到硬件层（iBMC/ethtool）第二独立证据。
2. **逻辑闭环**：传导链不允许跳跃，确保根因与现象之间有科学因果支撑。
3. **互斥排异**：判定故障为 A 网卡时，需核实同主板/同链路的其他端口是否正常，以排除共性故障（如主板 PCIe 控制器）。

### 3.2 强制：根因证据校验表 (Evidence Validation Matrix)
| 校验维度 | 校验标准要求 | 强制证据格式 |
| :--- | :--- | :--- |
| **E1: 时序连续性** | 从结果回溯到 T0，时序是否一致且无断层？ | `[✅/❌]` + 原生日志片段 |
| **E2: 物理同一性** | OS 层的 ethX 与物理层的 BDF/Slot 是否精准映射？ | `[✅/❌]` + 映射拓扑说明 |
| **E3: 现象排他性** | 是否排除了对端交换机配置变更、网线老化等干扰？ | `[✅/❌]` + 排除说明 |

---
## Step 4：界面输出分析报告

汇总 Step 0～3 结果，**直接在当前对话界面输出**。

**报告结构：**
1. **Executive Summary** — 故障端口、具体根因、直接后果。
2. **Fault Chains** — **时间链** (带时间戳的节点) + **传播链** (物理因果路径)。
3. **Technical Analysis & Root Cause** — 结合 E1/E2/E3 的多源证据分析。
4. **Recommendations** — 备件更换、物理操作或固件版本建议。

**诊断分析完成性检查（输出前必检）：**
- [ ] 是否给出了**精确的物理标识**（如 PCIe BDF 或网卡槽位）？
- [ ] 故障时间链中的每一个节点是否都有准确的时间点？

---
## 参考资料
* [网络故障场景分类](references/network_fault_scenarios.md)
* [网络故障场景专项分析指南](references/network_scenario_analysis.md)
* [InfoCollect 诊断指南](references/infocollect_guide.md)
* [OS Messages 诊断指南](references/messages.md)
* [Huawei iBMC 分析指南](references/huawei_ibmc.md)
* [H3C iBMC 分析指南](references/h3c_ibmc.md)
* [Inspur iBMC 分析指南](references/Inspur_ibmc.md)

---