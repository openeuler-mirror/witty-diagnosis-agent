# 冷存储故障根因定界规则 (R1–R16)

用户定义的**冷存储硬盘故障根因分类与定界规则**，来自《故障根因分类表》。本文件严格按分类表的六列结构逐条落地为规则：**故障域 · 范围 · 典型故障根因 · 故障诱因 · 故障修复措施 · 基于 FARM LOG+OS 日志故障定界方法（可操作量化标准）**（外加"说明"列的 Depop 适用性与 umount/带外重启修复能力）。

本文件是 SKILL.md **Step 5（FARM+OS 联合底层定界）**的权威规则集：
- 脚本 `scripts/analyze_farm.py` 已实现其中 FARM 侧可量化的判据（R 码定界引擎），输出【候选 R 码 + 判定依据 + OS 侧待交叉验证清单】；
- 分析人须按本文件每条 R 码的**定界方法**与**仲裁规则**，结合 Step 0-4 的 OS/iBMC 证据交叉验证后闭环最终 R 码。

> [!IMPORTANT]
> **规则优先级**：R 码定界规则命中时，故障模式/健康判定/处置建议**按本规则表给出**，作为根因结论层；8 类故障部位框架（[farm_analysis.md](farm_analysis.md)）仍作为部位定位层保留在逐类明细中，两层互补、不互相覆盖描述。
> **定界原则——因果链起始点**：多机理并发时（如 R2 演变 R1、R1 伴随 R7），分类取因果链起始点/主导故障，并发机理标注为加速因子。
> **本文件不含任何具体案例盘 SN**——案例是专家诊断的结果，不作为规则；本文件只承载"如何定界"的规则本身。

> [!CAUTION]
> **⛔ 用户定义的磁头/组件退化确定性规则优先于本文件所有 R 码规则**（含 R1 磁头信号退化）：
> - **逐头判据**：Velocity Observer > 200，或 DOS Write Count Threshold 非0 且 DOS Write Refresh Count > 1000 × Threshold → 该头组件退化。
> - **盘级终态**（仅按占比二选一）：**≥ 50% → 损坏**（备份→报废换盘）；**< 50%（且>0）→ 健康**（重新挂载 + DEPOP 隔离，固定命令见 SKILL.md §5.2.1）。
> - **严禁**用同盘的 Realloc / Candidate / URE / Pending Sector / SMART FAILED / XFS shutdown / 固件不可纠正错误改判——即使 R1 定界方法（DOS WR 倍率>200×等）同时命中，R1 也只作**并发根因描述**保留在 R 码定界段，健康判定与处置**不得偏离**确定性规则输出。详见 SKILL.md §5.2.1 三条硬约束。

## 0. 故障域总览

| 故障域 | 范围 | R 码 | 典型故障根因 | FARM 可定界? |
|---|---|---|---|---|
| 硬盘域 | 硬盘本体（磁头/介质/机械/固件） | R1 | 磁头信号退化 | ✅ 核心场景 |
| 硬盘域 | 硬盘本体 | R2 | 磁头飞行异常 | ✅ |
| 硬盘域 | 硬盘本体 | R3 | 盘片介质退化 | ✅ |
| 硬盘域 | 硬盘本体 | R4 | 振动致伤 | ✅ |
| 硬盘域 | 硬盘本体 | R5（R5a/R5b/R5c） | 硬盘固件异常 | R5a ✅ / R5b 先恢复后诊断 / R5c 需 SMART 辅助 |
| 硬盘域 | 硬盘本体 | R6 | 机械电机退化 | ⚠️ 部分（主要靠 SMART Attr3/10） |
| 链路域 | 互联链路（PCIe + SAS/SATA） | R7 | SAS/SATA 链路故障 | FARM 全健康 = 核心标志 |
| 链路域 | 互联链路 | R8 | PCIe 链路故障 | ❌（FARM 不受影响，OS 侧定界） |
| RAID 域 | RAID 卡（硬件/固件/驱动） | R9 | RAID 卡单板损伤 | ❌ |
| RAID 域 | RAID 卡 | R10 | RAID 卡固件/驱动故障 | ❌ |
| EXP 域 | EXP 背板（硬件/固件） | R11 | EXP 背板固件异常 | ❌ |
| EXP 域 | EXP 背板 | R12 | EXP 芯片故障 | ❌ |
| OS 域 | 操作系统/文件系统/内核 | R13 | 系统资源耗尽 | ❌ |
| OS 域 | 操作系统/文件系统/内核 | R14 | OS IO 栈配置异常 | ⚠️（可能有 R1 早期信号） |
| OS 域 | 操作系统/文件系统/内核 | R15 | 文件系统损坏 | ⚠️（FARM 健康与否决定独立/后果） |
| OS 域 | 操作系统/文件系统/内核 | R16 | 内核 Bug | ❌ |
| 待定界 | — | TBD | FARM/OS 数据不全，无法定界 | 补采 FARM+OS 后重新定界 |

---

## 1. 硬盘域

### R1 磁头信号退化

> [!CAUTION]
> **⛔ 本 R 码常与用户确定性规则同时触发**（VO>200 / DOS Write Refresh>1000×Threshold 本就是 R1 的 FARM 侧写侧退化信号）。此时**健康判定与处置以确定性规则为准**（<50%→健康+DEPOP；≥50%→损坏+报废换盘），R1 仅作**并发根因描述**保留。禁止把下文"晚期换盘"作为占比<50%时的处置建议。详见 SKILL.md §5.2.1。

