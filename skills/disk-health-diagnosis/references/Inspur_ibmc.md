# 浪潮（Inspur）服务器 iBMC 日志深度分析指南

---

## 一、Inspur iBMC 日志体系架构

Inspur iBMC 一键日志采用**扁平化 + 分类目录**结构，共 4 大目录：

```
onekeylog/
├── log/           ── 核心日志（SEL、系统、故障诊断、黑匣子）★最重要
├── runningdata/   ── 实时运行数据（传感器、性能、硬件状态）
├── configuration/ ── 配置快照（网络、用户、BIOS、服务）
└── component/     ── 部件信息（固件版本、硬件清单）
```

---

## 二、与华为/H3C iBMC 的核心差异

| 特性 | Inspur | 华为 | H3C |
|---|---|---|---|
| 日志目录结构 | 4目录扁平化 | 10+模块目录 | 10+模块目录 |
| 故障解析报告 | ✅ `ErrorAnalyReport.json` ★ | ❌ 无 | ❌ 无 |
| MCA寄存器 | ✅ `RegRawData.json` ★ | ❌ 无 | ❌ 无 |
| 80码诊断 | ✅ `rundatainfo.log` ★ | ❌ 无 | ❌ 无 |
| CPLD寄存器 | ✅ `cpldinfo.log` | ✅ | ✅ |
| Apache日志 | ❌ 无 | ❌ 无 | ✅ 3rdDump |
| FDM预告警 | ❌ 无 | ❌ 无 | ✅ |
| 系统日志分级 | ✅ 按级别分文件 ★ | 混合 | 混合 |
| IERR宕机截屏 | ✅ `IERR_Capture.jpeg` ★ | ✅ | ✅ |
| 崩溃录像 | ✅ `CrashVideoRecordCurrent` ★ | ✅ | ✅ |
| SMBIOS数据 | ✅ `smbios.dmp` | ❌ 无 | ❌ 无 |

---

## 三、错误类型全景分类

### 🔴 1. 硬件故障类（最高优先级）

| 日志文件 | 路径 | 错误类型 | 关键字 |
|---|---|---|---|
| `selelist.csv` | log/ | SEL硬件事件 | `Assert` / `Deassert` / `Critical` |
| `ErrorAnalyReport.json` | log/ | **AI故障解析报告** ★Inspur特有 | `fault` / `error` / `recommend` |
| `RegRawData.json` | log/ & runningdata/ | **MCA寄存器** ★硬件错误根因 | `MCA` / `bank` / `uncorrected` |
| `IERR_Capture.jpeg` | log/CaptureScreen/IERR/ | **IERR宕机截图** | BSOD / Kernel Panic |
| `CrashVideoRecordCurrent` | log/ | 崩溃录像 | 宕机前操作回放 |
| `psuFaultHistory.log` | log/ | 电源黑匣子 | `fault` / `power loss` |
| `rundatainfo.log` | runningdata/ | 电压/温度/转速 | 超阈值 / 异常值 |
| `faninfo.log` | runningdata/ | 风扇状态 | `fail` / `missing` / `0 RPM` |

---

### 🟠 2. 系统日志类（Inspur 独有分级体系）

Inspur 将系统日志**按严重级别拆分为独立文件**，分析优先级从高到低：

| 日志文件 | 级别 | 含义 | 优先级 |
|---|---|---|---|
| `emerg.log` | EMERG(0) | 系统不可用 | ⭐⭐⭐⭐⭐ |
| `alert.log` | ALERT(1) | 需立即处理 | ⭐⭐⭐⭐⭐ |
| `crit.log` | CRIT(2) | 严重错误 | ⭐⭐⭐⭐ |
| `err.log` / `err.log.1` | ERR(3) | 一般错误 | ⭐⭐⭐⭐ |
| `warning.log` / `.1` | WARNING(4) | 警告 | ⭐⭐⭐ |
| `notice.log` / `.1` | NOTICE(5) | 重要通知 | ⭐⭐ |
| `info.log` / `.1` | INFO(6) | 一般信息 | ⭐ |

```bash
# 按优先级依次查看
cat onekeylog/log/emerg.log
cat onekeylog/log/alert.log
cat onekeylog/log/crit.log
grep -iE "error|fail|fault" onekeylog/log/err.log | tail -50
```

---

### 🟡 3. 存储类

