# 磁盘和存储诊断指南与日志格式

## 一、 诊断方法论

在处理存储类故障时，建议按照以下 **四层模型** 进行逐级排查：

1.  **物理/固件层 (Physical & Firmware)**：
    *   确认硬件是否在位、物理健康状态 (SMART)、RAID 卡/控制器状态。
    *   **核心目标**：排除硬件损坏、掉盘、线缆故障。
2.  **逻辑/拓扑层 (Logical & Topology)**：
    *   确认 OS 是否识别到设备、盘符映射关系 (RAID 组与物理盘对应)、分区表状态。
    *   **核心目标**：确认驱动加载正常，设备树枚举正确。
3.  **性能层 (Performance)**：
    *   分析 I/O 吞吐、延迟、队列深度、调度策略。
    *   **核心目标**：识别慢盘、I/O 瓶颈、不合理的调度器配置。
4.  **系统/事件层 (System Events)**：
    *   检查内核报错、文件系统错误、应用层超时。
    *   **核心目标**：关联系统崩溃或卡顿与存储事件的时间戳。

---

## 二、 诊断关键文件快速检索表

| 优先级 | 文件路径 | 模块 | 查看目的 |
| :--- | :--- | :--- | :--- |
| ⭐⭐⭐ | `./infocollect_logs/disk/disk_smart.txt` | 硬盘 | SMART 健康指标、重分配扇区计数、待定扇区计数 |
| ⭐⭐⭐ | `./infocollect_logs/raid/sasraidlog.txt` | RAID | RAID 控制器状态、VD/PD 健康状况、重建进度 |
| ⭐⭐⭐ | `./infocollect_logs/raid/sashbalog.txt` | RAID | SAS HBA 控制器日志 |
| ⭐⭐⭐ | `./infocollect_logs/disk/hwdiag_hdd.txt` | 硬盘 | iBMA 硬盘健康评分 |
| ⭐⭐⭐ | `./infocollect_logs/system/iostat.txt` | 系统 | 磁盘 I/O 吞吐量、队列深度、await 延迟 |
| ⭐⭐ | `./infocollect_logs/disk/blktrace_log.txt` | 硬盘 | 块设备 I/O 延迟分布 (d2c/q2c) |
| ⭐⭐ | `./infocollect_logs/disk/scheduler.txt` | 硬盘 | I/O 调度器类型 (noop/deadline/cfq) |
| ⭐⭐ | `./infocollect_logs/raid/diskmap.txt` | RAID | 逻辑磁盘与物理磁盘的映射关系 |
| ⭐⭐ | `./infocollect_logs/disk/phy_info.txt` | 硬盘 | 用于定位槽位的硬盘 phy 路径 |
| ⭐⭐ | `./infocollect_logs/system/filesystem_config_log.txt` | 系统 | 文件系统脏页、队列深度、内核参数 |
| ⭐⭐ | `./infocollect_logs/scsi/scsi_info.txt` | SCSI | SCSI 设备识别状态 |
| ⭐⭐ | `./infocollect_logs/system/proc/diskstats` | 系统 | 磁盘读写统计 |
| ⭐ | `./infocollect_logs/disk/parted_disk.txt` | 硬盘 | 分区表与分区健康状况 |
| ⭐ | `./infocollect_logs/block/blk_list.txt` | 块设备 | 块设备清单与拓扑 |

---

## 三、 具体排查流程与操作指南

### 步骤 1：检查硬件健康与 RAID 状态（⭐⭐⭐ 高优先级）

**目的**：首先确认硬盘物理上是否损坏，RAID 组是否降级。

*   **查看文件**：`./infocollect_logs/disk/disk_smart.txt`
    *   **排查重点**：搜索 `Reallocated_Sector_Ct` (重映射扇区)、`Current_Pending_Sector` (待定扇区)、`Uncorrectable_Sector_Ct`。
    *   **判断标准**：上述数值非 0 或增长，通常意味着物理介质损坏；查看 `SMART overall-health self-assessment test result` 是否为 `PASSED`。
    *   **故障关键字**：`FAILED`, `Pre-fail`, `Old_age`, `Reallocated_Sector_Ct`, `Pending_Sector`, `Uncorrectable`
