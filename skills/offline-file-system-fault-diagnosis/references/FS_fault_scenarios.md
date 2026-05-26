# 文件系统故障场景分类

文件系统及其底层存储诊断过程中，主要涉及以下六大核心故障场景：

| 场景标签 | 中文描述 | 主要特征 |
|---------|---------|----------|
| `DISK_FAILURE` | 磁盘硬件故障 | SMART 状态 FAILED/FAILING、iBMC 报 Drive Fault/Media Error |
| `FS_CORRUPTION` | 文件系统损坏 | fsck 报错、内核报告 EXT4/XFS 元数据错误或位图不一致 |
| `IO_ERROR` | I/O 读写错误 | 内核日志出现 I/O error / Buffer I/O error / timeout |
| `MOUNT_ERROR` | 挂载异常 | systemd 日志出现 mount failed，常见于配置错误或底层不可达 |
| `SPACE_ISSUE` | 空间/索引耗尽 | 报错 No space left (容量不足) 或 inode exhausted (索引节点耗尽) |
| `PERMISSION_ISSUE` | 权限访问拒绝 | 报错 Permission denied 或 operation not permitted |
