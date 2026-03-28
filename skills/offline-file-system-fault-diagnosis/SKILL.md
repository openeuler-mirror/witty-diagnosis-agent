---
name: offline-file-system-fault-diagnosis
description: 通过离线分析系统日志文件诊断 Linux 文件系统故障。自动识别文件系统损坏、挂载异常、I/O 错误等问题，提供环境检查→日志采集→场景分类→深度分析→根因报告的完整诊断链路。本 Skill 仅基于提供的日志文件进行离线分析，不执行任何在线系统命令。当遇到以下场景时立即使用：Linux 文件系统故障诊断、磁盘 I/O 错误分析、文件系统损坏修复、挂载失败排查、磁盘空间不足问题、权限访问问题、系统启动失败、硬件故障检测、日志分析、离线故障诊断、系统维护、运维故障排查、服务器故障分析、存储问题诊断、文件系统修复、磁盘健康检查、SMART 预警分析、系统日志分析、故障根因定位。
---

# Linux 文件系统日志诊断 Skill

## 目录结构与输入文件

```text
fs_diagnosis/              # 故障诊断目录
├── kernel_dmesg.log       # 内核环形缓冲区日志（dmesg 输出）
├── systemd_boot.log       # systemd 启动日志（journalctl -b 输出）
├── fsck_check.log         # 文件系统检查日志（fsck 输出）
├── system_messages.log    # 系统消息日志（/var/log/messages）
├── disk_layout_lsblk.log  # 磁盘布局信息（lsblk 输出）
├── disk_uuid_blkid.log    # 磁盘 UUID 信息（blkid 输出）
├── mount_config_fstab.log # 挂载配置（/etc/fstab 内容）
└── disk_health_smart.log  # 磁盘健康状态（smartctl 输出）
```

**注意：** 以上文件不一定全部存在，诊断脚本会自动检测可用文件并适配分析策略。

---

## ⚠️ 强制执行流程

**必须严格按以下顺序执行，禁止跳过或乱序：**

```
Step 0 (环境检查) → Step 1 (故障日志采集) → Step 2 (场景分类) → Step 3 (深入分析) → Step 4 (生成报告)
```

**执行规则：**
1. **顺序强制**：必须完成当前步骤并验证通过后，才能进入下一步
2. **阻断机制**：Step 0 失败时立即停止，禁止继续执行
3. **场景分支**：Step 2 输出场景标签后，Step 3 必须执行对应的专项分析脚本
4. **文件适配**：日志文件不全时自动降级分析策略，但必须至少有一个日志文件

**每步完成标志：**
- Step 0：输出 `✅ Environment check passed!`
- Step 1：输出日志文件时间范围、文件统计、错误关键词概览
- Step 2：输出场景标签（FS_CORRUPTION / DISK_FAILURE / MOUNT_ERROR / IO_ERROR / PERMISSION_ISSUE / SPACE_ISSUE）
- Step 3：输出问题定位 + 关键证据 + 候选根因 + 修复建议
- Step 4：生成完整的诊断报告文件（.md）

---

## 分析流程总览

| 阶段 | 目标 | 脚本 |
|------|------|------|
| **Step 0** 环境检查 | 验证日志文件存在性和可读性 | `./scripts/check_environment.sh` |
| **Step 1** 故障日志采集 | 从日志目录采集关键故障事件摘要 | `python3 scripts/diagnose_fs_summary.py <log_dir> -o` |
| **Step 2** 场景分类 | 判断故障类型（文件系统损坏/磁盘故障/挂载异常等） | `python3 scripts/scene_classifier.py <log_dir>` |
| **Step 3** 深入分析 | 按场景执行专项分析 | `python3 scripts/diagnose_<scene>.py <log_dir>` |
| **Step 4** 生成报告 | 汇总证据链与根因，生成诊断报告 | `./scripts/generate_report.sh` |

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
# 采集日志目录全量概览
python3 scripts/diagnose_fs_summary.py <log_dir> -o

# 示例
python3 scripts/diagnose_fs_summary.py ./fs_diagnosis/ -o
```

**采集内容：**
- **日志时间范围**：各日志文件覆盖的最早/最晚时间
- **文件统计**：已识别的日志文件类型及数量（内核日志、SMART 日志、fsck 日志等）
- **错误关键词概览**：各文件中 error/fail/critical/corrupt 等关键词出现次数

**支持过滤采集（缩小分析范围）：**

```bash
# 按日期过滤采集
python3 scripts/diagnose_fs_summary.py <log_dir> -o -d "Mar 16"

# 按时间范围过滤采集
python3 scripts/diagnose_fs_summary.py <log_dir> -o -s "2026-03-10 08:00:00" -e "2026-03-10 12:00:00"