*   **查看文件**：`./infocollect_logs/raid/sasraidlog.txt` (或 `sashbalog.txt`)
    *   **排查重点**：检查 RAID 控制器日志，确认 VD (Virtual Drive) 和 PD (Physical Drive) 状态。
    *   **判断标准**：VD 状态应为 `Optimal`，PD 状态应为 `Online`。如有 `Degraded` (降级)、`Rebuild` (重建中)、`Offline` (掉线) 需立即处理。
    *   **故障关键字**：`Degraded`, `Offline`, `Failed`, `Rebuild`, `Media Error`
*   **查看文件**：`./infocollect_logs/disk/hwdiag_hdd.txt`
    *   **排查重点**：这是 iBMA 工具的打分报告，直观查看硬盘健康度评分。
    *   **故障关键字**：`score low`, `predicted failure`, `warning`

### 步骤 2：分析 I/O 性能瓶颈（⭐⭐⭐ 高优先级）

**目的**：如果硬件健康，但系统卡顿，需确认是否存在 I/O 延迟过高。

*   **查看文件**：`./infocollect_logs/system/iostat.txt`
    *   **排查重点**：查看 `%util` (利用率)、`await` (平均等待时间)、`svctm` (服务时间)。
    *   **判断标准**：
        *   `%util` 长期接近 100% 说明磁盘由于饱和导致瓶颈。
        *   `await` 远大于 `svctm` 说明 I/O 队列堆积严重。
        *   对于 SSD，`await` 超过 10ms 通常需关注；HDD 超过 50-100ms 需关注。
*   **查看文件**：`./infocollect_logs/disk/blktrace_log.txt`
    *   **排查重点**：块设备 I/O 的细粒度延迟分布。
    *   **判断标准**：
        *   `d2c` (Driver to Completion)：硬件处理耗时。如果高，说明是硬盘本身慢（硬件性能问题）。
        *   `q2c` (Queue to Completion)：总延迟。如果高但 `d2c` 低，说明卡在系统队列或调度层。
        *   **故障关键字**：`d2c high`, `q2c high`, `latency spike`

### 步骤 3：确认逻辑映射与配置（⭐⭐ 中优先级）

**目的**：定位物理槽位，确认 OS 配置是否符合最佳实践。

*   **查看文件**：`./infocollect_logs/raid/diskmap.txt`
    *   **排查重点**：逻辑盘（如 `/dev/sda`）与物理槽位（如 `Slot 0`）的对应关系。
    *   **应用场景**：当 `dmesg` 报错 `/dev/sdc` 有 I/O error 时，通过此文件找到对应的物理盘进行更换。
*   **查看文件**：`./infocollect_logs/disk/scheduler.txt`
    *   **排查重点**：I/O 调度算法 (`noop`, `deadline`, `cfq`, `mq-deadline`)。
    *   **判断标准**：SSD 通常建议使用 `noop` 或 `deadline` / `mq-deadline`，不建议使用 `cfq`。
    *   **故障关键字**：`cfq` (不推荐用于 SSD), `misconfigured`
*   **查看文件**：`./infocollect_logs/system/filesystem_config_log.txt`
    *   **排查重点**：检查 `dirty_ratio`, `queue_depth` 等内核参数是否配置不当导致刷盘阻塞。

### 步骤 4：系统级关联分析（⭐⭐ 中优先级）

**目的**：确认存储问题是否引发了系统层面的报错。

*   **查看文件**：`./infocollect_logs/system/dmesg.txt` (参考系统概览部分)
    *   **排查重点**：搜索 SCSI/ATA 相关的内核报错。
    *   **故障关键字**：`I/O error`, `SCSI error`, `buffer I/O error`, `rejecting I/O`, `xfs_force_shutdown`
*   **查看文件**：`./infocollect_logs/disk/phy_info.txt`
    *   **排查重点**：确认硬盘在 `/dev/disk/by-path` 下的路径，用于在多路径场景下确认链路状态。
    *   **故障关键字**：`not found`, `path missing`

