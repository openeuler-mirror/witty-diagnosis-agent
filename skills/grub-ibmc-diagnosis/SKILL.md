---
name: grub-ibmc-diagnosis
description: >
  提供基于 iBMC 日志包的 GRUB 启动故障深度诊断分析能力，涵盖华为 (Huawei)、浪潮 (Inspur) 和新华三 (H3C) 等主流服务器厂商。
  当用户提到服务器无法开机、系统引导失败、GRUB 启动失败、停留在 grub rescue 界面、找不到内核 (kernel not found)、BIOS/UEFI 启动异常、RAID 故障导致无法启动，或者要求进行 iBMC 日志分析时，务必触发此技能。
  即使用户没有明确提到 "GRUB" 或 "iBMC"，只要说 "帮我分析这个日志包"、"服务器启动不了"、"机器起不来" 并附带了日志文件，也应当主动使用本技能进行根因定位。
---

# GRUB 启动故障 iBMC 日志诊断技能

## 概述

本技能基于 iBMC 带外管理日志，对服务器 GRUB 启动故障进行系统级根因定位。核心思路是：**iBMC 是故障的旁观者和记录者——它在 OS 完全失控时仍在运行，因此其日志是还原故障现场的唯一可靠来源**。

**适用场景**：服务器上电后无法进入 OS、卡在 GRUB rescue、Kernel Panic、initramfs 失败、磁盘不识别等一切启动链故障。

> **核心原则**：iBMC 日志包动辄数百 MB、包含数千个文件，绝不直接全量读取——那会导致信息过载、关键线索被淹没。标准做法是先用预处理脚本做关键字 + 时间过滤，将原始日志蒸馏成可分析的精华，再进行深度推理。每一个结论都必须有日志来源作为支撑。

---

## 工作流程总览

本技能的核心诊断流程分为以下 4 个阶段，请严格按顺序执行：

