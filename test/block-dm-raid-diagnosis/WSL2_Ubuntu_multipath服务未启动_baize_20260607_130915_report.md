# 块设备/DM/RAID 故障诊断报告 — WSL2 Ubuntu multipath 服务未启动分析

## 基本信息
- **诊断时间**: 2026-06-07 13:09:15 (CST)
- **故障时间窗口**: 2026-06-07 13:33:00 ~ 2026-06-07 13:43:00
- **目标环境**: WSL Ubuntu-22.04 (WSL2 Kernel 6.6.114.1-microsoft-standard-WSL2)
- **故障设备路径**: 不适用（无物理多路径设备）
- **严重级别**: **P3（信息确认类）** — 非故障，属预期正常状态

---

## 问题确认

### 故障现象
WSL Ubuntu 22.04 系统中，`dm_multipath v1.14.0` 模块已存在于内核树中，但 `multipath -ll` 无任何输出，`multipathd` 服务未运行。用户期望了解该现象是否为异常及根因。

### 影响范围
- 仅限 WSL Ubuntu-22.04 本地开发/测试环境
- **未发现业务影响**（无 SAN/FC 存储依赖，无多路径硬件拓扑）
- 不影响 WSL 的正常文件系统与磁盘 IO 操作

### 复现方式
WSL2 环境启动后自动复现：`multipathd.service` 因 systemd 的 `ConditionVirtualization=!container` 条件不满足被跳过，服务不自启。

---

## 三堆栈分析结论

### L1 块层结论

| 指标 | 实际值 | 判定 |
|------|--------|------|
| 块设备数量 | 4 个虚拟磁盘 (sda/sdb/sdc/sdd) | 正常（WSL2 标准配置） |
| 设备类型 | Msft Virtual Disk (Hyper-V 虚拟化) | 正常 |
| dm-* 设备 | 无 | 正常（无 multipath 映射） |
| 块设备健康 | 所有设备 TUR checker 状态为 "up" | 正常 |
| D 状态进程 | 无异常堆积 | 正常 |
| **判定** | **正常** | 块层无异常 |

### L2 映射栈结论

| 组件 | 状态 | 详细 |
|------|------|------|
| DM 设备拓扑 (`dmsetup ls --tree`) | 无 DM 设备 | 返回 "No devices found" |
| multipath 映射 (`multipath -ll`) | 无 multipath 设备 | 4 个路径 (sda-sdd) 均为 `pri=-1 undef`，无 WWID |
| multipathd 服务 | **inactive (dead)** | 条件检测未通过: `ConditionVirtualization=!container was not met` |
| multipathd.socket | inactive (dead) | 同上条件失败 |
| dm_multipath 内核模块 | **未加载** | `lsmod | findstr dm_multipath` 无输出；`modinfo dm_multipath` 确认模块存在于内核树 |
| md RAID | 不适用 | 无 md 设备 |
| LVM | 不适用 | 非本次诊断目标 |
| **判定** | **预期状态（非异常）** | WSL2 容器环境中 multipathd 被 systemd 跳过属于正常行为 |

### L3 物理层结论

| 项 | 状态 | 详细 |
|-----|------|------|
| 设备健康 | 正常 | 所有虚拟磁盘 TUR checker 状态均为 "up" |
| 链路/硬件错误 | 无 | dmesg 无 multipath 相关错误 |
| WWID 标识 | 不存在 | 虚拟磁盘不支持 VPD page 80（序列号查询），`multipath` 无法获取 WWID |
| **判定** | **正常** | 物理/虚拟层无异常 |

---

## 诊断证据链

| 步骤 | 命令 | 输出摘要 | 关键结论 |
|------|------|---------|---------|
| 1 | `lsmod \| grep dm_multipath` | **无输出** | dm_multipath 内核模块未加载 |
| 2 | `modinfo dm_multipath` | 模块文件存在，vermagic: 6.6.114.1 | 模块已安装但未加载 |
| 3 | `systemctl status multipathd` | `inactive (dead)`; 条件: `ConditionVirtualization=!container was not met` | **WSL2 容器环境导致 multipathd 被跳过** |
| 4 | `multipath -v3 -ll` (root) | **"DM multipath kernel driver not loaded"** | 内核驱动未加载，路径均为 undef |
| 5 | `dmsetup ls --tree` | "No devices found" | DM 层无任何设备 |
| 6 | `lsblk` | 4 个 Msft Virtual Disk (sda-sdd) | 标准 WSL2 虚拟块设备拓扑 |
| 7 | `journalctl -u multipathd` | 仅 1 条: condition check skipped | 服务从未实际运行过 |
| 8 | `dmesg \| grep -i multipath` | 无输出 | 内核无 multipath 相关活动 |

---

## 根因定位

**根因描述**:

**这是一个非故障的预期行为**，根本原因在于 WSL2 (Windows Subsystem for Linux) 的环境特性与 multipath 服务启动条件的冲突：