| 日志文件 | 路径 | 错误类型 | 关键字 |
|---|---|---|---|
| `raid0.log` ~ `raid7.log` | log/ | RAID控制器日志 | `Degraded` / `Offline` / `Rebuild` / `error` |
| `selelist.csv` | log/ | 硬盘 SEL 事件 | `Drive Fault` / `Predictive Fail` |
| `component.log` | component/ | RAID卡/硬盘部件信息 | `not present` / `fail` |

---

### 🟢 4. 网络类

| 日志文件 | 路径 | 错误类型 | 关键字 |
|---|---|---|---|
| `rundatainfo.log` | runningdata/ | 网口收发包统计 | `errors` / `dropped` |
| `rundatainfo.log` | runningdata/ | BMC路由信息 | 路由缺失 / 网关异常 |
| `NetCard.log` | sollog/ | 网卡日志 | `link down` / `error` |
| `config.log` | configuration/ | BMC网络配置 | IP/掩码/网关 |

---

### 🔵 5. 安全审计类

| 日志文件 | 路径 | 错误类型 | 关键字 |
|---|---|---|---|
| `audit.log` / `.log1` | log/ | 用户操作审计 | `login fail` / `permission` |
| `maintenance.log` / `.1` | log/ | 维护操作记录 | 重启/配置变更 |
| `idl.log` | log/ | IDL接口日志 | `auth fail` / `unauthorized` |
| `index.log` | log/ | SNMP Trap统计 | `trap` / `fail` |

---

### 🟣 6. OS 侧类

| 日志文件 | 路径 | 用途 |
|---|---|---|
| `solHostCaptured.log` / `.1` | sollog/ | SOL串口完整OS日志 |
| `BMCUart.log` / `.1` | sollog/ | BMC串口日志 |
| `dmesg` | log/ | Linux内核消息 |
| `IERR_Capture.jpeg` | log/CaptureScreen/IERR/ | IERR宕机截图 |
| `CrashVideoRecordCurrent` | log/ | OS崩溃录像 |

---

## 四、Inspur 独有关键日志深度说明

### 📊 `ErrorAnalyReport.json` — 故障自动解析报告

这是 Inspur iBMC 最有价值的特色日志，系统自动完成故障分析并输出结论：

```bash
# 查看故障解析报告（JSON格式，需格式化）
cat onekeylog/log/ErrorAnalyReport.json | python3 -m json.tool

# 提取故障项
python3 -c "
import json
with open('onekeylog/log/ErrorAnalyReport.json') as f:
    data = json.load(f)
# 根据实际JSON结构提取 fault/error/recommend 字段
print(json.dumps(data, indent=2, ensure_ascii=False))
"

# 或用 jq 工具快速提取
jq '.[] | select(.level=="fault" or .level=="error")' onekeylog/log/ErrorAnalyReport.json
```

---

### 🔬 `RegRawData.json` — MCA 寄存器原始数据

MCA（Machine Check Architecture）是 CPU/内存硬件错误的最权威来源：

```bash
# 查看 MCA 寄存器数据
cat onekeylog/log/RegRawData.json | python3 -m json.tool
cat onekeylog/runningdata/RegRawData.json | python3 -m json.tool

# MCA Bank 分类（Intel平台）：
# Bank 0     → CPU 内部错误
# Bank 1     → 指令 TLB / Prefetch
# Bank 5     → 内存控制器 (IMC) → 内存ECC错误
# Bank 8/9   → QPI/UPI 互联总线
# Bank 16-19 → PCIe / I/O Hub

# 关键字段含义：
# MCi_STATUS[63]=VAL  → 此 Bank 有有效错误
# MCi_STATUS[61]=UC   → Uncorrected Error（严重）
# MCi_STATUS[57]=EN   → 错误已使能报告
# MCi_STATUS[31:16]   → MCA Error Code（错误类型编码）
```

---

### 🖥️ 80码 POST 诊断数据

```bash
# 查看 BIOS POST 80码和实时运行数据
cat onekeylog/runningdata/rundatainfo.log

# 80码含义（BIOS POST阶段）：
# 00       → 系统重置
# 19       → 内存初始化开始
# 32       → 内存初始化完成
# A0       → IDE初始化
# AA       → 进入OS引导
# 挂在中间值 → BIOS POST卡死，对应硬件初始化失败

# 在 rundatainfo.log 中同时还包含：
grep -i "temperature\|voltage\|current\|fan\|power" \
  onekeylog/runningdata/rundatainfo.log | head -50
```

---

