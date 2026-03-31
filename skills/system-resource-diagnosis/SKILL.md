---
name: system-resource-diagnosis
description: |
  专业的 Linux 系统资源故障在线诊断 skill。当用户提到进程数超 ulimit 限制、进程栈溢出、IPC 资源耗尽、inotify 句柄耗尽、内核模块加载失败、fork 失败、无法创建新进程、SIGSEGV core dump、消息队列/共享内存/信号量无法使用、文件监控失效、insmod/modprobe 失败等问题时，必须使用此 skill。
---

# 系统资源在线诊断 Skill

本技能通过收集系统资源使用状态数据，帮助诊断系统资源限制相关的故障问题。

> **重要原则**：本 skill 仅进行信息收集和分析诊断，**不执行任何修复命令**，只给出修复建议。所有修复操作需由用户确认后手动执行。

---

## 文件结构

```
system-resource-diagnosis/
├── SKILL.md                          # 诊断流程文档
└── scripts/
    └── collect_resource_info.sh      # 综合信息收集脚本
```

---

## 诊断流程

### 阶段一：信息收集与场景识别

#### 步骤 1：时间确认

根据用户描述计算故障时间窗口，**必须输出绝对时间**：

| 用户描述 | 时间窗口设定 |
|---------|-------------|
| 明确时间点 | `[故障时间 - 5分钟, 故障时间 + 持续时间 + 5分钟]` |
| "刚才/刚刚" | `[当前时间 - 30分钟, 当前时间]` |
| "间歇性/偶尔" | `[当前时间 - 2小时, 当前时间]` |
| 无法确定 | `[当前时间 - 1小时, 当前时间]` |

- **时间格式**：`YYYY-MM-DD HH:MM:SS`，例如 `2024-01-15 14:00:00`
- **持续性**：持续发生（如进程数持续超限）还是间歇性（如偶发 fork 失败）
- **影响范围**：特定用户、特定进程、特定服务

---

#### 步骤 2：执行信息收集脚本

📄 **脚本**：`scripts/collect_resource_info.sh`

**参数说明**：

| 参数 | 含义 | 是否必填 |
|------|------|---------|
| `-S <时间>` | 故障开始时间 (YYYY-MM-DD HH:MM:SS) | 可选 |
| `-E <时间>` | 故障结束时间 (YYYY-MM-DD HH:MM:SS) | 可选，默认为开始时间+1小时 |
| `-u <用户>` | 指定用户名 | 可选 |
| `-p <PID>` | 精确进程 ID | 可选 |

**调用示例**：

```bash
# 系统级全量分析
bash collect_resource_info.sh -S '2024-01-15 14:00:00' -E '2024-01-15 15:00:00'

# 指定用户分析
bash collect_resource_info.sh -S '2024-01-15 14:00:00' -u app

# 指定进程分析
bash collect_resource_info.sh -S '2024-01-15 14:00:00' -p 12345
```

**输出说明**：

| 输出类型 | 内容 | 说明 |
|---------|------|------|
| 终端直接输出 | ulimit 配置、进程数统计、IPC 资源、inotify 使用、关键异常提示 | 简单信息直接展示，附带诊断说明 |
| 文件输出 | 完整内核日志、详细资源列表、core dump 分析 | 大量数据保存到 `/tmp/resource_diag_*/` 目录 |

---

#### 步骤 3：场景识别

根据信息收集结果，综合分析各维度线索，识别可能的故障场景。

> **注意**：实际故障中多个场景可能同时存在，需要综合判断而非机械对照阈值。

**识别思路**：

1. **先看错误日志**
   - `Resource temporarily unavailable` → 关注进程数限制
   - `Segmentation fault` / `SIGSEGV` → 关注进程栈溢出
   - `No space left on device` (非磁盘场景) → 关注 IPC 资源
   - `inotify add watch failed` → 关注 inotify 句柄
   - `Could not insert module` → 关注内核模块加载

2. **再看资源使用情况**
   - 进程数接近 ulimit -u → 进程数超限
   - IPC 资源数接近内核参数上限 → IPC 资源耗尽
   - inotify 使用量接近上限 → inotify 句柄耗尽

