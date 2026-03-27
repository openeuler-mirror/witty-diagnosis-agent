# 日志错误模式识别指南

本文档描述如何从各类日志文件中识别常见错误特征模式，用于快速判断故障类型。本 Skill 基于离线日志分析，不执行任何在线系统命令。

## kernel_dmesg.log 错误模式

### 文件系统错误模式
```text
EXT4-fs error (device sda1): ext4_find_entry: inode #12345: reading directory
EXT4-fs error (device sda1): ext4_read_inode_bitmap: Cannot read inode bitmap
XFS (sdb1): metadata I/O error: block 0x12345
BTRFS error (device sdc1): btrfs read dev failed
```

**故障类型：** 文件系统损坏
**分析脚本：** `diagnose_fs_corruption.py`
**严重程度：**
- 单个错误：可能是个别文件问题
- 多个错误：文件系统结构损坏
- 连续错误：磁盘区域损坏

---

### I/O 错误模式
```text
Buffer I/O error on dev sda1, logical block 12345
blk_update_request: I/O error, dev sda, sector 12345
EXT4-fs error (device sda1): I/O error while writing superblock
ata1.00: exception Emask 0x0 SAct 0x0 action 0x0
ata1.00: irq_stat 0x40000008
```

**故障类型：** 磁盘I/O错误
**分析脚本：** `diagnose_io_error.py`
**错误模式分析：**
- 单点错误：个别扇区问题
- 连续错误：磁盘区域损坏
- 随机错误：磁盘全面问题
- 渐进增加：磁盘恶化过程

---

### 硬件错误模式
```text
Hardware Error
Machine Check Exception: 0000000000000000
MCE: The CPU has detected a problem with the hardware
DRDY ERR
UNC (Uncorrectable)
ICRC (Interface CRC error)
```

**故障类型：** 硬件故障
**分析脚本：** `diagnose_disk_failure.py`
**关联检查：**
1. 检查SMART日志中的磁盘健康状态
2. 检查系统日志中的温度/电压异常
3. 检查硬件事件日志

---

### 挂载错误模式
```text
mount: wrong fs type, bad option, bad superblock on /dev/sda1
VFS: Can't find ext4 filesystem on dev sda1
EXT4-fs (sda1): VFS: Can't find ext4 filesystem
XFS (sda1): Invalid superblock magic number
```

**故障类型：** 挂载错误
**分析脚本：** `diagnose_mount_error.py`
**失败原因分析：**
- 超级块损坏：文件系统结构损坏
- 设备不存在：磁盘未识别或故障
- 文件系统类型错误：配置错误
- 内核不支持：文件系统特性不兼容

---

## system_messages.log 错误模式

### 系统服务错误
```text
Failed to mount /data.
Dependency failed for /data.
Dependency failed for Local File Systems.
mount: mount point /data does not exist
Unit var-data.mount entered failed state.
```

**故障类型：** 系统服务依赖故障
**关联分析：**
1. 检查挂载配置（fstab）
2. 检查设备可用性
3. 检查文件系统完整性
4. 检查依赖服务状态

---

### 应用程序错误
```text
datanode[2847]: FATAL: Cannot access /data/storage: Input/output error
datanode[2847]: ERROR: DataStore backend /data is unavailable, errno=5
backup-agent[3012]: ERROR: cannot open /data/backup/daily.db: No such file or directory
```

**故障类型：** 应用访问故障
**根本原因追踪：**
1. 文件系统层面错误
2. 权限配置问题
3. 磁盘空间问题
4. 网络存储问题

---

## fsck_check.log 错误模式

### 超级块损坏
```text
Superblock has an invalid journal inode.
Superblock checksum does not match superblock.
Bad magic number in super-block
xfs_repair: Invalid superblock magic number
```

**故障类型：** 文件系统元数据损坏
**严重程度：**
- 备份超级块可用：可修复
- 所有超级块损坏：数据恢复困难
- 伴随磁盘错误：硬件故障导致

---

### inode 损坏
```text
Inode 12345, i_size is 0, should be 4096.
Inode 12345, i_blocks is 0, should be 8.
Illegal inode #12345 in directory entry.
xfs_repair: traversal error - bad inode 0x2f8b1
```

**故障类型：** 文件系统结构损坏
**影响范围：**
- 单个inode：影响个别文件
- 多个inode：影响多个文件
- inode位图损坏：影响文件系统管理

---

### 目录结构损坏
```text
Directory inode 12345 has an unallocated block #0.
Directory entry has invalid file type.
Directory contains duplicate entries.
xfs_repair: junking directory entry "backup_20260321" in directory inode 197120
```

**故障类型：** 目录结构异常
**修复难度：**
- 简单错误：自动修复可能成功
- 复杂错误：需要手动干预
- 严重损坏：数据可能丢失

---

## disk_health_smart.log 错误模式

### 磁盘健康状态
```text
SMART overall-health self-assessment test result: FAILED
Drive failure expected in less than 24 hours. SAVE ALL DATA.
```

**故障类型：** 磁盘即将故障
**紧急程度：** 立即处理
**关联证据：**
- 系统日志中的I/O错误
- 应用程序访问失败
- 文件系统错误

