# 硬盘健康度评估技术规范 (Standard)

本规范定义了硬盘健康度评估的客观硬指标、计算公式及处置等级映射关系。本规范为 [SKILL.md](../SKILL.md) Step 3 的核心判定依据。

## 1. 介质分流与数据来源

| 接口类型 | 规则集 | 主要数据来源 |
| :--- | :--- | :--- |
| SAS  | §2 SAS 故障规则 | `sasraidlog.txt` / smartctl SAS 段 |
| SATA | §3 SATA 故障规则 | `disk_smart.txt` / smartctl SATA 段 |
| NVMe | **暂未覆盖** | `nvme*.txt` / `es3000*.txt` |

---

## 2. SAS 硬盘故障规则 (Hard Fault Rules)

命中以下任一规则，则 **存活概率 = 0%**，建议 **立即更换** (`replacement: true`, `repairable: false`)。

| 规则 ID | 规则描述 | 阈值 | 判定逻辑 |
| :--- | :--- | :--- | :--- |
| SAS-R1 | Elements in grown defect list | > 1000 | 介质级坏道，不可修复 |
| SAS-R2 | Total uncorrected (write/read/verify) | > 50 / > 1000 / > 1000 | 累积不可纠正错误，不可修复 |
| SAS-R3 | SMART Health Status | != OK | 硬盘自检失败，不可修复 |
| SAS-R4 | asc=0x5d 预测性故障 | 出现 | 硬盘即将失效告警，不可修复 |

---

## 3. SATA 硬盘故障规则 (Hard Fault Rules)

命中以下任一规则，则 **存活概率 = 0%**，建议更换。

| 规则 ID | 规则描述 | 阈值 | `repairable` | 判定说明 |
| :--- | :--- | :--- | :--- | :--- |
| SATA-R1 | SMART Error Log | != "No Errors Logged" | `false` | 存在硬件记录的错误日志 |
| SATA-R2 | overall-health self-assessment | FAILED 或非 PASSED | `false` | 硬盘自评失败 |
| SATA-R3 | Reallocated_Sector_Ct (RAW) | ≥ 1000 | `false` | 重映射扇区超限 |
| SATA-R4 | Current_Pending_Sector (RAW) | ≥ 1000 | `false` | 待处理扇区超限 |
| SATA-R5 | Offline_Uncorrectable (RAW) | ≥ 1000 | `false` | 离线不可纠正扇区超限 |
| SATA-R6 | UDMA_CRC_Error_Count | ≠ 0 且持续增长 | `true` | 多为线缆/接口问题，更换可恢复 |
| SATA-R7 | Raw_Read_Error_Rate WORST | ≤ Thresh × 1.05 | `true` | 读取错误率退化，可通过自检恢复 |
| SATA-R8 | Seek_Error_Rate WORST | ≤ Thresh × 1.05 | `true` | 寻道错误率退化，可通过自检恢复 |
| SATA-R9 | Spin_Up_Time VALUE | ≤ 判定阈值* | `true` | 机械老化，建议加强监控 |
| SATA-R10 | Power_On_Hours | > 61320 h | `true` | 使用超 7 年，寿命预警 |

> \* **SATA-R9 阈值计算**: `VALUE <= 30% × (Default - Threshold) + Threshold`。WD 厂家 Default=200，其他=100。

---

## 4. 存活概率计算 (Survival Probability)

当未命中上述任何硬故障规则时，按以下指标偏离程度计算 **半年存活概率**:

### 4.1 参与计算的指标清单

| 指标类型 | 具体指标 | 健康值 (Healthy) | 阈值 (Threshold) |
| :--- | :--- | :--- | :--- |
| **正向 (越大越差)** | Reallocated_Sector_Ct (RAW) | 0 | 1000 |
| | Current_Pending_Sector (RAW) | 0 | 1000 |
| | Offline_Uncorrectable (RAW) | 0 | 1000 |
| | Power_On_Hours | 0 | 61320 (7年) |
| | Elements in grown defect list (SAS) | 0 | 1000 |
| | Uncorrected Write/Read/Verify (SAS) | 0 | 50 / 1000 / 1000 |
| **反向 (越小越差)** | Raw_Read_Error_Rate (WORST) | 健康初值 | Threshold |
| | Seek_Error_Rate (WORST) | 健康初值 | Threshold |
| | Spin_Up_Time (VALUE) | 健康初值 | 判定阈值* |

### 4.2 计算公式

1. **正向指标偏离度**: `D = (实际值 − 健康值) / (阈值 − 健康值)`
2. **反向指标偏离度**: `D = (健康值 − 实际值) / (健康值 − 阈值)`
3. **最终概率**: `存活概率 = 1.0 − max(所有指标的 D)`
4. **范围约束**: 结果限制在 `[0.0, 1.0]` (即 `0% - 100%`)。

---


## 5. 处置等级映射 (Action Level)

### 5.1 存活概率 → 更换建议 (`replacement`)
| 存活概率 (p) | 处置建议 | `replacement` |
| :--- | :--- | :--- |
| p = 0% | 立即更换 | `true` |
| p < 30% | 建议尽快更换 | `true` |
| 30% ≤ p < 70% | 加强监控 | `false` |
| p ≥ 70% | 维持运行 | `false` |

### 5.2 可修复性判定 (`repairable`)
- **不可修复 (`false`)**: 命中任何涉及介质损坏 (R1-R5) 或自检失败 (R3) 的规则。
- **可修复 (`true`)**: 仅命中链路问题 (R6)、性能退化 (R7-R9) 或寿命预警 (R10)；或未命中任何规则。