3. **检查配置限制**
   - ulimit 配置是否合理
   - 内核参数是否需要调整
   - 服务级配置是否覆盖系统配置

**常见场景组合**：

| 现象组合 | 可能场景 | 分析方向 |
|---------|---------|---------|
| fork 失败 + 进程数接近 ulimit | 进程数超 ulimit 限制 | 检查进程泄漏、调整 ulimit |
| SIGSEGV + 栈限制较小 + 递归调用 | 进程栈溢出 | 增大栈限制、优化递归深度 |
| IPC 调用失败 + IPC 资源达上限 | IPC 资源耗尽 | 清理泄漏资源、调整内核参数 |
| inotify 失败 + udev/rsyslog 异常 | inotify 句柄耗尽 | 调整 inotify 上限、优化监控 |
| insmod 失败 + modules_disabled=1 | 模块加载被禁用 | 检查内核安全配置 |

**输出场景识别结果**：

```
识别场景：场景 X - XXXXX
判断依据：
  - 线索1: 观察到的现象
  - 线索2: 观察到的现象
  - 综合判断: 分析结论
```

---

### 阶段二：分场景深入分析

根据识别的场景，执行对应的深入分析。

---

#### 场景 1：进程数超 ulimit 限制

**分析步骤**：

1. **查看进程数统计**（终端输出 Section 2）
   - 当前用户进程数是否接近 `max user processes` 限制
   - 哪些用户进程数最多

2. **查看 ulimit 配置**（终端输出 Section 1）
   - 当前用户的 `ulimit -u` 限制值
   - 是否有服务级配置覆盖

3. **查看内核日志**（输出目录 `kernel_errors.log`）
   - 搜索 `Resource temporarily unavailable`
   - 搜索 `fork` 相关错误

**配置诊断**：

| 配置状态 | 诊断结论 | 修复建议 |
|---------|---------|---------|
| 进程数 = ulimit -u | 已达上限 | 检查进程泄漏、增大 ulimit |
| ulimit -u 过小 | 限制过严 | 调整 /etc/security/limits.conf |
| 服务级 LimitNPROC 覆盖 | 服务配置限制 | 调整服务配置文件 |

**深入取证**：
```bash
# 查看进程树关系
pstree -p -s <pid>

# 实时监控进程数
watch -n 1 "ps -eo user | sort | uniq -c | sort -rn | head -10"

# 检查僵尸进程
ps -eo pid,ppid,stat,cmd | awk '$3 ~ /Z/ {print}'
```

---

#### 场景 2：进程栈溢出

**分析步骤**：

1. **查看栈限制配置**（终端输出 Section 3）
   - `stack size` 限制值
   - 是否有进程触发 SIGSEGV

2. **查看 core dump 信息**（终端输出 Section 4）
   - Core dump 文件是否存在
   - 信号类型是否为 SIGSEGV

3. **查看内核日志**（输出目录 `kernel_errors.log`）
   - 搜索 `Segmentation fault`
   - 搜索 `stack` 相关错误

**栈溢出诊断**：

| 特征 | 诊断结论 | 修复建议 |
|-----|---------|---------|
| 栈限制较小 + 递归调用深 | 递归过深导致栈溢出 | 增大栈限制或优化递归 |
| 栈限制较小 + 大数组 | 局部变量过大 | 改用堆分配 |
| Core dump 显示栈地址越界 | 栈越界 | 分析具体代码位置 |

**深入取证**：
```bash
# 分析 core dump 文件
gdb <binary> <core> -ex "bt" -ex "info registers" -ex "quit"

# 查看进程栈使用
cat /proc/<pid>/status | grep -E "VmStk|VmSize"

# 查看栈限制
ulimit -s
```

---

#### 场景 3：IPC 资源耗尽

**分析步骤**：

1. **查看 IPC 资源使用**（终端输出 Section 5）
   - 消息队列数量 vs `msgmni` 限制
   - 共享内存段数量 vs `shmmni` 限制
   - 信号量数组数量 vs `semmni` 限制

