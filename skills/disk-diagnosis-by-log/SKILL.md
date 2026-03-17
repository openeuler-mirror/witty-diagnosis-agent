---
name: disk-diagnosis-by-log
description: 分析服务器多源日志（iBMC, OS Messages, InfoCollect）以诊断磁盘故障与 I/O 性能问题。当用户请求“分析磁盘日志”、“排查存储故障”、“检查硬盘健康”或提供相关日志文件（如 disk_smart.txt, sasraidlog, dmesg, sel）时使用。
---

# 磁盘日志诊断

本技能通过分析从服务器收集的标准日志文件，帮助诊断磁盘和存储问题。

> **重要提示**：分析时应遵循 **“先宏观后微观”** 的原则：
> 1.  **全局扫描**：优先使用 **一键诊断脚本** (`scripts/diagnose_summary.py`) 快速识别异常模块和关键报错。
**注意：使用脚本时必须优先执行 `--help` 参数，了解脚本用法**

> 2.  **精准定位**：根据脚本输出的线索（如特定时间点或文件名），再使用 `grep` / `less` 等文件操作命令查看具体的原始日志上下文。

## 典型日志目录结构与对应诊断脚本

以 `/path/to/logs/xxxx` 为例，标准的服务器日志收集包通常具有以下层级结构。本技能提供了针对性的脚本来分析不同层级的日志。

> **注意**：在实际场景中，用户提供的日志包可能不完整，可能仅包含以下三种目录中的一种或多种。请根据实际存在的日志类型灵活选择对应的分析脚本。

```text
<日志根目录> (例如: 10.120.6.76)
├── ibmc_logs/                  # iBMC 硬件带外管理日志
│   └── (支持 Huawei, H3C, Inspur) -> 使用 scripts/diagnose_ibmc.py
├── infocollect_logs/           # 系统信息收集工具生成的分类日志
│   └── (磁盘/RAID/SMART信息)      -> 使用 scripts/diagnose_infocollect.py
└── messages/                   # 操作系统层面的系统日志
    └── (dmesg, syslog, messages) -> 使用 scripts/diagnose_messages.py
```

更深层次的文件架构及详细说明，请参考 `references/` 目录下对应的指南文档（如 [iBMC](references/huawei_ibmc.md), [InfoCollect](references/infocollect_guide.md), [Messages](references/messages.md)）。

## 诊断排查流程

本技能推荐遵循以下 **“快速定性 → 时序关联 → 分层深究 → 交叉验证”** 的四步排查流程，结合多源日志进行综合分析。

### 1. 快速定性 (Phase 1: Rapid Triage)
**目标**：通过自动化脚本快速扫描日志包，识别致命故障和关键时间点，初步判断故障性质。

*   **全局概览 (使用 `diagnose_summary.py`)**：
    *   **操作**：运行 `python3 scripts/diagnose_summary.py <日志根目录>`。
    *   **分析**：
        *   **时间范围对齐**：查看输出的 `[1. Metadata & Time Analysis]` 部分，确认各组件日志（iBMC, OS）的时间跨度是否覆盖故障发生时间。如果时间不一致，后续分析需注意时区差异。
        *   **关键错误扫描**：查看 `[2. Detailed Diagnosis Summary]` 部分。脚本会自动调用子模块扫描常见致命错误。
            *   若 **iBMC Diagnosis** 报出 `Critical` / `Drive Fault` → **硬件故障**可能性大。
            *   若 **OS Messages Diagnosis** 报出 `I/O error` / `SCSI error` 但 iBMC 无报错 → 可能是 **链路问题** 或 **软件/驱动问题**。
            *   若 **OS Messages** 报出 `Kernel panic` / `Soft lockup` → **系统/内核问题**。

*   **组件级快速检查 (可选)**：
    *   如果需要更详细的统计信息，可单独运行组件脚本的概览模式：
        *   **硬件侧**：`python3 scripts/diagnose_ibmc.py <ibmc目录> --overview` → 查看 SEL 报错统计。
        *   **系统侧**：`python3 scripts/diagnose_messages.py <messages目录> --overview` → 查看系统日志中的 Panic/Oops 统计。

### 2. 时序关联 (Phase 2: Timeline Reconstruction)

**目标**：通过多源日志的时间戳对齐，重建故障发生的完整时间轴，厘清事件的先后顺序与因果链，为根因定位提供时序证据。

#### 2.1 确定故障零点 (T0)

故障零点（T0）是时序分析的基准锚点，定义为**最早可观测到异常的时间戳**，而非告警触发时间或人工发现时间（两者通常存在滞后）。

**T0 确定优先级**（由高到低）：