### 🗃️ `SEL日志 selelist.csv` — 结构化硬件事件

```bash
# CSV 格式，可直接用 Excel 打开，也可命令行分析
head -5 onekeylog/log/selelist.csv   # 查看表头

# 按时间排序查看所有 Assert 事件
grep -i "assert" onekeylog/log/selelist.csv | sort -t',' -k1

# 找 Critical 级别事件
grep -i "critical\|fatal\|fault" onekeylog/log/selelist.csv

# 统计事件类型分布
awk -F',' '{print $NF}' onekeylog/log/selelist.csv | sort | uniq -c | sort -rn

# 找特定时间段的事件（假设第1列是时间）
awk -F',' '$1>="2025-03-01" && $1<="2025-03-10"' onekeylog/log/selelist.csv
```

---

## 五、标准分析流程（SOP）

```
┌──────────────────────────────────────────────────────────────┐
│  STEP 1：故障快速定性（10分钟）                               │
│  ErrorAnalyReport.json → IERR截图 → emerg/alert/crit日志     │
└──────────────────────┬───────────────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────────────┐
│  STEP 2：硬件根因分析                                         │
│  selelist.csv + RegRawData.json + cpldinfo.log               │
└──────────────────────┬───────────────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────────────┐
│  STEP 3：实时运行数据分析                                     │
│  rundatainfo.log（80码/传感器/性能/网络）                     │
└──────────────────────┬───────────────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────────────┐
│  STEP 4：存储专项分析                                         │
│  raid0~7.log + BMC SEL.dat + component.log                   │
└──────────────────────┬───────────────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────────────┐
│  STEP 5：OS 侧综合分析                                        │
│  solHostCaptured + dmesg + CrashVideoRecord                  │
└──────────────────────┬───────────────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────────────┐
│  STEP 6：配置 & 审计回溯                                      │
│  audit.log + maintenance.log + config.log                    │
└──────────────────────────────────────────────────────────────┘
```

---

## 六、各阶段详细操作指导

### STEP 1：故障快速定性

```bash
BASE="onekeylog"

# ① 查看 AI 故障解析报告（Inspur 最重要特色）
echo "=== 故障解析报告 ==="
cat ${BASE}/log/ErrorAnalyReport.json | python3 -m json.tool 2>/dev/null \
  || cat ${BASE}/log/ErrorAnalyReport.json

# ② 查看宕机截图（打开图片文件）
ls -la ${BASE}/log/CaptureScreen/IERR/IERR_Capture.jpeg 2>/dev/null \
  && echo "  ⚠️ 存在 IERR 宕机截图！" || echo "  无 IERR 截图"

# ③ 按级别查看系统日志（从高到低）
for level in emerg alert crit; do
    f="${BASE}/log/${level}.log"
    [ -s "$f" ] && echo "=== ${level^^} ===" && cat "$f" || echo "  [${level}] 无内容"
done

# ④ 查看错误日志（最近50条）
grep -iE "error|fail|fault|panic" ${BASE}/log/err.log | tail -50
```

---

### STEP 2：硬件根因分析

```bash
# ① SEL 事件全量分析
echo "=== SEL 事件统计 ==="
wc -l ${BASE}/log/selelist.csv
grep -i "assert\|critical\|fault" ${BASE}/log/selelist.csv | head -30

# ② 找最早的 Assert 事件（故障起点）
grep -i "assert" ${BASE}/log/selelist.csv | \
  sort -t',' -k1 | head -10

# ③ MCA 寄存器分析（最权威硬件错误来源）
echo "=== MCA 寄存器数据 ==="
cat ${BASE}/log/RegRawData.json | python3 -m json.tool 2>/dev/null
cat ${BASE}/runningdata/RegRawData.json | python3 -m json.tool 2>/dev/null

# ④ CPLD 寄存器（板级硬件状态）
echo "=== CPLD 寄存器 ==="
cat ${BASE}/runningdata/cpldinfo.log
# 关注非零寄存器值，对应硬件异常状态

# ⑤ 电源黑匣子（电源故障前历史）
echo "=== 电源黑匣子 ==="
cat ${BASE}/log/psuFaultHistory.log | grep -iE "fault|error|loss" | tail -30

# ⑥ 传感器实时值（找超阈值项）
echo "=== 传感器异常项 ==="
grep -iE "sensor|temperature|voltage|current|power" \
  ${BASE}/runningdata/rundatainfo.log | \
  grep -v "Normal\|OK\|0x00" | head -30

# ⑦ 内存详细信息（内存故障分析）
cat ${BASE}/runningdata/meminfo.log
grep -iE "error|fail|uncorrect|mismatch" ${BASE}/runningdata/meminfo.log
```

