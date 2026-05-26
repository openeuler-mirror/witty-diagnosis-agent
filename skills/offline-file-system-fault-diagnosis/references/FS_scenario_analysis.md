# 文件系统故障场景专项分析指南

## 概述

本指南提供了针对文件系统六种核心故障场景的专项分析流程。在 Step 1 确定场景标签后，应转入对应的专项分析。

---

## 1. 文件系统损坏分析 (FS_CORRUPTION)

### 1.1 核心证据源
- `infocollect_logs/system/dmesg.txt` - 内核检测到的位图、inode 或 Journal 错误。
- `messages/messages` - 系统级存储与挂载错误。

### 1.2 关键模式匹配
| 错误关键字 | 场景含义 |
| :--- | :--- |
| `EXT4-fs error` | EXT4 元数据物理或逻辑错误 |
| `loading journal` | 日志回滚失败，通常伴随断电 |
| `corrupt` | XFS 元数据结构损坏 |
| `Structure needs cleaning` | 强制要求运行 fsck/xfs_repair |

### 1.3 根因推理框架 (示例)
**场景：异常断电导致 Journal 损坏**
- **故障时间链 (Fault Time Chain)**：
    - `T0` (2026-03-10 10:00:01) ├─ [iBMC SEL] `Power Loss` 记录，外部供电丢失。
    - `T0+1m` ├─ [OS restart] 系统尝试引导。
    - `T0+1.5m` ├─ [OS dmesg] `EXT4-fs (sdb1): error loading journal`。
- **故障传导链 (Fault Propagation Chain)**：
    `供电失效 -> 内存脏数据未同步 -> Journal 日志损坏 -> 文件系统校验失败 -> 挂载被动关闭`。

---

## 2. 磁盘硬件故障分析 (DISK_FAILURE)

### 2.1 核心证据源
- `infocollect_logs/disk/disk_smart.txt` - SMART 健康度与坏扇区统计。
- `ibmc_logs/sel.db` - 硬件层面的 Drive Fault 告警。

### 2.2 关键模式匹配
| 错误关键字 | 场景含义 |
| :--- | :--- |
| `Reallocated_Sector_Ct` | 物理扇区重映射（非零即风险） |
| `Standard_Health_Status: FAILED` | 磁盘寿命终结或物理报错 |
| `Drive Slot #X Fault` | 槽位级致命硬件故障 |

---

## 3. I/O 读写错误分析 (IO_ERROR)

### 3.1 核心证据源
- `infocollect_logs/system/dmesg.txt` - SCSI/ATA 传输层超时信息。
- `infocollect_logs/raid/sasraidlog.txt` - RAID 卡底层链路日志。

---

## 4. 挂载异常分析 (MOUNT_ERROR)

### 4.1 核心证据源
- `messages/messages` - systemd 挂载单元状态。
- `infocollect_logs/system/fstab` - 挂载配置文件。

---

## 5. 空间/索引耗尽 (SPACE_ISSUE)

### 5.1 核心证据源
- `infocollect_logs/system/df.txt` - `df -h` (空间) 与 `df -i` (inode) 现状。

---

## 6. 权限访问拒绝 (PERMISSION_ISSUE)

### 6.1 关键模式匹配
- `Permission denied`: 基础权限位限制。
- `avc: denied`: SELinux 强制策略阻断。

---

## 7. 执行策略总结

1. **组合联动原则**：必须同时查看 `diagnose_ibmc.py` (硬件) 与 `diagnose_messages.py` (系统) 的输出。
2. **时序对齐原则**：必须确定唯一的致命故障点 T0，并由此展开传导链分析。
3. **证据闭环要求**：最终结论必须落地到具体的物理坐标（槽位）或逻辑坐标（块偏移）。