- **范围**：硬盘本体（磁头/介质/机械/固件）
- **故障诱因**：① 写极尖磁性疲劳（反复磁翻转→矫顽力下降→写入场强不足）② 读传感器退化（TMR 隧道结老化→磁阻比下降→信噪比降低）③ 校准参数漂移（磁头电气特性渐变超出初始校准范围）。
- **故障修复措施**：带内 badblocks 触发重映射 + fsck/xfs_repair 修复 FS；带外 Depop 隔离退化磁头延寿；晚期换盘。**（注：当用户确定性规则同时触发时，本行不适用，以规则表口径为准。）**

**基于 FARM LOG+OS 日志故障定界方法（可操作量化标准）**：
- **【Step 1】FARM Per-Head 横向比较**
  - ① 写侧退化判定——**DOS WR 倍率 = 该头 DOS WR 值 / 该头 Threshold 值**：健康 < 50×（所有磁头）；正常老化 50×–200×（个别磁头，持续监控）；退化告警 200×–1000×（Depop 候选）；严重退化 > 1000×（强烈建议 Depop）。
  - ② 读侧退化判定——**H2SAT 指标**：%codewords in error = 0 → 健康；%codewords ≠ 0 → 退化；BER > 300 → 退化；收敛迭代次数 > 6 → 退化。
- **【Step 2】梯度判定（区分 R1 vs R4）——梯度比 = 最差磁头 DOS WR 倍率 / 最佳磁头 DOS WR 倍率**：> 10× → 显著梯度，R1 特征；< 3× 且异常磁头占比 > 50% → 无梯度，R4 特征；3×–10× → 中间区，需结合 Shock 值判断。
- **【Step 3】排除 R2——VO 标准**：VO ≤ 30（所有磁头）= 正常 → 排除 R2；VO 30–100 = 监控区；VO > 100 = 异常 → 可能 R2 或 R1+R2 并发。
- **【Step 4】排除 R4——Shock 标准**：Shock < 10,000 → 排除 R4；Shock > 10,000 + 异常磁头占比 > 50% + 梯度比 < 3× → R4。
- **【Step 5】OS 侧交叉验证——SMART 量化标准（月度采集周期）**：
  - Attr5 Reallocated Sectors：Raw 从 0 变为 ≥1 → 告警；两次采集间 Raw 增加 ≥1 → 持续退化。
  - Attr187 Reported UNC：Raw 从 0 变为 ≥1 → 告警（出现首个不可纠正错误）。
  - Attr197 Current Pending：Raw 从 0 变为 ≥1 → 告警。
  - Attr198 Offline UNC：Raw 从 0 变为 ≥1 → 告警。
  - Attr195 ECC Fast：Normalized VALUE 从 100 降至 ≤011（SN02 固件）→ 版本统计模式异常。
  - dmesg：`medium error` / `I/O error` **集中在特定 LBA 范围**。
  - messages：可能记录 `XFS shutdown`（晚期）。
- **【Attr195 区分规则（R1 vs R5c）】**：FARM DOS WR < 50× 但 Attr195 VALUE ≤ 011（SN02 固件）→ R5c 固件统计 Bug；FARM DOS WR > 200× 且 Attr195 异常 → R1 真实磁头退化。**仲裁：以 FARM DOS WR 是否同步异常为准。**

**说明（Depop 适用性 / 修复能力）**：
- Depop 适用性（按磁头占比）：✅ 异常磁头占比 ≤ 25% → 可行；🟡 25% < 占比 ≤ 50% → 边际，需评估剩余容量；❌ 占比 > 50% → 不推荐，换盘。
- umount+mount：仅临时恢复 FS，不修复磁头退化；带外重启：不可修复磁头退化。
- ⚠️ Depop 附加判定：相邻磁头同时异常 ≥2 对 → 降级为"边际可行"（可能影响伺服稳定性）；需评估硬盘剩余服役寿命与存储池容量冗余度。
- ⚠️ Depop 数据迁移风险：操作需先将数据从待隔离磁头区域读出；弱读磁头在大规模读取时可能彻底失效（H2SAT 弱读能力评估）；建议优先迁移非异常磁头区域数据、限制单次读取量。

### R2 磁头飞行异常

- **范围**：硬盘本体（磁头/介质/机械/固件）
- **故障诱因**：① ABS（空气轴承面）几何退化→气动特性改变→飞高偏离设计点 ② 盘腔颗粒污染附着 ABS→飞行不稳定 ③ Load/Unload 加载机构磨损→初始飞高偏差 ④ Load/Unload 斜坡磨损→滑橇与斜坡摩擦产生碎屑→盘腔颗粒污染→飞行不稳定（冷存储频繁 L/P 策略加速此过程）。
- **故障修复措施**：轻度监控+定期 FARM 复采；重度 Depop 隔离或换盘（若演变为 R1 则按 R1 处理）。

**基于 FARM LOG+OS 日志故障定界方法**：
- **【Step 1】飞行指标判定**：Velocity Observer > 100（任一磁头）→ 飞行异常；或 Fly Height Clearance Delta |值| > 200（任一区域）→ 飞高偏离。
- **【Step 2】轻重度区分**：
  - 轻度 R2（须**同时满足**）：VO 100–500 且 Fly Height |delta| 200–500；无 OS 侧读写错误（dmesg 无 medium error，SMART Attr5/197/198 Raw=0）；DOS WR 倍率 < 50×（尚未演变为 R1）。
  - 重度 R2（**满足任一**）：VO > 500 或 Fly Height |delta| > 500；或伴随 OS 侧读写错误（dmesg 有 medium error，Attr5/197/198 Raw>0）；或 DOS WR 倍率上升至 50×–200×（R2 开始演变为 R1）。
