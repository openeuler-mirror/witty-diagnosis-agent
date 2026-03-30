---
name: offline-file-system-fault-diagnosis
description: 通过分析服务器离线日志（iBMC、OS Messages、InfoCollect）诊断 EulerOS 文件系统故障并定位根本原因。适用场景：用户提供日志文件（dmesg、messages、fsck 输出、InfoCollect 包等）并询问文件系统损坏、挂载失败、磁盘 I/O 错误、空间不足、inode 耗尽、权限拒绝等问题的原因或修复方案；用户要求进行日志分析、故障溯源、根因定位或生成诊断报告时。
---

# 离线文件系统日志诊断

本技能通过分析从服务器收集的标准日志文件，帮助诊断 EulerOS 文件系统故障。

> **重要提示**：分析时应遵循 **"先宏观后微观"** 的原则：
> 1. **全局扫描**：优先使用 **一键诊断脚本** (`scripts/diagnose_summary.py`) 快速识别异常模块和关键报错。
> **注意：使用脚本时必须优先执行 `--help` 参数，了解脚本用法**
> 2. **精准定位**：根据脚本输出的线索（如特定时间点或文件名），再使用 `grep` / `less` 等文件操作命令查看具体的原始日志上下文。

## 日志目录结构与对应诊断脚本

以 `/path/to/logs/xxxx` 为例，标准的服务器日志收集包通常具有以下层级结构。本技能提供了针对性的脚本来分析不同层级的日志。

> **注意**：在实际场景中，用户提供的日志包可能不完整，可能仅包含以下三种目录中的一种或多种。请根据实际存在的日志类型灵活选择对应的分析脚本。

```text
<日志根目录> (例如: 10.120.6.76)
├── ibmc_logs/                  # iBMC 硬件带外管理日志
│   └── (支持 Huawei, H3C, Inspur) -> 使用 scripts/diagnose_ibmc.py
├── infocollect_logs/           # 系统信息收集工具生成的分类日志
│   └── (文件系统/挂载/空间信息)    -> 使用 scripts/diagnose_infocollect.py
└── messages/                   # 操作系统层面的系统日志
    └── (dmesg, syslog, messages) -> 使用 scripts/diagnose_messages.py
```

更深层次的文件架构及详细说明，请参考 `references/` 目录下对应的指南文档（如 [iBMC](references/huawei_ibmc.md), [InfoCollect](references/infocollect_guide.md), [Messages](references/messages.md)）。

---

## ⚠️ 强制执行流程

**必须严格按以下顺序执行，禁止跳过或乱序：**

```
Step 0 (环境检查) → Step 1 (故障日志采集) → Step 2 (场景分类) → Step 3 (深入分析) → Step 4 (交叉验证) → Step 5 (生成报告)
```

**执行规则：**
1. **顺序强制**：必须完成当前步骤并验证通过后，才能进入下一步
2. **阻断机制**：Step 0 失败时立即停止，禁止继续执行
3. **场景分支**：Step 2 输出场景标签后，Step 3 必须执行对应的专项分析脚本
4. **交叉验证**：Step 4 必须验证通过后才能生成最终报告
5. **文件适配**：日志文件不全时自动降级分析策略，但必须至少有一个日志文件

**每步完成标志：**
- Step 0：输出 `✅ Environment check passed!`
- Step 1：输出日志文件时间范围、文件统计、错误关键词概览
- Step 2：输出场景标签（FS_CORRUPTION / DISK_FAILURE / MOUNT_ERROR / IO_ERROR / PERMISSION_ISSUE / SPACE_ISSUE）
- Step 3：输出问题定位 + 关键证据 + 候选根因 + 修复建议
- Step 4：输出验证结果 + 置信度调整 + 矛盾点检测
- Step 5：生成完整的诊断报告文件（.md）

---

## 分析流程总览

