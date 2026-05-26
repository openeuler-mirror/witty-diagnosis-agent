# NPU 故障场景专项分析指南

在执行 Step 1 完成初步场景分类后，深入分析必须参考不同场景的专项特征和日志表现。以下为常见场景的取证和诊断说明：

## 1. NPU_HARDWARE_FAILURE (硬件级损坏)
**现象描述**：NPU 设备完全无法识别、内部核心模块致命错误或处于物理不可用状态。
**关键证据位置**：
- **iBMC/SEL 日志**：搜索 `Hardware Error`, `Sensor Assertion`, `Unrecoverable`。例如，直接看到对应 PCIe Slot 的报错告警。
- **dmesg 日志**：搜索 `davinci`, `ascend`, `hardware fatal error` 相关的内核打印。
**分析路径**：
1. 确认 iBMC 是否亮起故障红灯且有明确的 `CRITICAL` 告警指向该槽位。
2. 确认 `npu-smi` 是否返回空或返回错误状态（如 `Offline`）。
3. 根因大概率为纯硬件毁坏，需更换备件。

## 2. NPU_PCIE_LINK_ISSUE (PCIe 链路与拓扑故障)
**现象描述**：NPU 计算单元可能正常，但与 CPU 的通信总线出现电气或协议层面的不稳，导致设备时隐时现或降速。
**关键证据位置**：
- **dmesg/messages 日志**：高频搜索关键字 `AER: Uncorrected (Fatal) error`, `PCIe Bus Error`, `link down`, `resetting device`。
- **iBMC/SEL 日志**：PCIe 链路相关的底层事件、主板报警。
**分析路径**：
1. 若系统伴随大量 AER 报错，确认是 Root Port 报出还是 NPU Endpoint 报出。
2. 结合时间戳观察，是偶尔断开还是持续处于断链状态。
3. 鉴别是 NPU 本身金手指氧化/损坏，还是 Riser 卡、主板 PCIe 插槽的共性故障（可观察同一 Riser 的其他卡是否正常）。

## 3. NPU_DRIVER_SW_STACK (驱动固件与软件栈故障)
**现象描述**：物理卡在位且 PCIe 正常，但上层应用启动时反复报错，或者 `npu-smi` 异常、内核触发 Panic 抛出 NPU `Call Trace`。
**关键证据位置**：
- **dmesg/syslog**：检查 NPU 内核驱动加载记录 (如 `davinci_install` 等)，搜索 `Version mismatch`, `Fail to load firmware`, `Call Trace`, `Oops`。
- **InfoCollect**：检查截取的操作系统与驱动版本包，比对 CANN 和驱动依赖关系。
**分析路径**：
1. 若日志显示 `firmware version mismatch`，可定性为运维升升级或部署不规范问题。
2. 若抛出 `Panic` 且调用栈包含 `npu` 相关驱动模块，则需调查触发该异常的应用代码，或是否存在驱动 Bug。
3. `Acl Error` 类应用级报错，需追溯到底层是否有对应的 I/O 或者 DMA 超时日志。

## 4. NPU_HBM_PERFORMANCE (HBM 显存报错与失效)
**现象描述**：NPU 在执行需要大量内存操作的算子时突然宕机，或者 iBMC/系统定期报出纠错日志。
**关键证据位置**：
- **iBMC/SEL**：搜索 `ECC`, `Memory Error`, `Uncorrectable`。
- **dmesg**：内核空间接收到的内存错误报告，或显存分配失败警告 (`OOM` in device memory)。
**分析路径**：
1. 区分 **CE (Correctable Error)** 和 **UE (Uncorrectable Error)**。
2. 零星的 CE 偶尔存在且可由系统修复，若呈现暴增趋势则是颗粒劣化的先兆。
3. 报出 UE 则意味着对应周期的计算数据被污染且无法挽回，必定导致相关的业务进程崩溃。此场景属于物理硬件瑕疵，常常需要拔卡换件。

## 5. NPU_THERMAL_POWER (环境热电告警)
**现象描述**：由于机箱风扇故障、风道不合理或环境温度过高等原因，导致 NPU 被迫降频甚至断电自我保护（掉卡）。
**关键证据位置**：
- **iBMC/Sensor Readings**：查阅服务器风扇转速（`Fan Speed`）、环境温度计（`Inlet Temp`）以及 NPU 自身的温度和功耗读数。
- **iBMC SEL / dmesg**：搜索 `Over Temperature`, `Thermal Throttling`, `Power limit`, `Power fault`。
**分析路径**：
1. 优先对齐温度曲线与故障 T0 的发生时间。如果 T0 前有明显的温度徒增曲线，说明是环境散热导致。
2. 若电源模块（PSU）在 T0 出现报警或者输出电压突降，则说明掉卡的物理根因在于供电通道，而非 NPU 自身。此时应检查机柜供电 PDU 或 PSU 工作状态。
