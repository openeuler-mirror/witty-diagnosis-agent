# 希捷 FARM 日志底层诊断指南

在离线磁盘故障诊断的基础流程中，当我们通过日志（iBMC, InfoCollect, OS messages 等）定位到疑似故障的磁盘时，如果该磁盘提供了更深层次的 **FARM (Field-Accessible Reliability Metrics) 级遥测日志**，我们就可以执行进一步的底层诊断，将故障收敛到具体的磁头、盘面或读写通道等核心部件。

> [!IMPORTANT]
> **FARM 是单帧快照，不是时间序列。**
> FARM 日志只有一份 `copy 0`，**没有 `poh` 趋势可读**。因此本指南**严禁**使用"旧→新方向 / 持续增长 / 活跃增长 vs 暂稳"这类**趋势话术**。活跃度改用 **`Reallocated Candidate Sectors`（候选坏道数）** 近似：候选 > 0 = 退化进行中，候选 = 0 = 暂稳。
> 字段字典、json↔txt↔SMART 三方映射、临界值与判定矩阵详见 [farm_field_reference.md](farm_field_reference.md)。

## 适用场景判断 (触发条件)

本指南对应 SKILL.md **Step 5（FARM+OS 联合底层定界）**，触发条件只有一条：

**数据条件**：当前分析数据集中存在 `farmlog/` 目录（或散落的 `*_FARM_*.{json,txt}` 文件）——**存在即必须执行 Step 5**。FARM 日志文件每盘可有两种来源：
- `<SN>_FARM_<时间戳>_<IP>_<设备名>.json`（openSeaChest_LogParser 导出，**字段最全，优先**）
- `<SN>_FARM_disktool_<时间戳>_<IP>_<设备名>.txt`（华为 disktool 导出，**关键字段约 40%，兜底**）
- 另兼容时间戳前置格式：`<时间戳>_<SN>_FARM_<IP>_<设备名>[_disktool].{json,txt}`

> [!IMPORTANT]
> - 若 Step 0–4 已锁定某块问题磁盘，本步骤聚焦该 SN 深挖；若尚未锁定，则对 farmlog 内**所有盘**做机群级定界，再与 OS 侧证据（时序/盘符/槽位）对齐锁定涉事盘。
> - 本步骤输出两层结论：**部位层（8 类故障部位，本指南）** + **根因层（冷存储 R1-R16 R 码定界，见 [root_cause_rules.md](root_cause_rules.md)）**。脚本 `analyze_farm.py` 已内置两层引擎；R 码的 FARM 侧候选须按脚本给出的"OS 侧交叉验证清单"与 Step 0-4 证据闭环后才是最终 R 码。

---

## 数据源纪律 (json 优先 / txt 兜底)

> [!WARNING]
> **必须先确认数据源是 json 还是 txt！**
> json 是 txt 的**超集**——大量字段仅 json 有。脚本默认 json 优先、txt 兜底，并在报告"数据源"列标注覆盖度。
> - **json 能做、txt 不能做**的判定：逐头重分配定位、逐头不可恢复读、Flash LED（固件 Assert）事件、Depop 状态、型号识别、CTO 5s/7.5s 分档。
> - **txt 来源**时，故障常只能判到**"整盘介质退化（未定位到磁头）"**，且第 2/7 类降级。若结论关键，应索取该盘 json 重新分析。

---

## 8 类故障部位 (分析框架)

对照标准 SMART，FARM 对各故障类别的覆盖度（详见 [farm_field_reference.md](farm_field_reference.md) 第 3 章映射表）：