| 阶段 | 目标 | 脚本 |
|------|------|------|
| **Step 0** 环境检查 | 验证日志文件存在性和可读性 | `./scripts/check_environment.sh` |
| **Step 1** 故障日志采集 | 从日志目录采集关键故障事件摘要 | `python3 scripts/diagnose_summary.py <log_dir> -o` |
| **Step 2** 场景分类 | 判断故障类型（文件系统损坏/磁盘故障/挂载异常等） | `python3 scripts/scene_classifier.py <log_dir>` |
| **Step 3** 深入分析 | 按场景执行专项分析 | `python3 scripts/diagnose_<source>.py <log_dir>` |
| **Step 4** 交叉验证 | 多源日志相互佐证，排除误判 | `python3 scripts/cross_validator.py <log_dir>` |
| **Step 5** 生成报告 | 汇总证据链与根因，生成诊断报告 | `./scripts/generate_report.sh` |

> **强制阻断规则**：`./scripts/check_environment.sh` 返回非 0 退出码时，**立即停止**后续所有步骤。

---

## Step 0：环境检查

```bash
./scripts/check_environment.sh [--log-dir PATH]
```

**检查项目：**
- 日志目录是否存在
- 至少存在一个日志文件且非空

输出 `✅ Environment check passed!` 后方可继续，输出 `❌ Environment check FAILED! 请修复上述问题后重试。` 时，必须立即停止后续所有步骤。

---

## Step 1：故障日志采集

使用概览模式（`-o`）从日志目录中采集关键故障事件摘要：

```bash
python3 scripts/diagnose_summary.py <log_dir> -o
```

**采集内容：**
- **日志时间范围**：各日志文件覆盖的最早/最晚时间
- **文件统计**：已识别的日志文件类型及数量
- **错误关键词概览**：各文件中 error/fail/critical/corrupt 等关键词出现次数

**支持过滤采集（缩小分析范围）：**

```bash
# 按日期过滤采集
python3 scripts/diagnose_summary.py <log_dir> -o -d "Mar 16"

# 按时间范围过滤采集
python3 scripts/diagnose_summary.py <log_dir> -o -s "2026-03-10 08:00:00" -e "2026-03-10 12:00:00"

# 按关键词过滤采集
python3 scripts/diagnose_summary.py <log_dir> -o -k "I/O error" "corrupt"
```

**选项说明：**

| 选项 | 说明 |
|------|------|
| `-o, --overview` | 概览模式，仅输出日志摘要（Step 1 采集专用）|
| `-k, --keywords` | 关键词过滤（可多个） |
| `-d, --date` | 日期过滤（如 `"Mar 16"`）|
| `-s, --start-time` | 开始时间（如 `"2026-03-10 08:00:00"`）|
| `-e, --end-time` | 结束时间（如 `"2026-03-10 12:00:00"`）|

**Step 1 完成标志：** 输出日志时间范围、文件类型统计、各文件错误关键词出现次数后，即可进入 Step 2。

---

## Step 2：场景分类

根据 Step 1 采集的日志概览，执行以下脚本自动识别故障类型：

```bash
python3 scripts/scene_classifier.py <log_dir> [选项]
```

**场景分类规则（按优先级）：**

| 场景标签 | 触发条件 | 优先级 |
|---------|---------|--------|
| `DISK_FAILURE` | SMART 状态 FAILED/FAILING，或内核检测到 MCE/硬件错误 | ⭐⭐⭐⭐⭐ |
| `FS_CORRUPTION` | fsck 检测到 error/corrupt，或内核报告 EXT4/XFS 文件系统错误 | ⭐⭐⭐⭐⭐ |
| `IO_ERROR` | 内核日志出现 I/O error / Buffer I/O error / timeout | ⭐⭐⭐ |
| `MOUNT_ERROR` | systemd 启动日志出现 mount.*failed / Failed to mount | ⭐⭐⭐⭐ |
| `SPACE_ISSUE` | 系统日志出现 No space left / inode exhausted | ⭐⭐⭐⭐ |
| `PERMISSION_ISSUE` | 系统日志出现 Permission denied / operation not permitted | ⭐⭐⭐ |

### 场景 → 根因假设矩阵