1. **systemd 容器检测拦截（直接原因）** — systemd 在 WSL2 上检测到虚拟化类型为 `container`，导致 `multipathd.service` 和 `multipathd.socket` 的 `ConditionVirtualization=!container` 条件判断为 false，**服务被 systemd 自动跳过**（显示为 `start condition failed`），不会启动。

2. **dm_multipath 内核模块未加载（中间状态）** — 由于 multipathd 服务未启动，没有触发多路径设备发现过程，`dm_multipath` 内核模块作为依赖不会被自动加载。`lsmod` 确认模块不在内存中，`modinfo` 确认模块文件存在于内核树中。

3. **无 SAN/FC 多路径硬件（根本事实）** — WSL2 使用 Hyper-V 虚拟化存储，所有磁盘设备均为 `Msft Virtual Disk`，每个设备只有**单一虚拟 SCSI 路径**，不存在多路径拓扑。即使手动加载模块并启动服务，也无法创建任何多路径映射。

4. **无 WWID 标识（技术障碍）** — WSL2 的虚拟磁盘不支持 VPD page 80（设备序列号查询），`multipath` 工具无法获取 WWID（World Wide Identifier），因此无法构建路径分组和映射。

**置信度**: **高** — 三层证据完全吻合，反事实验证通过

---

## 故障因果链

```
[根因] WSL2 被 systemd 检测为容器虚拟化环境
  │  ConditionVirtualization=!container 条件为 false
  │
  ├─→ multipathd.service 被 systemd 跳过（inactive/dead）
  │
  ├─→ dm_multipath 内核模块未自动加载
  │
  ├─→ 无 SAN/FC 硬件 → 所有盘为 Msft Virtual Disk（单路径）
  │
  ├─→ 虚拟磁盘无 WWID（VPD pg80 读取失败）
  │
  └─→ [用户可见现象] multipath -ll 无输出，multipathd 未运行
```

---

## 排除的替代假设

| 假设 | 排除原因 |
|------|---------|
| multipath 配置损坏 | `/etc/multipath.conf` 虽然极简但语法正确，`multipath -t` 能正常输出完整默认配置树 |
| multipath 工具链缺失/损坏 | multipath-tools v0.8.8 已安装且可执行，libdevmapper 1.02.175 正常 |
| 内核不支持 DM multipath | `modinfo dm_multipath` 确认模块存在于内核树 (`/lib/modules/...`)，版本匹配 6.6.114.1 |
| 块设备异常 | 所有虚拟磁盘 TUR checker 状态为 "up"，设备正常工作，无 IO 错误 |
| multipathd 因配置错误崩溃 | `journalctl -u multipathd` 仅显示条件跳过日志，无崩溃/错误记录 |

---

## 修复建议

### 当前状态评估

当前诊断**未发现故障**。系统处于无 SAN/FC 硬件的 WSL2 容器环境下的**预期正常运行状态**。**无需采取任何修复措施。**

### 若需在 WSL2 上测试/开发 multipath 功能（可选）

| 措施 | 风险等级 | 说明 |
|------|---------|------|
| 手动加载 dm_multipath 内核模块 | **低** | `sudo modprobe dm_multipath` — 仅当前会话有效，重启后失效 |
| 手动启动 multipathd 服务 | **低** | `sudo systemctl start multipathd` — 需先解除条件限制或 `systemctl edit` override |
| 创建 loop 设备的 multipath 模拟测试环境 | **中** | 使用 `losetup` 创建虚拟回环设备，通过修改 `multipath.conf` 手动绑定 WWID，仅供开发测试 |
| 修改 multipathd.service 移除条件限制 | **中** | `sudo systemctl edit multipathd.service` → 添加 `[Unit]\nConditionVirtualization=` 覆盖原条件，不建议在生产环境使用此方式 |

### 验证方法
- 加载内核模块后：`lsmod | grep dm_multipath` 应显示模块已加载
- 启动服务后：`systemctl status multipathd` 应显示 `active (running)`
- 创建测试路径后：`multipath -ll` 应显示多路径设备映射

---

## 附加信息

| 项目 | 值 |
|------|-----|
| WSL2 内核版本 | 6.6.114.1-microsoft-standard-WSL2 |
| multipath-tools 版本 | v0.8.8 (2021-03-12) |
| libdevmapper 版本 | 1.02.175 |
| 内核 DM 版本 | v4.48.0 |
| dm_multipath 模块 | 存在于内核树，vermagic 6.6.114.1，描述 "device-mapper multipath target" |
| 虚拟磁盘 | sda (365M), sdb (145M), sdc (4G swap), sdd (1T) — 均为 Msft Virtual Disk |
| 关键诊断命令 | `multipath -v3 -ll` 输出明确指示 "DM multipath kernel driver not loaded" |