---

### 关键指标异常
| 指标 | 正常值 | 警告阈值 | 严重阈值 | 含义 |
|------|--------|----------|----------|------|
| Reallocated_Sector_Ct | 0 | > 0 | > 10 | 重新分配扇区数 |
| Current_Pending_Sector | 0 | > 0 | > 5 | 待处理扇区数 |
| Offline_Uncorrectable | 0 | > 0 | > 0 | 离线不可纠正 |
| Seek_Error_Rate | 低值 | 显著增加 | 持续高值 | 寻道错误率 |
| UDMA_CRC_Error_Count | 0 | > 0 | > 10 | CRC错误计数 |

**分析要点：**
1. 关注RAW值（实际值），非归一化值
2. 观察趋势变化，非单次数值
3. 结合多个指标综合判断

---

## 时间戳模式识别

### 系统日志时间戳
```text
Mar 25 03:47:11 storage-node-01 kernel: blk_update_request: I/O error
Mar 25 03:47:14 storage-node-01 kernel: XFS (sdb1): metadata I/O error
Mar 25 03:47:15 storage-node-01 systemd[1]: Failed to mount /data.
```

**时间线分析：**
1. **故障起点**：第一个错误出现时间
2. **恶化过程**：错误频率增加时间
3. **故障爆发**：服务中断时间
4. **恢复尝试**：修复操作时间

### 内核时间戳
```text
[ 4823.182341] XFS (sdb1): Reclaiming stale inode
[15284.712341] ata2: exception Emask 0x0
[15312.481234] blk_update_request: I/O error
```

**相对时间分析：**
1. **系统启动时间**：第一个时间戳
2. **故障发生时间**：相对系统启动的时间
3. **错误间隔**：判断错误频率
4. **持续时间**：故障持续时长

---

## 错误频率分析

### 偶发性错误
**特征：**
- 错误间隔时间长（分钟/小时级）
- 错误位置随机
- 无明确恶化趋势
**可能原因：** 临时性问题，环境干扰

### 渐进性错误
**特征：**
- 错误频率逐渐增加
- 错误位置相对集中
- 有明确恶化时间线
**可能原因：** 硬件老化，磁盘表面损坏

### 爆发性错误
**特征：**
- 短时间内大量错误
- 错误连续出现
- 服务立即中断
**可能原因：** 硬件突然故障，严重损坏

---

## 跨日志关联分析

### 证据链构建
1. **时间关联**：不同日志中的错误时间匹配
2. **位置关联**：错误指向相同设备/文件系统
3. **因果关联**：硬件错误导致文件系统错误
4. **影响关联**：文件系统错误导致应用错误

### 典型关联模式
```
磁盘硬件故障证据链：
1. disk_health_smart.log: SMART FAILED, 坏扇区增加
2. kernel_dmesg.log: I/O错误, ATA异常
3. system_messages.log: 挂载失败, 应用错误
4. fsck_check.log: 文件系统结构损坏
```

```
软件配置问题证据链：
1. system_messages.log: 权限错误, 配置错误
2. kernel_dmesg.log: 无硬件错误
3. disk_health_smart.log: SMART正常
4. fsck_check.log: 文件系统结构正常
```

---

## 快速诊断检查表

### 1. 检查磁盘健康
- [ ] SMART状态是否为FAILED
- [ ] 重新分配扇区数是否>0
- [ ] 待处理扇区数是否>0
- [ ] 离线不可纠正扇区是否>0

### 2. 检查文件系统
- [ ] 是否有超级块损坏错误
- [ ] 是否有inode损坏错误
- [ ] 是否有目录结构错误
- [ ] 是否有日志子系统错误

### 3. 检查I/O错误
- [ ] I/O错误频率（偶发/渐进/爆发）
- [ ] 错误位置（单点/连续/随机）
- [ ] 错误类型（读取/写入/超时）

### 4. 检查系统服务
- [ ] 挂载操作是否失败
- [ ] 依赖服务是否正常
- [ ] 应用程序是否报错
- [ ] 系统日志是否有异常

### 5. 时间线分析
- [ ] 确定故障开始时间
- [ ] 分析错误恶化过程
- [ ] 识别故障爆发点
- [ ] 检查恢复尝试记录

---

## 诊断优先级指南

### 紧急优先级（立即处理）
1. SMART FAILED且预测24小时内故障
2. 大量连续I/O错误导致服务中断
3. 文件系统无法挂载且数据不可访问
4. 关键业务应用因存储问题停止服务

### 高优先级（今日处理）
1. SMART警告但未FAILED
2. 渐进增加的I/O错误
3. 文件系统错误但可挂载
4. 应用程序偶发访问错误

### 中优先级（本周处理）
1. 少量偶发I/O错误
2. 文件系统警告但功能正常
3. 磁盘属性缓慢变化
4. 性能下降但未影响服务

### 低优先级（计划处理）
1. 历史错误无近期复发
2. 轻微属性变化无恶化趋势
3. 不影响功能的警告信息
4. 已修复问题的残留日志