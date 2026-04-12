# 磁盘故障场景专项分析指南

## 概述

本指南提供了六种磁盘故障场景的专项分析流程。在 Step 1 确定故障场景后，应根据对应的场景执行专项分析。如果没有匹配的场景，则使用通用分析流程。

## 1. 磁盘硬件故障分析 (DISK_HARDWARE_FAILURE)

### 1.1 核心日志文件

- `ibmc_logs/sel.db` / `sel.tar` - iBMC 系统事件日志（磁盘硬件错误、槽位离线）
- `infocollect_logs/storage/smart.txt` - 磁盘 S.M.A.R.T. 健康状态数据
- `messages/messages` - 系统级底层 I/O 错误记录
- `infocollect_logs/storage/sasraidlog` - RAID 卡视角下的物理磁盘报错

### 1.2 关键错误模式 (指纹识别)

| 错误类型 | 错误关键字 | 含义 |
| :--- | :--- | :--- |
| iBMC SEL | `Drive .* Fault` / `Predictive Failure` | 物理磁盘致命故障或预警告警 |
| 内核日志 | `MEDIUM ERROR [03/11/00]` / `UNC` / `UF` | **UNC/UF 坏道**：读取特定扇区时 ECC 无法纠正数据错误 |
| 内核日志 | `WRITE PROTECTED [07/27/00]` | **WP 写保护**：磁盘/分区被设置为只读，导致写入失败 |
| 内核日志 | `NOT READY [02/3a/00] No Medium` | **介质异常**：逻辑设备存在但物理介质丢失或未就绪 |
| SMART | `Reallocated_Sector_Ct` / `Current_Pending_Sector` | 物理扇区重映射计数异常，指示介质老化 |
| 内核日志 | `I/O error, dev sd.*` | 块设备读写错误（通用表现） |

### 1.3 分析命令

```bash
# 检查 iBMC SEL 中的磁盘告警
python3 scripts/diagnose_ibmc.py <ibmc_logs目录> -k "Drive" "Fault" "Predictive"

# 检查内核日志中的 I/O 报错及特定错误码 (UNC, WP, No Medium)
python3 scripts/diagnose_messages.py <messages目录> -k "I/O error" "MEDIUM ERROR" "WRITE PROTECTED" "No Medium"

# 检查磁盘 SMART 和详细状态
python3 scripts/diagnose_infocollect.py <infocollect目录> -k "smart" "Reallocated" "Pending"
```

### 1.4 根因推理框架

- **坏道路径**：`MEDIUM ERROR` 伴随 `Current_Pending_Sector` 增加 -> 确定为物理介质老化导致的 UNC 坏道。
- **保护路径**：`WRITE PROTECTED` -> 检查是否触发了磁盘固件的安全锁定或物理写保护开关。
- **介质路径**：`No Medium` -> 检查热插拔过程中是否由于驱动未释放导致逻辑路径残留，或物理介质确实被移除。

---

## 2. I/O 性能问题分析 (DISK_IO_PERFORMANCE)

### 2.1 核心日志文件

- `infocollect_logs/storage/iostat.txt` - 历史 I/O 性能指标（await, %util）
- `messages/messages` - SCSI 指令超时重置记录
- `infocollect_logs/storage/sasraidlog` - RAID 卡背景任务记录

### 2.2 关键错误模式

| 错误类型 | 错误关键字 | 含义 |
| :--- | :--- | :--- |
| iostat | **await 持续升高 > 200ms** | **落盘缓慢**：磁盘写缓冲区刷盘延迟过高，导致请求积压 |
| 内核日志 | `task .* blocked for more than 120 seconds` | 由于 I/O 长期不响应导致的内核软锁死 |
| 内核日志 | `aborting command` | SCSI 命令因超时被驱动层强行终止 |
| RAID卡 | `Background Initialization` / `CC` | RAID 后台一致性检查等任务占用大量控制器带宽 |

### 2.3 根因推理框架

**重点确认**：如果是单盘 `await` 远高于同阵列其他盘，且伴随少量 `MEDIUM ERROR`（即使未离线），根因为**磁盘老化导致的读写重试过频**。如果全阵列 `await` 升高，则检查 RAID 背景任务或前端业务瞬间负载峰值。