---

### STEP 3：实时运行数据综合分析

```bash
# ① 80码 POST 状态（BIOS 卡死分析）
echo "=== 80码 POST 状态 ==="
grep -i "port80\|postcode\|80h\|post code" ${BASE}/runningdata/rundatainfo.log | head -10

# ② BMC 自身性能
echo "=== BMC CPU 使用率 ==="
grep -i "cpu.*usage\|cpu.*utiliz\|cpu.*percent" \
  ${BASE}/runningdata/rundatainfo.log | tail -5

echo "=== BMC 内存使用率 ==="
grep -i "mem.*usage\|memory.*utiliz" \
  ${BASE}/runningdata/rundatainfo.log | tail -5

echo "=== BMC FLASH 使用率 ==="
grep -i "flash.*usage\|flash.*utiliz" \
  ${BASE}/runningdata/rundatainfo.log | tail -5

# ③ 风扇详情（转速和状态）
echo "=== 风扇信息 ==="
cat ${BASE}/runningdata/faninfo.log
grep -iE "fail|missing|0 RPM|speed" ${BASE}/runningdata/faninfo.log

# ④ 网口收发包统计
echo "=== 网口异常统计 ==="
grep -iE "errors|dropped|collision" \
  ${BASE}/runningdata/rundatainfo.log | grep -v " 0$" | head -20

# ⑤ 功率统计（找骤变点）
grep -i "power\|watt" ${BASE}/runningdata/rundatainfo.log | tail -20

# ⑥ I2C 通道状态
grep -i "i2c\|i2c.*error\|i2c.*timeout" \
  ${BASE}/runningdata/rundatainfo.log | grep -i "error\|fail" | head -20

# ⑦ BMC 累计运行时间
grep -i "uptime\|running time" ${BASE}/runningdata/rundatainfo.log | head -5

# ⑧ 中断信息（异常中断分析）
cat ${BASE}/runningdata/interrupts | sort -k2 -rn | head -20
```

---

### STEP 4：存储专项分析

```bash
# ① 遍历所有 RAID 卡日志（支持8个控制器）
for i in $(seq 0 7); do
    f="${BASE}/log/raid${i}.log"
    if [ -s "$f" ]; then
        echo "=== RAID 控制器 ${i} ==="
        grep -iE "Degraded|Offline|Rebuild|Failed|error|fault" "$f" | tail -20
    fi
done

# ② 硬件部件清单（RAID卡/硬盘型号和状态）
cat ${BASE}/component/component.log
grep -iE "raid\|disk\|drive\|hdd\|ssd\|nvme" \
  ${BASE}/component/component.log | grep -iE "fail|error|not present|offline"

# ③ SMBIOS 硬件资产（硬盘详情）
ls -la ${BASE}/runningdata/smbios.dmp
# 可用 dmidecode 解析：dmidecode --from-dump smbios.dmp -t 9

# ④ SEL 中的存储相关事件
grep -iE "drive\|disk\|raid\|storage\|predictive fail" \
  ${BASE}/log/selelist.csv | tail -20

# ⑤ BMC 原始 SEL 数据
ls -la ${BASE}/log/BMC1/SEL.dat
# 需 ipmitool 解析：ipmitool sel list -f SEL.dat
```

---

### STEP 5：OS 侧综合分析

```bash
# ① 打开 IERR 宕机截图（图像文件）
ls -la ${BASE}/log/CaptureScreen/IERR/IERR_Capture.jpeg
# 用图片查看工具打开，检查是否有 Kernel Panic / BSOD 信息

# ② 崩溃录像（视频文件，需对应播放器）
ls -la ${BASE}/log/CrashVideoRecordCurrent
echo "  请用视频播放器查看崩溃前的操作录像"

# ③ SOL 串口日志（最完整的 OS 启动/运行日志）
cat ${BASE}/sollog/solHostCaptured.log | \
  grep -iE "panic|error|fail|crash|oops|trace" | head -50

# 查看历史串口日志
cat ${BASE}/sollog/solHostCaptured.log.1 | \
  grep -iE "panic|error|fail" | tail -30

# ④ BMC UART 日志（BMC 串口输出）
cat ${BASE}/sollog/BMCUart.log | \
  grep -iE "error|fail|watchdog|reset" | tail -30

# ⑤ Linux 内核消息
cat ${BASE}/log/dmesg | grep -iE "error|fail|panic|oops|call trace" | head -50

# ⑥ 网卡日志
cat ${BASE}/sollog/NetCard.log | \
  grep -iE "error|link down|fail" | tail -20
```

