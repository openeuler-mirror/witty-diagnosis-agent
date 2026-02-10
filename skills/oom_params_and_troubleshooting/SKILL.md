---
name: oom-params-and-troubleshooting
description: 当系统日志中出现“Out of memory: Killed process”、“invoked oom-killer”或“Memory cgroup out of memory”等内存溢出（OOM）相关错误时，使用此技能。本技能用于诊断和解决 Linux 系统中的 OOM 问题，包括 OOM Killer 相关内核参数的查看与配置、分析 OOM 发生的多种原因（如 cgroup 内存限制、系统全局内存不足、NUMA 节点内存不足等），并通过系统日志和进程信息进行问题排查与解决。
metadata:
  keywords: ["OOM Killer", "cgroup", "NUMA", "内存溢出", "Linux", "Huawei Cloud EulerOS", "Out of memory"]
---

# Case13 OOM 参数配置与故障排查
> 诊断 Linux 内存溢出问题，配置 OOM Killer 参数，分析并解决内存不足故障。

## 概述 (Overview)

本技能用于处理 Linux 系统因内存耗尽而触发的 Out-Of-Memory (OOM) 事件。核心内容包括：理解 OOM Killer 机制，配置和管理相关内核参数（`panic_on_oom`, `oom_kill_allocating_task`, `oom_dump_tasks`, `oom_score_adj`），分析 `/var/log/messages` 中的 OOM 日志以定位根本原因（如 cgroup 限制、全局内存不足、NUMA 节点问题等），并提供相应的解决方案（如调整 cgroup 限制、排查内存泄漏、升级服务器规格）。

## 何时使用此技能 (When to Use)
- 当用户报告进程被意外终止，系统日志中出现 `"Out of memory: Killed process"` 或 `"invoked oom-killer"` 等 OOM 相关错误信息时。
- 当用户需要了解或调整系统在内存不足时的行为策略（如触发 panic 还是杀死进程）时。
- 当用户需要排查内存不足的根本原因，例如怀疑是 cgroup 配置不当、特定进程内存泄漏或 NUMA 架构导致的内存局部不足时。
- 当用户需要调整特定进程的 OOM 优先级（`oom_score_adj`），以保护关键进程或优先终止非关键进程时。

## 核心概念 (Core Concepts)

### OOM Killer 机制
Linux 内核的 OOM Killer 在系统内存严重不足时，会选择并终止一个或多个进程以释放内存，防止系统完全崩溃。选择目标进程的依据是 `oom_score`，该分数由系统根据进程内存使用量自动计算，并可通过 `oom_score_adj` 进行人工调整。

### 关键内核参数
| 参数 | 作用 | 常用值 |
| :--- | :--- | :--- |
| `panic_on_oom` | 控制 OOM 时触发 kernel panic 还是 OOM Killer。 | `0` (触发 OOM Killer，默认) |
| `oom_kill_allocating_task` | 控制 OOM Killer 选择触发 OOM 的进程还是 `oom_score` 最高的进程。 | `0` (选择得分最高的进程，默认) |
| `oom_dump_tasks` | 控制 OOM 发生时是否在日志中 dump 所有进程的内存信息，用于事后分析。 | `1` (打印详细信息，默认) |
| `oom_score_adj` | 调整指定进程的 OOM 优先级（范围：-1000 到 1000）。 | `-1000` (禁止杀死该进程) |

## 核心指令 (Core Instructions)

### 步骤 1：检查当前 OOM 相关参数配置
首先查看系统当前的 OOM 行为配置，了解基线情况。

```bash
# 查看关键 OOM 参数
cat /proc/sys/vm/panic_on_oom
cat /proc/sys/vm/oom_kill_allocating_task
cat /proc/sys/vm/oom_dump_tasks

# 或使用 sysctl 查看
sysctl -a | grep -E "panic_on_oom|oom_kill_allocating_task|oom_dump_tasks"
```

### 步骤 2：收集 OOM 诊断信息
当 OOM 事件发生后，从系统日志和进程信息中收集证据。

> **状态追踪清单**：
> - [ ] 检查系统日志中的 OOM 记录
> - [ ] 检查相关进程的 OOM 评分调整值
> - [ ] 检查 cgroup 内存限制（如果适用）
> - [ ] 汇总诊断信息

