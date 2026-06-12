# SM2 / FARM 日志字段与判读参考(多盘 · 8 类故障部位)

希捷(Seagate)硬盘 **SM2 / FARM 级遥测日志**的字段字典、8 类故障部位映射、临界值、
健康判定矩阵与处理方法。配合 `scripts/analyze_sm2.py` 使用:脚本做确定性提取与分类,本文件解释"为什么这么判"。

> **先读方法论再查字段。** 专家级的判断逻辑(部位→机理→严重度→趋势→决策)、依据与整体流程见
> `SKILL.md` 的「专家判读方法论(判断逻辑 · 依据 · 流程)」一节;本文件是那套逻辑落到**具体字段、阈值与映射**的查询手册。

## 目录
- [1. 日志是什么 / 多盘结构](#1-日志是什么--多盘结构)
- [2. 时间方向纪律(最易错)](#2-时间方向纪律最易错)
- [3. 八类故障部位 ↔ SM2 字段映射(能不能分析)](#3-八类故障部位--sm2-字段映射能不能分析)
- [4. 关键字段字典](#4-关键字段字典)
- [5. 临界值表](#5-临界值表)
- [6. 健康判定矩阵与故障模式](#6-健康判定矩阵与故障模式)
- [7. 标记值 / 常量](#7-标记值--常量)
- [8. 处理方法](#8-处理方法)
- [9. 与主机日志联动](#9-与主机日志联动)
- [10. 资料来源](#10-资料来源)

---

## 1. 日志是什么 / 多盘结构

**FARM = Field-Accessible Reliability Metrics**,希捷专有"现场可读可靠性指标",
比标准 SMART(CrystalDiskInfo 约 30 项)详细得多,正常可用 `smartctl -l farm /dev/sdX` 读取。
本类 **SM2** 是更详尽的工厂变体,关键差异是**把指标拆到每个磁头**单独成文件。

**单盘** = 一组同序列号(SN)的文件:
| 文件 | 数量 | 内容 |
|---|---|---|
| `<SN>_SMART_<ts>_SLog.txt` | 1 | 整盘级(电压/温度/振动/超时/马达/缺陷表… 约 100 列) |
| `<SN>_SMART_<ts>_head{0..N}.txt` | N | 逐磁头(飞高/磁阻/读错误/译码迭代/伺服… 约 48 列) |

**多盘(一台服务器)**:把多块盘的文件放在一个父目录(可有子目录)。脚本**递归扫描、按文件名 SN 前缀分组**成多块盘,
逐盘分析后给出**机群汇总表**(按健康度差→好排序)。每个文件是 CSV 时间序列(常见 1000 条记录,首行表头)。

机型识别:18 磁头 + 双致动器 = **Mach.2(如 Exos 2X18 / ST20000NM002H)**,H0–H8 属致动器0、H9–H17 属致动器1。

---

## 2. 时间方向纪律(最易错)

记录用 `poh`(power-on 累计计数)排时间,**不是日历时间**。**`poh` 最大 = 最新快照。**
多数导出是**倒序**(record 0 = 最新)。

> **必须按 旧→新 解读趋势。** 否则会把"`g_list` 0→1100 持续增长(在恶化)"读成
> "1100→0 下降(自愈)",健康结论彻底反掉——真实事故报告里出现过该误判。
> 自检:`g_list` 与 `command_timeout` 是单调累计计数器,正常只增不减;若你的解读出现它们"下降",
> 几乎一定是时间方向读反了。脚本已统一按 `poh` 升序计算,输出 `方向: grow/shrink/flat` 即旧→新。

---

## 3. 八类故障部位 ↔ SM2 字段映射(能不能分析)

按"故障部位 + 失效机理"对照标准 SMART,列出 SM2 实际可用字段与覆盖度。
**覆盖度**:✅ 可分析(≥标准SMART) / ⚠ 部分可分析 / ❌ 不适用。

| # | 故障部位 | 标准 SMART | SM2 可用字段 | 覆盖 |
|---|---|---|---|---|
| 1 | **盘片表面/坏扇区** | 5 / 196 / 197 / 198 | 逐头 `g_list`(增长缺陷表≈重分配)、`vis_rd_err`(不可恢复读≈198)、`arre`(自动重分配读事件)、`initial_rd_err`;盘级 `g_list`、`rsvd_zone_scan_count` | ✅ 优于标准(逐头) |
| 2 | **磁头/读写通道/ECC** | 187 / 1 / 195 / 7 / 189 | 逐头 `hid_rd_err`/`vis_rd_err`/`initial_rd_err`(≈187/1)、`iterOD/MD/ID`(LDPC 译码迭代≈ECC 努力/195)、`ampOD/MD/ID`(读信号幅度)、`fafh_*`(飞高/TFC≈189 高飞写)、`head_resistance`/`mr2_head_resistance`(MRR 磁头电阻,标准 SMART 无)、`bad_sample`、`berp_rec_error`、`asymRead`、`bieOD/MD/ID` | ✅ 远优于标准(逐头逐区) |
| 3 | **机械/马达/伺服** | 3 / 10 / 4 / 192 / 193 | 盘级 `motor_power`(主轴功率)、`power_cycle_cnt`;逐头 `servo_swd_*`、`vel_no_tmd`/`vel_obs`、`oc_limit4/9/14`(执行器过流限幅) | ⚠ 部分(无 spin-up time / spin-retry / load-unload 计数) |
| 4 | **接口/传输/线缆** | 199 / 188 | 盘级 `command_timeout_9`(≈188)、`host_reset`、`hard_reset` | ⚠ 部分(SAS 盘无 UDMA CRC 项) |
| 5 | **温度/环境/振动** | 194 / 190 / 191 | 盘级 `temperature`/`_min`/`_max`、`rv`/`rv_max`(旋转振动)、`lv_Shock`、`humidity`/`_min`/`_max`(湿度,标准 SMART 无) | ✅ 优于标准(含湿度) |
| 6 | **寿命/工况** | 9 / 12 / 240 / 241 / 242 | 盘级 `poh`、`power_cycle_cnt`、`read_cmd_*`/`write_cmd_*`、`idle_*`;逐头 `sector_rd`/`sector_wt` | ✅ |
| 7 | **固件/服务区/内部** | 深度日志核心 | `g_list` 规模、`rsvd_zone_scan_count`、`bms_smart_unlock_status`、`flag_wsv4`/`flags1`、`trigger_capture`、`fw_activity_idle_time`;**`command_timeout` × `g_list` 联动**(188 深层常指向服务区/转换表) | ⚠ 部分(无离散 SA/translator/固件 assert 事件记录,需原厂工具解析深度事件日志) |
| 8 | **SSD 特有** | 磨损/PE/TBW | — | ❌ 不适用(本类为机械盘:有磁头/飞高/主轴) |

**一句话**:SM2 把第 1/2/5/6 类做到**优于或等于**标准 SMART(且逐头),第 3/4/7 类**部分**覆盖,第 8 类对 HDD 不适用。
SM2 还**额外**提供标准 SMART 没有的维度:逐头 MRR 电阻、逐区飞高/TFC、译码迭代、信号幅度、伺服/执行器过流、湿度。

---

## 4. 关键字段字典

### 4.1 整盘级(SLog)
| 字段 | 含义 | 看什么 |
|---|---|---|
| `serial_number`/`firmware`/`head_cnt`/`sector_size` | 身份与配置 | 18 头=Mach.2 |
| `poh` | 累计上电计数 | 仅用于时间排序 |
| `temperature`(`_min`/`_max`) | 温度 ℃ | 过温诱发不稳 |
| `volt_5`/`volt_12` | 供电 | 越限→不稳 |
| `rv`/`rv_max`、`lv_Shock` | 旋转振动/冲击 | 高→寻道抖动 |
| `humidity`(`_min`/`_max`) | 湿度 | 环境(标准 SMART 无) |
| `command_timeout_9` | SCSI 命令超时累计(≈188) | **关键**:旧→新增长=盘在超时,会向上抛 SCSI 错误 |
| `host_reset`/`hard_reset` | 主机/硬复位 | 链路异常旁证 |
| `motor_power` | 主轴马达功率 | 机械/轴承旁证 |
| `rsvd_zone_scan_count` | 保留区扫描 | 服务区/缺陷管理活动 |
| `g_list` | 整盘增长缺陷表 | 注意:**整盘级可能恒为 0,而退化只在逐头可见**(标准 smartctl 易漏判) |

### 4.2 逐磁头级(headN)— 健康判定主战场
| 字段 | 含义 | 看什么 |
|---|---|---|
| `g_list` | 该磁头增长缺陷表(已重映射坏扇区累计) | **核心**:>0 即有物理缺陷;旧→新增长=活跃退化。重映射是往 g_list 里"加",不会减 |
| `vis_rd_err` | 可见/不可恢复读错误(已上抛主机) | **正常应为 0**;>0 = 真实坏道暴露到业务层 |
| `hid_rd_err`/`initial_rd_err` | 内部恢复/首次读错误 | 相对同族偏高=信号裕量下降早期信号 |
| `fafh_passclr_od/md/id`、`fafh_applied_*` | 飞高/TFC 间隙(OD/MD/ID=外/中/内圈) | **核心**:某头显著高于同族=盘面物理特性偏移;FAFH=0 瞬态=TFC 中断 |
| `iterOD/MD/ID` | LDPC 译码迭代次数 | **某头高于同族=低 SNR 下解码吃力**(读通道劣化) |
| `ampOD/MD/ID` | 读信号幅度 | 某头偏低=信号弱 |
| `head_resistance`(MRR1)/`mr2_head_resistance`(MRR2) | 磁阻读头电阻 | 0xFFFF=磁头开路/饱和(死);离族过远=边缘磁头 |
| `arre` | 自动重分配读事件 | 重映射活动量 |
| `oc_limit4/9/14`、`servo_swd_*`、`vel_*` | 执行器过流限幅 / 伺服 | 非零或离族=寻道/伺服压力 |
| `sector_rd`/`sector_wt` | 该头读写扇区量 | 工作负载,横向对比 |
| `bad_sample`、`berp_rec_error`、`*_scrubs`、`bg_*` | 坏采样/纠错恢复/巡检/后台 | 退化活跃度佐证 |
| `OTFErr` | On-The-Fly 错误 | **本类盘恒为 26728(0x6868),固件常量,忽略** |

**判读心法——种群相对法:** 同一块盘的 N 个磁头同工艺同负载,**横向互比**挑离群头,比绝对阈值更灵敏。
脚本对 `fafh`、`iter`(取高离群)、`amp`(取低离群)做中位数 × 比例的离群判定。

---

## 5. 临界值表

| 指标 | 正常 | 关注 | 异常/临界 |
|---|---|---|---|
| 温度 | < 50℃ | ≥ 60℃ | ≥ 70℃ |
| 5V / 12V | 4.75–5.25 / 11.40–12.60 | 接近边界 | 越限 |
| `rv_max` | 低 | ≥ 40 | ≥ 80 |
| 湿度 | 正常 | ≥ 80% | — |
| `command_timeout` | 0 且不增长 | 出现少量 | 旧→新持续增长 |
| 逐头 `g_list` | 0 | 出现且稳定/下降 | **>0 且旧→新增长**,或绝对值数百~上千 |
| 逐头 `vis_rd_err` | 0 | — | **任意 >0** |
| 逐头 `hid_rd_err` | 0 或极少 | 相对同族偏高 | 持续增长 |
| 逐头 FAFH 均值 | 同族中位 ±20% | 超中位 ×1.2 | 远超 / 频繁 =0 / 达标记值 |
| 逐头 `iter` 译码迭代 | 同族中位附近 | 超中位 ×1.2 | 显著高于同族 |
| 逐头 `amp` 信号幅度 | 同族中位附近 | 低于中位 ×0.8 | 显著低于同族 |
| `head_resistance`(MRR) | 落在同族区间 | 离族 | = 0xFFFF(开路) |
| `oc_limit*` 执行器过流 | 0 | 个别非零 | 多头非零/离族 |

> 阈值集中在 `scripts/analyze_sm2.py` 顶部(`TEMP_*`、`V*_*`、`RV_*`、`OUTLIER_HI/LO` 等),换机型可调。

---

## 6. 健康判定矩阵与故障模式

逐盘按"受影响磁头数 × 是否仍在恶化 × 命令超时/TFC失效 × 最高类别严重度"归类:

| 故障模式 | 特征 | 判定 | 延寿可行性 |
|---|---|---|---|
| **健康** | 全头 g_list=0、读错误=0、FAFH/iter 同族、环境正常 | 健康 | — |
| **轻度异常/早期预警** | 个别头/某类别仅"关注"级,无失效头 | 亚健康 | 高,监控即可 |
| **单磁头退化** | 仅 1 头在表面/通道异常,其余健康 | 退化(看活跃/暂稳) | 活跃→降级/换盘;暂稳→可中期留用 |
| **多磁头介质退化** | ≥2 头退化 | 严重 | 中,倾向换盘 |
| **某类别异常** | 无失效磁头,但某类(如接口/环境)达"退化" | 严重 | 按该类处置 |
| **固件死锁/多头 TFC 失效** | 多头 FAFH=0 或标记值 + 命令超时大量增长 | 失效 | 低,优先带外重启+换盘 |

**"活跃 vs 暂稳"判据(单磁头退化最关键):** 满足任一即活跃退化——
`g_list` 旧→新增长、`g_list` 最新值 >0、`vis_rd_err` >0、`command_timeout` 增长。
活跃=不能简单留用;暂稳=RAID 兜底下可中期观察。

**组合原则(对应实践经验)**:单看一项 Raw>0 故障概率约 30–40%;**第1类(g_list/vis_rd_err)+ 第2类(187 类不可恢复)同时非零并持续增长**,概率升至约 76%,是最该立即备份换盘的组合。增长速率越快越糟。

---

## 7. 标记值 / 常量

| 十六进制 | 十进制 | 含义 |
|---|---|---|
| `0xFFFF` | 65535 | 满量程/溢出,常表磁头开路或传感器饱和(故障) |
| `0xDEAD` | 57005 | 固件"未校准/无效数据" |
| `0x6868` | 26728 | 本类盘 `OTFErr` 固定常量,**非故障,忽略** |

---

## 8. 处理方法

- **健康/亚健康**:常规或加密监控。重点盯逐头 `g_list` 增长率、FAFH/iter 趋势——整盘 SMART(g_list 常为 0)看不出单磁头退化。
- **单磁头退化(活跃)**:确认 RAID 冗余 → 优先**磁头级降级**(希捷工具禁用该头,损约 `1/磁头数`)→ 无工具则**换盘**;若该盘已致文件系统损坏,先 `xfs_repair` 再挂载。
- **单磁头退化(暂稳)**:RAID 兜底下中期留用 + 强化监控;**退出条件(满足任一立即降级/换盘)**:该头 g_list 再增长 / 新 vis_rd_err、hid_rd_err / FAFH、iter 持续升高 / command_timeout 再增长 / RAID 组内出现 Predicted Failure。
- **多磁头介质退化**:抢救数据 → `xfs_repair` → 评估降级,通常尽快换盘。
- **接口/传输类**:先排查线缆/背板/HBA(SAS 重插、换槽位);若伴 g_list 增长则按服务区问题对待(见第7类)。
- **温度/振动类**:改善散热/减振,复测;非盘体本征故障。
- **固件死锁/多头 TFC 失效**:带内修复多无效,走 IPMI/带外重启恢复,随后换盘并排查/升级固件。
- **机群处置顺序**:按机群汇总表"差→好"排序,优先处理"失效/退化"盘;同等级看活跃度与受影响磁头数。

---

## 9. 与主机日志联动

SM2 是盘体内部遥测,不含文件系统/业务影响。接到 I/O 错误/卷宕机需主机内核日志:

- `dmesg`/`/var/log/messages` 关键词:`Medium Error`、`Unrecovered read error`、`critical medium error`、
  `I/O error, dev sdX`、`command timed out`、`XFS ... metadata I/O error`、`xfs_do_force_shutdown`、`Shutting down filesystem`。
- 典型链路:**某磁头介质/飞高退化(SM2 定位到 HN)→ 不可恢复读错误/命令超时 → SCSI I/O 错误上抛 → XFS 元数据损坏 → 文件系统强制 shutdown**。
- 恢复:`umount` 不修元数据;脏日志会让 `mount` 拒绝 rw;需 `xfs_repair -v /dev/sdX` 后再 `mount`(前提:盘仍能响应 SCSI 且仅元数据损坏)。

```bash
smartctl -l farm /dev/sdX        # 读 FARM 日志
smartctl -x /dev/sdX             # 扩展 SMART
dmesg | grep -iE 'xfs|medium error|i/o error|timed out'
xfs_repair -v /dev/sdX
```

---

## 10. 资料来源
- Seagate FARM Public Specification: Field-Accessible Reliability Metrics — https://studylib.net/doc/27859506/seagate-farm-specification
- SNIA, *Introduction to HDD Field Accessible Reliability Metrics* (SDC 2021) — https://www.snia.org/sites/default/files/SDC/2021/pdfs/SNIA-SDC21-Burnett-Shumway-Introduction-to-HDD-Field-Accessible-Reliability-Metrics.pdf
- toolhouse, *Seagate FARM-LOG* — https://www.toolhouse.de/en/support/knowledgebase/seagate-farm-log/
- Seagate, *MACH.2 Multi-Actuator Hard Drive* — https://www.seagate.com/innovation/multi-actuator-hard-drives/
- Backblaze, *Hard Drive SMART Stats*(5/187/188/197/198 与故障相关性)— https://www.backblaze.com/blog/hard-drive-smart-stats/