- **【Step 3】排除 R1**：DOS WR 倍率 < 50×（所有磁头）→ 排除 R1 主导；H2SAT %codewords = 0 → 排除 R1 读侧退化；若 DOS WR 50×–200× 且 VO > 100 → R1+R2 并发，取因果链起始点（R2 先于 R1）。
- **【Step 4】排除 R4**：Shock < 10,000 → 排除 R4；若 Shock > 10,000 且异常磁头占比 > 50% → R4。
- **【Step 5】OS 侧交叉验证**：SMART G-Sense Error Rate（Attr194 Raw）较基线增长 → 伴随振动；dmesg `read retry` 出现；iostat 间歇性高延迟（svctm 波动大）。
- **【R2→R1 工程化判定规则】**（FARM 为快照数据，无法回溯 VO 与 DOS WR 升高时序）：若已出现读写错误/重分配 → 按 R1 分类（主导故障），R2 标注为并发加速因子；若仅 VO 异常、无读写退化 → 判为纯 R2。
- **【冷存储专项——L/P 斜坡磨损监控】**：SMART Attr192 Power-Off Retract Count > 同批次中位数×2 → L/P 磨损预警；SMART Attr193 Load/Unload Cycle Count > 同批次中位数×2 → L/P 频次异常；评估继发 R2（颗粒污染→飞高异常）和 R3（碎屑划伤盘面）风险。

**说明**：可演变为 R1（飞行异常→擦写盘面→介质+信号双重退化），分类取因果链起始点（R2 先于 R1）。Depop 适用性：✅ 异常磁头占比 ≤ 25% → 可 Depop；❌ 占比 > 25% → 换盘。umount+mount / 带外重启均不可修复。

### R3 盘片介质退化

- **范围**：硬盘本体（磁头/介质/机械/固件）
- **故障诱因**：① 磁性涂层制造缺陷→局部磁畴失稳→信号衰减 ② 写入应力疲劳→高频写入区域磁性疲劳 ③ 热衰减→磁畴自然退磁 ④ 非振动原因的盘面物理损伤。
- **故障修复措施**：带内 badblocks + fsck/xfs_repair（临时措施）；物理坏道不可修复仅能隔离；晚期换盘。

**基于 FARM LOG+OS 日志故障定界方法**：
- **【Step 1】Realloc 与 DOS WR 相关性判定（区分 R3 vs R1）**：列出所有 Realloc>0 的磁头，检查这些磁头的 DOS WR 倍率——
  - 相关（→R1）：Realloc>0 的磁头中，≥50% 的磁头 DOS WR 倍率 > 200×（重分配集中在高 DOS WR 磁头 = 磁头退化导致写入失败→重分配）。
  - 不相关（→R3）：Realloc>0 的磁头中，≥50% 的磁头 DOS WR 倍率 < 50×（重分配分散在 DOS WR 正常的磁头 = 介质本身缺陷，非磁头问题）。
- **【Step 2】Realloc 分布广度判定**：R3 特征 = Realloc 跨 > 25% 磁头分布（如 16 头盘中 >4 头有 Realloc>0）；R1 特征 = Realloc 集中在 ≤ 25% 磁头（1–4 头）。
- **【Step 3】早期介质退化（Realloc=0 时）**：SMART Attr197 Current Pending Sector Raw > 500 → 早期介质退化；持续监控 Candidates 增长趋势（月度采集）。
- **【Step 4】物理损伤判定**：FARM Disc Slip > 0 → 盘片物理位移/损伤；需排除 R4（Shock < 10,000）。
- **【Step 5】OS 侧交叉验证**：SMART Attr5 Raw 跨多磁头区域增长；dmesg `medium error` **分布在多个不连续 LBA 范围**；iostat 多区域读写延迟异常。
- **【R1 vs R3 读侧交叉验证】**（R3 介质退化可能触发固件写电流补偿→DOS WR↑，导致误判 R1）：R1 特征 = 读侧先退化（H2SAT↑→BER↑）、写侧后补偿（DOS WR↑），**有磁头选择性**；R3 特征 = 写侧先退化（Realloc↑）、读侧退化均匀**无磁头选择性**。**仲裁规则**：当 Realloc 与 DOS WR 同时异常时，以 H2SAT 是否具有磁头选择性为准——H2SAT 集中在特定磁头 → R1；H2SAT 均匀分布或无异常 → R3。

**说明**：Depop 有限适用——🟡 退化集中在 ≤ 25% 磁头可尝试 Depop；❌ 退化跨 > 25% 磁头分布，Depop 效果有限。umount+mount 仅临时恢复 FS；带外重启不可修复介质。

### R4 振动致伤

- **范围**：硬盘本体（磁头/介质/机械/固件）
- **故障诱因**：① 旋转振动(RV)累积→磁头持续微偏离→累积性写入偏差+读取错误 ② 机械冲击→磁头瞬间大幅偏离或撞击盘面 ③ 机柜结构共振→特定频率下振动放大。
- **故障修复措施**：换盘 + 机柜级 RV 治理；Depop 不适用。