确定场景标签后，**必须从以下矩阵中选取 2~3 个候选根因假设**，并在 Step 3 中逐一验证：

| 场景标签 | 候选根因假设（需在 Step 3 中验证） |
|---------|----------------------------------|
| `FS_CORRUPTION` | ① 异常断电导致元数据未落盘 ② 磁盘坏扇区导致文件系统元数据损坏 ③ 内核/驱动 bug 导致写入不一致 |
| `DISK_FAILURE` | ① 磁盘物理介质老化（Reallocated Sector 超阈值） ② 固件/控制器故障 ③ 电源电压异常导致磁盘损坏 |
| `MOUNT_ERROR` | ① fstab 中 UUID 配置与实际设备不匹配 ② 文件系统类型不匹配（wrong fs type） ③ 底层文件系统损坏导致无法挂载 |
| `IO_ERROR` | ① 磁盘物理坏道（SMART 指标恶化） ② RAID 控制器/HBA 固件问题 ③ SAS/SATA 线缆或背板故障 |
| `SPACE_ISSUE` | ① 日志文件异常增长占满磁盘 ② inode 耗尽（文件数量超限，非容量不足） ③ 大文件或临时文件未清理 |
| `PERMISSION_ISSUE` | ① SELinux/AppArmor 策略阻断 ② 文件/目录权限位被误修改 ③ 挂载选项包含 noexec/nosuid 等限制 |

> ⚠️ **强制要求**：Step 3 分析结束后，必须对上述候选根因逐一标注：✅ 已证实 / ❌ 已排除 / ❓ 证据不足

**Step 2 完成标志：** 输出场景标签，并将结果写入 `/tmp/fs_diagnosis_scene.conf`，从根因假设矩阵中选定候选根因后，进入 Step 3。

---

## Step 3：深入分析

根据 Step 2 的场景分类结果，执行对应的专项分析脚本：

### 3.1 通用分析脚本

```bash
# iBMC 日志分析（硬件层）
python3 scripts/diagnose_ibmc.py <ibmc_logs目录> [选项]

# InfoCollect 日志分析（系统信息层）
python3 scripts/diagnose_infocollect.py <infocollect_logs目录> [选项]

# OS Messages 日志分析（操作系统层）
python3 scripts/diagnose_messages.py <messages目录> [选项]
```

### 3.2 按场景专项分析

#### 3A：文件系统损坏分析 (FS_CORRUPTION)

**核心日志文件**：
- `infocollect_logs/system/dmesg.txt` - 内核文件系统错误
- `infocollect_logs/raid/sasraidlog.txt` - RAID 控制器日志
- `messages/messages` 或 `messages/syslog` - 系统级文件系统错误

**关键错误模式：**

| 文件系统类型 | 错误关键字 | 含义 |
|-------------|-----------|------|
| EXT4 | `EXT4-fs error` | EXT4 文件系统错误 |
| EXT4 | `superblock` | 超级块损坏 |
| EXT4 | `inode` | inode 错误 |
| XFS | `XFS: ... error` | XFS 文件系统错误 |
| XFS | `xfs_force_shutdown` | XFS 强制关闭 |
| BTRFS | `BTRFS: error` | BTRFS 文件系统错误 |
| 通用 | `corrupt` | 数据损坏 |
| 通用 | `orphaned inode` | 孤儿 inode |

**分析命令**：
```bash
# 检查文件系统错误
python3 scripts/diagnose_messages.py <messages目录> -k "EXT4-fs error" "XFS.*error" "corrupt"

# 检查 dmesg 中的文件系统错误
python3 scripts/diagnose_infocollect.py <infocollect目录> -k "filesystem" "superblock" "inode"
```

**根因推理框架（执行脚本后必须完成）：**