---

### STEP 6：配置与审计回溯

```bash
# ① 用户操作审计（排查人为变更）
cat ${BASE}/log/audit.log | grep -iE "login fail\|permission\|deny\|change" | tail -30
cat ${BASE}/log/audit.log.1 | tail -20

# ② 维护操作日志（系统重启/配置变更时间线）
cat ${BASE}/log/maintenance.log
cat ${BASE}/log/maintenance.log.1

# ③ BMC 网络配置确认
grep -iE "ip\|netmask\|gateway\|dns\|vlan" \
  ${BASE}/configuration/config.log | head -20

# ④ 用户账号信息（检查非法账号）
cat ${BASE}/configuration/config.log | \
  grep -iE "user\|password\|role\|privilege" | head -20

# ⑤ SSH 配置检查
cat ${BASE}/configuration/conf/ssh_server_config | \
  grep -v "^#" | grep -v "^$"

# ⑥ 服务配置（KVM/IPMI/Web 是否异常）
cat ${BASE}/configuration/conf/ncml.conf | \
  grep -iE "enable\|disable\|port" | head -20

# ⑦ SNMP Trap 统计
cat ${BASE}/log/index.log | tail -20

# ⑧ syslog 配置
cat ${BASE}/configuration/conf/syslog.conf
```

---

## 七、典型故障场景速查

### 场景 A：服务器 IERR 宕机

```
分析路径：
1. log/CaptureScreen/IERR/IERR_Capture.jpeg  → 确认宕机截图内容
2. log/ErrorAnalyReport.json                 → AI自动分析报告
3. log/RegRawData.json                       → MCA寄存器找硬件错误 Bank
4. log/selelist.csv                          → 找 IERR 前的 Assert 事件
5. log/CrashVideoRecordCurrent               → 崩溃前操作录像回放
6. sollog/solHostCaptured.log                → OS 层 panic 堆栈
7. runningdata/rundatainfo.log               → 宕机时传感器状态
```

### 场景 B：内存 ECC 错误

```
分析路径：
1. log/RegRawData.json       → 查 Bank 5（IMC），确认 CE/UCE 类型
2. log/ErrorAnalyReport.json → 系统是否已定位到具体DIMM槽位
3. log/selelist.csv          → 查 Memory ECC / Correctable / Uncorrectable
4. runningdata/meminfo.log   → 内存配置和状态详情
5. log/err.log               → 内存相关错误消息
6. log/dmesg                 → 内核层 MCE 记录
```

### 场景 C：RAID 降级 / 硬盘故障

```
分析路径：
1. log/raid0.log ~ raid7.log   → RAID控制器日志，找 Degraded/Fail
2. log/selelist.csv            → 找 Drive Fault / Predictive Failure
3. component/component.log     → 确认硬盘型号和槽位
4. log/ErrorAnalyReport.json   → 是否输出存储故障结论
5. log/err.log                 → 存储相关错误
```

### 场景 D：BMC 无法访问

```
分析路径：
1. log/flash_status            → Flash 存储是否异常
2. runningdata/rundatainfo.log → BMC CPU/内存/FLASH 使用率是否满载
3. log/err.log                 → BMC 服务层错误
4. log/audit.log               → 是否因暴力破解被锁定
5. configuration/config.log    → 网络配置是否正确
6. runningdata/rundatainfo.log → 网口收发包是否正常
```

### 场景 E：服务器无法开机（BIOS卡住）

```
分析路径：
1. runningdata/rundatainfo.log → 80码，确认 POST 卡在哪个阶段
2. log/selelist.csv            → POST 阶段的硬件初始化事件
3. log/ErrorAnalyReport.json   → 系统是否给出 POST 失败原因
4. component/component.log     → 哪个部件 not present 或失败
5. runningdata/cpldinfo.log    → 板级上电序列是否正常
6. sollog/BMCUart.log          → BMC 串口输出，看 POST 信息
```

### 场景 F：系统温度告警