**基于 FARM LOG+OS 日志故障定界方法**：
- **【Step 1】振动指标判定**：Over-Limit Shock Events > 10,000 → 振动异常；> 50,000 → 极端振动（确认 R4）；< 1,000 → 排除 R4。
- **【Step 2】多磁头同步退化判定（区分 R4 vs R1）——须同时满足**：a) 异常磁头占比 > 50%（异常 = DOS WR 倍率 > 200× 或 VO > 100）；b) 梯度比 < 3×（各头退化程度相近，无单头主导，梯度比 = 最差磁头 DOS WR 倍率 / 最佳磁头 DOS WR 倍率）；c) Shock > 10,000。
- **【Step 3】边界情形处理**：Shock > 10,000 但梯度比 > 10× → R1 + F4（振动为加速因子，非根因；即有振动史，但退化仍集中在少数头 = 磁头自身问题为主）；Shock < 10,000 但多磁头退化无梯度 → 需排查批次缺陷等。
- **【Step 4】OS 侧交叉验证**：SMART Status = FAILED（整体）；SMART G-Sense Error Rate（Attr194 Raw）大幅高于同型号基线；dmesg 可能伴随硬件错误风暴（多条 medium error 密集出现）；messages 机柜级振动时可能记录多盘同步异常。

**说明**：必须独立分类。❌ Depop 不适用——① 异常磁头占比 > 50%，隔离后剩余容量不足；② 振动是持续外力，剩余磁头会继续退化；③ 无梯度=所有磁头都不健康，无"好头"可保留。umount+mount / 带外重启均不可修复。
**关键区分速记**：`R4 = 外力 + 多头(>50%) + 无梯度(<3×) + Shock>10K`；`R1 = 内源 + 少数头(≤25%) + 有梯度(>10×) + Shock<10K`。
📋 设计说明：R4 采用"因果链起始点"原则独立分类（不归入 R1/R2/R3 子类）——修复决策（换盘+机柜治理）与 R1（Depop 延寿）完全不同；损伤模式（多头同步+无梯度）有独立诊断特征；机柜级振动溯源：同机柜多盘同步异常→机柜级 RV，单盘异常→盘级冲击。

### R5 硬盘固件异常（R5a / R5b / R5c）

- **范围**：硬盘本体（磁头/介质/机械/固件）
- **故障诱因**：R5a 固件代码缺陷/校准参数错误；R5b 控制器状态机死锁（异常边界条件触发不可恢复状态）；R5c 特定固件版本系统性缺陷（如 SN02 版本）。
- **故障修复措施**：R5a 厂家固件修复工具/固件升级；R5b hiraidadm link reset → 带外上下电 → 换盘；R5c 固件升级（厂商发布修复版本后）。

**基于 FARM LOG+OS 日志故障定界方法**：
- **R5a（可 FARM 定界）**：FARM Flash LED Events > 0 → 固件主动标记异常；或 FARM 中 LBA = 0x0fffffff UNC 模式 → 固件特定异常模式；FARM 可正常采集 → 直接定界。
- **R5b（先恢复后诊断——盘不可响应）**：❌ 盘不可响应，FARM 无法采集；恢复流程 hiraidadm link reset（首选）→ 带外上下电 → 换盘；**恢复后采集 FARM**——全健康（所有磁头 DOS WR<50×、VO≤30、Realloc=0）→ R5b 确认；FARM 异常（有磁头退化或 Shock 异常）→ 有并发物理根因（R1/R4 等），R5b 为表现、物理根因为主因。
- **R5c（需 SMART 辅助）**：FARM 本身无直接指标；SMART Attr195 Normalized VALUE = 010–011（SN02 固件版本统计模式，已累计 10 例 SN02 固件 7 年盘呈现此模式）；需结合固件版本号交叉验证。
- **OS 侧日志**：messages `sense code: 0x04 0x01`（逻辑单元通信失败）/ `0x06 0x29`（Power on/Reset occurred）；dmesg `link reset` / `I/O timeout` / `device reset` / `scsi host: resetting host`；hiraidadm 盘状态异常（Unconfigured Bad / Offline）。
- **【R5c 与 R1 的 Attr195 区分规则】**：FARM DOS WR < 50× 但 Attr195 VALUE ≤ 011（SN02 固件）→ R5c 固件统计 Bug；FARM DOS WR > 200× 且 Attr195 异常 → R1 真实磁头退化。判据：以 FARM DOS WR 是否同步异常为准。
- **【R5c 厂商知识库机制】**：Attr195 ≤ 011（SN02 固件）为希捷特定版本已知模式，**不作为通用标准**；建议建立"已知固件统计异常列表"，按型号+固件版本匹配触发，避免跨型号推广产生假阳性。

**说明**：R5b 核心原则先恢复后诊断。umount+mount 不可修复；带外重启——✅ R5b 可修复（hiraidadm 失败后带外上下电使控制器重新初始化），❌ R5a/R5c 需固件升级。注：IO Hang 可能是 R5b（固件挂死），也可能是 R1 晚期（磁头退化触发固件无尽重试）→ 恢复后 FARM 可区分。

### R6 机械电机退化

- **范围**：硬盘本体（磁头/介质/机械/固件）
- **故障诱因**：① 主轴轴承润滑剂退化/滚道磨损→旋转精度下降 ② 音圈电机(VCM)磁体老化→寻道精度下降 ③ 频繁启停损伤（电源异常导致频繁 Spin-up/down→轴承加速磨损）④ 冷存储工况：磁头粘连/静摩擦力增大（长期断电后首次上电起旋困难）⑤ 轴承润滑剂凝结（低温润滑剂粘度增大→起旋困难→Spin-Up Time 波动）⑥ 频繁 Spin-up/down（冷上电策略导致轴承加速磨损）。
- **故障修复措施**：换盘（不可修复）；R6 导致的盘停转可尝试带外重启临时恢复。