| # | 故障部位 | FARM 覆盖度 | 关键分析字段 |
|---|---|---|---|
| 1 | 盘片表面 / 坏扇区 | ✅ 优于标准（逐磁头） | `Reallocated Sectors` / `Reallocated Candidate` / `Unrecoverable Read Errors` / 逐头 `Reallocated Sectors by Head` / `Cum Lifetime Unrecoverable by head` |
| 2 | 磁头 / 读写通道 / ECC | ✅ 远优于标准 | 逐头 `Fly height clearance delta`（飞高 FAFH） / `MR Head Resistance`（MRR） / `H2SAT amplitude·iterations·asymmetry` / `Bit Error Rate by Head` |
| 3 | 机械 / 马达 / 伺服 | ⚠️ 部分覆盖 | `Mechanical Start Failures` / `Spin Retry` / `Helium Pressure Tripped` / `Motor Power` / 逐头 `TMD` / `Velocity Observer` |
| 4 | 接口 / 传输 | ✅ 优于 SAS | `Interface CRC Errors`（ATA 有） / `CTO Count Total·5s·7.5s` / `Hardware Reset` |
| 5 | 温度 / 环境 / 振动 | ✅ 优于标准 | `Highest Temperature` / `Time In Over Temperature` / `Over-Limit Shock` / `Humidity` / `High Fly Write` |
| 6 | 寿命 / 工况 | ✅ 相当 | `Power on Hour` / `Power Cycle` / `Rated Workload %` / 读写命令与扇区量 |
| 7 | 固件 / 服务区 | ⚠️ 部分覆盖（TXT 降级） | `Flash LED (Assert) Events` 及事件表 / `Has Drive been Depopped` / `Depopulation Head Mask` / `Uncorrectable errors` |
| 8 | SSD 磨损 | ❌ 不适用 | HDD 机械硬盘不适用 |

---

## 专家判读方法论 (判断逻辑 · 依据 · 流程)

有经验的硬盘失效分析工程师面对 FARM 日志时的思考方式。**先理解这套逻辑，再去跑脚本**——脚本是这套方法论的自动化，但遇到边界形态、需要解释"为什么"或对外提供结论依据时，靠的是这套物理因果推理。

### A. 判断逻辑 (怎么想)

专家不是单纯地"逐个字段查阈值"，而是按五个步骤进行收敛：**部位 → 机理 → 严重度 → 活跃度 → 决策**。

1. **先定部位，再谈数值**：任何异常先归到 8 类故障部位之一。同样是"读错误多"，落在"盘片坏扇区"还是"接口超时"上，处置完全不同（换盘 vs 更换线缆/背板）。
2. **用机理串因果，而不是堆砌指标**：真正可信的结论是一条**物理因果链**。
   > HDD 最典型的退化链：
   > 盘面/磁头介质退化 → 飞高 (FAFH) 偏移、信号裕量下降 → 读错误 → 坏扇区重映射 (Reallocated ↑) → 命令超时 (CTO) → SCSI I/O 错误 → 操作系统文件系统只读/宕机。

   能把观察到的字段对号入座到这条链的某几环，结论才立得住。
3. **种群相对法 > 绝对阈值**：同一块盘的 $N$ 个磁头同工艺、同负载、同环境，是天然的对照组。"全家就它一个不一样"的离群磁头，比任何手册阈值都更灵敏可靠——这是 FARM 逐头数据最大的分析价值。
   > [!WARNING]
   > **飞高 FAFH clearance delta 是出厂校准量，逐头天然差异很大**（不同盘的种群中位可相差数倍）。单纯 FAFH 离群**只算"关注"**，**不能单独**判"退化"。只有当**同一磁头同时有介质损伤**（类 1 的重分配/不可恢复读）时，FAFH 离群才作为因果链佐证升级为"退化"。脚本已按此实现（类 2 FAFH 离群默认 sev=1，与同头坏道共振才升 sev=2）。
4. **严重度分级看"是否已伤到数据面"**：`Reallocated Sectors` > 0 说明已动用备用扇区；`Unrecoverable Read Errors`（不可恢复、已上抛主机）是已经伤到业务的硬证据。
   > **分级定义**：关注（校准离群/单项轻微） < 退化（已重分配/已上抛） < 失效（磁头开路 0xFFFF / 固件 Assert / 氦气泄漏）。
5. **单快照下用"候选数"近似活跃度**（替代 SM2 的趋势）：
   > [!IMPORTANT]
   > FARM 是**单帧快照，没有趋势**。判"退化进行中 vs 暂稳"的近似规则：
   > - `Reallocated Candidate Sectors` > 0（整盘或任一头） → **退化进行中**（有坏道已检出待重分配，说明退化仍在发生）。
   > - 候选 = 0 且已重分配 > 0 → **暂稳**（坏道已处理完，暂未发现新坏道）。

