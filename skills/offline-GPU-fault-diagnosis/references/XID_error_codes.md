# NVIDIA XID 错误对照表

XID 错误是由 NVIDIA 驱动程序发送到系统日志（如 `/var/log/messages` 或 `dmesg`）的错误识别代码。它们是定位 GPU 故障的最核心证据。

## 常见 XID 错误详表

| XID 代码 | 错误名称 | 故障倾向 | 详细描述 | 建议动作 |
| :--- | :--- | :--- | :--- | :--- |
| **31** | **GPU Memory Error** | 硬件 | 显存发生不可纠正（Uncorrectable）错误，导致硬件上报致命异常。 | 检查 iBMC 显存记录，必要时换卡。 |
| **32** | **Invalid Address Space** | 软件/驱动 | 应用程序请求了无效的地址空间，通常是业务逻辑或 CUDA 驱动 Bug。 | 更新驱动/检查代码逻辑。 |
| **43** | **GPU Stopping** | 硬件/驱动 | GPU 发生致命错误并被强制停止，常见于严重的 ECC 错误之后。 | 结合 T0 时序排查前序报错。 |
| **45** | **Preemptive Termination** | 硬件 | 硬件引擎检测到非法状态并主动终止当前上下文。 | 排查散热与供电。 |
| **61** | **Internal Microcontroller Error** | 硬件/固件 | GPU 内部微控制器报错，通常与物理链路或固件死锁有关。 | 尝试冷重启或更新固件。 |
| **62** | **Internal Microcontroller Halt** | 软件/驱动 | 内部调度器挂起，通常在驱动程序发生严重竞争或溢出时出现。 | 检查驱动版本兼容性。 |
| **74** | **NVLINK Error** | 硬件/链路 | NVLink 链路层检测到不可恢复的传输错误。 | 检查 NVLink 桥接器物理连接。 |
| **79** | **GPU Fallen Off the Bus** | 硬件 | **最严重故障**：GPU 在 PCIe 总线上完全丢失，操作系统已无法感知该设备。 | 检查 PCIe 插槽、供电线及 GPU 本身。 |
| **92** | **Full RPC Error** | 驱动 | 驱动程序与硬件之间的远程过程调用（RPC）超时或失败。 | 检查 CPU 负载及内核锁定。 |

## XID 诊断原则

1.  **首发原则 (First Event)**：当日志中爆发大量 XID 时，必须通过 `grep` 找到时间最早的第一个 XID（T0）。
2.  **因果关联**：
    *   31 -> 43：通常表示显存硬件损坏导致卡停止。
    *   79：通常表示物理拔出、供电熔断或严重的 PCIe 链路崩溃。
3.  **软件 vs 硬件区分**：
    *   **硬件型**：31, 45, 61, 74, 79。
    *   **软件/环境型**：32, 62, 92 (部分情况下)。

## 参考资料
- [NVIDIA 开发者文档: XID Errors](https://docs.nvidia.com/deploy/xid-errors/index.html)