# 按关键词过滤采集
python3 scripts/diagnose_fs_summary.py <log_dir> -o -k "I/O error" "corrupt"
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

# 示例：
python3 scripts/scene_classifier.py ./fs_diagnosis/
python3 scripts/scene_classifier.py ./fs_diagnosis/ -k "I/O error" "corrupt"
python3 scripts/scene_classifier.py ./fs_diagnosis/ -d "Mar 16"
python3 scripts/scene_classifier.py ./fs_diagnosis/ -s "2026-03-10 08:00:00" -e "2026-03-10 12:00:00"
```

**支持的日志文件类型：**

| 维度 | 日志文件 | 目的 |
|------|----------|------|
| 内核消息 | kernel_dmesg.log | 捕获 I/O 错误、文件系统错误、硬件异常 |
| 启动日志 | systemd_boot.log | 分析启动过程中的挂载失败、服务启动异常 |
| 文件系统检查 | fsck_check.log | 识别文件系统损坏、修复结果 |
| 系统消息 | system_messages.log | 捕获系统级错误、守护进程异常 |
| 磁盘布局 | disk_layout_lsblk.log | 了解磁盘分区结构、挂载点 |
| 磁盘标识 | disk_uuid_blkid.log | 确认设备 UUID、文件系统类型 |
| 挂载配置 | mount_config_fstab.log | 检查挂载配置正确性 |
| 磁盘健康 | disk_health_smart.log | 评估磁盘硬件健康状态 |

**场景分类规则（按优先级）：**

| 场景标签 | 触发条件 |
|---------|---------|
| `DISK_FAILURE` | SMART 状态 FAILED/FAILING，或内核检测到 MCE/硬件错误 |
| `FS_CORRUPTION` | fsck 检测到 error/corrupt，或内核报告 EXT4/XFS 文件系统错误 |
| `IO_ERROR` | 内核日志出现 I/O error / Buffer I/O error / timeout |
| `MOUNT_ERROR` | systemd 启动日志出现 mount.*failed / Failed to mount |
| `SPACE_ISSUE` | 系统日志出现 No space left / inode exhausted |
| `PERMISSION_ISSUE` | 系统日志出现 Permission denied / operation not permitted |

**Step 2 完成标志：** 输出场景标签，并将结果写入 `/tmp/fs_diagnosis_scene.conf`，进入 Step 3。

---

## Step 3：深入分析

根据 Step 2 的场景分类结果，执行对应专项分析脚本：

```bash
# 文件系统损坏分析（FS_CORRUPTION）
python3 scripts/diagnose_fs_corruption.py <log_dir> [选项]

# 磁盘硬件故障分析（DISK_FAILURE）
python3 scripts/diagnose_disk_failure.py <log_dir> [选项]

# 挂载错误分析（MOUNT_ERROR）
python3 scripts/diagnose_mount_error.py <log_dir> [选项]

# I/O 错误分析（IO_ERROR）
python3 scripts/diagnose_io_error.py <log_dir> [选项]

# 权限问题分析（PERMISSION_ISSUE）
python3 scripts/diagnose_permission.py <log_dir> [选项]

# 空间问题分析（SPACE_ISSUE）
python3 scripts/diagnose_space.py <log_dir> [选项]

# 通用选项：
#   -k, --keywords    关键词过滤（可多个）
#   -d, --date        日期过滤（如 "Mar 16"）
#   -s, --start-time  开始时间（如 "2026-03-10 08:00:00"）
#   -e, --end-time    结束时间（如 "2026-03-10 12:00:00"）
```

> ⚠️ **DISK_FAILURE 场景紧急处理**：检测到磁盘硬件故障时，**立即停止对该磁盘的写入操作**，优先备份数据后再执行分析。

**若场景为 UNKNOWN，使用集成诊断工具全量分析：**

```bash
python3 scripts/diagnose_fs_summary.py <log_dir> [选项]
```

每个专项脚本均输出：
- 问题定位信息（受影响设备、文件系统、挂载点）
- 关键证据（从日志中提取的关键行）
- 候选根因列表
- 修复建议

**Step 3 完成标志：** 所有分析输出完整的问题定位 + 关键证据 + 候选根因 + 修复建议后，进入 Step 4。

---

## Step 4：生成报告

汇总 Step 1～3 的所有分析结果，生成结构化诊断报告：

```bash
./scripts/generate_report.sh --output ./fs_diagnosis_report.md

# 可附带专项分析输出文件，自动嵌入报告证据链
./scripts/generate_report.sh \
    --output ./fs_diagnosis_report_$(date +%Y%m%d).md \
    --analysis /tmp/diagnose_fs_corruption_output.txt,/tmp/diagnose_disk_failure_output.txt
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