```
分析路径：
1. runningdata/rundatainfo.log → 找超阈值的温度传感器
2. runningdata/faninfo.log     → 风扇转速是否正常
3. log/selelist.csv            → Temperature Threshold 告警事件
4. log/warning.log             → 温度相关警告消息
5. component/component.log     → 散热模块（风扇/散热器）状态
6. log/ErrorAnalyReport.json   → 是否给出散热故障结论
```

---

## 八、一键健康检查脚本

```bash
#!/bin/bash
# Inspur iBMC 日志健康快速诊断脚本
BASE="${1:-onekeylog}"

echo "================================================"
echo "  浪潮 Inspur iBMC 日志健康快速诊断报告"
echo "  时间：$(date)"
echo "================================================"

chk() { [ -f "$1" ] && return 0; return 1; }
chk_s() { [ -s "$1" ] && return 0; return 1; }

echo ""
echo "【1. AI故障解析报告】"
chk "${BASE}/log/ErrorAnalyReport.json" && \
  python3 -m json.tool ${BASE}/log/ErrorAnalyReport.json 2>/dev/null | \
  grep -iE "fault|error|fail|recommend" | head -10 || echo "  无故障解析报告"

echo ""
echo "【2. IERR 宕机截图】"
chk_s "${BASE}/log/CaptureScreen/IERR/IERR_Capture.jpeg" && \
  echo "  ⚠️  存在 IERR 宕机截图！请立即查看图像" || echo "  无 IERR 截图"

echo ""
echo "【3. 紧急系统日志】"
for level in emerg alert crit; do
    f="${BASE}/log/${level}.log"
    chk_s "$f" && echo "  ⚠️  [${level^^}]:" && cat "$f" | head -5 || \
      echo "  [${level}] 无内容"
done

echo ""
echo "【4. MCA 寄存器异常】"
chk "${BASE}/log/RegRawData.json" && \
  grep -i "uncorrect\|fatal\|bank" ${BASE}/log/RegRawData.json | head -5 || \
  echo "  无 MCA 数据"

echo ""
echo "【5. SEL 硬件事件统计】"
chk "${BASE}/log/selelist.csv" && {
  total=$(wc -l < ${BASE}/log/selelist.csv)
  assert=$(grep -ic "assert" ${BASE}/log/selelist.csv 2>/dev/null || echo 0)
  echo "  总事件: ${total} 条，Assert: ${assert} 条"
  grep -i "critical\|fault\|fail" ${BASE}/log/selelist.csv | tail -5
} || echo "  无 SEL 数据"

echo ""
echo "【6. RAID 状态检查】"
for i in $(seq 0 7); do
    f="${BASE}/log/raid${i}.log"
    chk_s "$f" && {
        issues=$(grep -icE "Degraded|Offline|Failed" "$f" 2>/dev/null || echo 0)
        [ "$issues" -gt 0 ] && echo "  ⚠️  RAID${i}: 发现 ${issues} 个存储异常" || \
          echo "  RAID${i}: 正常"
    }
done

echo ""
echo "【7. 电源黑匣子】"
chk_s "${BASE}/log/psuFaultHistory.log" && \
  grep -icE "fault|error|loss" ${BASE}/log/psuFaultHistory.log | \
  xargs -I{} echo "  电源故障记录: {} 条" || echo "  无电源故障记录"

echo ""
echo "【8. BMC 自身性能】"
chk "${BASE}/runningdata/rundatainfo.log" && {
  grep -i "cpu.*usage\|cpu.*util" ${BASE}/runningdata/rundatainfo.log | tail -2
  grep -i "mem.*usage\|mem.*util" ${BASE}/runningdata/rundatainfo.log | tail -2
  grep -i "flash.*usage" ${BASE}/runningdata/rundatainfo.log | tail -2
}

echo ""
echo "【9. 风扇告警】"
chk "${BASE}/runningdata/faninfo.log" && \
  grep -iE "fail|missing|0 RPM|speed" ${BASE}/runningdata/faninfo.log || \
  echo "  风扇状态正常"

echo ""
echo "【10. OS 侧异常】"
chk "${BASE}/log/dmesg" && \
  grep -cE "panic|oops|call trace" ${BASE}/log/dmesg | \
  xargs -I{} echo "  内核严重错误: {} 条" || echo "  无内核日志"

echo ""
echo "【11. 安全审计】"
chk "${BASE}/log/audit.log" && \
  grep -ic "login fail\|permission deny\|auth" ${BASE}/log/audit.log | \
  xargs -I{} echo "  认证异常事件: {} 条" || echo "  无审计日志"

echo ""
echo "================================================"
echo "  ⚠️  优先处理上方标注项目"
echo "  核心诊断：ErrorAnalyReport.json + RegRawData.json"
echo "================================================"
```