**基于 FARM LOG+OS 日志故障定界方法**：
- **【Step 1】电机指标判定**：SMART Attr10 Spin Retry Count Raw ≥ 1 → 主轴启旋异常；SMART Attr3 Spin-Up Time——与同型号同批次其他盘横向比较，Raw > 同批次中位数×2 → 异常增长，或两次月度采集间 Raw 持续增长（正常盘应稳定）→ 轴承磨损（**必须同型号比较**，不同型号基线不同）。
- **【Step 2】排除磁头选择性退化（区分 R6 vs R1–R4）**：R6 特征 = 全盘性能下降、无磁头选择性退化（所有磁头 DOS WR 倍率 < 50× 且 VO ≤ 30，但整体 SMART 性能指标异常）；R1–R4 特征 = 有磁头选择性（特定磁头异常，其他正常）。
- **【Step 3】排除 R5b（盘不可响应时）**：R6 可能导致盘片停转→盘不可响应→类似 R5b；区分——恢复后若 Spin Retry ≥ 1 且无磁头选择性退化 → R6；恢复后若 FARM 全健康且 Spin Retry = 0 → R5b。
- **【Step 4】OS 侧交叉验证**：SMART Attr3/Attr10 异常；dmesg `spin-up timeout` / `spin-up retry` / `drive not ready`；iostat 全盘（非特定磁头区域）性能下降（svctm 整体升高，非单 LBA 范围）。
- **【冷存储专项监控】**：Spin-Up Time 季节性变化分析（冬季/夏季对比，排除温度干扰）；首次上电 Spin-Up Time 异常 + 多次上电后恢复 → 磁头粘连特征；Attr192/Attr193 横向比较（同批次冷存储盘 L/P 次数基线）。

**说明**：理论补充类。Depop 不适用（非磁头级问题）；umount+mount 不可修复；带外重启 ✅ 盘停转可临时尝试恢复（可能重新 spin-up 成功）但根因不可修复。冷存储专项提示：长期断电/待机→首次上电起旋困难是常见工况；冷上电策略建议避免高频 Spin-up/down、控制上电间隔；低温环境（<10℃）需预热后再上电。

---

## 2. 链路域

### R7 SAS/SATA 链路故障

- **范围**：互联链路（PCIe + SAS/SATA）
- **故障诱因**：① SAS/SATA 连接器接触不良 ② 线缆损伤 ③ 链路误码/降速/建链异常。
- **故障修复措施**：轻度 umount + mount（华为表确认可修复大多数接触不良）；hiraidadm link reset（phy func=disable/hardreset/linkreset）；严重时重新插拔/更换线缆。分布式存储适配（Ceph/MinIO 等无传统挂载点场景）：Ceph BlueStore 重启 OSD 进程（`systemctl restart ceph-osd@X`）；通用 `echo 1 > /sys/block/sdX/device/delete` + `rescan-scsi-bus.sh`；MinIO 重启进程或重新扫描设备。

**基于 FARM LOG+OS 日志故障定界方法**：
- **【定界特征】FARM 全健康 = R7 的核心标志**：所有磁头 DOS WR 倍率 < 50×；所有磁头 VO ≤ 30；H2SAT %codewords = 0；Realloc = 0；Shock < 1,000 → 盘体完全健康，问题在链路层。
- **OS 侧定界——messages/dmesg 特征**：
  - dmesg（SAS 链路异常典型模式）：`mpt3sas: phy(4): link rate changed from 12.0 Gbps to 6.0 Gbps`（降速告警）；继续降至 `6.0 Gbps to 1.5 Gbps`（严重退化）；`scsi host4: mpt3sas: removing: handle(0x000a)`（设备被移除=链路断开）；`DID_TRANSPORT_DISRUPTED`（传输中断）。
  - messages（链路速率降速记录）：`sas: expander-phy(4): link reset`；`sas: phy(4): link rate: 12.0 Gbps → 6.0 Gbps`。
  - hiraidadm 显示 phy 状态异常；SMART 无异常（所有属性 Raw 正常）；iostat 间歇性 IO 超时（svctm 周期性飙升）。
- **【SAS PHY 层误码定量标准】**：`/sys/class/sas_phy/phy-X/invalid_dword_count` 月度增量 > 10 → 链路误码异常；`loss_of_dword_sync_count` 月度增量 > 5 → 同步异常；`running_disparity_error_count` 月度增量 > 10 → 编码异常。注：间歇性误码不降速时仅表现为 OSD 随机慢盘/重传增加。

**说明**：✅ umount+mount 可修复轻度链路故障（华为表确认"大多数该类故障可通过 umount/mount 解决"）；✅ hiraidadm link reset 是核心带内恢复手段（`hiraidadm c0:e0:s1 set phy func=disable/hardreset/linkreset`，不依赖带外重启）；带外重启可恢复但非首选。**定界关键：FARM 全健康 + OS 日志有链路异常 = R7。**

### R8 PCIe 链路故障

- **范围**：互联链路（PCIe + SAS/SATA）
- **故障诱因**：① PCIe 插槽接触不良 ② PCIe 链路误码/降速/断开 ③ PCIe Retimer/Redriver 故障。
- **故障修复措施**：人工插拔 / PCIe rescan；严重时更换 PCIe 设备或线缆。