### B. 判断依据 (凭什么)

- **现场统计规律**：单项指标非零时故障概率约 30%–40%，而**第 1 类（重分配/坏扇区）与第 2 类（不可恢复读）同时非零时，故障概率升至约 76%**——所以分析重在组合与共振，不轻信单项指标。
- **计数器语义**：`Reallocated Sectors`、`CTO Count`、`Unrecoverable Read Errors` 都是**累计量**；`Reallocated Candidate` 是"已检出但尚未完成重分配的坏道"，是单快照下最接近"活跃度"的指标。
- **物理量含义**：`Fly height clearance delta` = 飞高间隙偏移、`MR Head Resistance` = 磁阻磁头电阻（0xFFFF = 开路）、`Interface CRC Errors` = 接口链路误码、`CTO` = 命令超时——直接对应磁头/盘面/接口的物理状态。
- **整盘↔逐头对账**：整盘 `Reallocated Sectors` 若能与某磁头的 `Reallocated Sectors by Head` 对上（如整盘总数恰好等于某单头的逐头数），即可**定位到具体磁头**；若整盘很大而逐头全 0，则诚实标注"本帧未填充逐头分布，无法定位到磁头"。
- **覆盖度自知**：第 3/7 类只是部分覆盖，TXT 来源时第 2/7 类及逐头明细进一步降级，第 8 类不适用——结论中应当明确标注"此类看不全"。

### C. 分析流程 (怎么走)

```
①归集分组：按 farmlog 下的 SN（或文件名）分盘；每盘选数据源（json 优先, txt 兜底）
②身份识别：读型号/固件/磁头数；18 磁头 + ST20000NM002H = Mach.2 双致动器
③逐头体检：每块盘 N 个磁头横向互比，挑出离群头（种群相对法）
④整盘↔逐头对账：用逐头数把整盘坏道定位到具体磁头；定不到则诚实标注
⑤八类归位：把每项异常落到 8 类故障部位，标注覆盖度
⑥机理串链：用物理因果链把字段串成一句"哪里坏了、怎么坏的"
⑦分级研判：按"是否伤到数据面 + 候选数活跃度"定严重度（注意 FAFH 单独离群只算关注）
⑧给出处置：换盘 / 磁头级降级 / 换线缆 / 改环境 / 带外重启 + 留用退出条件
```
脚本已自动执行 ①–⑧ 并给出建议；判读人重点复核 ⑥（因果链是否成立）、④（定位是否可信）与 ⑧（处置是否匹配现场）。

---

## 健康判定矩阵 (单快照版)

根据"受影响磁头数 × 候选数活跃度 × 接口/固件异常 × 最高严重度"进行整盘归类。**与 SM2 不同：这里没有趋势，活跃度用候选数近似。** 详细矩阵与处理方法见 [farm_field_reference.md](farm_field_reference.md) 第 7、9 章。

| 故障模式 | 物理与遥测特征 | 最终判定 | 延寿可行性 |
|---|---|---|---|
| **健康** | 所有磁头重分配=0、不可恢复读=0，FAFH 无显著离群，环境正常 | 健康 | — |
| **轻度异常 / 早期预警** | 个别磁头 FAFH 校准离群，或单项分类达"关注"（CTO 少量、shock 偏高），无介质损伤 | 亚健康 | **高**（维持监控） |
| **单磁头退化** | 仅 1 个磁头有介质损伤（重分配/不可恢复读），其余健康 | 退化 | 候选>0：低，建议磁头级降级/换盘；候选=0：高，RAID 兜底可中期留用 |
| **多磁头介质退化** | ≥ 2 个磁头有介质损伤 | 严重退化 | 中等偏低，尽快备份并换盘 |
| **整盘介质退化（未定位到磁头）** | 整盘重分配/不可恢复读很大，但逐头数全 0（本帧未填充，或 txt 来源） | 退化 | 备份；候选>0 倾向换盘，候选=0 可加强监控 |
| **某类别异常** | 无具体磁头失效，但盘级某项分类（接口 CRC、温度）达"退化" | 严重异常 | 按故障类别特定处置（改环境/换线） |
| **固件/硬件级失效** | `Flash LED Assert` > 0 / `Helium Tripped` > 0 / ≥ 2 头 MRR=0xFFFF | 失效 | **低**，优先带外重启 + 备份 + 换盘 |