2. **查看 IPC 资源详情**（输出目录 `ipc_details.txt`）
   - 哪些进程占用了 IPC 资源
   - 资源创建时间和权限

3. **查看内核日志**（输出目录 `kernel_errors.log`）
   - 搜索 `No space left on device` (IPC 场景)
   - 搜索 IPC 相关错误

**IPC 资源诊断**：

| 资源类型 | 诊断结论 | 修复建议 |
|---------|---------|---------|
| 消息队列达上限 | msgmni 限制 | 清理泄漏资源、增大 msgmni |
| 共享内存达上限 | shmmni 限制 | 清理泄漏资源、增大 shmmni |
| 信号量达上限 | semmni 限制 | 清理泄漏资源、增大 semmni |

**深入取证**：
```bash
# 查看消息队列
ipcs -q

# 查看共享内存
ipcs -m

# 查看信号量
ipcs -s

# 查看内核参数
sysctl -a | grep -E "msgmni|shmmni|semmni"
```

---

#### 场景 4：inotify 句柄耗尽

**分析步骤**：

1. **查看 inotify 使用情况**（终端输出 Section 6）
   - `max_user_instances` 和 `max_user_watches` 限制
   - 当前使用量是否接近限制

2. **查看 inotify 详情**（输出目录 `inotify_details.txt`）
   - 哪些进程占用了大量 inotify 实例
   - 监控的文件数量

3. **检查受影响服务**
   - udev 服务状态
   - rsyslog 服务状态

**inotify 诊断**：

| 特征 | 诊断结论 | 修复建议 |
|-----|---------|---------|
| inotify 实例达上限 | max_user_instances 不足 | 增大内核参数 |
| watch 数量达上限 | max_user_watches 不足 | 增大内核参数 |
| 特定进程占用过多 | 应用监控过多文件 | 优化监控策略 |

**深入取证**：
```bash
# 查看 inotify 使用
find /proc/*/fd -lname anon_inode:inotify 2>/dev/null | wc -l

# 查看每个进程的 inotify 使用
for pid in $(ps -eo pid); do
  count=$(sudo find /proc/$pid/fd -lname anon_inode:inotify 2>/dev/null | wc -l)
  if [ $count -gt 0 ]; then
    echo "PID $pid: $count inotify instances"
  fi
done

# 查看内核参数
sysctl fs.inotify
```

---

#### 场景 5：内核模块加载失败

**分析步骤**：

1. **查看模块加载状态**（终端输出 Section 7）
   - 当前已加载模块数量
   - `modules_disabled` 是否为 1

2. **查看内核日志**（输出目录 `kernel_errors.log`）
   - 搜索 `Could not insert module`
   - 搜索 `Module already exists`
   - 搜索 `modules_disabled`

**模块加载诊断**：

| 特征 | 诊断结论 | 修复建议 |
|-----|---------|---------|
| modules_disabled = 1 | 模块加载被禁用 | 检查安全策略、重启后修改 |
| 模块已存在 | 重复加载 | 先卸载旧模块 |
| 依赖缺失 | 缺少依赖模块 | 先加载依赖模块 |
| 签名验证失败 | 模块签名问题 | 检查内核签名配置 |

**深入取证**：
```bash
# 查看模块依赖
modprobe --show-depends <module>

# 查看模块信息
modinfo <module>

# 查看已加载模块
lsmod | grep <module>

# 检查 modules_disabled
cat /proc/sys/kernel/modules_disabled
```

---

### 阶段三：输出诊断报告

```markdown
# 系统资源故障诊断报告

## 基本信息
- 诊断时间：
- 故障时间窗口：
- 严重级别：（P2/P3）

## 问题确认
**报错信息**：

**影响范围**：

**复现方式**：

## 场景识别结果
**识别场景**：场景 X - XXXXX

**判断依据**：
- 指标1: 值 (阈值)
- 指标2: 值 (阈值)

## 深入分析
**分析过程**：

**关键证据**：

## 故障结论
**根因描述**：

**置信度**：

## 修复建议
### 临时措施
1.
2.

### 永久措施
1.
2.
```

---