**基于 FARM LOG+OS 日志故障定界方法**：
- **【定界特征】整卡级故障 = R8 核心标志**：该 RAID 卡/HBA 卡下所有硬盘同时受影响；FARM 不受影响（非硬盘侧问题）。
- **OS 侧定界**：
  - `lspci -vvv | grep -i "lnksta"`：正常 `LnkSta: Speed 8GT/s, Width x8`；异常 `Speed 2.5GT/s, Width x4`（降速+降宽）或设备消失（lspci 无输出）。
  - dmesg：`pcieport 0000:03:00.0: AER: Root Port error`；`pci 0000:04:00.0: link state: L0s → L1`（降级）；`PCIe Bus error: severity=Corrected, type=Physical Layer`（早期告警）；`severity=Uncorrected`（严重，需立即处理）。
  - messages：`PCIe device lost` / `PCIe link down`；hiraidadm 可能无法识别整张 RAID 卡。
- **【PCIe AER 定量标准】**：`lspci -vvv` 查看 AER 计数器——BadDLLP/BadTLP 月度增量 > 10 → PCIe 链路误码异常；RxErr+/TxErr+ 计数递增 → 物理层错误。注：长线缆老化可能间歇误码但不降速。

**说明**：整卡级，影响该卡所有硬盘。umount+mount 不可修复；带外重启可能临时恢复（触发 PCIe rescan）但根因未除易复发；彻底修复需重新插拔或更换硬件。

---

## 3. RAID 域

### R9 RAID 卡单板损伤

- **范围**：RAID 卡（硬件/固件/驱动）
- **故障诱因**：① RAID 卡元器件老化/损伤 ② 电源异常导致 RAID 卡硬件损伤 ③ 散热不良导致芯片过热损伤。
- **故障修复措施**：更换 RAID 卡。

**基于 FARM LOG+OS 日志故障定界方法**：【定界特征】RAID 卡硬件级故障；FARM 不受影响（非硬盘侧问题）。OS 侧定界——messages `RAID card not detected` / `card error` / `hardware fault on RAID controller`；BMC 显示 RAID 卡离线；hiraidadm/storcli `Card state: Failed` / 无法查询 RAID 卡状态；lspci 可能显示 RAID 卡设备异常或消失。

**说明**：硬件损伤需更换。umount+mount 不可修复；带外重启系统重启可能触发 card error 但不可修复硬件。

### R10 RAID 卡固件/驱动故障

- **范围**：RAID 卡（硬件/固件/驱动）
- **故障诱因**：① RAID 卡固件代码缺陷 ② 驱动程序 Bug ③ 固件与驱动版本不匹配。
- **故障修复措施**：系统重启 → 固件升级 + 驱动更新。

**基于 FARM LOG+OS 日志故障定界方法**：【定界特征】RAID 卡软件级故障；FARM 不受影响。OS 侧定界——dmesg 驱动错误典型模式 `hiraid: timeout waiting for command completion`（命令超时=驱动与固件通信异常）/ `hiraid: reset controller due to firmware hang`（固件挂死触发控制器重置）/ `hiraid: FW is in FAULT state, resetting adapter`（固件进入 FAULT 状态）/ `hiraid: adapter reset failed`（重置失败=严重，需重启系统）；messages `RAID card initialization failed` / `driver version mismatch: fw=x.x, driver=y.y`；hiraidadm/storcli `Card state: Abnormal` / 固件版本不兼容告警；iostat 整卡级 IO 延迟异常（所有下挂盘均受影响）。

**说明**：固件+驱动的软件层问题。umount+mount 不可修复；带外重启 ✅ 可修复（系统重启触发 RAID 卡重新初始化）；彻底修复需固件升级+驱动更新。

---

## 4. EXP 域

### R11 EXP 背板固件异常

- **范围**：EXP 背板（硬件/固件）
- **故障诱因**：① 固件跑挂/命令超时 ② 固件版本缺陷 ③ 背板温控异常触发保护。
- **故障修复措施**：ipmitool power cycle / BMC 上下电 → 固件升级。

**基于 FARM LOG+OS 日志故障定界方法**：【定界特征】EXP 背板固件级故障；FARM 不受影响；EXP 背板下挂硬盘可能全部受影响。OS 侧定界——messages `EXP backplane firmware abnormal` / `backplane command execution timeout`；BMC 日志背板温度/电压异常（`Backplane thermal warning`）；hiraidadm `EXP communication error`，EXP 下挂硬盘全部不可见。

**说明**：固件异常不一定是 Bug，可能是跑挂、命令超时等。umount+mount 不可修复；带外重启 ✅ BMC 上下电可修复（背板固件重新初始化）；彻底修复需固件升级。

### R12 EXP 芯片故障

- **范围**：EXP 背板（硬件/固件）
- **故障诱因**：① EXP 背板芯片硬件损伤 ② 连接器物理损坏 ③ 电源异常导致背板芯片损伤。
- **故障修复措施**：更换背板（需备份拓扑配置）。

**基于 FARM LOG+OS 日志故障定界方法**：【定界特征】EXP 背板硬件级故障；FARM 不受影响；背板下挂全部硬盘失效。OS 侧定界——messages `Backplane chip error` / `hardware fault`；BMC 诊断芯片级故障；hiraidadm 无法识别 EXP 下挂任何硬盘。

**说明**：硬件损伤需更换。umount+mount 不可修复；带外重启不可修复硬件。

---

## 5. OS 域