1. **因果链条**：整理从"最早的异常日志时间戳"到"故障发生时间"的完整事件序列
2. **鉴别排除**：从 Step 2 矩阵中逐一标注 ✅/❌/❓（例：先有 `I/O error` 再出现 `FS error` → 磁盘层传导；仅有 `FS error` 无底层 `I/O error` → 纯软件写入不一致）
3. **根因锁定**：至少有 2 条独立证据支持，且无矛盾证据时，方可锁定根因
4. **不确定标注**：若证据不足以锁定，明确标注"待验证假设"并说明缺失的证据类型

> 🔍 **重点确认**：损坏是从磁盘层传导上来（先有 `I/O error` 再有 `FS error`）？还是纯软件层写入不一致（仅有 `FS error`，无底层 `I/O error`）？两者根因和修复方案截然不同。



#### 3B：挂载错误分析 (MOUNT_ERROR)

**核心日志文件**：
- `messages/messages` - 系统挂载日志
- `infocollect_logs/system/dmesg.txt` - 内核挂载错误
- `infocollect_logs/disk/parted_disk.txt` - 分区信息
- `infocollect_logs/raid/diskmap.txt` - 磁盘映射

**关键错误模式：**

| 错误关键字 | 含义 |
|-----------|------|
| `mount: wrong fs type` | 文件系统类型不匹配 |
| `mount: bad option` | 挂载选项错误 |
| `mount: bad superblock` | 超级块损坏 |
| `special device does not exist` | 设备不存在 |
| `UUID=xxx does not exist` | UUID 对应设备不存在 |
| `Dependency failed` | 依赖挂载失败 |

**分析命令**：
```bash
# 检查挂载错误
python3 scripts/diagnose_messages.py <messages目录> -k "mount.*failed" "Failed to mount" "wrong fs type"

# 检查设备映射
python3 scripts/diagnose_infocollect.py <infocollect目录> -k "mount" "fstab" "UUID"
```

**根因推理框架（执行脚本后必须完成）：**

1. **因果链条**：整理从"最早的异常日志时间戳"到"故障发生时间"的完整事件序列
2. **鉴别排除**：从 Step 2 矩阵中逐一标注 ✅/❌/❓
3. **根因锁定**：至少有 2 条独立证据支持，且无矛盾证据时，方可锁定根因
4. **不确定标注**：若证据不足以锁定，明确标注"待验证假设"并说明缺失的证据类型

> 🔍 **重点确认**：是配置问题（UUID/fstab 错误）导致挂载无法找到设备？还是底层设备不可达（文件系统损坏、设备离线）导致挂载无法成功？两者修复路径不同，前者改配置，后者需先修复底层。



#### 3C：空间问题分析 (SPACE_ISSUE)

**核心日志文件**：
- `infocollect_logs/system/iostat.txt` - I/O 统计
- `infocollect_logs/disk/parted_disk.txt` - 分区信息
- `messages/messages` - 空间告警

**关键错误模式：**

| 错误关键字 | 含义 |
|-----------|------|
| `No space left on device` | 磁盘空间不足 |
| `inode` + `exhausted` | inode 耗尽 |
| `disk full` | 磁盘满 |
| `cannot create` + `full` | 无法创建文件 |

**分析命令**：
```bash
# 检查空间问题
python3 scripts/diagnose_messages.py <messages目录> -k "No space left" "inode" "full"
```

**根因推理框架（执行脚本后必须完成）：**

1. **因果链条**：整理从"最早的异常日志时间戳"到"故障发生时间"的完整事件序列
2. **鉴别排除**：从 Step 2 矩阵中逐一标注 ✅/❌/❓
3. **根因锁定**：至少有 2 条独立证据支持，且无矛盾证据时，方可锁定根因
4. **不确定标注**：若证据不足以锁定，明确标注"待验证假设"并说明缺失的证据类型

> 🔍 **重点确认**：是总容量不足（`df -h` 显示使用率 100%）？还是 inode 耗尽（`df -i` 显示 inode 使用率 100%，但磁盘空间剩余）？两者现象相同但根因与处理方式完全不同；同时需确认是哪个子目录/进程导致占满。



#### 3D：权限问题分析 (PERMISSION_ISSUE)