---

## 九、分析优先级矩阵

| 优先级 | 文件路径 | 判断依据 |
|---|---|---|
| ⭐⭐⭐⭐⭐ | `log/ErrorAnalyReport.json` | AI 输出 fault 结论 |
| ⭐⭐⭐⭐⭐ | `log/CaptureScreen/IERR/IERR_Capture.jpeg` | 存在宕机截图 |
| ⭐⭐⭐⭐⭐ | `log/emerg.log` / `alert.log` | 有内容即最高优先 |
| ⭐⭐⭐⭐⭐ | `log/RegRawData.json` | MCA UCE 类型错误 |
| ⭐⭐⭐⭐ | `log/selelist.csv` | 硬件事件时间线 |
| ⭐⭐⭐⭐ | `log/crit.log` / `err.log` | 系统级严重错误 |
| ⭐⭐⭐⭐ | `log/psuFaultHistory.log` | 电源黑匣子数据 |
| ⭐⭐⭐⭐ | `log/CrashVideoRecordCurrent` | OS 崩溃录像 |
| ⭐⭐⭐ | `log/raid*.log` | RAID 降级/离线 |
| ⭐⭐⭐ | `runningdata/cpldinfo.log` | 板级硬件状态 |
| ⭐⭐⭐ | `sollog/solHostCaptured.log` | OS 串口全日志 |
| ⭐⭐ | `log/audit.log` | 安全/操作审计 |
| ⭐⭐ | `runningdata/faninfo.log` | 散热系统状态 |
| ⭐ | `configuration/config.log` | 配置回溯参考 |

---

**Inspur iBMC 分析核心原则**：充分利用 `ErrorAnalyReport.json`（AI自动分析）+ `RegRawData.json`（MCA硬件错误）+ `selelist.csv`（CSV结构化SEL）的"黄金三角"快速定位根因；系统日志的**分级文件体系**（emerg → alert → crit → err）让优先级判断极为清晰；`80码`数据是 POST 卡死类故障的独特诊断利器。

---