### R13 系统资源耗尽

- **范围**：操作系统/文件系统/内核
- **故障诱因**：① 内存耗尽（OOM）② CPU 过载 ③ 句柄/文件描述符耗尽 ④ 线程池耗尽。
- **故障修复措施**：杀业务进程 / 重启 / 热升级扩容。

**基于 FARM LOG+OS 日志故障定界方法**：【定界特征】系统资源耗尽，非硬盘故障；FARM 不受影响。OS 侧量化标准——free 可用内存 < 总内存×5%（使用率 > 95%）；df 磁盘使用率 > 90%；top CPU load > 核数×2；dmesg `Out of memory: Killed process xxxx`（OOM killer 触发=内存耗尽）/ `No space left on device`（磁盘空间耗尽）；messages 进程异常退出记录；iostat IO 队列堆积（非硬盘原因）。

**说明**：非硬盘故障。umount+mount 不可修复；带外重启可临时恢复（清空资源占用），需扩容/优化根治。

### R14 OS IO 栈配置异常

- **范围**：操作系统/文件系统/内核
- **故障诱因**：① IO 调度器参数不当（cfq/deadline/mq-deadline 配置错误）② IO 队列深度（nr_requests）设置不合理 ③ 预读（readahead）参数不当 ④ 慢盘拖累整体 IO 性能（非独立根因，为 R1 早期表现）。
- **故障修复措施**：隔离慢盘 / 调整 OS 参数（io_scheduler / nr_requests / readahead 等）。

**基于 FARM LOG+OS 日志故障定界方法**：【定界特征】IO 性能问题，可能是 R1 早期表现；FARM 可能有 R1 早期信号（DOS WR 50×–200×），也可能全健康。OS 侧量化标准——iostat（与基线比较）%util > 95% 且 await > 基线×1.5 → IO 异常，svctm > 100ms → 慢盘确认；top D 状态（不可中断睡眠）进程数 > 基线×3；dmesg `IO timeout` / `blocked for more than 120 seconds`（进程阻塞超 120 秒=IO 严重异常）；smartctl 长延迟（SMART self-test 超时）。

**说明**：非硬盘硬故障，但可能伴随 R1 早期退化。umount+mount 不可修复；带外重启临时缓解，需调参或隔离慢盘。

### R15 文件系统损坏

- **范围**：操作系统/文件系统/内核
- **故障诱因**：① 异常断电导致日志不一致 ② R1/R3 底层坏块引发 FS 元数据损坏 ③ 多进程并发写入冲突。
- **故障修复措施**：⚠️ 前置——执行 xfs_repair/fsck 前必须先只读挂载备份关键数据（底层坏道场景下存在元数据丢失风险）。看得到盘符：umount + mount（首选）→ fsck / xfs_repair；看不到盘符：带外重启 → fsck / xfs_repair；严重重建文件系统。分布式存储适配：Ceph BlueStore 无传统 FS 层，通过重启 OSD 进程触发 BlueStore 自修复；MinIO 重启进程触发对象级修复（替代 umount/mount 的块设备重新激活路径）。

**基于 FARM LOG+OS 日志故障定界方法**：【定界特征】FS 损坏可能是独立故障，也可能是 R1/R3 后果——FARM 全健康 + FS 损坏 → R15 独立（如断电导致）；FARM 有 R1/R3 信号 + FS 损坏 → 硬盘域根因为主、R15 为后果；判据：FS 修复后无复发且 FARM 健康 → R15 独立，FS 修复后复发或 FARM 异常 → HDD 根因为主。OS 侧 dmesg/XFS 典型模式——XFS `Metadata I/O Error in xlog_write` / `xfs_log_force: error` / `Corruption of in-memory data` / `Unmount and run xfs_repair`；ext4 `EXT4-fs error (device sdb): ext4_find_entry` / `checktime reached, running e2fsck`；mount 失败（`wrong fs type` 或 `structure needs cleaning`）；lsblk 可能无法识别盘符。

**说明**：✅ umount+mount 首选修复（看得到盘符时）；✅ 带外重启可修复（看不到盘符时）。关键注意：若 FS 损坏由 R1/R3 引发，修复 FS 仅为临时措施，需同时处理底层硬盘根因，否则 FS 损坏会反复发生。

### R16 内核 Bug

- **范围**：操作系统/文件系统/内核
- **故障诱因**：① 内核 IO 栈 Bug ② 文件系统驱动 Bug ③ VFS 层 Bug。
- **故障修复措施**：重启 → 内核升级 / 补丁。

**基于 FARM LOG+OS 日志故障定界方法**：【定界特征】内核级软件 Bug，非硬盘故障；FARM 不受影响。OS 侧 dmesg 典型模式——`kernel BUG at fs/xfs/xfs_trans.c:xxxx`（确认内核 Bug）/ `kernel: Call Trace:`（定位 Bug 位置）/ `kernel: panic`（内核崩溃=系统不可用）/ `kernel: Oops: 0000 [#1] SMP`（Oops=内核异常但未崩溃）；需确认内核版本是否有已知 Bug（`uname -r` 对照 CVE 列表）。

**说明**：非硬盘故障。umount+mount 不可修复；带外重启可临时恢复，需升级内核修复。

---

## 6. 待定界