> **报告生成说明**：报告框架自动生成，需人工根据 Step 3 分析结果填写具体内容。所有修复建议需在原系统上验证后执行。

---

## 离线分析模式（基于日志文件）

**重要说明：本 Skill 仅基于提供的日志文件进行离线分析，不执行任何在线系统命令。**

### 诊断脚本概览

| 脚本 | 所属步骤 | 功能 | 关键特性 |
|------|---------|------|----------|
| `check_environment.sh` | Step 0 | 环境检查 | 验证日志文件存在性和可读性，强制阻断 |
| `diagnose_fs_summary.py -o` | Step 1 | 故障日志采集 | 概览模式，输出时间范围/文件统计/错误概览 |
| `scene_classifier.py` | Step 2 | 场景分类器 | 支持时间/关键词过滤，精确分类，保存场景标签 |
| `diagnose_fs_summary.py` | Step 3 | 集成诊断总览 | 支持时间/关键词过滤，概览模式，统一接口 |
| `diagnose_fs_corruption.py` | Step 3 | 文件系统损坏分析 | 支持时间/关键词过滤，详细错误分析，修复建议 |
| `diagnose_disk_failure.py` | Step 3 | 磁盘硬件故障分析 | SMART指标分析，硬件错误检测，紧急处理建议 |
| `diagnose_mount_error.py` | Step 3 | 挂载错误分析 | fstab配置检查，设备验证，挂载选项分析 |
| `diagnose_io_error.py` | Step 3 | I/O错误分析 | 错误类型分类，设备统计，时间线分析 |
| `diagnose_permission.py` | Step 3 | 权限问题分析 | SELinux/AppArmor分析，用户/文件/进程关联 |
| `diagnose_space.py` | Step 3 | 空间问题分析 | 空间使用模式，inode分析，配额检查 |
| `generate_report.sh` | Step 4 | 报告生成 | 汇总分析结果，生成结构化诊断报告 |

### 关键错误模式

| 场景 | 日志文件 | 关键错误模式 |
|------|---------|-------------|
| 文件系统损坏 | kernel_dmesg.log | error、corrupt、damage、superblock、inode |
| 磁盘故障 | disk_health_smart.log | FAIL、SMART、Reallocated、Pending |
| 挂载错误 | systemd_boot.log | mount.*failed、Failed to mount、Dependency failed |
| I/O 错误 | kernel_dmesg.log | I/O error、timeout、Buffer I/O error |
| 空间问题 | system_messages.log | No space、inode、full |

### 时间过滤功能

所有Python脚本支持以下时间过滤选项：
- `-s, --start-time`: 开始时间（格式：YYYY-MM-DD HH:MM:SS）
- `-e, --end-time`: 结束时间（格式：YYYY-MM-DD HH:MM:SS）
- `-d, --date`: 日期字符串（如 "Mar 16"）
- `-k, --keywords`: 关键词过滤（可多个）

**日志文件来源说明：**
- 所有日志文件应由用户预先从故障系统采集并放置到诊断目录
- 脚本仅读取和分析这些日志文件，不会执行任何系统命令
- 分析结果基于日志内容推断，建议在修复前验证

---

## 参考资料

| 文件 | 使用时机 | 说明 |
|------|---------|------|
| `references/log_patterns.md` | 识别各类日志中的错误特征模式 | 日志错误模式识别指南 |
| `references/fs_fault_patterns.md` | 文件系统故障模式识别 | 从日志中识别文件系统故障模式 |
| `references/disk_health_analysis.md` | 磁盘健康日志分析 | 从SMART日志中识别磁盘故障迹象 |
| `references/log_quality_check.md` | 日志文件质量检查 | 验证收集的日志是否完整有效 |
| `references/repair_strategies.md` | 基于诊断结果的修复策略 | 制定合理的修复计划 |

**重要说明：** 所有参考资料均为离线分析指南，不包含在线命令执行。本 Skill 仅基于提供的日志文件进行离线分析，不执行任何在线系统命令。

---

## 分析原则

1. **硬件优先**：检测到硬件故障迹象时，优先排查硬件，避免数据进一步损坏
2. **证据驱动**：每个结论必须有日志数据支撑，无数据则标注"待验证假设"
3. **深挖根因**：止步于直接原因是不够的，用 5 Whys 追到系统性问题
4. **安全第一**：在确认硬件健康前，避免执行写入类修复操作
5. **完整记录**：保留所有原始日志和分析过程，便于后续追溯
6. **风险评估**：对每个修复方案评估数据丢失风险，优先选择保守方案
7. **离线分析**：本 Skill 仅基于日志文件进行分析，不执行任何在线系统命令