**核心日志文件**：
- `messages/messages` - 系统权限日志
- `ibmc_logs/` - iBMC 安全审计日志

**关键错误模式：**

| 错误关键字 | 含义 |
|-----------|------|
| `Permission denied` | 权限拒绝 |
| `operation not permitted` | 操作不允许 |
| `access denied` | 访问拒绝 |
| `SELinux` | SELinux 阻止 |

**分析命令**：
```bash
# 检查权限问题
python3 scripts/diagnose_messages.py <messages目录> -k "Permission denied" "operation not permitted"
```

**根因推理框架（执行脚本后必须完成）：**

1. **因果链条**：整理从"最早的异常日志时间戳"到"故障发生时间"的完整事件序列
2. **鉴别排除**：从 Step 2 矩阵中逐一标注 ✅/❌/❓
3. **根因锁定**：至少有 2 条独立证据支持，且无矛盾证据时，方可锁定根因
4. **不确定标注**：若证据不足以锁定，明确标注"待验证假设"并说明缺失的证据类型

> 🔍 **重点确认**：是权限位问题（`stat` 查看文件/目录权限）、SELinux/AppArmor 上下文阻断（日志中出现 `avc: denied`），还是挂载选项限制（如 `noexec`、`nosuid`）？三者处理方式各异，不可混淆。



#### 3E：I/O 错误分析 (IO_ERROR)

**核心日志文件**：
- `infocollect_logs/system/dmesg.txt` - 内核 I/O 错误
- `infocollect_logs/disk/disk_smart.txt` - SMART 状态
- `messages/messages` - 系统 I/O 日志

**关键错误模式：**

| 错误关键字 | 含义 |
|-----------|------|
| `I/O error` | I/O 错误 |
| `Buffer I/O error` | 缓冲区 I/O 错误 |
| `timeout` | I/O 超时 |
| `read-error` / `write-error` | 读写错误 |

**分析命令**：
```bash
# 检查 I/O 错误
python3 scripts/diagnose_messages.py <messages目录> -k "I/O error" "Buffer I/O error" "timeout"

# 检查 SMART 状态
python3 scripts/diagnose_infocollect.py <infocollect目录> -k "FAILED" "Reallocated" "Pending"
```

**根因推理框架（执行脚本后必须完成）：**

1. **因果链条**：整理从"最早的异常日志时间戳"到"故障发生时间"的完整事件序列
2. **鉴别排除**：从 Step 2 矩阵中逐一标注 ✅/❌/❓
3. **根因锁定**：至少有 2 条独立证据支持，且无矛盾证据时，方可锁定根因
4. **不确定标注**：若证据不足以锁定，明确标注"待验证假设"并说明缺失的证据类型

> 🔍 **重点确认**：I/O 错误是否能定位到特定物理设备（确认 `/dev/sdX` 设备名）？SMART 指标是否同步恶化（`Reallocated_Sector_Ct` 或 `Current_Pending_Sector` 非零）？还是逻辑卷/RAID 映射层问题（物理磁盘 SMART 正常但逻辑层 I/O 异常）？

**Step 3 完成标志：** 所有分析输出完整的问题定位 + 关键证据 + 候选根因（含 ✅/❌/❓ 标注）+ 修复建议后，进入 Step 4。


---

## Step 4：交叉验证

**目标**：通过不同来源的日志相互佐证，**验证 Step 3 锁定的根因假设**，确保结论准确性。

在进行诊断前，请确保您收集的日志目录中包含以下类型的日志文件：

1.  **硬件层日志**：
    *   **SMART 日志** (`disk_smart.txt`): 记录硬盘内部的健康指标，如重映射扇区、通电时间等。
    *   **RAID/HBA 日志** (`sasraidlog.txt`, `sashbalog.txt`): 记录 RAID 卡控制器事件，如掉盘、重建、介质错误。
    *   **健康评分** (`hwdiag_hdd.txt`): 厂商工具提供的硬盘健康度评分。
    *   **iBMC SEL** (`sel.db`, `sel.tar`, `onekeylog/log/selelist.csv`): 记录硬件底层事件。