| 优先级 | 来源 | 说明 |
|--------|------|------|
| P1 | 硬件错误日志（BMC/IPMI/SEL） | 最底层事件，时间最早 |
| P2 | 内核日志（`dmesg` / `kern.log`） | 驱动层感知，优先于应用层 |
| P3 | 系统服务日志（`syslog` / `journalctl`） | OS 层面的异常记录 |
| P4 | 应用/业务日志 | 通常有感知延迟，作为辅助验证 |
| P5 | 监控告警触发时间 | 滞后最大，仅作参考边界 |

> ⚠️ **时钟偏差处理**：多节点场景下，需先校验各节点 NTP 同步状态（`chronyc tracking` / `timedatectl`），若存在时钟漂移，记录偏差量并在对齐时修正，避免因时钟不一致产生错误的因果判断。

#### 2.2 多维日志对齐

以 T0 为基准，将各维度日志事件投影到统一时间轴，构建**事件序列矩阵**：

```text
时间轴示例：

T0-120s  ├─ [硬件] DIMM CE Error count 开始上升（可纠正错误，低频）
T0-30s   ├─ [硬件] DIMM CE Error 频率突增，触发 EDAC 阈值
T0       ├─ [内核] EDAC: too many correctable errors → 标记 T0
T0+5s    ├─ [内核] kernel: page alloc failure / memory hwpoison
T0+8s    ├─ [系统] OOM Killer 触发，进程被杀
T0+12s   └─ [应用] 业务报错：connection reset / timeout
```

**对齐维度清单**：
- **硬件层**：BMC SEL、EDAC、PCIe AER、存储控制器日志
- **内核层**：`dmesg`（含时间戳 `dmesg -T`）、`kern.log`
- **驱动层**：块设备驱动报错、网卡驱动报错
- **OS 层**：`syslog`、`messages`、`journalctl`
- **应用层**：业务日志、中间件日志、数据库慢查询日志

#### 2.3 因果推断规则

基于时序矩阵，按以下规则进行因果方向判断：

**规则一：硬件先行 → 倾向硬件故障**
```text
条件：硬件日志异常事件早于内核/系统层报错
结论：物理故障（磁盘坏块、内存 ECC、网卡 CRC）导致上层 I/O 报错
验证：硬件健康检查（SMART、memtest、链路诊断）
```

**规则二：软件先行，硬件无记录 → 倾向软件/性能问题**
```text
条件：硬件日志无异常，系统日志出现超时、OOM、死锁等报错
结论：软件缺陷、配置错误、资源耗尽或性能瓶颈
验证：资源利用率曲线（CPU/MEM/IO）、进程状态、内核参数
```

**规则三：硬件与系统同时异常 → 需鉴别主从关系**
```text
条件：硬件与系统层报错时间戳接近（差值 < 阈值，如 ±5s）
处理：
  1. 检查是否为同一物理事件的不同层面反映（如同一磁盘错误在驱动层和系统层的双重记录）
  2. 若为独立事件，引入第三方证据（性能数据、网络流量）辅助判断
  3. 考虑"软硬件交互故障"场景：软件压力触发硬件潜在缺陷暴露
```

**规则四：存在异常前驱信号 → 识别故障孕育期**
```text
条件：T0 之前数小时/数天存在低频异常信号（间歇性报错、性能抖动）
意义：区分"突发故障"与"渐进性劣化"，影响修复策略
验证：拉取更长时间窗口（24h/7d）的历史日志进行趋势分析
```

#### 2.4 时序分析产出

完成时序分析后，需输出以下结论：

- **故障零点 T0**：精确时间戳及确定依据
- **事件序列描述**：按时间顺序的关键事件列表（含各事件来源）
- **因果链判断**：初步根因方向（硬件 / 软件 / 配置 / 外部依赖）
- **存疑点记录**：时序中存在矛盾或证据不足的位置，指导 Phase 3 深入分析
- **细粒度根因定位**：硬件故障根因必须定位到具体的物理位置，例如，某磁盘故障的逻辑设备为sdm故障，其对应的物理设备id为8号磁盘故障

### 3. 分层深究 (Phase 3: Deep Dive by Subsystem)

根据前两步锁定的线索，逐层深入相关子系统进行根因挖掘。本阶段的核心不是"看完所有日志"，而是**以假设驱动分析**——先提出可证伪的假设，再用证据验证或推翻它。

#### 分析范式

每个子系统的分析均遵循以下三步：

1. **聚焦**：依据上层线索，明确本层需要回答的核心问题
2. **取证**：从对应日志/指标中提取与假设直接相关的证据
3. **🔁 反思**：新证据是否支持初始假设？若出现矛盾，立即修正方向，而非选择性忽略