1.  **检查系统日志**：在 `/var/log/messages` 或 `journalctl` 中搜索 OOM 关键字，获取事件时间、被杀死进程、内存使用量、触发原因（如 cgroup 限制）等关键信息。
    ```bash
    grep -i "oom\|out of memory" /var/log/messages
    # 或使用 journalctl
    journalctl --since="1 hour ago" | grep -i "oom\|out of memory"
    ```
2.  **检查特定进程的 OOM 优先级**：如果怀疑某个进程被误杀或应被优先杀死，查看其 `oom_score_adj`。
    ```bash
    # 假设进程 PID 为 2939
    cat /proc/2939/oom_score_adj
    ```
3.  **检查 cgroup 内存限制**：如果日志提示 `"Memory cgroup out of memory"`，检查相关 cgroup 的内存限制。
    ```bash
    # 需要根据日志确定具体的 cgroup 路径，例如 /sys/fs/cgroup/memory/<cgroup_name>/
    cat /sys/fs/cgroup/memory/<cgroup_name>/memory.limit_in_bytes
    cat /sys/fs/cgroup/memory/<cgroup_name>/memory.usage_in_bytes
    ```

### 步骤 3：分析 OOM 根本原因
根据收集到的日志信息，判断 OOM 属于以下哪种类型，并采取相应分析思路。

> **根据日志特征进行分支判断**：

*   **场景 A: cgroup 内存不足**
    - **日志特征**：包含 `"Memory cgroup out of memory"`，并显示 `usage` 和 `limit`。
    - **分析动作**：
        - 确认业务进程内存使用是否超出 `memory.limit_in_bytes` 的设置。
        - 检查是否有子 cgroup 内存充足但父 cgroup 超限的情况。

*   **场景 B: 系统全局内存不足**
    - **日志特征**：包含 `"global_oom"`，并显示节点（Node）空闲内存低于最低水位线（low）。
    - **分析动作**：
        - 使用 `free -h`、`top` 等命令检查系统整体内存使用情况。
        - 排查是否有进程存在内存泄漏。

*   **场景 C: NUMA 节点内存不足**
    - **日志特征**：包含 `"constraint=CONSTRAINT_MEMORY_POLICY"` 和 `"nodemask"`，显示特定 Node 内存不足。
    - **分析动作**：
        - 使用 `numastat` 检查各 NUMA 节点的内存分配。
        - 确认进程是否绑定了特定的 NUMA 节点。

*   **⚠️ 其他/未知场景**
    - 若日志信息不明确或不符合上述模式：
        - 检查内核日志中是否有伙伴系统（buddy system）相关的错误。
        - 建议使用提供的诊断脚本进行更全面的信息收集。

### 步骤 4：实施解决方案
**⚠️ 重要安全警告**：本步骤中的部分操作（特别是修改内核参数和 cgroup 限制）会直接影响系统行为，可能导致服务中断或系统不稳定。**在执行任何修改操作前，务必：**
1.  **评估环境**：确认是否为生产环境。对于极高风险操作（如设置 `panic_on_oom=2`），**严禁在生产环境执行**。
2.  **备份原值**：在修改前，记录原始配置值，以便需要时回滚。
3.  **人工确认**：建议在执行前获取用户或管理员的明确确认。
4.  **验证结果**：操作后，必须验证修改是否生效且未引发新的问题。

根据原因分析结果，执行相应的解决措施。

1.  **调整 cgroup 内存限制**：如果 cgroup 限制过小，且业务需要更多内存。
    > **注意**：以下为操作模板。具体脚本示例位于 `examples/adjust_cgroup_memory.sh`。
    ```bash
    # 1. 备份原有限制值
    original_limit=$(cat /sys/fs/cgroup/memory/<cgroup_name>/memory.limit_in_bytes)
    echo "原始限制值: $original_limit"

    # 2. 执行调整（例如调整为 200M）
    echo 209715200 > /sys/fs/cgroup/memory/<cgroup_name>/memory.limit_in_bytes

    # 3. 验证操作是否成功
    new_limit=$(cat /sys/fs/cgroup/memory/<cgroup_name>/memory.limit_in_bytes)
    if [[ "$new_limit" == "209715200" ]]; then
        echo "✅ cgroup 内存限制已成功调整为 200M。"
    else
        echo "❌ 调整失败，当前限制为: $new_limit。请检查权限或路径。"
        # 4. 执行回滚（如果验证失败）
        echo "正在回滚到原始限制值..."
        echo $original_limit > /sys/fs/cgroup/memory/<cgroup_name>/memory.limit_in_bytes
        if [[ $(cat /sys/fs/cgroup/memory/<cgroup_name>/memory.limit_in_bytes) == "$original_limit" ]]; then
            echo "✅ 已成功回滚到原始限制值。"
        else
            echo "⚠️ 回滚失败，请手动检查 cgroup 状态。"
        fi
    fi
    ```

