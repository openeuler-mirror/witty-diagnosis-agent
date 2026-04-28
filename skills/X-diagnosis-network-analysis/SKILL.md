---
name: X-diagnosis-network-analysis
description: |
  专业的 Linux 网络系统在线故障诊断 skill。该 skill 严格限制使用 X-diagnosis 工具栈中的 6 种核心网络诊断工具（xd_ntrace, xd_tcpresetstack, xd_tcpskinfo, xd_arpstormcheck, xd_netvringcheck, xd_skblen_check）进行精准探测。
---

# 在线网络系统故障诊断

本技能旨在利用 Agent 自动化在目标故障主机上实时执行 X-diagnosis 网络工具栈，采用“实时探测、微观交互、多维证伪”的在线手段，精准探测网络及其协议栈子系统的内核级故障。

## 技能目录结构

本技能包含在线诊断引导脚本与深度参考资料，结构如下：

```text
X-diagnosis-network-analysis/
├── SKILL.md                           # 本技能的主文档与流程规范
├── scripts/
│   └── show_location_index.sh         # [Step 1] 快速问题定位索引 (仅含 xd 网络工具)
└── references/
    └── xdiagnosis_reference.md        # [手册] 6 种 xd 网络工具详细说明
```

## ⚠️ 强制执行流程

**必须严格按以下顺序执行，禁止跳过或乱序：**

```
Step 0 (现象确认) → Step 1 (索引对标) → Step 2 (深入交互探测) → Step 3 (证据校验) → Step 4 (输出报告)
```

**执行规则：**
1. **顺序强制**：必须完成当前步骤并验证通过后，才能进入下一步。
2. **“先确认，后探测”**：在进行深度探测前，必须通过标准 OS 命令确认故障现象，防止盲目执行。
3. **XD 工具受限**：诊断时仅允许使用 `xdiagnosis_reference.md` 中列出的 6 种 `xd` 工具，严禁使用其他未说明的复杂诊断工具。
4. **不留冗余**：分析结果展示在回复流中即可，**严禁在目标服务器生成独立分析文件残留**。

---

## 分析流程总览

| **Step** | **阶段目标** | **主要工具/方法** |
| :--- | :--- | :--- |
| **Step 0** | 故障现象初步确认 | `ip`, `ss`, `dmesg`, `ping` 等基础 OS 命令 |
| **Step 1** | **场景对标与工具匹配** | 执行 `bash scripts/show_location_index.sh` 匹配诊断工具 |
| **Step 2** | **内核深度专项探测** | 运行选定的 `xd_*` 工具进行时序关联分析 |
| **Step 3** | 三重交叉质询 | 对比 `xd_*` 证据与标准 OS 计数器数据 |
| **Step 4** | 结构化诊断报告输出 | 按固定格式输出，核心证据需引用 `xd_*` 结果 |

---

## Step 0：故障现象初步确认

**目标**：通过基础 OS 命令快速锁定故障表现，为 Step 1 的工具匹配提供依据。

**常用命令示例**：
- **连通性确认**：`ping -c 4 <目标IP>`
- **监听状态检查**：`ss -tlnp`
- **内核报错核查**：`dmesg -T | tail -n 50`
- **统计计数器**：`cat /proc/net/snmp`

---

## Step 1：场景对标与工具匹配

**执行动作**：
执行以下脚本以获取当前故障场景对应的推荐 `xd` 工具：
```bash
bash scripts/show_location_index.sh
```

**匹配决策树简述**：
- **TCP 连接被 RST** → `xd_tcpresetstack`
- **TCP 性能异常/卡顿** → `xd_tcpskinfo`
- **ARP 风暴/IP 冲突** → `xd_arpstormcheck`
- **协议栈静默丢包** → `xd_ntrace`
- **虚拟网卡队列拥塞** → `xd_netvringcheck`
- **报文长度不一致** → `xd_skblen_check`

---

## Step 2：深度交互分析与证据获取

Agent **必须**根据 Step 1 选定的方向，通过专项工具进行深度分析。

**执行动作**：
1. **查阅手册**：必须查阅 `references/xdiagnosis_reference.md` 确定工具参数。
2. **场景探测**：执行 `xd_*` 工具并捕获关键输出（如内核调用栈、丢包点、Ring 队列状态等）。

**核心框架：T0 锚定与传导链**
- **T0 (故障零点)**：通过 `dmesg` 或 `xd_ntrace` 捕获的最早异常时间。
- **传导链重建**：描述从内核底层异常到业务层感知的完整演进路径。

---

## Step 3：根因反思与交叉校验

### 3.1 交叉质询铁律
1. **孤证不立**：`xd` 工具的深度证据必须与 OS 基础计数器（如 `netstat -s`）的增长趋势相互印证。
2. **资源隔离**：排除 CPU 软中断饱和或内存瓶颈对网络数据处理的影响。

### 3.2 证据校验表 (Evidence Validation Matrix)
| 维度 | 校验标准 | 强制证据 |
| :--- | :--- | :--- |
| **E1: 资源隔离** | CPU/内存是否正常？ | `top/free 摘要` |
| **E2: 路径一致** | 报错对象是否与业务受损路径一致？ | `ip route/ethtool 说明` |
| **E3: 双向验证** | 握手包/响应包是否确实入站？ | `xd_ntrace/tcpdump 证据` |

---

## Step 4：输出结构化诊断报告

**报告结构要求如下：**

1. **Executive Summary**：事发时间、结论定性。
2. **Fault Chains**：
   - **时间链**：带准确时间戳的关键节点。
   - **传播链**：物理/逻辑演进路径（例：`全连接队列满 -> 溢出丢包 -> TCP 重传`）。
3. **Technical Evidences**：**必须引用 `xd_*` 关键输出**，并配合 E1-E3 校验结果。
4. **Recommendations**：内核参数调整或处置建议。

**诊断完备性检查清单：**
- [ ] 故障时间链中每一个节点是否有准确时间？
- [ ] 是否包含 `xd_*` 核心证据？
- [ ] 是否排除了系统资源负载干扰？
- [ ] **是否无任何本地诊断文件残留？**
