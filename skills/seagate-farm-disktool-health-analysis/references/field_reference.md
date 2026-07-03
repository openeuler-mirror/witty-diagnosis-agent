# FARM 日志字段与判读参考 (多盘 · 8 类故障部位)

希捷 (Seagate) 硬盘 **FARM (Field-Accessible Reliability Metrics) 日志**的字段字典、json↔txt↔标准 SMART 三方映射、8 类故障部位映射、临界值、健康判定矩阵与处理方法。配合 `scripts/analyze_farm.py` 脚本使用:脚本执行自动化提取与分类,本文件解释"为什么这么判"。

> [!TIP]
> **先读方法论再查字段**
> 专家级的判断逻辑 (部位 → 机理 → 严重度 → 活跃度 → 决策)、依据与整体流程请参见 `SKILL.md` 中的「专家判读方法论」一节。本文件是那套逻辑落到**具体字段、阈值与映射**的查询手册。

## 目录
- [1. 日志是什么 / 目录结构](#1-日志是什么--目录结构)
- [2. 数据源纪律 (json 优先 / txt 兜底)](#2-数据源纪律-json-优先--txt-兜底)
- [3. 八类故障部位 ↔ FARM 字段映射 (能不能分析)](#3-八类故障部位--farm-字段映射-能不能分析)
- [4. json ↔ txt ↔ 标准 SMART 三方字段映射](#4-json--txt--标准-smart-三方字段映射)
- [5. 关键字段字典](#5-关键字段字典)
- [6. 临界值表](#6-临界值表)
- [7. 健康判定矩阵与故障模式 (单快照版)](#7-健康判定矩阵与故障模式-单快照版)
- [8. 标记值 / 常量](#8-标记值--常量)
- [9. 处理方法](#9-处理方法)
- [10. 与主机日志联动](#10-与主机日志联动)

---

## 1. 日志是什么 / 目录结构

**FARM = Field-Accessible Reliability Metrics**,希捷专有"现场可读可靠性指标",比标准 SMART (CrystalDiskInfo 约 30 项) 详细得多,关键差异是**把指标拆到每个磁头**。

本技能处理的是 **FARM (ATA/SATA) 日志的单帧导出**,按子目录组织 (每盘一个目录,目录名不限——脚本递归遍历、只认里面的 `*_FARM_*.{json,txt}`,IP/SN 从文件名解析而非目录名),每盘两种来源 (文件名以现场主流的时间戳前置格式列出;SN 前置的旧格式脚本亦兼容):
| 文件 | 工具 | 规模 | 内容 |
|---|---|---|---|
| `<ts>_<SN>_FARM_<ip>_<dev>.json` | openSeaChest_LogParser | ~1178 行 | **最全**:整盘 + 完整逐头通道/H2SAT/FAFH/逐头不可恢复读/Flash LED 事件/Depop |
| `<ts>_<SN>_FARM_<ip>_<dev>_disktool.txt` | 华为 disktool | ~590 行 | **关键子集 (约 40%)**:整盘指标 + 部分逐头块 (飞高/MRR/TMD/DOS刷新),无逐头重分配/不可恢复读、无 Flash LED、无型号/Depop |

> [!NOTE]
> 父目录 (如 `log/`) 下除盘目录外,可能还混有其它非 FARM 内容 (如主机 OS 日志、采集脚本目录)——脚本递归遍历所有子目录、只认 `*_FARM_*.{json,txt}`,其余自动跳过;盘目录名不限,IP/SN 均从**文件名**解析而非目录名。

> [!NOTE]
> **与 SM2 日志的根本区别**:SM2 是**时间序列** (每磁头一个约 1000 条按 `poh` 排序的 CSV);FARM 是**单帧快照** (一份 `copy 0`)。FARM 的 JSON 里虽出现多个同名 "copy 0" 键,实为重复键,Python 解析后只保留一份——**没有第二帧可对比趋势**。因此本技能不做"时间方向"判定。

**机型识别**:18 磁头 + `ST20000NM002H` = **Mach.2 双致动器** (如 Exos 2X18),`Drive Recording Type` 区分 CMR/SMR。

---

## 2. 数据源纪律 (json 优先 / txt 兜底)

> [!WARNING]
> **必须先确认数据源是 json 还是 txt!**
> json 是 txt 的**超集**——约 525 个字段仅 json 有。脚本默认 json 优先、txt 兜底,并在报告"数据源"列标注。
> - **json 能做、txt 不能做**的判定:逐头重分配定位、逐头不可恢复读 (`Cum Lifetime Unrecoverable by head`)、Flash LED (固件 Assert) 事件、Depop 状态、型号识别、CTO 5s/7.5s 分档。
> - txt 来源时,故障常只能判到**"整盘介质退化(未定位到磁头)"**,且第 2/7 类降级。若结论关键,应索取该盘 json 重新分析。

脚本用 `--source {auto,json,txt}` 控制:`auto` (默认) = json 优先;`txt` 用于测试降级路径。两路均把字段归一化成同一套内部字段名,使下游判定逻辑只认一套名字 (见第 4 章映射)。

---

## 3. 八类故障部位 ↔ FARM 字段映射 (能不能分析)

按"故障部位 + 失效机理"对照标准 SMART,列出 FARM 实际可用字段与覆盖度。
**覆盖度**:✅ 可分析 (≥ 标准 SMART) / ⚠️ 部分可分析 / ❌ 不适用。

| # | 故障部位 | 标准 SMART | FARM 可用字段 (json) | 覆盖度 |
|---|---|---|---|---|
| 1 | **盘片表面 / 坏扇区** | `5`,`197`,`198` | `Reallocated Sectors`、`Reallocated Candidate`、`Unrecoverable Read Errors`、逐头 `Reallocated Sectors by Head`、逐头 `Reallocation Candidate by Head`、`Cum Lifetime Unrecoverable by head {Unique,Repeating}` | ✅ 优于标准 (逐头) |
| 2 | **磁头 / 读写通道 / ECC** | `1`,`187`,`195` | 逐头 `Fly height clearance delta {outer,middle,inner}` (飞高/TFC)、`MR Head Resistance`+`Second MR Head Resistance` (MRR)、`Current H2SAT {amplitude,iterations,asymmetry,bits in error}`、`Bit Error Rate by Head` | ✅ 远优于标准 (逐头逐区) |
| 3 | **机械 / 马达 / 伺服** | `3`,`4`,`10`,`192` | `Mechanical Start Failures`、`Spin Retry Count`、`Helium Pressure Threshold Tripped`、`Current Motor Power`、`Servo Status`、逐头 `Number of TMD`、`Velocity Observer`、`High Priority Unload Events`、逐头 `DOS Write Refresh Count`+`DOS Write Count Threshold`(→"磁头/组件退化"确定性规则,见第 6/7/9 章) | ⚠️ 部分 (无 spin-up time 序列) |
| 4 | **接口 / 传输 / 线缆** | `188`,`199` | `Interface CRC Errors` (≈`199`,**ATA 有**)、`CTO Count Total`+`Over 5s`+`Over 7.5s` (≈`188`)、`Hardware Reset count` | ✅ 优于 SAS (含 CRC) |
| 5 | **温度 / 环境 / 振动** | `190`,`191`,`194` | `Current/Highest/Lowest Temperature`、`Time In Over Temperature`、`Over-Limit Shock Events`、`Current Relative Humidity`、`High Fly Write Count`、`RV Absolute Mean` | ✅ 优于标准 (含湿度) |
| 6 | **寿命 / 工况** | `9`,`12`,`241`,`242` | `Power on Hour`、`Power Cycle count`、`Rated Workload %`、`Total Read/Write Commands`、`Logical Sectors Read/Written`、`Head Load Events` | ✅ |
| 7 | **固件 / 服务区 / 内部** | 深度日志核心 | `Total Flash LED (Assert) Events` + `Flash LED Event 0..7` 事件表、`Has Drive been Depopped`、`Depopulation Head Mask`、`Uncorrectable errors`、`G-List Reclamations` | ⚠️ 部分 (无离散 translator/assert 深度记录;**TXT 完全缺失,降级**) |
| 8 | **SSD 特有** | 磨损 / PE / TBW | — | ❌ 不适用 (本类为机械盘) |

**一句话总结**:FARM 把第 1/2/4/5/6 类做到**优于或等于**标准 SMART (且逐头),第 3/7 类**部分**覆盖 (第 7 类 TXT 还要再降级),第 8 类对 HDD 不适用。

---

## 4. json ↔ txt ↔ 标准 SMART 三方字段映射

脚本内部字段名 (`m["..."]`) 与两种数据源、标准 SMART 的对应。**"TXT 有?"列为否的字段,txt 来源时拿不到。**

| 内部字段 | openSeaChest JSON 键 | 华为 disktool TXT 键 | TXT 有? | ≈SMART |
|---|---|---|---|---|
| `model` | `Model Number` | — | ❌ | — |
| `firmware` | `Firmware Rev` | `Firmware Revision` | ✅ | — |
| `heads` | `Number of heads` | `Number of Heads` | ✅ | — |
| `rec_type` | `Drive Recording Type` | — | ❌ | — |
| `poh` | `Power on Hour` | `Power-on Hours` | ✅ | 9 |
| `unrec_read` | `Unrecoverable Read Errors` | `Number of Unrecoverable Read Errors` | ✅ | 187/198 |
| `realloc` | `Number of Reallocated Sectors` | `Number of Reallocated Sectors` | ✅ | 5 |
| `realloc_cand` | `Number of Reallocated Candidate Sectors` | `Number of Reallocated Candidate Sectors` | ✅ | 197 |
| `crc_err` | `Number of Interface CRC Errors` | `Number of Interface CRC Errors` | ✅ | 199 |
| `cto_total` / `cto_5s` / `cto_75s` | `CTO Count Total/Over 5s/Over 7.5s` | `CTO Count Total/Over 5s/Over 7.5s` | ✅ | 188 |
| `flash_led` | `Total Flash LED (Assert) Events` | `Total Flash LED (Assert) Events` | ✅(仅计数) | — |
| `temp_max` | `Highest Temperature` | `Highest Temperature in Celsius` | ✅ | 194 |
| `shock` | `Over-Limit Shock Events Count(Raw)` | `Over-Limit Shock Events Count(...191...)` | ✅ | 191 |
| `humidity` | `Current Relative Humidity` (单位 %) | `Current Relative Humidity(in units of .1%)` (需 ÷10) | ✅ | — |
| `depopped` | `Has Drive been Depopped` | — | ❌ | — |
| `h_realloc[i]` | `Number of Reallocated Sectors by Head i` | — | ❌ | — |
| `h_cand[i]` | `Number of Reallocation Candidate Sectors by Head i` | — | ❌ | — |
| `h_cum_uniq[i]` | `Cum Lifetime Unrecoverable by head i → Unique` | — | ❌ | — |
| `h_mrr[i]` | `MR Head Resistance from Head i` | `MR Head Resistance ... by Head` 块 | ✅ | — |
| `h_fafh_{od,md,id}[i]` | `Fly height clearance delta {outer,middle,inner} by Head i` | `Applied fly height clearance delta ... Diameter {0-Outer,2-Middle,1-Inner}` 块 | ✅ | 189 |
| `h_dos_refresh[i]` | `DOS Write Refresh Count by Head i` | `#DOS Write Refresh Count` 块(标题**不含** "by Head") | ✅ | — |
| `h_dos_thresh[i]` | `DOS Write Count Threshold by Head i`(已核对真实键名) | `#DOS Write Count Threshold` 块 | ⚠️ 常缺失 | — |
| `h_velobs[i]` | `Velocity Observer by Head i` | `#Velocity Observer over last 3 SMART Summary Frames by Head` 块 | ✅ | — |
| `h_tmd[i]` | `Number of TMD by Head i` | `#Number of TMD over last 3 SMART Summary Frames by Head` 块 | ✅ | — |

> [!NOTE]
> **单位/进制清洗** (脚本已自动处理):TXT 湿度为 `.1%` 需除以 10;部分 RAW 值为十六进制字符串 (`0x...`) 需转十进制;数值字段可能带引号 (`'42.00'`)。

> [!WARNING]
> **`DOS Write Count Threshold` 常缺失**:真实 dump 中该逐头字段**并非总是存在**——JSON 里部分盘有、部分盘无;disktool TXT 则**普遍不含**此块。缺失时用户规则中 "DOS Write Count Threshold 非0 且 DOS Write Refresh Count > 1000×Threshold" 这一半**无法评判**(脚本静默跳过该头这一判据,不误触发也不报错),此时组件退化判定只能靠 `Velocity Observer > 200` 那一半。因此**同一块盘 JSON 与 TXT 的组件退化占比可能不同**(JSON 有阈值→占比更全,TXT 无阈值→常偏低);JSON 优先即为此。
>
> **TXT 逐头块解析**:disktool TXT 的逐头块是"一行 `#块标题`(无冒号值)+ 若干 `headN : 值` 行"。绝大多数块标题含 "by Head",但 `#DOS Write Refresh Count` **不含**——脚本 `load_txt()` 已改为"任何无值的 `#标题` 行都开启逐头块",故此块能正确捕获。
>
> **FAFH 单位差异**:disktool TXT 的飞高值单位为"千分之一埃",与 JSON 已换算值**量纲不同**(TXT 数量级更大);因 FAFH 只做**同盘逐头相对离群**(中位×2.0),量纲差异不影响判定,两源各自内部比较即可,不可跨源比绝对值。

---

## 5. 关键字段字典

### 5.1 整盘级
| 字段 | 含义 | 判读重点 |
|---|---|---|
| `Serial Number` / `Model Number` / `Firmware Rev` / `Number of heads` | 身份与配置 | 18 头 + ST20000NM002H = Mach.2 双致动器 |
| `Drive Recording Type` | 记录方式 | CMR / SMR;SMR 写放大特性不同 |
| `Power on Hour` | 累计上电小时 | 工况/寿命参考 (注:无时间序列,仅作单点) |
| `Unrecoverable Read Errors` | 不可恢复读错误 (已上抛主机) | **核心指标**:正常应为 0;> 0 表示物理坏道已影响业务层 |
| `Number of Reallocated Sectors` | 整盘重分配扇区 | **核心指标**:> 0 即已动用备用扇区;可与逐头数对账定位磁头 |
| `Number of Reallocated Candidate Sectors` | 重分配候选 (已检出待处理坏道) | **活跃度近似**:> 0 → 退化进行中;= 0 → 暂稳 |
| `Interface CRC Errors` | 接口链路误码 | > 0 指向线缆/背板/HBA (ATA FARM 有此项,优于 SAS) |
| `CTO Count Total / Over 5s / Over 7.5s` | 命令超时累计及分档 | > 5s/7.5s 的超时严重,会引起上层 SCSI 报错 |
| `Over-Limit Shock Events Count` | 过限冲击事件 | 机柜振动/搬运冲击的旁证 |
| `Helium Pressure Threshold Tripped` | 氦气压力阈值触发 | 氦气盘**泄漏 = 失效级**,非零须高度警惕 |
| `Total Flash LED (Assert) Events` | 固件断言事件 | > 0 = 固件异常断言 (失效级旁证) |
| `Has Drive been Depopped` / `Depopulation Head Mask` | 是否已屏蔽磁头降级 | True 说明已做过磁头级降级 |

### 5.2 逐磁头级 —— 健康判定主战场 (仅 json 完整)
| 字段 | 含义 | 判读重点 |
|---|---|---|
| `Number of Reallocated Sectors by Head` | 该磁头重分配数 | **核心**:把整盘坏道定位到具体磁头 |
| `Number of Reallocation Candidate by Head` | 该磁头候选坏道 | 该头是否仍在活跃退化 |
| `Cum Lifetime Unrecoverable by head {Unique,Repeating}` | 该磁头累计不可恢复读 | **核心**:逐头的"已伤到业务"硬证据 |
| `Fly height clearance delta {outer,middle,inner}` | 飞高/TFC 间隙偏移 (外/中/内圈) | ⚠️ **出厂校准量,逐头天然差异大** (种群中位 43~323 不等)。**单独离群只算关注**,须与同头坏道共振才升退化 |
| `MR Head Resistance` / `Second MR Head Resistance` | 磁阻读头电阻 (MRR) | `0xFFFF` = 磁头开路 (硬故障);偏离种群中位为边缘磁头。注:本批 dump 中常为 0 (未填充) |
| `Current H2SAT {amplitude,iterations,asymmetry}` | 读通道译码努力/信号 | 有值时:幅度偏低/迭代偏高 = 读通道劣化。本批 dump 中多为 0 |
| `DOS Write Refresh Count` / `Number of TMD` | 后台刷新 / 热机械抖动 | 辅助佐证该磁头的工作压力与伺服状态 |
| `Velocity Observer` | 磁头速度观测(伺服) | ⚠️ **确定性规则**:> 200 直接判该头"组件退化"(见第 6/7/9 章),不属于种群相对/关注-升级模式,是绝对阈值 |
| `DOS Write Count Threshold` | 该磁头 DOS 写刷新次数门限 | ⚠️ **确定性规则**:非 0 且 `DOS Write Refresh Count` > 1000×该值 → 判该头"组件退化"(见第 6/7/9 章) |

> [!NOTE]
> **判读心法 —— 种群相对法**
> 同一块盘的 $N$ 个磁头处于相同工艺、负载和环境,**横向互比**寻找离群磁头,比绝对阈值更灵敏。脚本对 FAFH 取每头 OD/MD/ID 的最大绝对偏移做中位数 × 比例的离群判定 (阈值 `OUTLIER_HI=2.0`,且 FAFH 单独离群只记 sev=1)。

---

## 6. 临界值表

| 指标 | 正常范围 | 关注阈值 | 异常 / 临界阈值 |
|---|---|---|---|
| 温度 | < 50℃ | ≥ 50℃ (`TEMP_WARN`) | ≥ 60℃ (`TEMP_CRIT`,FARM 标定 Max=60) |
| `Over-Limit Shock` | 较低 | ≥ 100000 (`SHOCK_WARN`) | — |
| 湿度 | 正常 | ≥ 80% (`HUMID_WARN`) | — |
| `CTO Count Total` | 0 | ≥ 1 (`CTO_WARN`) | 含 >5s/7.5s 的超时 |
| `Interface CRC Errors` | 0 | — | **任意 > 0** (线缆/背板) |
| 整盘 / 逐头 `Reallocated Sectors` | 0 | — | **> 0** (`HEAD_REALLOC_WARN=1`) |
| `Reallocated Candidate` | 0 | — | **> 0 → 退化进行中** |
| `Unrecoverable Read Errors` / 逐头不可恢复读 | 0 | — | **任意 > 0** |
| 逐头 `FAFH` 偏移 | 处于同族中位附近 | 超出中位 × 2.0 (`OUTLIER_HI`,**仅关注**) | 与同头坏道共振 → 退化 |
| `MR Head Resistance` | 处于同盘正常区间 | 偏离正常范围 | `= 0xFFFF` (磁头开路) |
| `Flash LED Assert` / `Helium Tripped` | 0 | — | **任意 > 0 → 失效级** |
| 逐头 `Velocity Observer` | ≤ 200 | — | **> 200 (`VELOBS_WARN`) → 该头"组件退化"(绝对阈值,非关注)** |
| 逐头 `DOS Write Refresh Count` | ≤ 1000×`Threshold` | — | **`Threshold` 非0 且 `Refresh Count` > 1000×`Threshold` (`DOS_THRESH_MULT`) → 该头"组件退化"** |
| 组件退化磁头占比(占全盘磁头数) | 0% | — | **≥ 50% (`HEAD_DEGRADE_RATIO_CRIT`) → 终态"损坏",覆盖其它类别;<50%(且>0)→ 终态"健康"+DEPOP处置(见第 9 章)** |

> [!NOTE]
> 阈值集中定义在 `scripts/analyze_farm.py` 顶部 (如 `TEMP_*`、`SHOCK_WARN`、`CTO_WARN`、`OUTLIER_HI`、`HEAD_REALLOC_WARN`),针对不同机型分析时可按需微调。

---

## 7. 健康判定矩阵与故障模式 (单快照版)

根据"受影响磁头数 × 候选数活跃度 × 接口/固件异常 × 最高严重度"进行整盘归类。**与 SM2 不同:这里没有趋势,活跃度用候选数近似。**

| 故障模式 | 物理与遥测特征 | 最终判定 | 延寿可行性评估 |
|---|---|---|---|
| **健康** | 所有磁头重分配=0、不可恢复读=0,FAFH 无显著离群,环境指标正常 | 健康 | — |
| **轻度异常 / 早期预警** | 个别磁头 FAFH 校准离群,或单项分类达"关注" (如 CTO=少量、shock 偏高),无介质损伤 | 亚健康 | **高** (维持监控即可) |
| **单磁头退化** | 仅 1 个磁头有介质损伤 (重分配/不可恢复读),其余健康 | 退化 | **退化进行中** (候选>0):可行性低,建议磁头级降级或换盘;<br>**暂稳** (候选=0):可行性高,RAID 兜底可中期留用 |
| **多磁头介质退化** | ≥ 2 个磁头有介质损伤 | 严重退化 | **中等偏低**,尽快备份并换盘 |
| **整盘介质退化 (未定位到磁头)** | 整盘重分配/不可恢复读很大,但逐头数全 0 (本帧未填充逐头分布,或为 txt 来源) | 退化 | 备份数据;候选>0 倾向换盘,候选=0 可加强监控 |
| **某类别异常** | 无具体磁头失效,但盘级某项分类 (如接口 CRC、温度) 达"退化" | 严重异常 | 按故障类别特定处置 (改环境/换线) |
| **固件/硬件级失效** | `Flash LED Assert` > 0 / `Helium Tripped` > 0 / ≥ 2 头 MRR=0xFFFF | 失效 | **低**,优先带外重启 + 备份 + 换盘 |
| **磁头/组件退化(确定性规则,覆盖以上所有行)** | 存在 `Velocity Observer`>200 或 `DOS Write Refresh Count`>1000×`Threshold` 的磁头 | 占比≥50% → **损坏**;占比<50%(且>0) → **健康** | 不是"可行性评估",是固定处置文案:见第 9 章。命中时**直接作为终态结论输出,不再综合本表以上其它行的判定** |

> [!NOTE]
> **"退化进行中 vs 暂稳"判据 (单快照近似,替代 SM2 的趋势)**
> 满足以下任一即归为**退化进行中**,否则为**暂稳**:
> - 整盘 `Reallocated Candidate Sectors` > 0
> - 任一磁头 `Reallocation Candidate by Head` > 0
>
> 退化进行中的磁盘不能轻易留用;暂稳状态的磁盘可在 RAID 冗余保护下中期观察。

> [!IMPORTANT]
> **指标组合研判原则**
> 单一指标异常时故障概率约 30%–40%;而**第 1 类 (重分配/坏扇区) 与第 2 类 (不可恢复读) 同时非零**时,设备失效概率升至约 76%——这是最应优先安排数据备份和换盘的故障组合。
> **FAFH 例外**:飞高 clearance delta 单独离群**不计入**上述组合,因其逐头校准差异天然大 (实测种群中位 43~323),单独出现不代表退化。

---

## 8. 标记值 / 常量

| 十六进制 | 十进制 | 含义与判读建议 |
|---|---|---|
| `0xFFFF` | 65535 | 满量程/溢出,通常代表磁头开路或传感器饱和 (确定硬件故障) |
| `0xDEAD` | 57005 | 固件标志值,代表"未校准 / 无效数据" |

> [!NOTE]
> 与 SM2 不同:本批 FARM 日志中**未观察到** `OTFErr=0x6868` 之类的固件固定常量;若在 H2SAT/MRR 字段中遇到 `0xFFFF`/`0xDEAD`,按上表处理。

---

## 9. 处理方法

- **健康 / 亚健康**:常规或周期性监控。重点监控逐磁头重分配增量、FAFH 离群是否与坏道共振。由于整盘级指标可能滞后,单磁头退化只在逐头遥测中可见 (须 json)。
- **单磁头退化 (退化进行中)**:确认 RAID 冗余 → 优先尝试**磁头级降级** (希捷专有工具屏蔽故障磁头,整盘容量减少约 $1/磁头数$) → 若无专用工具则**换盘**。若已导致文件系统只读/损坏,先运行 `xfs_repair` 再重新挂载。
- **单磁头退化 (暂稳)**:RAID 冗余下中期留用并加强监控。**触发退出 (满足任一须立即换盘/降级)**:故障磁头重分配再次增长;出现新的候选坏道;出现新的不可恢复读;`CTO` 增加;RAID 组内其它盘出现 Predicted Failure。
- **多磁头介质退化**:立刻抢救数据 → `xfs_repair` 修复 → 通常建议尽快换盘。
- **整盘介质退化 (未定位到磁头)**:若为 txt 来源,**先索取 json** 尝试定位到磁头;确实无逐头分布时,按整盘严重度处置 (候选>0 倾向换盘)。
- **接口 / 传输类异常** (CRC>0 / CTO 多):优先排查连接线缆、背板或 HBA (重插拔、换槽位)。若伴随重分配增长,则按介质退化对待。
- **温度 / 振动类异常**:改善机柜散热、优化减震后重测,通常不是盘体本身坏道。
- **固件 / 硬件级失效** (Flash LED Assert / 氦气泄漏 / 多头开路):磁盘多已无响应,通过 IPMI/带外管理电源重启,恢复后备份并换盘,排查是否需升级固件。
- **机群级处置优先级**:按"机群汇总表""差 → 好"顺序处理。脚本同评级下按"不可恢复读 + 整盘重分配 + 候选×10 + 退化头数×1000 + 活跃×5000"加权排序,优先处置失效与退化活跃度高、受影响磁头多的磁盘。
- **磁头/组件退化(确定性规则,占比≥50%,判定"损坏")**:不建议修复,建议备份数据后报废更换硬盘。
- **磁头/组件退化(确定性规则,占比<50%,判定"健康")**:
  1. 建议重新挂载硬盘:
     ```bash
     # 按设备名卸载
     umount /dev/sdx
     # 重新挂载 mount,格式:mount 设备路径 挂载目录
     mount /dev/sdx /mnt/data
     ```
  2. 建议将退化的磁头通过 DEPOP 隔离:
     ```bash
     # 设备待机、磁头归位
     seachest_power --standbyImmediate -d /dev/sdb
     # 休眠锁磁头
     seachest_power --sleepImmediate -d /dev/sdb
     ```
  上述两条为固定处置文案(脚本 `ACTION_COMPONENT_SCRAP` / `ACTION_COMPONENT_DEPOP` 常量),命中时**直接作为该盘的最终结论与处置建议输出,覆盖本章其它按类别给出的处置方法**。

---

## 10. 与主机日志联动

FARM 是磁盘内部的硬件遥测指标,并不包含文件系统或具体上层业务的影响。当需要诊断上层 I/O 错误或挂载卷挂死时,必须联动操作系统内核日志:

- **主机日志关键词** (`dmesg` / `/var/log/messages`):`Medium Error`、`Unrecovered read error`、`critical medium error`、`I/O error, dev sdX`、`command timed out`、`XFS ... metadata I/O error`、`xfs_do_force_shutdown`、`Shutting down filesystem`。
- **典型链路传导**:`某磁头介质/飞高退化 (FARM 定位到具体 headN)` → `产生不可恢复读错误/命令超时` → `操作系统上抛 SCSI I/O 错误` → `XFS 文件系统元数据损坏` → `触发文件系统强制 shutdown (只读)`。
- **应急恢复**:仅 `umount` 不能修复损坏的元数据;须在卸载状态下运行 `xfs_repair` 修复后方可重新挂载读写 (前提是磁盘仍能响应 SCSI 且仅有元数据层面的损坏)。

---
