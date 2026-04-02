# 磁盘故障场景分类

磁盘诊断过程中，主要涉及以下六大核心故障场景：

| 场景标签 | 中文描述 | 主要特征与案例 |
| :--- | :--- | :--- |
| `DISK_HARDWARE_FAILURE` | 磁盘硬件故障 | ① **UNC/UF 坏道** (MEDIUM ERROR)；② **SMART 阈值超限** (Reallocated Sectors)；③ **WP 写保护** (WRITE PROTECTED)；④ **介质异常** (No Medium/Changed)；⑤ **Illegal Request** (不支持指令) |
| `DISK_IO_PERFORMANCE` | I/O 性能问题 | ① **落盘缓慢** (Write Cache 刷盘延迟、await 升高)；② 业务压力过载；③ 块请求堆积；④ RAID 背景任务冲突 |
| `DISK_RAID_ERROR` | RAID/控制器故障 | ① RAID 掉盘/离线；② 控制器 Cache 故障；③ 超级电容/电池告警；④ 阵列降级 (Degraded) |
| `DISK_LINK_ISSUE` | 链路/背板故障 | ① **阵列断链/热插拔** (PHY Reset/COMRESET)；② **接口错误** (ICRC/ABRT/IDNF)；③ PCIe AER 错误；④ 背板供电电压波动 |
| `STORAGE_INDUCED_FS_ERROR` | 存储诱发的文件系统故障 | ① 文件系统由于底层持续 I/O 错误被动切换为只读 (Remount RO)；② 元数据损坏 (由于介质故障) |
| `DISK_SYSTEM_CONFIG` | 系统/配置与兼容性限制 | ① **盘符漂移** (未使用 UUID 导致 /dev/sdX 变化)；② **数量过载** (超过 HBA/内核枚举上限)；③ 指令集不兼容 |