**Step 1：[厂商识别与知识加载](#step-1厂商识别与知识加载)**
- **动作**：通过询问用户或观察日志包目录结构，判断服务器厂商（Huawei / Inspur / H3C）。
- **产出**：确定对应的参考文档路径并阅读，了解该厂商日志的目录结构和独有文件（如 Inspur 的 `ErrorAnalyReport.json`，Huawei 的 `fdm_output`）。

**Step 2：[自动化脚本提取](#step-2自动化脚本提取信息蒸馏)**
- **动作**：将对应厂商的四个分析脚本复制到解压后的日志根目录，依次运行以提取高价值的故障线索。
- **产出**：生成四个分析切片：
  - `step1_timeline_builder.sh` → `timeline_xxx.txt`（建立宏观时间轴）
  - `step2_hardware_check.sh`   → `hardware_check_xxx.txt`（排查底层硬件/RAID故障）
  - `step3_grub_os_check.sh`    → `grub_os_check_xxx.txt`（抓取引导层原始报错现场）
  - `step4_summary.py`          → 终端输出（交叉汇总与分层定界结论）

**Step 3：[多维交叉推理](#step-3多维交叉推理深度分析)**
- **动作**：不要停留在单一脚本的报错上。将 Step2 提取到的线索拼接成“时间轴”，并从底层（硬件）向上层（GRUB/Kernel）逐级推导因果关系。
- **产出**：确认根因，形成证据链（要求：每一个结论必须有 ≥ 2 个不同日志来源相互印证，孤证不立）。

**Step 4：[标准诊断报告输出](#step-4标准诊断报告输出)**
- **动作**：按照给定的 Markdown 报告模板向用户输出最终诊断结论。
- **产出**：包含根因、故障链、排除项与置信度论证的结构化报告。

> **快速路径提示（Inspur 特有）**：若在执行 Step 2 时，发现 `step4_summary.py` 输出中 `ErrorAnalyReport.json` 已给出明确的 AI 故障分类和建议，可直接跳至 Step 3 进行交叉验证后输出报告，无需从头重建时间线。

---

## Step 1：厂商识别与知识加载

### 1.1 识别方法

根据用户告知或日志包目录特征判断，无法判断时直接询问：**"请问服务器是华为、浪潮还是H3C？"**

| 厂商 | 核心目录特征 | 参考文档 |
|------|------------|---------|
| **Huawei** | `OSDump/`、`AppDump/`、`LogDump/fdm_output`、`SensorAlarm/sel.db`、`StorageMgnt/RAID_Controller_Info.txt` | `references/huawei_ibmc.md` |
| **Inspur** | `onekeylog/log/`（含 `selelist.csv`、`ErrorAnalyReport.json`）、`onekeylog/sollog/`、`onekeylog/runningdata/` | `references/inspur_ibmc.md` |
| **H3C** | `LogDump/`（含 `PD_SMART_INFO_C*`、`LSI_RAID_Controller_Log`）、`AppDump/`、`RTOSDump/`、`OSDump/` | `references/h3c_ibmc.md` |

**识别后务必加载对应参考文档**，三个厂商的日志体系存在显著差异，必须用正确的路径和关键字才能定位。

### 1.2 三厂商核心能力差异（专家须知）

这些差异决定了分析路径和置信度——不同厂商的"杀手锏"文件完全不同：

| 能力 | Huawei | Inspur | H3C |
|------|--------|--------|-----|
| **AI 故障解析报告** | ❌ | ✅ `ErrorAnalyReport.json` ★最高价值 | ❌ |
| **MCA 寄存器（CPU/内存硬件错误根因）** | ❌ | ✅ `RegRawData.json` | ❌ |
| **BIOS 80 诊断码** | ❌ | ✅ `rundatainfo.log` | ❌ |
| **硬盘 SMART 逐盘文件** | ❌ | ❌ | ✅ `PD_SMART_INFO_C*` ★ |
| **LSI RAID 控制器原始日志** | ❌ | ❌ | ✅ `LSI_RAID_Controller_Log` |
| **PHY 误码率日志** | ❌ | ❌ | ✅ `LogDump/phy/` |
| **iBMC 内核黑匣子** | ❌ | ❌ | ✅ `RTOSDump/kbox_info` |
| **FDM 预告警（预测性维护）** | ❌ | ❌ | ✅ `fdm_pfae_log` |
| **系统日志按严重级别分文件** | ❌ | ✅ `emerg.log` ~ `info.log` | ❌ |
| **IERR 宕机截图** | ✅ `OSDump/img*.jpeg` | ✅ `IERR_Capture.jpeg` | ✅ `OSDump/img*.jpeg` |
| **SOL 串口日志** | ✅ `systemcom.tar` | ✅ `solHostCaptured.log` | ✅ `systemcom.tar` |
| **FDM 硬件故障权威判定** | ✅ `fdm_output` ★ | ❌ | ✅ `arm_fdm_log` |
| **电源黑匣子** | ✅ `ps_black_box.log` | ✅ `psuFaultHistory.log` | ✅ `ps_black_box.log` |

> **实践启示**：Inspur 的 `ErrorAnalyReport.json` 是三厂商中最直接的诊断起点；H3C 的 SMART 逐盘文件是磁盘预失效分析的最强工具；Huawei 的 `fdm_output` 是最权威的硬件故障判定依据，有 `Fault` 记录即可直接定性。

---

## Step 2：自动化脚本提取（信息蒸馏）

### 2.0 为什么要用脚本而不是直接分析日志

这是本技能最重要的工程决策，必须理解其背后逻辑：

**问题背景**：一个完整的 iBMC 日志包通常包含 500~3000 个文件、总体积 50~500 MB。如果直接读取，有三个致命问题：

1. **信息过载**：原始日志含大量正常运行记录，异常信号被淹没在噪音中，凭直觉浏览极易遗漏关键证据
2. **路径混乱**：不同厂商目录结构差异巨大，在不熟悉结构的情况下手工翻找效率极低
3. **上下文丢失**：孤立地读某个文件看不出故障时序，需要跨文件关联才能建立因果链

**解决方案：通过四个脚本进行日志蒸馏。**
针对 GRUB 及启动链相关的故障，排查的核心文件和维度如下（具体文件路径可参考 `references/` 下各厂商说明）：
- **底层硬件日志**：RAID 控制器状态文件（如 `RAID_Controller_Info`）、SMART 健康度文件、FDM/MCA 硬件故障诊断日志。
- **系统事件与时间轴**：SEL (System Event Log) 及告警摘要（如 `current_event`、`ErrorAnalyReport.json`），用于梳理重启与掉电事件。
- **启动层现场日志**：SOL 串口日志（如 `systemcom.tar`、`solHostCaptured.log`），**这是抓取 GRUB 报错原文及 Kernel Panic 堆栈最核心的数据源**。
- **系统配置与挂载**：对于 GRUB 配置验证，重点核查 `grub.cfg` 中 `root=UUID=XXXX` 与 `blkid` 输出是否一致，以及 `/etc/fstab` 挂载点是否存在拼写错误或不存在的块设备。

脚本的作用就是针对上述核心日志文件，用关键字过滤 + 时间窗口限制，将“数百MB的噪音”转化为“数KB的可分析精华”。每个脚本的产出物都是一个特定分析层次的证据切片。

### 2.1 四个脚本的分工逻辑

四个脚本严格遵循"先宏观建轴、再自底向上分层"的专家分析思路，不可乱序执行：

```
step1_timeline_builder   → 建立时间主轴
  │  目的：先搞清楚"什么时候出问题"，找到故障时间窗口
  │  产出：带时间戳的关键事件序列（SEL告警、BMC重启、BIOS配置变更等）
  │  分析价值：所有后续分析都要以这条时间线为锚点做关联
  │
  ▼
step2_hardware_check     → 硬件层扫描（P1层，优先级最高）
  │  目的：排查最底层故障——磁盘、RAID、控制器、电源
  │  产出：RAID状态 / SMART健康 / 存储通信异常 / SEL硬件告警
  │  分析价值：底层故障会伪装成GRUB错误，必须先排除或确认
  │  ⚠️ 专家经验：80%的"GRUB报no such partition"根因在这一层
  │
  ▼
step3_grub_os_check      → GRUB/OS层扫描（P3/P4层）
  │  目的：采集启动链上层的原始现场——控制台串口输出、内核崩溃信息
  │  产出：SOL串口日志（GRUB报错原文）/ 崩溃截图列表 / dmesg错误
  │  分析价值：这是GRUB层和内核层故障的第一手现场证据
  │  ⚠️ 专家经验：如果step2已确认硬件故障，step3的报错是果不是因
  │
  ▼
step4_summary            → 交叉汇总与分层判断
     目的：综合前三步所有发现，自动做分层归类，给出初步诊断方向
     产出：按 hardware/bios/grub/filesystem/kernel 五层的证据汇总表
     分析价值：消除单步分析的视角局限，暴露跨层关联
     ⚠️ Inspur特有：会优先解析ErrorAnalyReport.json，若有明确结论可直接采用
```

### 2.2 脚本执行指引

**准备工作**：确定厂商后，将 `scripts/[对应厂商]/` 目录下的四个分析脚本复制到用户提供的 iBMC 日志包解压后的根目录中（即与 `onekeylog/`、`AppDump/` 等目录同级），然后在该目录下依次执行这四个脚本。

以下为通用执行范例（以 Huawei 为例，其他厂商同理，只需替换路径与产物后缀）：

```bash
# step1：建立时间主轴（从 SEL / FDM / BMC 等日志提取关键事件）
bash step1_timeline_builder.sh  .   # 生成 timeline_huawei.txt

# step2：硬件层扫描（RAID状态 / Storage通信 / SEL磁盘告警）
bash step2_hardware_check.sh    .   # 生成 hardware_check_huawei.txt

# step3：GRUB/OS层扫描（提取控制台串口输出 / 宕机截图列表 / dmesg）
bash step3_grub_os_check.sh     .   # 生成 grub_os_check_huawei.txt

# step4：汇总分析（扫描所有关键文件，按层归类，给出初步诊断方向）
python3 step4_summary.py        .   # 直接打印到终端
```

### 2.3 输出回传规范

执行完成后，将以下内容提供给 AI 进行分析：

| 文件 / 输出 | 提供方式 | 说明 |
|-----------|---------|------|
| `timeline_*.txt` | **全文粘贴** | 通常 < 100 行，是时序分析的基础，必须完整 |
| `hardware_check_*.txt` | **全文粘贴**，若超 150 行则粘贴**全部**（硬件问题不能截断）| RAID 状态和 SMART 属性不能丢行 |
| `grub_os_check_*.txt` | 若超 200 行，粘贴**头 80 行 + 尾 80 行** | 头部含关键字匹配，尾部含最终失败现场 |
| `step4 终端输出` | **全文粘贴** | 汇总摘要，通常 < 80 行 |

> ⚠️ **截断原则**：step2（硬件层）的输出**不得截断**，RAID 状态和 SMART 属性任何一行缺失都可能导致根因判断偏差。step3 可按头+尾截断，因为异常通常在头部（关键字命中）和尾部（最终报错）。

### 2.4 信息完整性检查（分析前必做）

在进入 Step 3 分析之前，先核对以下关键证据文件是否存在。若缺失，主动告知用户补采，而不是在后续分析中遭遇证据缺口：

| 厂商 | 关键文件 | 缺失影响 | 补采方式 |
|------|---------|---------|---------|
| **Huawei** | `OSDump/systemcom.tar` | 无法分析 GRUB/内核层，置信度降级为"中" | 重新触发 iBMC 一键日志采集，确保 OS Dump 选项已勾选 |
| **Huawei** | `LogDump/fdm_output` | 无法获得硬件故障权威判定 | 同上 |
| **Inspur** | `onekeylog/log/ErrorAnalyReport.json` | 失去 AI 预诊断能力 | 同上 |
| **Inspur** | `onekeylog/sollog/solHostCaptured.log` | 无法分析控制台启动现场 | 同上 |
| **H3C** | `OSDump/systemcom.tar` | 无法分析 GRUB/内核层 | 同上 |
| **H3C** | `LogDump/PD_SMART_INFO_C*` | 无法评估磁盘物理健康状态 | 同上；或通过 iBMC WebUI → 存储 → 物理硬盘 查看 SMART 数据 |
| **全厂商** | SOL 串口日志 + OSDump 截图 **同时缺失** | 对 GRUB/OS 层完全无能见度，需升级为 **boot-forensics 场景** | 见特殊场景处理 |

---

## Step 3：多维交叉推理（深度分析）

收到脚本输出后，严格按以下方法论展开，不得跳步，不得在证据不足时下结论。

### 3.1 建立启动时间线

从所有脚本输出中提取**带时间戳的事件**，映射到启动链各阶段：

```
[上电]
  │
  ▼
[POST / BIOS 自检]          ← BIOS日志、SEL上电事件
  │  检查：内存、CPU、PCIe 设备识别
  ▼
[存储设备枚举]              ← RAID Controller日志、SEL硬盘事件
  │  检查：RAID卡识别、硬盘在位、逻辑卷状态
  ▼
[RAID 初始化]               ← RAID状态（Optimal / Degraded / Offline）
  │  ⚠️ Degraded 不一定阻止启动，Offline 通常会
  ▼
[Boot Device 选择]          ← BIOS 启动顺序配置
  │  检查：启动顺序、UEFI / Legacy 模式匹配
  ▼
[GRUB Stage1 加载]          ← SOL 串口日志（最关键）
  │  检查：MBR / GPT 引导扇区是否损坏
  ▼
[GRUB Stage2 / grub.cfg]   ← SOL 串口 + 截图
  │  检查：UUID 匹配、/boot 分区可读性
  ▼
[内核加载 vmlinuz]          ← SOL 串口
  │  检查：内核文件是否存在、签名验证是否通过
  ▼
[initramfs 初始化]          ← SOL 串口 + dmesg
  │  检查：initramfs 完整性、根文件系统挂载
  ▼
[系统启动 / 失败]           ← OSDump 截图、Kernel Panic 信息
```

**时间线标注规范**：每个事件标注 `[时间戳]`、`[日志来源:文件名]`、`[异常等级: INFO/WARN/ERROR/FAULT]`，并标记故障触发点 `[T=0]`——之前为因，之后为果。

### 3.2 故障分层定位（严格从底层到上层）

| 优先级 | 故障层次 | 典型症状 | 关键日志证据 |
|--------|---------|---------|------------|
| **P1** | **硬件层**（磁盘 / RAID / 电源 / 内存） | 磁盘掉线、RAID Degraded/Offline、ECC Uncorrected | SEL `Asserted`、FDM `Fault`、RAID `Offline`、SMART `Reallocated Sector` |
| **P2** | **固件层**（BIOS / UEFI） | 启动设备未找到、Secure Boot 阻断、启动顺序错误 | BIOS 日志 `config failed`、SEL `Boot Device Not Found` |
| **P3** | **引导器层**（GRUB） | `grub rescue>`、`no such partition`、`unknown filesystem` | SOL 串口输出、截图文件 |
| **P4** | **OS 层**（Kernel / initramfs） | Kernel Panic、`kernel not found`、initramfs 失败 | SOL 串口、dmesg、截图 |

> ⚠️ **铁律：底层故障会伪装成上层症状。** 磁盘掉线会让 GRUB 报 `no such partition`，但真正的根因在硬件层。必须从 P1 开始确认，不能被 GRUB 错误信息直接引导到 P3。

### 3.3 根因深挖（打破砂锅到底）

每发现一个异常，必须追问下一层：

```
磁盘 Offline
  → 是硬件坏道？（SMART Reallocated Sector 非零）
  → 是控制器通信中断？（StorageMgnt: comm lost / MCTP timeout）
  → 是电源波动触发？（ps_black_box 时间与 SEL 掉电事件对上了吗）
  → 是人工操作触发？（maintenance_log 是否有拔插记录）

GRUB 报 no such partition
  → /boot 分区 UUID 是否被修改？（grub.cfg UUID ≠ blkid 输出）
  → /boot 所在磁盘是否已 Offline？（向上追溯到 P1）
  → GRUB 是否安装在错误的磁盘上？（多盘环境常见）
  → 是否因分区表变更（fdisk/parted 操作）导致分区偏移？

RAID Degraded（降级）
  → 降级盘数量？（1 盘降级 RAID-1/5 通常仍可读，多盘降级可能 Offline）
  → 降级时间点是否与操作记录吻合？
  → 控制器是否已将逻辑卷 Offline（不同于 Degraded）？
  → 是否正在 Rebuild 中？（Rebuild 中读取性能极差但通常不阻止启动）
```

### 3.4 证据交叉验证要求

**每一个诊断结论必须有 ≥ 2 个不同日志来源相互印证，孤证不立。**

| 结论类型 | 最低证据要求 | 推荐印证组合 |
|---------|------------|------------|
| 磁盘物理故障 | 2 源 | SMART 异常 + SEL 硬盘告警（Predictive Fail / Drive Fault）|
| RAID 逻辑卷 Offline | 2 源 | RAID_Controller_Info `Offline` + StorageMgnt/LSI 日志操作记录 |
| BIOS 启动配置错误 | 2 源 | BIOS 日志 `config failed` + SEL `Boot Device Not Found` |
| GRUB 配置错误 | 2 源 | SOL 串口报错内容 + OSDump 截图中的文字 |
| Kernel Panic | 2 源 | SOL 串口 panic 信息 + dmesg / kbox_info |
| 电源触发的掉电重启 | 2 源 | ps_black_box 故障记录 + SEL 上电/断电事件时序 |

### 3.5 厂商专项分析策略

#### Huawei 专项分析路径
1. **首看 `fdm_output`**：华为最权威的硬件故障判定，`Fault` 条目直接指向故障组件，有即可定性
2. **次看 `current_event.txt`**：当前未清除告警，Critical/Major 级别必须全部解释
3. **`ps_black_box.log` 存在即告警**：代表有电源故障事件，时间点与启动失败高度相关
4. **`sel.db` 是时间线主轴**：所有硬件事件的时间戳都在这里，用于建立因果顺序
5. **`OSDump/systemcom.tar`**：解压后是 SOL 串口原始输出，GRUB/内核层分析的第一手资料

#### Inspur 专项分析路径
1. **首看 `ErrorAnalyReport.json`**：Inspur 独有的 AI 故障解析报告，直接输出故障分类和处理建议，三厂商中信息密度最高的单一文件，读到 `fault`/`recommend` 字段即可快速定向
2. **次看系统日志（按级别从高到低）**：`emerg.log` → `alert.log` → `crit.log` → `err.log`，`emerg.log` 有内容说明曾发生系统级崩溃
3. **`RegRawData.json` MCA 寄存器**：非零值说明 CPU/内存存在硬件错误，是内核 panic 的直接根因
4. **`solHostCaptured.log` 末尾 100 行**：最终失败现场，必查
5. **IERR 截图路径**：`onekeylog/log/CaptureScreen/IERR/IERR_Capture.jpeg`，优先提取文字

#### H3C 专项分析路径
1. **首看 `current_event.txt`（AppDump）**：当前告警全景
2. **次看 `arm_fdm_log`（LogDump）**：FDM 判定结果；`fdm_pfae_log` 含预告警，可能在故障前已有预兆
3. **SMART 逐盘分析**：`PD_SMART_INFO_C{槽位}` 检查属性 ID `#5`（Reallocated Sectors）、`#196`（Reallocation Events）、`#197`（Current Pending Sectors）、`#198`（Offline Uncorrectable）——任一非零即代表磁盘存在物理坏道
4. **`LSI_RAID_Controller_Log`**：RAID 控制器原始操作日志，能还原 RAID 状态变化的完整时序
5. **`RTOSDump/kbox_info`**：H3C 独有内核黑匣子，记录重置原因，可区分是硬件触发 reset 还是软件 panic
6. **`LogDump/phy/` 误码日志**：`invalid dword count` 持续增长是磁盘链路质量劣化的前兆，可解释间歇性掉盘现象

---

## Step 4：标准诊断报告输出

**格式规范**：简洁但核心内容全面。每个字段必须填写，不允许留"未知"或"待定"——如果真的无法确定，说明原因并给出最可能的推断及所需的补充证据。

```markdown
## GRUB 启动故障诊断报告

**服务器厂商**：[Huawei / Inspur / H3C]
**日志采集时间**：[来自 dump_info / rundatainfo / current_event 的时间戳]

---

### 🔴 故障根因（Root Cause）
[格式："[故障层次] — [具体组件] 发生 [故障类型]，导致 [直接影响]"]

示例："硬件层 — Slot 2 物理磁盘（SN: XXXXXXXX）发生不可纠正读错误，
       导致 RAID-1 逻辑卷标记 Offline，GRUB 无法访问 /boot 分区。"

---

### ⚙️ 故障组件（Faulty Component）
- 组件类型：[物理磁盘 / RAID 控制器 / BIOS 配置 / GRUB 文件 / 内核镜像 / 分区表]
- 组件标识：[槽位号 / 设备序列号 / 分区 UUID / 文件路径]
- 组件当前状态：[Offline / Degraded / Corrupted / Missing / Misconfigured]

---

### ⏰ 故障时间（Fault Time）
- 首次异常信号：[时间戳] ← [来源文件 关键字: "原文片段"]
- 故障确认时间：[时间戳]（逻辑卷 Offline / GRUB 报错 / 系统停止响应）
- 时间关联性：[与上次操作/重启/断电的时间差，是否吻合]

---

### 🔗 故障链与时间线（Fault Chain & Timeline）

[时间戳1] 前兆事件
           ← [日志文件]  关键字: "[原文片段]"

[时间戳2] 根因触发 ← T=0 基准点
           ← [日志文件]  关键字: "[原文片段]"

[时间戳3] 次级扩散（如 RAID 逻辑卷状态变化）
           ← [日志文件]  关键字: "[原文片段]"

[时间戳4] 用户可见的故障现象（GRUB 报错 / Kernel Panic）
           ← SOL 串口 / OSDump 截图

**因果关系说明**：[一段话解释链条逻辑。例如：
"磁盘 P1 扇区重分配耗尽 → I/O 请求持续超时 → RAID 控制器将盘标记 Offline
→ 逻辑卷从 Degraded 变为 Offline → 重启后 RAID 驱动无法加载逻辑卷
→ GRUB 找不到 /boot 所在分区，输出 'no such partition'"]

---

### ✅ 已排除项（Excluded Causes）

| 候选原因 | 排除依据（具体日志证据） |
|---------|----------------------|
| GRUB 配置文件损坏 | SOL 串口显示 GRUB Stage2 正常加载，错误在磁盘读取阶段，非 grub.cfg 解析失败 |
| BIOS 启动顺序错误 | BIOS 日志无 config failed，SEL 无 Boot Device Not Found 事件 |
| Secure Boot 阻断 | security_log 无 auth fail，截图无 Secure Boot violation 字样 |
| [其他候选原因] | [具体证据] |

---

### 🎯 为什么确定是这个问题（Confidence Reasoning）

从三个维度论证，每条必须引用具体日志来源：

1. **直接证据**：
   [文件名] 第 [行号] 行：`[原文关键字]` → 直接证明故障组件状态

2. **时序证据**：
   [时间戳A] [文件A] 记录 [事件A]，早于 [时间戳B] [文件B] 的 [事件B]，
   时序逻辑自洽，证明因果而非巧合。

3. **排他证据**：
   若为其他原因（如 GRUB 配置错误），则 SOL 串口中应出现 [特征X]，
   但实际输出为 [特征Y]，因此排除。

**综合置信度**：[高 / 中 / 低]
[说明原因，例如"所有证据链完整，置信度高"或
"缺少 SOL 串口日志，GRUB 层无法直接确认，置信度中，建议补采"]

---

### 🔧 修复建议（Fix Recommendations）

**立即操作（按优先级排序）：**

1. [针对根因的直接修复，含具体命令/步骤]
2. [数据保护 / 备份操作]
3. [GRUB/OS 层修复，如需救援模式]

救援模式参考：
   grub-install --recheck /dev/sdX
   update-grub  # 或 grub2-mkconfig -o /boot/grub2/grub.cfg

**验证方法：**
- 重启后观察 SOL 串口，确认 GRUB 菜单正常出现
- 通过 iBMC WebUI 确认 RAID 逻辑卷状态变为 Optimal
- [其他验证点]

**预防措施：**
- [根据此次故障类型的针对性建议，如 SMART 定期巡检、RAID 告警订阅、备份策略]
```

---

## 特殊场景处理

### OFFLINE_ONLY（纯离线环境）
无法执行救援操作时的分析策略：
- 优先确认哪些数据分区尚可读（通过 RAID 状态判断逻辑卷可访问性）
- 提供离线救援 USB 制作指引（以日志中的 OS 版本为基准）
- 明确哪些文件需要从正常系统复制进行修复（initramfs / grub.cfg / vmlinuz）

### boot-forensics（启动取证分析）
深度还原故障现场——适用于 SOL 串口和 OSDump 截图同时存在时：
1. 提取 OSDump 截图中的完整错误信息（Huawei/H3C：`img*.jpeg`；Inspur：`IERR_Capture.jpeg`）
2. SOL 串口末尾 200 行逐行分析，重建启动失败的最后上下文
3. 将截图文字与串口日志做交叉比对，确认故障帧与时间点

### rescue-environment-debugging（救援模式调试）
引导用户在 rescue 环境下补充收集：
```bash
# 磁盘与分区状态
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,UUID
blkid
fdisk -l

# RAID 软 RAID 状态（如有）
cat /proc/mdstat
mdadm --detail /dev/md*

# GRUB 安装位置探测
grub-probe -t device /boot
grub-probe -t fs /boot

# 文件系统完整性检查（只检查不修复）
fsck -n /dev/sdXN
```

---

## 高频故障模式速查

分析前先对照以下模式，快速锁定方向，避免从零开始：

| 模式 | 典型现象 | 首要证据文件 | 快速判断依据 |
|------|---------|------------|------------|
| **RAID 逻辑卷 Offline 阻断启动** | 卡在 BIOS 后，无 GRUB 输出 | RAID_Controller_Info | 逻辑卷状态 = `Offline`（非仅 `Degraded`）|
| **磁盘物理坏道** | GRUB 读错误 / fsck 失败 / I/O 超时 | SMART（H3C）/ SEL `Predictive Fail` | SMART `#5` 或 `#197` 非零 |
| **UUID 不匹配** | `grub rescue>` + `no such partition` | SOL 串口 + grub.cfg 内容 | grub.cfg UUID ≠ blkid 输出 |
| **GRUB 未安装在启动盘** | 多盘环境，某盘更换后失败 | SOL 串口 + BIOS 启动顺序 | GRUB 安装位置与 BIOS 启动盘不一致 |
| **内核 / initramfs 文件缺失** | `error: file '/boot/vmlinuz' not found` | SOL 串口 | /boot 目录文件被删或分区被格式化 |
| **Secure Boot 阻断** | 卡在 UEFI shell，无 GRUB 菜单 | security_log / BIOS 日志 | `Secure Boot violation` 记录 |
| **异常断电致文件系统损坏** | fsck journal 错误 / ext4 read-only 挂载 | SEL 断电事件 + SOL fsck 输出 | SEL 有异常断电，fsck 报 journal 损坏 |
| **iBMC 时钟偏差导致时间线混乱** | 各日志时间戳无法对齐 | ntp_info | `NTP synchronization failed`，各文件时间相差超过数分钟 |

---

## 参考资料

分析时按需加载，加载前看各文件 ToC 确认所需章节：

| 文件 | 核心内容 | 关键章节 |
|------|---------|---------|
| `references/huawei_ibmc.md` | 华为 7 大类日志体系、各文件故障关键字、SOP 流程、优先级速查矩阵 | §二 错误类型分类；§七 优先级矩阵 |
| `references/inspur_ibmc.md` | 浪潮 4 目录结构、与华为/H3C 差异对比、系统日志分级体系、ErrorAnalyReport 解析方法 | §二 差异对比；§三 错误分类 |
| `references/h3c_ibmc.md` | H3C 10 模块体系、SMART 分析、LSI 日志解读、PHY 误码分析、kbox_info 解读 | §二 错误分类；§三 存储&RAID章节 |

---

## 报告质量自检（输出前必过）

- [ ] 根因是**单一明确**的结论，不是"可能是A或B"的模糊表述
- [ ] 时间线**连续无跳跃**，故障链每一步都有日志来源
- [ ] **每个结论 ≥ 2 个**不同来源日志相互印证，无孤证
- [ ] 排除项有**具体日志证据**支撑，不是主观推断
- [ ] 修复建议**具体可执行**，不需要再次猜测或追问
- [ ] 已检查 iBMC 时钟准确性（NTP 状态），避免时间线分析偏差
- [ ] Step 2.4 信息完整性检查已过，关键文件均存在（或已告知用户补采）
- [ ] **Inspur**：是否查阅了 `ErrorAnalyReport.json` 和 `emerg.log`
- [ ] **H3C**：是否检查了所有 `PD_SMART_INFO_C*` 的 #5/#197/#198 属性
- [ ] **Huawei**：是否确认了 `fdm_output` 中的 `Fault` 条目