2.  **系统层日志**：
    *   **内核日志** (`dmesg.txt`): 记录内核环形缓冲区信息，包含 SCSI/ATA 子系统的底层报错。
    *   **系统消息** (`messages`, `syslog`): 记录系统运行期间的服务和内核事件，包含时间戳。
    *   **Drop Message** (`drop_message/`): 来自 `/var/log/messages` 的系统日志转储，通常包含 `I/O error`, `SCSI error` 及 `smartd` 监控告警，是分析系统侧故障的关键来源。

3.  **性能层日志**：
    *   **I/O 统计** (`iostat.txt`): 记录磁盘的吞吐量、IOPS、队列深度和延迟。
    *   **块跟踪** (`blktrace_log.txt`): 记录块设备 I/O 请求的详细生命周期延迟。

4.  **配置与拓扑日志**：
    *   **磁盘映射** (`diskmap.txt`, `phy_info.txt`): 记录逻辑盘符与物理槽位的对应关系。

### 根因验证检查清单（必须逐项确认）

在确认根因前，通过以下问题检验多源日志的一致性：

| 验证点 | 验证方法 | 通过条件 |
|--------|---------|----------|
| **时间一致性** | 对比 iBMC SEL 事件时间、dmesg 内核日志时间、messages 系统日志时间 | 所有来源的异常时间戳在同一时间窗口内（±5 分钟） |
| **层级传导性** | 检查是否存在"硬件层 → 内核层 → 应用层"的错误传导链 | 有明确的上下层因果关系（如 SMART 恶化 → I/O error → FS error）|
| **设备一致性** | 确认所有日志中的设备标识（`/dev/sdX`、槽位号、WWN）指向同一物理设备 | 无跨设备混淆 |
| **根因唯一性** | 检查是否存在多个并发故障（如同时有 `SPACE_ISSUE` + `DISK_FAILURE`） | 明确主根因，次根因单独标注 |
| **矛盾检测** | 检查是否存在相互矛盾的证据（如 SMART 正常但 I/O error 持续） | 矛盾点必须给出合理解释（如 NVMe 无 SMART 支持）或标注"待验证" |

**Step 4 完成标志：** 根因验证清单全部通过，或矛盾点已合理解释，无严重矛盾点时，进入 Step 5。


---

## Step 5：生成报告

汇总 Step 1～4 的所有分析结果，生成结构化诊断报告：

```bash
./scripts/generate_report.sh --output ./fs_diagnosis_report.md

# 可附带专项分析输出文件
./scripts/generate_report.sh \
    --output ./fs_diagnosis_report_$(date +%Y%m%d).md \
    --analysis /tmp/diagnose_output.txt
```

**报告结构：**

1. **Executive Summary（故障摘要）** — 故障场景、根本原因、修复建议概述
2. **Technical Analysis（技术分析）** — 日志文件概览、故障现象、故障机理、证据链（E1/E2/E3...）
3. **Root Cause（根本原因）** — 直接原因 + 根本原因 + 5 Whys 分析
4. **Recommendations（修复建议）** — 立即 / 短期 / 中期 / 长期修复措施
5. **风险评估** — 数据丢失、服务中断、复发风险评估
6. **最终验证清单** — 确认分析足够深入的检查清单
7. **附录** — 关键日志片段与相关命令参考

**根因具体性要求（笼统描述视为分析不足）：**

| ❌ 笼统 | ✅ 具体 |
|--------|--------|
| "磁盘坏了" | "/dev/sda 存在 128 个坏扇区，SMART Reallocated_Sector_Ct 超过阈值" |
| "文件系统错误" | "EXT4 文件系统 /dev/sdb1 的 inode #12345 损坏，导致 /data 目录无法访问" |
| "挂载失败" | "/etc/fstab 中 UUID=xxx 对应的设备不存在，实际设备 UUID 为 yyy" |

**根因推理完成性检查（调用 `generate_report.sh` 前必须通过）：**