- **诱因**：FARM/OS 日志数据不全，无法定界。
- **修复措施**：补采 FARM+OS 日志后重新定界。
- **定界方法**：数据不全时**严禁强行定界**，输出"待定界 (TBD)"并列明补采需求。常见待补采形态：FARM 为空但仅 OS 日志可用（且 SMART 可能误采到其它 SN）；FARM 完全缺失、IP/盘符需现场确认；Per-Head URE 全零计数器异常且 OS 采集为空需重采；缺乏 FARM Per-Head 数据仅有 OS 日志。
- **补采要求**：补采该盘 FARM（**json 优先**，openSeaChest_LogParser）+ 当期 OS 日志（dmesg/messages/smartctl）；SMART 采集须核对 SN 与盘符一致（防误采到其它盘）；Per-Head 计数器全零但整盘指标极端时标注"数据质量存疑"。

---

## 7. R 码定界决策树（Step 5 联合定界主线）

脚本 `analyze_farm.py` 的 R 码引擎按下述优先级实现 FARM 侧判据；最终 R 码须结合 OS 侧证据闭环。

```
输入:FARM 报告(analyze_farm.py) + OS/iBMC 证据(Step 0-4)
│
├─ 盘不可响应、FARM 无法采集? ──是──► R5b 流程:先恢复(link reset→带外上下电)后复采 FARM
│                                        ├─ 恢复后 FARM 全健康 → R5b 确认
│                                        └─ 恢复后 FARM 异常 → 按下面主线定界(R5b 为表现)
├─ FARM Flash LED > 0? ──是──► R5a(可与物理根因并发,取主导)
├─ Shock>10K 且 异常头占比>50% 且 梯度比<3×? ──是──► R4(换盘+机柜治理)
│      └─ Shock>10K 但梯度比>10× → R1+F4(振动为加速因子)
├─ 任一头 DOS WR>200×(有磁头选择性)? ──是──► R1(按 50/200/1000× 分级;VO>100 并发标注 R2 加速)
├─ Realloc>0?
│      ├─ 与高 DOS WR 相关 或 集中≤25%磁头 → R1(介质损伤集中型)
│      ├─ 与 DOS WR 不相关 且 跨>25%磁头 → R3(H2SAT 无磁头选择性佐证)
│      └─ 不确定 → H2SAT 磁头选择性仲裁(集中→R1;均匀/无→R3)
├─ Realloc=0 但候选(Pending)>500? ──是──► R3 早期(候选积累型)
├─ 全头 DOS WR<50× 但 VO>100 或 |FAFH|>200? ──是──► R2(轻/重度按 §1;若有读写错误→按 R1)
├─ Spin Retry≥1 且无磁头选择性? ──是──► R6 候选(OS 侧 Attr3/10 同批次确认)
├─ FARM 全健康(盘体口径:DOS WR<50×、VO≤30、H2SAT 无异常、Realloc/候选/URE=0、Shock<1K)?
│      ├─ OS 有链路错误(降速/DID_NO_CONNECT/PL log_info/PHY误码) → R7
│      ├─ 整卡级(所有下挂盘受影响) → R8/R9/R10;背板下挂全失效 → R11/R12
│      ├─ 仅 FS 损坏、修复后不复发 → R15 独立
│      ├─ 资源/调度/内核特征 → R13/R14/R16
│      └─ OS 亦无异常 → 健康盘
└─ 数据不全(FARM 缺失/Per-Head 全零/SMART 误采) ──► 待定界:补采 FARM(json)+OS 日志后重新定界
```

## 8. 修复能力速查矩阵（umount+mount / 带外重启 / Depop）

来自各 R 码"说明"列，闭环修复建议时逐码核对。

| R 码 | umount+mount | 带外重启 | Depop | 根治手段 |
|---|---|---|---|---|
| R1 | 仅临时恢复 FS | ❌ | ✅ ≤25% / 🟡 ≤50% / ❌ >50% | Depop 延寿 → 换盘 |
| R2 | ❌ | ❌ | ✅ ≤25% / ❌ >25% | 监控 → Depop/换盘 |
| R3 | 仅临时恢复 FS | ❌ | 🟡 有限（集中≤25% 可试） | 隔离坏道 → 换盘 |
| R4 | ❌ | ❌ | ❌ | 换盘 + 机柜 RV 治理 |
| R5a | ❌ | ❌ | ❌ | 固件修复工具/升级 |
| R5b | ❌ | ✅（link reset 失败后带外上下电） | ❌ | 恢复 → 复采定界 → 换盘 |
| R5c | ❌ | ❌ | ❌ | 固件升级 |
| R6 | ❌ | ✅ 停转可临时恢复 | ❌（非磁头级问题） | 换盘 |
| R7 | ✅ 轻度可修复 | 可恢复非首选 | ❌ | link reset → 换线缆/背板 |
| R8 | ❌ | 可能临时恢复 | ❌ | 插拔/换硬件 |
| R9 | ❌ | ❌ | ❌ | 更换 RAID 卡 |
| R10 | ❌ | ✅ 系统重启可修复 | ❌ | 固件+驱动升级 |
| R11 | ❌ | ✅ BMC 上下电可修复 | ❌ | 固件升级 |
| R12 | ❌ | ❌ | ❌ | 更换背板 |
| R13 | ❌ | ✅ 临时 | ❌ | 扩容/优化 |
| R14 | ❌ | 临时缓解 | ❌ | 调参/隔离慢盘 |
| R15 | ✅ 首选（看得到盘符） | ✅（看不到盘符时） | ❌ | fsck/xfs_repair（先备份）；底层根因须同治 |
| R16 | ❌ | ✅ 临时 | ❌ | 内核升级/补丁 |