#### 跨层反思原则

每完成一个子系统的分析后，须主动回溯已有结论：

*   **时序一致性**：各层异常的发生时间是否吻合？若某层报错早于预期，根因锚点可能需要上移。
*   **因果方向性**：当前判断的"原因"与"结果"，是否存在被倒置的可能？
*   **覆盖完整性**：是否有与结论矛盾的证据被忽略？矛盾证据比支持证据更值得关注。

#### 迭代终止条件

当且仅当满足以下条件时，方可退出本阶段：

> 用全部已收集的证据，**无法推翻**当前根因假设，且各层证据在时序与逻辑上完全自洽。

否则，修正假设后重新进入分析循环。

---

### 4. 交叉验证 (Phase 4: Cross-Validation)

**目标**：通过不同来源的日志相互佐证，确保结论的准确性。

*   **证据链闭环**：推断的故障原因必须能在所有相关层级的日志中找到对应痕迹（例如：硬件报坏道 → 系统报读写错误 → 业务报超时）。
*   **排除干扰项**：确认所谓的"故障"是否为历史遗留告警，或已知的不影响业务的误报。

## 诊断日志类型

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

## 用法

本技能包含三个核心诊断脚本，分别针对不同层级的日志进行分析。所有脚本均支持统一的参数格式（如 `-d`, `-s`, `-e`, `-k`, `-o`, `-h`）。
**注意：使用脚本时必须优先执行 `--help` 参数，了解脚本用法**

### 1. iBMC 日志分析 (`scripts/diagnose_ibmc.py`)
**适用场景**：分析硬件底层故障（如 SEL 事件、传感器告警）。
**支持厂商**：
- **Huawei** (参考: `references/huawei_ibmc.md`)
- **H3C** (参考: `references/h3c_ibmc.md`)
- **Inspur** (参考: `references/Inspur_ibmc.md`)

```bash
python3 scripts/diagnose_ibmc.py <ibmc_logs目录>
```

### 2. 磁盘信息收集分析 (`scripts/diagnose_infocollect.py`)
**适用场景**：分析 `infocollect_logs` 中的磁盘健康度（SMART）、RAID 状态及 I/O 性能。
**参考指南**：`references/infocollect_guide.md`
*(原 diagnose_disk.py)*

```bash
python3 scripts/diagnose_infocollect.py <infocollect_logs目录>
```

### 3. 操作系统日志分析 (`scripts/diagnose_messages.py`)
**适用场景**：分析操作系统层面的存储报错（I/O Error, SCSI Error）及内核 Panic。
**参考指南**：`references/messages.md`

```bash
python3 scripts/diagnose_messages.py <messages目录>
```

### 常用参数说明

| 参数 | 说明 | 示例 |
| :--- | :--- | :--- |
| `-o`, `--overview` | **快速概览**。查看日志时间跨度、硬件概况及错误文件分布。 | `python3 scripts/diagnose_ibmc.py <dir> -o` |
| `-d`, `--date` | **特定日期排查**。只显示包含特定日期字符串的日志行。 | `python3 scripts/diagnose_messages.py <dir> -d "Mar 5"` |
| `-s`, `--start-time` | **开始时间**。格式 "YYYY-MM-DD HH:MM:SS"。 | `... -s "2023-03-05 10:00:00"` |
| `-e`, `--end-time` | **结束时间**。格式 "YYYY-MM-DD HH:MM:SS"。 | `... -e "2023-03-05 12:00:00"` |
| `-k`, `--keywords` | **关键词搜索**。增加自定义故障关键词搜索。 | `... -k "sense key" error` |

### 场景示例

1.  **快速检查 iBMC 是否有硬件告警**：
    ```bash
    python3 scripts/diagnose_ibmc.py /opt/data/logs/ibmc_logs --overview
    ```

2.  **分析特定时间段的系统 I/O 错误**：
    ```bash
    python3 scripts/diagnose_messages.py /opt/data/logs/messages -s "2023-03-05 10:00:00" -e "2023-03-05 11:00:00"
    ```

3.  **检查磁盘 SMART 信息与 RAID 状态**：
    ```bash
    python3 scripts/diagnose_infocollect.py /opt/data/logs/infocollect_logs
    ```

## 参考资料

*   [InfoCollect 诊断指南](references/infocollect_guide.md)
*   [Huawei iBMC 分析](references/huawei_ibmc.md)
*   [H3C iBMC 分析](references/h3c_ibmc.md)
*   [Inspur iBMC 分析](references/Inspur_ibmc.md)
*   [OS Messages 分析](references/messages.md)