在调用 `./scripts/generate_report.sh` 生成报告框架之前，必须能够回答以下所有问题：

- [ ] 根因是否具体到：**设备名**（`/dev/sdX`）+ **错误类型**（超级块损坏/坏扇区/UUID不匹配）+ **触发条件**（断电/老化/配置错误）？
- [ ] Step 2 矩阵中所有候选根因是否已完成 ✅/❌/❓ 标注？
- [ ] 是否能描述从"根因"到"最终症状"的完整因果链条（至少 3 层，例：坏扇区 → I/O error → EXT4 超级块损坏 → 挂载失败）？
- [ ] 是否排除了至少一个"相似但非真正根因"的情况（即做过鉴别诊断）？

> ⚠️ **若有任何未通过项，必须返回 Step 3 继续分析（追加关键词或缩小时间范围），而非直接填写报告模板。**

---

## 诊断脚本概览

| 脚本 | 所属步骤 | 功能 | 关键特性 |
|------|---------|------|----------|
| `check_environment.sh` | Step 0 | 环境检查 | 验证日志文件存在性和可读性，强制阻断 |
| `diagnose_summary.py` | Step 1 | 故障日志采集 | 概览模式，输出时间范围/文件统计/错误概览 |
| `scene_classifier.py` | Step 2 | 场景分类器 | 支持时间/关键词过滤，精确分类，保存场景标签 |
| `diagnose_ibmc.py` | Step 3 | iBMC 日志分析 | SEL 事件分析，硬件告警检测 |
| `diagnose_infocollect.py` | Step 3 | InfoCollect 日志分析 | SMART/RAID/iostat 分析 |
| `diagnose_messages.py` | Step 3 | OS 消息日志分析 | 文件系统错误、挂载错误、空间问题检测 |
| `generate_report.sh` | Step 5 | 报告生成 | 汇总分析结果，生成结构化诊断报告 |

### 常用参数说明

| 参数 | 说明 | 示例 |
| :--- | :--- | :--- |
| `-o`, `--overview` | **快速概览**。查看日志时间跨度、硬件概况及错误文件分布。 | `python3 scripts/diagnose_ibmc.py <dir> -o` |
| `-d`, `--date` | **特定日期排查**。只显示包含特定日期字符串的日志行。 | `python3 scripts/diagnose_messages.py <dir> -d "Mar 5"` |
| `-s`, `--start-time` | **开始时间**。格式 "YYYY-MM-DD HH:MM:SS"。 | `... -s "2023-03-05 10:00:00"` |
| `-e`, `--end-time` | **结束时间**。格式 "YYYY-MM-DD HH:MM:SS"。 | `... -e "2023-03-05 12:00:00"` |
| `-k`, `--keywords` | **关键词搜索**。增加自定义故障关键词搜索。 | `... -k "EXT4-fs error" "mount failed"` |

---

## 参考资料

* [InfoCollect 诊断指南](references/infocollect_guide.md)
* [Huawei iBMC 分析](references/huawei_ibmc.md)
* [H3C iBMC 分析](references/h3c_ibmc.md)
* [Inspur iBMC 分析](references/Inspur_ibmc.md)
* [OS Messages 分析](references/messages.md)

---

## 分析原则

0. **根因优先**：诊断的最终目标是**定位根因（Root Cause）**，而非仅描述症状。每个分析步骤都应推进"为什么会发生"的答案，而非停留在"发生了什么"。症状描述（如"文件系统错误"）只是中间过程，根因（如"断电导致元数据未落盘"）才是终点。
1. **软件优先**：文件系统问题优先排查软件层面，确认非硬件故障引起
2. **证据驱动**：每个结论必须有日志数据支撑，无数据则标注"待验证假设"
3. **配置检查**：挂载问题需检查 fstab 配置、设备 UUID 映射
4. **风险评估**：评估修复操作对数据的影响，优先选择保守方案
5. **交叉验证**：通过多源日志相互佐证，确保结论准确性
6. **离线分析**：本 Skill 仅基于日志文件进行分析，不执行任何在线系统命令