---

## 四、 快速排查清单 (Cheat Sheet)

| 现象 | 优先查看文件 | 重点关注指标/关键字 |
| :--- | :--- | :--- |
| **硬盘亮黄灯/系统掉盘** | `sasraidlog.txt` / `sel.csv` | `Offline`, `Failed`, `Predictive Failure` |
| **系统卡顿/IO wait高** | `iostat.txt` / `blktrace_log.txt` | `await` > 100ms, `%util` 100%, `d2c` high |
| **文件读写报错** | `dmesg.txt` / `disk_smart.txt` | `I/O error`, `Reallocated_Sector_Ct` |
| **新盘无法识别** | `scsi_info.txt` / `lspci.txt` | 确认 RAID 卡和磁盘是否被 OS 枚举 |

---

## 五、 日志文件详细说明

| 模块 | 文件名称 | 收集命令 | 说明 | 相关组件 | 故障关键字 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 硬盘 | `./infocollect_logs/disk/disk_smart.txt` | smartctl -a | 硬盘 SMART 属性（重分配扇区、待定扇区、不可纠正扇区）、通电时间、温度、自检结果 | 硬盘 (SAS/SATA/NVMe) | Reallocated_Sector_Ct, Pending_Sector, Uncorrectable, FAILED, old age |
| 硬盘 | `./infocollect_logs/disk/phy_info.txt` | ls -l /dev/disk/by-path | 硬盘 phy 路径与 /dev/sdX 的映射，用于物理槽位定位 | 硬盘, SAS 控制器 | not found, path missing |
| 硬盘 | `./infocollect_logs/disk/sys_block.txt` | ls -l /sys/block/sd* | /sys/block 下的块设备链接，确认 OS 识别情况 | 硬盘, 内核块层 | missing device |
| 硬盘 | `./infocollect_logs/disk/parted_disk.txt` | parted /dev/sda print | 磁盘容量、分区表类型 (GPT/MBR)、分区起止位置与文件系统类型 | 硬盘, 文件系统 | error, unaligned, unknown partition table |
| 硬盘 | `./infocollect_logs/disk/hwdiag_hdd.txt` | hwdiag -t disk -d | iBMA 硬盘健康评分、关键 SMART 指标、预测性故障 | 硬盘, iBMA | score low, predicted failure, warning |
| 硬盘 | `./infocollect_logs/disk/es3000_v2.txt` | hio_info/hio_log | ES3000 V2 PCIe SSD 设备信息、标签、日志、温度 | ES3000 V2 SSD | error, temperature high, wear out |
| 硬盘 | `./infocollect_logs/disk/es3000.txt` | hioadm info/log | ES3000 V3/V5/V6 SSD 状态、错误日志、寿命信息 | ES3000 SSD | error, wear indicator low, media error |
| 硬盘 | `./infocollect_logs/disk/udisk.txt` | ./udisk 系列 | uDisk 工具获取的硬盘基本信息、健康状态、事件、SMART 及 phy 信息 | 硬盘 | health degraded, event error, phy error |
| 硬盘 | `./infocollect_logs/disk/scheduler.txt` | cat /sys/block/*/queue/scheduler | 每个块设备的 I/O 调度算法 | 硬盘, 内核 I/O 子系统 | cfq (不推荐用于 SSD), misconfigured |
| 硬盘 | `./infocollect_logs/disk/blktrace_log.txt` | blktrace+blkparse+btt | 块 I/O 请求的完整生命周期延迟 (Q->G->I->D->C 阶段) | 硬盘, I/O 栈 | d2c high, q2c high, latency spike |
| 硬盘 | `./infocollect_logs/disk/disk_other_info.txt` | sg_logs/sg_modes/lspci | SCSI 日志页/模式页数据及硬盘 PCI 总线信息 | 硬盘, PCIe | error counter, background scan errors |
| 硬盘 | `./infocollect_logs/disk/operations.log` | cp .../operations.log | ES3000 SSD 操作的 hioadm 工具执行日志 | ES3000 SSD | operation failed, error |
