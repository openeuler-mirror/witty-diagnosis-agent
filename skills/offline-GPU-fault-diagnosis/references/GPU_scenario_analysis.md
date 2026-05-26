# GPU 故障场景专项分析指南

## 概述

本指南提供了五种 GPU 故障场景的专项分析流程。在 Step 1 确定故障场景后，应根据对应的场景执行专项分析。

---

## 1. GPU 硬件致命故障 (GPU_HARDWARE_FATAL)

### 1.1 核心日志文件
- `ibmc_logs/sel.db` - iBMC 系统事件日志（GPU 硬件报错、离线告警）
- `messages/messages` - 系统级 GPU 丢失记录（Fallen off the bus）
- `infocollect_logs/gpu/nvidia-smi.txt` - GPU 状态快照

### 1.2 关键指纹
| 错误类型 | 关键字 | 含义 |
| :--- | :--- | :--- |
| OS 日志 | `XID 79` / `Fallen off the bus` | **GPU 掉卡**：PCIe 总线链路完全中断 |
| iBMC SEL | `GPU .* Fault` / `Voltage Abnormal` | 物理层致命报错或供电电压异常 |
| OS 日志 | `XID 31` / `Uncorrectable ECC` | 显存硬件损坏导致的引擎终止 |

### 1.3 分析命令
```bash
# 检查 iBMC SEL 中的 GPU 硬件告警
python3 scripts/diagnose_ibmc.py <ibmc_logs> -k "GPU" "Fault" "Voltage"

# 检查系统日志中的掉卡记录
python3 scripts/diagnose_messages.py <messages> -k "XID 79" "Fallen off"
```

---

## 2. 驱动与软件层故障 (GPU_DRIVER_CRASH)

### 2.1 关键指纹
| 错误类型 | 关键字 | 含义 |
| :--- | :--- | :--- |
| OS 日志 | `NVRM: API mismatch` | **版本不匹配**：用户态库与内核驱动版本冲突 |
| OS 日志 | `XID 62` / `Internal Microcontroller Halt` | 驱动调度算法或微码执行进入死锁/挂起 |
| OS 日志 | `rm_init_adapter failed` | 驱动初始化适配器失败 |

### 2.2 根因推理
- **软件重启**：如果只有 XID 62 且物理层无报错，优先考虑驱动版本更新或业务负载调优。
- **环境冲突**：检查 `API mismatch`，通过 `nvidia-smi` 核对当前加载驱动的具体版本。

---

## 3. 显存 ECC 错误分析 (GPU_MEMORY_ECC)

### 3.1 核心逻辑
显存错误分为纠正（Correctable）和不纠正（Uncorrectable）。
- **Uncorrectable (UE)**：直接导致 XID 31，业务中断。**这是硬件换卡的主要指标**。
- **Correctable (CE)**：短期爆发（ECC Storm）会导致性能损失，系统会执行 Page Retirement（页退休）。

### 3.2 诊断指纹
| 错误类型 | 关键字 | 含义 |
| :--- | :--- | :--- |
| OS 日志 | `XID 31` / `XID 43` | 硬件纠检错逻辑上报致命内存错误 |
| nvidia-smi | `ECC Errors` -> `Aggregate Uncorrectable` | 累积不可纠正错误计数 > 0 |

---

## 4. 散热与功耗限制 (GPU_THERMAL_POWER)

### 4.1 诊断逻辑
当 GPU 温度超过阈值或供电受限时，驱动会主动下调时钟频率（Throttling）。

### 4.2 关键指纹
| 错误类型 | 关键字 | 含义 |
| :--- | :--- | :--- |
| nvidia-smi | `Clocks Throttle Reasons` -> `HW Slowdown` | 硬件原因导致的强行降频 |
| iBMC SEL | `GPU .* Temp` / `Over Temperature` | iBMC 监控到的散热告警 |

---

## 5. PCIe 链路异常 (GPU_PCIE_LINK)

### 5.1 诊断指纹
| 错误类型 | 关键字 | 含义 |
| :--- | :--- | :--- |
| OS 日志 | `XID 61` / `PCIe Bus Error` | PCIe 协议层检测到数据传输异常 |
| nvidia-smi | `Max Link Width` vs `Current Link Width` | **链路缩水**：实际位宽小于最大物理位宽（如 x16 变成 x8） |

### 5.2 分析建议
1. 检查 `nvidia-smi -a` 输出中的 `Pcie` 章节。
2. 核对 GPU 是否安装在推荐的 PCIe 插槽上。
3. 检查背板（Backplane）连接是否牢靠。