2.  **调整进程 OOM 优先级**：保护关键进程或标记非关键进程。
    > **注意**：以下为操作模板。具体脚本示例位于 `examples/adjust_oom_priority.sh`。
    ```bash
    # 保护 PID 为 1234 的关键进程，禁止 OOM Killer 杀死它
    original_score_1234=$(cat /proc/1234/oom_score_adj)
    echo -1000 > /proc/1234/oom_score_adj
    # 验证
    if [[ $(cat /proc/1234/oom_score_adj) == "-1000" ]]; then
        echo "✅ 进程 1234 的 oom_score_adj 已成功设置为 -1000。"
    else
        echo "❌ 设置失败。正在回滚..."
        echo $original_score_1234 > /proc/1234/oom_score_adj
    fi

    # 标记 PID 为 5678 的非关键进程，使其更容易被杀死
    original_score_5678=$(cat /proc/5678/oom_score_adj)
    echo 500 > /proc/5678/oom_score_adj
    # 验证
    if [[ $(cat /proc/5678/oom_score_adj) == "500" ]]; then
        echo "✅ 进程 5678 的 oom_score_adj 已成功设置为 500。"
    else
        echo "❌ 设置失败。正在回滚..."
        echo $original_score_5678 > /proc/5678/oom_score_adj
    fi
    ```

3.  **修改系统 OOM 行为参数**（**极高风险操作，需极其谨慎**）。
    > **安全操作建议**：对于此类高风险内核参数调整，**仅提供查看方法**。具体修改指令应在获得明确授权和确认后，由管理员手动执行。以下为查看和备份示例。
    ```bash
    # 查看当前值并备份（记录到变量或文件）
    current_panic_on_oom=$(cat /proc/sys/vm/panic_on_oom)
    echo "当前 panic_on_oom 值: $current_panic_on_oom"
    # 记录备份，例如：echo "vm.panic_on_oom=$current_panic_on_oom" >> /tmp/oom_params_backup.txt

    # 修改操作（需人工确认后由管理员执行）：
    # 临时修改: sysctl -w vm.panic_on_oom=2
    # 持久化修改（修改前请备份 /etc/sysctl.conf）: echo "vm.panic_on_oom=0" >> /etc/sysctl.conf && sysctl -p
    ```
    **⚠️ 警告**：修改 `panic_on_oom` 为 2 将导致 OOM 时系统触发 kernel panic 并可能重启。此操作仅用于测试环境，严禁在生产环境执行。

4.  **业务与硬件层面**：
    - 排查并修复应用程序的内存泄漏（需结合业务日志和内存 profiling 工具）。
    - 如果业务内存需求持续增长，建议升级云服务器的内存规格。**此操作通常需要人工审批和停机维护。**

## 可执行脚本与示例 (Scripts and Examples)

本技能目录下提供了自动化诊断脚本和操作示例。

### 诊断脚本
**脚本路径**: `scripts/collect_oom_diagnostics.sh`
**功能描述**: 采集 OOM 相关的系统诊断信息，包括检查内核参数、列出进程信息、查看 `oom_score_adj`、搜索系统日志中的 OOM 记录。
**使用方法**:
```bash
./scripts/collect_oom_diagnostics.sh --help
./scripts/collect_oom_diagnostics.sh <进程名> [PID]
```

### 操作示例
为保持核心指令的精炼，具体的、可复用的操作脚本示例已外置：
- **`examples/adjust_cgroup_memory.sh`**: 调整 cgroup 内存限制的完整脚本，包含备份、验证和回滚。
- **`examples/adjust_oom_priority.sh`**: 调整进程 `oom_score_adj` 的完整脚本，包含备份、验证和回滚。

**注意**: 所有脚本执行都需要相应权限。诊断脚本仅用于信息收集，示例脚本中的修改操作均包含安全验证和回滚机制。

## 参考文件说明
本技能基于详细的参考文档。完整理论、日志示例和深入分析请查阅：
- `references/13_oom_相关参数配置与原因排查.md`
- `references/index.md`
- `scripts/README.md`