# 表 6-1 一键日志收集内容列表
| 分类 | 信息项 | 一键日志文件中的路径 |
| ---- | ---- | ---- |
| 日志 | SEL日志 | onekeylog/log/selelist.csv |
| 日志 | 审计日志 | onekeylog/log/audit.log, audit.log1 |
| 日志 | IDL日志 | onekeylog/log/idl.log |
| 日志 | 系统日志 | onekeylog/log/info.log, info.log1<br>onekeylog/log/warning.log, warning.log1<br>onekeylog/log/err.log, err.log.1<br>onekeylog/log/crit.log<br>onekeylog/log/alert.log<br>onekeylog/log/emerg.log |
| 日志 | 调试日志 | onekeylog/log/inspur_debug.log, inspur_debug.log.1 |
| 日志 | 维护日志 | onekeylog/log/maintenance.log, maintenance.log.1 |
| 日志 | 电源黑匣子 | onekeylog/log/psuFaultHistory.log |
| 日志 | RAID卡日志 | onekeylog/log/raid%d.log（%d=0~7） |
| 日志 | 系统串口日志 | onekeylog/sollog/solHostCaptured.log, solHostCaptured.log.1 |
| 日志 | BMC Uart日志 | onekeylog/sollog/BMCUart.log, BMCUart.log.1 |
| 日志 | 网卡日志 | onekeylog/sollog/NetCard.log, NetCard.log.1 |
| 日志 | 宕机截屏 | onekeylog/log/CaptureScreen/IERR/IERR_Capture.jpeg |
| 日志 | 崩溃录像 | onekeylog/log/CrashVideoRecordCurrent |
| 日志 | Linux内核日志 | onekeylog/log/dmesg |
| 日志 | BMC SEL日志 | onekeylog/log/BMC1/SEL.dat |
| 日志 | Flash状态日志 | onekeylog/log/flash_status |
| 日志 | SnmpTrap统计日志 | onekeylog/log/index.log |
| 日志 | Notice日志 | onekeylog/log/notice.log, notice.log.1 |
| 日志 | 故障诊断后的解析日志 | onekeylog/log/ErrorAnalyReport.json<br>onekeylog/log/RegRawData.json |
| 运行数据 | CPLD寄存器 | onekeylog/runningdata/cpldinfo.log |
| 运行数据 | MCA寄存器 | onekeylog/runningdata/RegRawData.json |
| 运行数据 | 80码 | onekeylog/runningdata/rundatainfo.log |
| 运行数据 | BMC时间 | onekeylog/runningdata/rundatainfo.log |
| 运行数据 | BMC CPU使用率 | onekeylog/runningdata/rundatainfo.log |
| 运行数据 | BMC内存使用率 | onekeylog/runningdata/rundatainfo.log |
| 运行数据 | BMC FLASH使用率 | onekeylog/runningdata/rundatainfo.log |
| 运行数据 | 电压、温度、电流、转速、功率 | onekeylog/runningdata/rundatainfo.log |
| 运行数据 | 传感器信息 | onekeylog/runningdata/rundatainfo.log |
| 运行数据 | 进程信息 | onekeylog/runningdata/rundatainfo.log |
| 运行数据 | 内存信息 | onekeylog/runningdata/meminfo.log |
| 运行数据 | 风扇信息 | onekeylog/runningdata/faninfo.log |
| 运行数据 | 中断信息 | onekeylog/runningdata/interrupts |
| 运行数据 | I2C通道信息 | onekeylog/runningdata/rundatainfo.log |
| 运行数据 | I2C从设备、EEPROM、寄存器实时数据 | onekeylog/runningdata/rundatainfo.log |
| 运行数据 | 功率统计 | onekeylog/runningdata/rundatainfo.log |
| 运行数据 | SMBIOS | onekeylog/runningdata/smbios.dmp |
| 运行数据 | 运行中创建的文件 | onekeylog/runningdata/var/ |
| 运行数据 | 在线会话信息 | onekeylog/runningdata/racsessioninfo |
| 运行数据 | 当前BMC网络信息 | onekeylog/runningdata/rundatainfo.log |
| 运行数据 | 当前BMC路由信息 | onekeylog/runningdata/rundatainfo.log |
| 运行数据 | 网口收发包信息 | onekeylog/runningdata/rundatainfo.log |
| 运行数据 | BMC累计运行时间 | onekeylog/runningdata/rundatainfo.log |
| 运行数据 | 驱动信息 | onekeylog/runningdata/rundatainfo.log |
| 配置 | 用户信息 | onekeylog/configuration/config.log |
| 配置 | DNS | onekeylog/configuration/conf/dns.conf |
| 配置 | BMC网络 | onekeylog/configuration/config.log |
| 配置 | sshd配置 | onekeylog/configuration/conf/ssh_server_config |
| 配置 | 服务（SSH/Web/KVM/IPMI LAN等）配置 | onekeylog/configuration/conf/ncml.conf |
| 配置 | BIOS菜单项配置 | onekeylog/configuration/conf/redfish/bios/BiosAttributeRegistry0.24.00.0.24.0.json |
| 配置 | 功率封顶配置 | onekeylog/configuration/conf/redfish/bios/bios_current_settings.json |
| 配置 | email配置 | onekeylog/configuration/conf/redfish/bios/bios_future_settings.json |
| 配置 | SNMP TRAP配置 | onekeylog/configuration/conf/SnmTrapCfg.json |
| 配置 | SMTP配置文件 | onekeylog/configuration/conf/SmtpCfg.json |
| 配置 | syslog配置 | onekeylog/configuration/conf/syslog.conf |
| 部件 | CPU | onekeylog/configuration/conf/dhcp.preip_4 |
| 部件 | 内存 | onekeylog/configuration/conf/dhcp6c.conf<br>onekeylog/configuration/conf/dhcp6c_duid |
| 部件 | 硬盘 | onekeylog/configuration/conf/dcmi.conf |
| 部件 | 电源 | onekeylog/component/component.log |
| 部件 | 风扇 | onekeylog/component/component.log |
| 部件 | PCIe卡 | onekeylog/component/component.log |
| 部件 | RAID卡 | onekeylog/component/component.log |
| 部件 | 网卡 | onekeylog/component/component.log |
| 部件 | BMC | onekeylog/component/component.log |
| 部件 | 主板 | onekeylog/component/component.log |
| 部件 | 硬盘背板 | onekeylog/component/component.log |
| 部件 | PCIe Riser卡 | onekeylog/component/component.log |
| 部件 | 固件版本信息 | onekeylog/component/component.log |