> [!IMPORTANT]
> **指标组合研判原则**：单一指标异常时故障概率约 30%–40%；而**第 1 类（重分配/坏扇区）与第 2 类（不可恢复读）同时非零**时，设备失效概率升至约 76%——这是最应优先安排数据备份和换盘的故障组合。
> **FAFH 例外**：飞高 clearance delta 单独离群**不计入**上述组合，因其逐头校准差异天然大，单独出现不代表退化。

---

## 冷存储 R 码定界层（与 8 类部位层的关系）

8 类框架回答"**盘内哪个部位坏了**"；R 码规则（[root_cause_rules.md](root_cause_rules.md)）回答"**根因是什么、怎么修**"（含 Depop 25%/50% 分级、umount/带外重启修复能力）。两层由 `analyze_farm.py` 一次性输出，判读要点：

| R 码 | FARM 侧核心判据（详见 root_cause_rules.md §1-§5 各 R 码定界方法） | 与 8 类的对应 |
|---|---|---|
| R1 磁头信号退化 | DOS WR 倍率 >200×（梯度比 >10×，磁头选择性）或 Realloc 集中 ≤25% 磁头 + H2SAT 选择性 | 类 2/3 逐头异常 + 类 1 集中损伤 |
| R2 磁头飞行异常 | 全头 DOS WR<50× 且无介质损伤，但 VO>100 或 \|FAFH\|>200 | 类 2/3 飞行指标异常、类 1 干净 |
| R3 盘片介质退化 | Realloc 跨 >25% 磁头且与 DOS WR 不相关；或 Realloc=0 但候选 >500 | 类 1 分散损伤、类 2/3 无选择性 |
| R4 振动致伤 | Shock>10K + 异常头占比>50% + 梯度比<3×（或 Shock>50K + 全头飞高异常） | 类 5 冲击 + 类 1/2/3 多头同步 |
| R5a 固件异常 | Flash LED Events > 0 | 类 7 |
| R6 机械电机退化 | Spin Retry ≥1 且无磁头选择性 | 类 3 |
| R7 链路故障 | **FARM 盘体全健康**（DOS WR<50×、VO≤30、Realloc=0、H2SAT 无异常、Shock<1K）+ OS 侧链路错误 | 类 1/2/3/5 全干净（类 4 CRC/CTO 可佐证） |

> [!IMPORTANT]
> 结论冲突时以 R 码规则表为准（用户定义规则为根因结论层）；8 类结论保留在逐类明细作部位证据。FARM 侧候选 R 码**必须**经 OS 侧交叉验证清单闭环（脚本已逐盘列出待验项），仲裁规则（R1 vs R3 / R1 vs R5c / R2→R1 / R4 vs R1）见 root_cause_rules.md。

## 与主机日志联动

FARM 仅反映磁盘内部的物理及遥测指标，并不包含文件系统或上层业务的影响。若需要论证磁头退化对上层业务的影响（如 I/O 错误、卷宕机），须结合主机内核日志（`dmesg` / `/var/log/messages`）闭环佐证：

- **主机日志关键词**：`Medium Error`、`Unrecovered read error`、`critical medium error`、`I/O error, dev sdX`、`command timed out`、`XFS ... metadata I/O error`、`xfs_do_force_shutdown`、`Shutting down filesystem`。
- **典型链路传导**：`某磁头介质/飞高退化（FARM 定位到具体 headN）` → `产生不可恢复读错误/命令超时` → `操作系统上抛 SCSI I/O 错误` → `XFS 文件系统元数据损坏` → `触发文件系统强制 shutdown（只读）`。
- **应急恢复**：仅 `umount` 不能修复损坏的元数据；须在卸载状态下运行 `xfs_repair` 修复后方可重新挂载（前提是磁盘仍能响应 SCSI 且仅有元数据层面的损坏）。