---

## 3. RAID/控制器故障分析 (DISK_RAID_ERROR)

### 3.1 核心日志文件

- `infocollect_logs/storage/sasraidlog` - RAID 控制器固件日志
- `ibmc_logs/sel.db` - 控制器硬件（Cache, BBU/Capacitor）告警

### 3.2 关键错误模式

| 错误类型 | 错误关键字 | 含义 |
| :--- | :--- | :--- |
| iBMC SEL | `Battery` / `Capacitor .* Failed` | RAID卡能量包故障，通常触发写策略降级 |
| RAID日志 | `Degraded` / `Offline` / `Failed` | 逻辑卷状态异常 |
| RAID日志 | `Cache discarded` | 电源中断且无备份电源时，缓存数据丢失（高风险） |

---

## 4. 链路/背板故障分析 (DISK_LINK_ISSUE)

### 4.1 核心日志文件

- `messages/messages` - SAS 链路重置、PCIe 错误
- `infocollect_logs/storage/sasraidlog` - 物理链路协议层错误

### 4.2 关键错误模式

| 错误类型 | 错误关键字 | 含义 |
| :--- | :--- | :--- |
| 内核日志 | **`PHY Reset` / `COMRESET`** | **阵列断链/热插拔**：控制器检测到链路中断，触发重连或移除 |
| 内核日志 | **`log_info(0x31110e03)`** (以 mpt3sas 为例) | **ICRC 错误**：接口 CRC 校验失败，通常由线缆或背板干扰引起 |
| 内核日志 | `ABRT` / `IDNF` | **接口异常**：命令被磁盘中止或逻辑块地址匹配失败 |
| iBMC SEL | `Backplane .* Voltage` | 背板供电不稳定导致的瞬间掉盘 |

### 4.3 根因推理框架

- **物理损坏 vs 链路抖动**：瞬间爆发的大量 `PHY Reset` 后跟 `Removal` 事件，通常是背板供电跌落或线缆完全脱落。
- **信号质量问题**：零星出现的 `ICRC` 报错且磁盘未离线，通常由于 SAS 线缆老化或接口电气干扰导致。

---

## 5. 存储诱发的文件系统故障分析 (STORAGE_INDUCED_FS_ERROR)

### 5.1 核心逻辑

文件系统异常（如 `Remounting filesystem read-only`）在本技能下均视为**存储层故障的级联反应**。

### 5.2 诊断指纹

- **因果链条对齐**：必须找到早于 FS 报错的 `sdX: I/O error` 或 `scsi reset`。
- **根因判定**：如果 FS 只读前存在 `journal commit I/O error`，则确定为底层介质损坏导致日志同步失败，触发了文件系统的安全保护。

---

## 6. 系统/配置与兼容性限制分析 (DISK_SYSTEM_CONFIG)

### 6.1 核心现象

| 故障类别 | 典型表现 | 根因逻辑 |
| :--- | :--- | :--- |
| **盘符漂移 (Drift)** | 重启后 `/dev/sdX` 变化导致挂载失败 | fstab 中使用盘符而非 UUID/Label，依赖了不稳定的设备枚举顺序 |
| **指令不兼容** | 报错 `ILLEGAL REQUEST [05/20/00]` | 向磁盘下发了其固件不支持的指令（如特定的 TRIM 或安全擦除） |
| **数量过载** | 启动枚举极慢或 udev 事件积压 | 连接磁盘数超过 HBA 控制器或内核子实体的性能/资源上限 |

### 6.2 分析建议

1. **检查挂载方式**：使用 `lsblk -f` 查看是否所有关键分区都已采用 UUID 挂载。
2. **校验固件兼容性**：在 `sasraidlog` 中核对磁盘型号与固件版本，确认是否在厂家支持列表中。
3. **统计物理路径**：确认 HBA 卡下挂的物理盘总数，对比该型号卡的最大支持拓补。

---

## 7. 执行策略

1. **多维证据交叉**：物理故障必须满足 iBMC/SMART + OS 内核两方的交叉证据。
2. **严防误诊**：在判定硬件损坏前，务必排除 RAID 背景任务和链路干扰因素。
3. **离线诊断守则**：仅基于目前获取的日志上下文，不生成猜测性结论。
