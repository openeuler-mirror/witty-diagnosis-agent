# 内存故障场景专项分析指南

## 概述

本指南提供了七种内存故障场景的专项分析流程。在 Step 1 确定故障场景后，应根据对应的场景执行专项分析。如果没有匹配的场景，则使用通用分析流程。

---

## 1. 内存 ECC 错误分析 (MEMORY_ECC_ERROR)

### 1.1 核心日志文件
- `ibmc_logs/sel.db` / `sel.tar` - iBMC 系统事件日志（致命内存错误、纠错分满等）
- `infocollect_logs/system/dmesg.txt` - 内核 MCE/EDAC 记录
- `messages/messages` - 硬件错误对系统应用层的传导影响汇总

### 1.2 关键错误模式 (指纹识别)

| 错误来源 | 错误关键字 | 含义 |
| :--- | :--- | :--- |
| **iBMC SEL** | `Correctable error, logging limit reached` | **华为/H3C CE 风暴**：内存 CE 错误频率超过阈值，预警颗粒老化 |
| **iBMC SEL** | `Memory Device Fatal` / `UCE` | **致命错误**：无法通过硬件纠错逻辑（ECC）修复的位反转 |
| **内核日志** | `Machine Check Exception [4/b2/04]` | **MCE 报错**：CPU 捕获到内存控制器异常，[x/y/z] 代表具体硬件错误码 |
| **内核日志** | `EDAC MC0: 1 CE on DIMM_A1` | **纠错记录**：内核检测并修复了单位 flip，定位到 DIMM_A1 |
| **内核日志** | `Memory failure: ... Isolated` | **hwpoison**：内核标记了包含坏道的物理页，禁止后续访问 |

### 1.3 分析命令
```bash
# 检查 iBMC 中的内存告警
python3 scripts/diagnose_ibmc.py <log_dir> -k "ECC" "DIMM" "Correctable" "Fatal"

# 检查内核日志中的 MCE 及 ECC 报错
python3 scripts/diagnose_messages.py <log_dir> -k "Machine Check" "EDAC" "Isolated" "hwpoison"
```

### 1.4 根因推理框架
- **老化路径**：`CE 风暴` -> 若伴随 `DIMM ID` 固定 -> 确定为特定物理颗粒老化，需申请备件更换。
- **致命路径**：`UCE / FATAL` -> `MCE` -> 检查是否触发系统 Panic，若为固定插槽反复触发，判定为硬件物理损坏。

---

## 2. 内存硬件/单元故障分析 (MEMORY_HARDWARE_FAILURE)

### 2.1 核心日志文件
- `ibmc_logs/sel.db` - 启动过程中的培训状态（Training Status）
- `infocollect_logs/system/dmidecode.txt` - 内存插槽在位及物理规格核验

### 2.2 关键错误模式

| 错误类型 | 错误关键字 | 含义 |
| :--- | :--- | :--- |
| **iBMC SEL** | `Memory Training Failed` / `SPD Read Error` | **初始化失败**：内存条无法在指定频率下完成握手/SPD 数据读取失败 |
| **iBMC SEL** | `Memory Device Removed / Missing` | **在位丢失**：插槽中物理探测不到内存条（通常伴随 CPU CATERR 信号） |
| **dmidecode** | `Size: No Module Installed` | **逻辑丢失**：硬件 BIOS 层级认为该插槽为空，需核对自己定义的插槽配置 |

---

## 3. 内存配置与拓扑冲突分析 (MEMORY_CONFIG_ISSUE)

### 3.1 核心逻辑
当内存配置（插法、频率、厂商）不符合 CPU 及主板推荐拓扑时，系统通常会自动降级运行或报错。

### 3.2 诊断指纹
| 故障类别 | 典型表现 | 根因逻辑 |
| :--- | :--- | :--- |
| **频率降级 (Fallback)** | 标称 3200MHz 但运行在 2666MHz | 混插了低频内存条同步或散热方案无法支撑高频 |
| **非对称布局** | `Non-optimal Configuration` | 内存未按 A1, B1, C1... 的顺序对等平衡插入，引发带宽瓶颈 |
| **Node Asymmetry** | `NUMA unbalanced` | 某颗 CPU 挂载的内存显著少于另一颗，导致总线调度效率低下 |

---

## 4. 硬件诱发的内存损坏分析 (MEMORY_CORRUPTION)

### 4.1 核心现象
物理位反转（Bit-flip）除了触发 ECC 外，还可能引发逻辑层面的数据不一致。

### 4.2 诊断指纹
- **Segfault 定位**：通过 `grep "segfault"` 提取崩溃地址，若多个不同进程在**相同物理地址段**持续报错，确定为 hardware corruption。
- **Page Table 报错**：`kernel BUG: unable to handle page fault` 且伴随底层 `MCE`。

---

## 5. 内存带宽与访问性能分析 (MEMORY_PERFORMANCE)

### 5.1 核心逻辑
探讨为何业务在内存量充足时依然感受到卡顿。

### 5.2 诊断指纹
- **远程节点访问 (NUMA Miss)**：`numastat` 中 `node_miss` 过高，指控大部分内存访问跨越了 CPU 总线链路。
- **交换分区剧烈抖动 (Thrashing)**：`vmstat` 中 `si/so` 长期不为 0，即使 `MemFree` 尚存（由于 Page Cache 挤占）。

---

## 6. 内存耗竭 (OOM) 与 系统/内核级泄漏 (MEMORY_OOM / LEAK)

### 6.1 核心逻辑 (硬件关联性)
本项仅分析非应用层（驱动、内核）引发的资源耗竭。

### 6.2 诊断指纹
- **Slab 泄漏**：`cat /proc/meminfo` 中 `SUnreclaim` 远大于 `SReclaimable`。
- **分配失败**：`page allocation failure` 指定 `order=2` 或更高，指示内存碎片化极其严重，无法满足硬件驱动申请。

### 6.3 驱动/模块识别
使用 `diagnose_memory.py --leak` 扫描 `Slab` Top 分配器，识别具体的 `module` 驱动。

---

## 7. 执行策略 (Vendor-Specific Rules)

1. **华为 (Huawei)**：优先检查 `SEL` 中的 `Logging Limit Reached`，这是备件更换的重要量化依据。
2. **H3C/Inspur**：重点核对 `SPD Read Error`，区分内存条物理损坏与主板插槽（Backplane）供电异常。
3. **离线诊断守则**：物理定位必须满足 **插槽 ID** 这一关键维度，禁止输出类似“系统内存出问题”的泛化建议。
