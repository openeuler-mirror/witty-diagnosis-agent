# H3C 服务器 iBMC 日志深度分析指南

---

## 一、H3C iBMC 日志体系架构

H3C iBMC 日志共分为 **10 大模块目录**，与华为 iBMC 同源但有独特扩展：

```
H3C iBMC 日志体系
├── AppDump      ── 应用模块日志（核心业务逻辑）
├── 3rdDump      ── 第三方组件（Apache Web服务）★H3C特有
├── BMALogDump   ── 带内管理代理日志
├── CoreDump     ── 进程崩溃转储
├── RTOSDump     ── iBMC操作系统级信息 ★比华为更详细
├── SpLogDump    ── SP快速部署模块 ★H3C特有
├── LogDump      ── 汇总运行日志（含RAID/PHY/SMART）★更丰富
├── OSDump       ── 业务OS侧故障现场
├── DeviceDump   ── I2C器件寄存器
└── Register     ── CPLD寄存器 ★H3C特有
```

---

## 二、错误类型全景分类

### 🔴 1. 硬件故障类（最高优先级）

| 日志文件 | 位置 | 错误类型 | 关键字 | 含义 |
|---|---|---|---|---|
| `current_event.txt` | AppDump | 全局告警 | `Critical` / `Major` | 未清除的严重/重要告警 |
| `sel.tar` | AppDump | 硬件事件库 | `Asserted` / `Deasserted` | 告警触发/恢复事件 |
| `sensor_info.txt` | AppDump | 传感器读数 | `reading unavailable` | 传感器失效 |
| `sensor_alarm_dfl.log` | AppDump | 阈值越界 | `threshold crossed` | 温度/电压/电流超限 |
| `arm_fdm_log` | LogDump | FDM诊断 | `Fault` / `fault detected` | 系统自检出硬件故障 |
| `fdm_pfae_log` | LogDump | **FDM预告警** ★H3C特有 | `warn` / `predict` | 故障预测告警（预防性维护）|
| `fdm_me_log` | LogDump | ME运行日志 | `error` / `fail` | 管理引擎异常 |
| `ps_black_box.log` | LogDump | 电源黑匣子 | `power fault` | 电源故障前历史快照 |
| `fan_info.txt` | AppDump | 风扇状态 | `speed low` / `missing` | 风扇低速或缺失 |
| `psu_info.txt` | AppDump | 电源模块 | `power loss` / `input lost` | 电源输入丢失 |
| `PD_SMART_INFO_C*` | LogDump | **硬盘SMART** ★H3C特有 | `Reallocated` / `Uncorrectable` | 硬盘预失效指标 |

---

### 🟠 2. iBMC 自身系统类

| 日志文件 | 位置 | 错误类型 | 关键字 |
|---|---|---|---|
| `BMC_dfl.log` | AppDump | BMC核心异常 | `error` / `exception` / `watchdog` |
| `CoreDump/core-*` | CoreDump | 进程崩溃 | `segfault` / `abort` |
| `linux_kernel_log` | LogDump | 内核崩溃 | `panic` / `oops` |
| `dmesg_info` | RTOSDump | 内核启动消息 | `error` / `fail` / `call trace` |
| `nandflash_info.txt` | AppDump | Flash存储损坏 | `bad block` / `read only` |
| `df_info` | RTOSDump | 磁盘空间 | `100% usage` / `disk full` |
| `free_info` | RTOSDump | 内存耗尽 | `Out of memory` |
| `loadavg` | RTOSDump | 系统高负载 | `high load` |
| `uptime` | RTOSDump | 意外重启 | iBMC运行时间异常短 |
| `kbox_info` | RTOSDump | **内核黑匣子** ★H3C特有 | `panic` / `reset reason` |

---

### 🟡 3. 存储 & RAID 类

| 日志文件 | 位置 | 错误类型 | 关键字 |
|---|---|---|---|
| `RAID_Controller_Info.txt` | AppDump | RAID状态 | `Degraded` / `Offline` / `Rebuild` |
| `StorageMgnt_dfl.log` | AppDump | 存储通信 | `comm lost` / `error` |
| `LSI_RAID_Controller_Log` | LogDump | **LSI RAID控制器原始日志** ★H3C特有 | `error` / `reset` / `fail` |
| `drivelog/` | LogDump | **SAS/SATA硬盘日志** ★H3C特有 | `error` / `timeout` |
| `phy/` | LogDump | **PHY误码日志** ★H3C特有 | `error count` / `invalid dword` |
| `PD_SMART_INFO_C*` | LogDump | 硬盘SMART健康 | `197` / `198` (重分配扇区) |
| `*_com_log` | LogDump | **RAID扣卡串口日志** ★H3C特有 | `assert` / `error` |
| `card_manage_dfl.log` | AppDump | 扣卡管理 | `card error` / `init failed` |

---

### 🟢 4. 网络类

| 日志文件 | 位置 | 错误类型 | 关键字 |
|---|---|---|---|
| `ifconfig_info` | RTOSDump | 网口统计 | `errors` / `dropped` |
| `net_info.txt` | AppDump | 管理口配置 | `link down` / `collision` |
| `MCTP_dfl.log` | AppDump | 管理总线 | `packet drop` / `timeout` |
| `lldp_info.txt` | AppDump | 上联交换机 | `no neighbor` |
| `ntp_info.txt` | AppDump | 时钟同步 | `synchronization failed` |
| `netstat_info` | RTOSDump | TCP连接 | `TIME_WAIT` |
| `route_info` | RTOSDump | 路由信息 | 路由缺失/错误 |
| `netcard_info.txt` | LogDump | 网卡配置 | `error` / `link down` |

---

### 🔵 5. Web 服务类（H3C 特有 Apache 日志）

| 日志文件 | 位置 | 错误类型 | 关键字 |
|---|---|---|---|
| `error_log` | 3rdDump | Apache错误 | `error` / `fail` / `AH0` |
| `access_log` | 3rdDump | 访问记录 | `403` / `404` / `500` |
| `httpd.conf` | 3rdDump | 配置检查 | 端口/协议配置 |
| `httpd-ssl.conf` | 3rdDump | HTTPS配置 | 证书路径/协议版本 |

```bash
# Apache 错误日志分析示例
grep -E "\[error\]|\[crit\]|\[alert\]" error_log | tail -50

# 查看 HTTP 状态码分布（5xx为服务端错误）
awk '{print $9}' access_log | sort | uniq -c | sort -rn

# 查看访问频率最高的 IP（排查暴力攻击）
awk '{print $1}' access_log | sort | uniq -c | sort -rn | head -20

# 检查 SSL/TLS 协议问题
grep -iE "ssl|tls|handshake|certificate" error_log | tail -30
```

---

### 🟣 6. 安全审计类

| 日志文件 | 位置 | 错误类型 | 关键字 |
|---|---|---|---|
| `security_log` | LogDump | 认证攻击 | `auth fail` |
| `User_dfl.log` | AppDump | 权限异常 | `permission denied` |
| `operate_log` | LogDump | 用户操作 | 非预期操作追溯 |
| `maintenance_log` | LogDump | 维护操作 | 登录/重启/配置变更 |
| `pam_tally2` | RTOSDump | **登录锁定规则** ★H3C特有 | 账号锁定策略 |

---

### 🟤 7. SP 快速部署类（H3C 特有）

| 日志文件 | 位置 | 用途 |
|---|---|---|
| `quickdeploy_debug.log` | SpLogDump | 极速部署过程日志 |
| `images.log` | SpLogDump | 系统克隆日志 |
| `images_restore.log` | SpLogDump | 系统还原日志 |
| `sp_upgrade_info.log` | SpLogDump | SP自升级日志 |
| `diagnose` | SpLogDump | SP硬件诊断结果 |
| `DriveErase` | SpLogDump | 硬盘擦除日志 |

---

### ⚫ 8. OS 侧类

| 日志文件 | 位置 | 用途 |
|---|---|---|
| `OSDump/img*.jpeg` | OSDump | OS崩溃最后截图 |
| `OSDump/*.rep` | OSDump | KVM屏幕录像 |
| `systemcom.tar` | OSDump | SOL串口完整日志 |
| `agentless_dfl.log` | AppDump | iBMC与OS交互 |

---

## 三、H3C 与华为 iBMC 核心差异对照

| 功能 | H3C | 华为 | 分析要点 |
|---|---|---|---|
| Web服务日志 | ✅ `3rdDump/error_log` | ❌ 无 | H3C需额外检查Apache |
| FDM预告警 | ✅ `fdm_pfae_log` | ❌ 无 | H3C可做预防性维护 |
| 硬盘SMART | ✅ `PD_SMART_INFO_C*` | ❌ 无 | H3C可预判硬盘寿命 |
| PHY误码日志 | ✅ `phy/` 目录 | ❌ 无 | H3C可分析链路质量 |
| RAID串口日志 | ✅ `*_com_log` | ❌ 无 | H3C更底层RAID调试 |
| SP部署日志 | ✅ `SpLogDump/` | ❌ 无 | H3C快速部署专属 |
| 内核黑匣子 | ✅ `kbox_info` | ❌ 无 | H3C重启原因追溯 |
| CPLD寄存器 | ✅ `Register/cpld_reg_info` | ❌ 无 | H3C硬件级寄存器调试 |
| OS截图/录像 | ✅ OSDump | ✅ OSDump | 相同 |
| SEL事件日志 | ✅ sel.tar/sel.db | ✅ sel.db | 相同 |

---

## 四、标准分析流程（SOP）

```
┌──────────────────────────────────────────────────────────────┐
│  STEP 1：全局健康评估（5分钟快速定性）                        │
│  AppDump/current_event.txt + sel.tar + LedInfo               │
└──────────────────────┬───────────────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────────────┐
│  STEP 2：iBMC 自身稳定性检查                                  │
│  CoreDump/ + RTOSDump/kbox_info + nandflash + df_info        │
└──────────────────────┬───────────────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────────────┐
│  STEP 3：时间线还原                                           │
│  LogDump/maintenance_log + operate_log + BMC_dfl.log         │
└──────────────────────┬───────────────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────────────┐
│  STEP 4：按故障类型深入分析（硬件/存储/网络/Web/安全）        │
└──────────────────────┬───────────────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────────────┐
│  STEP 5：H3C 特有日志分析                                     │
│  PHY误码 + SMART + LSI RAID日志 + FDM预告警                  │
└──────────────────────┬───────────────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────────────┐
│  STEP 6：OS 侧综合分析                                        │
│  OSDump截图 + systemcom串口日志 + agentless通信状态           │
└──────────────────────────────────────────────────────────────┘
```

---

## 五、各阶段详细操作指导

### STEP 1：全局健康评估

```bash
# ① 查看当前未清除告警
cat AppDump/current_event.txt
grep -iE "Critical|Major|Minor" AppDump/current_event.txt

# ② 解析 SEL 事件（按时间排序，找最早的 Asserted）
tar -xf AppDump/sel.tar
# 解压后通常有 sel_cur.txt（当前）和 sel_his.txt（历史）
grep "Asserted" sel_cur.txt | head -20
# 按时间找故障起点
sort -k1,2 sel_cur.txt | grep "Asserted" | head -5

# ③ 查看 LED 状态
cat AppDump/LedInfo
# 告警灯亮/UID灯亮 → 需要现场处理

# ④ 查看 FDM 诊断（最权威故障判定）
cat LogDump/arm_fdm_log | grep -i "fault\|error" | tail -30

# ⑤ 查看 FDM 预告警（H3C独有，提前发现问题）
cat LogDump/fdm_pfae_log
```

---

### STEP 2：iBMC 自身稳定性检查

```bash
# ① 检查是否有进程崩溃
ls -la CoreDump/
# 有 core-* 文件 → 记录时间戳，iBMC有进程崩溃

# ② H3C 特有：检查内核黑匣子（最后一次重启原因）
cat RTOSDump/kbox_info
# 关键信息：reset reason / panic message

# ③ 检查 Flash 坏块
cat AppDump/nandflash_info.txt
grep -iE "bad block|read only|error" AppDump/nandflash_info.txt

# ④ 检查 iBMC 分区空间
cat RTOSDump/df_info
awk '$5=="100%"' RTOSDump/df_info   # 找满载分区

# ⑤ 检查内存使用
cat RTOSDump/free_info
cat RTOSDump/meminfo | grep -E "MemFree|MemAvailable"

# ⑥ 检查系统负载（格式：1min 5min 15min）
cat RTOSDump/loadavg
# 超过 CPU 核心数 × 2 = 高负载

# ⑦ 检查进程资源占用
cat RTOSDump/top_info
# 找 CPU/MEM 占用异常高的进程

# ⑧ 检查 iBMC 运行时长（是否发生过意外重启）
cat RTOSDump/uptime

# ⑨ 检查 slab 内存泄漏（H3C RTOSDump 独有）
cat RTOSDump/slabinfo | sort -k3 -rn | head -20
```

---

### STEP 3：时间线还原

```bash
# ① 用户操作历史（排除人为变更）
cat LogDump/maintenance_log
cat LogDump/operate_log

# ② 大量操作日志（批量操作场景）
cat LogDump/mass_operate_log | grep -iE "error|fail" | tail -50

# ③ BMC 核心运行日志
grep -iE "error|exception|watchdog|reset" AppDump/BMC_dfl.log | tail -100

# ④ 结合 SEL 时间戳构建时间线
# 时间线示例：
# 09:00 - SEL: Fan01 Speed Low Asserted
# 09:01 - SEL: Temp_CPU01 Upper Critical Asserted
# 09:02 - SEL: System Power Off
# 09:03 - maintenance_log: 系统下电事件
```

---

### STEP 4：按故障类型深入分析

#### 4A：硬件故障（传感器/温度/电源）

```bash
# 查看所有传感器当前值
cat AppDump/sensor_info.txt
grep -v "ok\|normal" AppDump/sensor_info.txt   # 过滤正常项，只看异常

# 风扇详情
cat AppDump/fan_info.txt
grep -iE "fail|missing|0 RPM|error" AppDump/fan_info.txt

# 散热模块日志
grep -iE "over temperature|fan fail|cooling" AppDump/cooling_app_dfl.log | tail -30

# 电源状态
cat AppDump/psu_info.txt
grep -iE "power loss|input lost|absent|mismatch" AppDump/psu_info.txt

# 电源黑匣子（故障前历史，多个轮转文件）
cat LogDump/ps_black_box.log
zcat LogDump/ps_black_box.log.1.gz 2>/dev/null | tail -50

# 功率历史统计（找功率骤变点）
cat AppDump/power_statistics.csv | tail -100
```

#### 4B：存储 RAID 深度分析（H3C 比华为更丰富）

```bash
# 第一步：查看 RAID 全局状态
cat AppDump/RAID_Controller_Info.txt
grep -iE "Degraded|Offline|Rebuild|Failed|Critical" AppDump/RAID_Controller_Info.txt

# 第二步：查看 LSI RAID 控制器原始日志（H3C独有）
cat LogDump/LSI_RAID_Controller_Log
grep -iE "error|reset|rebuild|fail|abort" LogDump/LSI_RAID_Controller_Log | tail -50
# 历史轮转日志
zcat LogDump/LSI_RAID_Controller_Log.1.gz | grep -i "error" | tail -30

# 第三步：查看 SAS/SATA 硬盘驱动日志（H3C独有）
ls LogDump/drivelog/
cat LogDump/drivelog/*.log 2>/dev/null | grep -iE "error|timeout|reset" | tail -50

# 第四步：查看 PHY 误码日志（链路质量分析，H3C独有）
ls LogDump/phy/
cat LogDump/phy/*.log 2>/dev/null
# PHY error count > 0 表示链路存在误码，可能是线缆或背板问题

# 第五步：查看硬盘 SMART（H3C独有，预判硬盘寿命）
ls LogDump/PD_SMART_INFO_C*
cat LogDump/PD_SMART_INFO_C0   # C0 = 第0个RAID控制器
# 重点关注以下 SMART 属性：
# ID 5   Reallocated_Sector_Ct  > 0 = 有坏扇区
# ID 197 Current_Pending_Sector > 0 = 待重分配扇区
# ID 198 Offline_Uncorrectable  > 0 = 不可修正错误

# 第六步：查看 RAID 扣卡串口日志（H3C独有）
cat LogDump/*_com_log 2>/dev/null | grep -iE "error|assert|fail" | tail -30

# 第七步：查看 PCIe 扣卡日志文件夹
ls LogDump/pciecard/
cat LogDump/pciecard/*.log 2>/dev/null | grep -iE "error|link" | tail -20
```

#### 4C：网络分析

```bash
# 网口统计（errors/dropped 不为0需关注）
cat RTOSDump/ifconfig_info
grep -E "errors|dropped" RTOSDump/ifconfig_info | grep -v " 0 "

# 路由检查（H3C RTOSDump独有）
cat RTOSDump/route_info

# TCP 连接状态
cat RTOSDump/netstat_info
grep "TIME_WAIT" RTOSDump/netstat_info | wc -l   # TIME_WAIT过多影响新连接

# MCTP 通信（板内管理总线）
grep -iE "packet drop|timeout|error" AppDump/MCTP_dfl.log | tail -30

# 网卡配置信息（LogDump层）
cat LogDump/netcard_info.txt
grep -iE "error|link down|speed" LogDump/netcard_info.txt
```

#### 4D：Web 服务分析（H3C 独有 Apache 日志）

```bash
# Apache 错误日志（最重要）
cat 3rdDump/error_log
grep -E "\[error\]|\[crit\]|\[emerg\]" 3rdDump/error_log | tail -30

# 历史错误日志
cat 3rdDump/error_log.1

# HTTP 访问状态码分布
awk '{print $9}' 3rdDump/access_log | sort | uniq -c | sort -rn
# 5xx = 服务端错误, 4xx = 客户端错误/认证失败

# 查看高频访问 IP（排查扫描/暴力破解）
awk '{print $1}' 3rdDump/access_log | sort | uniq -c | sort -rn | head -20

# 检查 HTTPS/TLS 配置
cat 3rdDump/httpd-ssl.conf | grep -E "SSLProtocol|SSLCipher|SSLCertificate"
cat 3rdDump/httpd-ssl-protocol.conf

# 端口配置
cat 3rdDump/httpd-port.conf
```

---

### STEP 5：H3C 特有日志专项分析

#### 5A：CPLD 寄存器分析

```bash
# 查看 CPLD 寄存器（H3C独有，硬件层面状态）
cat Register/cpld_reg_info
# CPLD 寄存器记录了电源序列、板卡在位信号等底层硬件状态
# 异常值需对照 H3C 服务手册的寄存器定义
```

#### 5B：FDM 预告警分析（预防性维护）

```bash
# 查看 FDM 预告警日志（提前预警即将发生的故障）
cat LogDump/fdm_pfae_log
# 预告警类型包括：
# - 硬盘寿命预警（基于SMART数据）
# - 内存CE错误累积预警
# - 风扇退化预警
# - 电源效率下降预警

# 查看 FDM 板卡配置日志
cat LogDump/fdm_mmio_log
zcat LogDump/fdm_mmio_log.tar.gz 2>/dev/null | grep -i "error"

# 查看 ME 运行日志
cat LogDump/fdm_me_log
```

#### 5C：SP 快速部署日志分析

```bash
# 极速部署过程日志
cat SpLogDump/quickdeploy_debug.log | grep -iE "error|fail" | tail -30

# 系统克隆日志
cat SpLogDump/images.log | tail -50

# SP 维护日志
# 注意：SP运行过程中无法收集这些日志，需SP完成后才能获取
cat SpLogDump/maintainlog.csv 2>/dev/null

# 小系统 dmesg（SP环境下的内核日志）
cat SpLogDump/dmesg.log 2>/dev/null | grep -iE "error|fail|panic"

# 网络通信日志（SP部署阶段的网络测试）
cat SpLogDump/ping6.log 2>/dev/null
```

#### 5D：M7 协处理器和 IMU 日志

```bash
# CPU M7 协处理器日志（仅支持M7的机型）
cat LogDump/cpu1_m7_log | grep -iE "error|fail" | tail -30
zcat LogDump/cpu1_m7_log.tar.gz 2>/dev/null | grep -i "error" | tail -30

# IMU 模块日志
cat LogDump/imu_log | grep -iE "error|fail" | tail -20
```

---

### STEP 6：OS 侧综合分析

```bash
# ① 查看 OS 崩溃截图
# 打开 OSDump/img*.jpeg，判断是否存在 Kernel Panic / BSOD 文字

# ② 解析 SOL 串口日志
tar -xf OSDump/systemcom.tar
ls -la systemcom/
cat systemcom/*.log | grep -iE "panic|error|fail|crash|oops" | head -50

# ③ 检查 Agentless 通信状态
grep -iE "connection lost|timeout|error|fail" AppDump/agentless_dfl.log | tail -30
# connection lost = iBMC 与 OS 侧带内代理断连，可能 OS 挂死

# ④ 结合 openEuler /var/log/messages 做交叉验证
# 将 SEL 时间戳 与 OS 侧日志时间戳对比，确认因果关系
```

---

## 六、典型故障场景速查

### 场景 A：服务器无响应/宕机

```
1. OSDump/img*.jpeg        → 确认 OS 层是否 Kernel Panic
2. RTOSDump/kbox_info      → 确认 iBMC 层重启原因
3. AppDump/current_event   → 查告警状态
4. AppDump/sel.tar         → 找宕机时间点前的 Asserted 事件
5. LogDump/ps_black_box    → 是否电源故障导致
6. OSDump/systemcom.tar    → SOL 串口里 OS panic 堆栈
```

### 场景 B：RAID 降级 / 硬盘离线

```
1. AppDump/RAID_Controller_Info.txt  → 确认哪块盘 Offline
2. LogDump/LSI_RAID_Controller_Log   → RAID控制器原始事件
3. LogDump/PD_SMART_INFO_C*          → 硬盘 SMART 健康分析
4. LogDump/drivelog/                 → 硬盘驱动层日志
5. LogDump/phy/                      → PHY 误码（排查线缆/背板）
6. AppDump/sel.tar                   → 硬盘离线时间线
```

### 场景 C：Web 管理界面无法访问

```
1. 3rdDump/error_log        → Apache 服务是否报错
2. RTOSDump/netstat_info    → 443/80 端口是否在监听
3. RTOSDump/df_info         → 分区是否已满导致服务异常
4. AppDump/BMC_dfl.log      → BMC核心是否有watchdog复位
5. LogDump/security_log     → 是否因暴力攻击被锁定 IP
6. 3rdDump/httpd-ssl.conf   → SSL 证书是否过期
```

### 场景 D：温度告警 / 频繁宕机

```
1. AppDump/sensor_info.txt          → 哪个温度传感器超阈值
2. AppDump/fan_info.txt             → 风扇是否全部正常运转
3. AppDump/cooling_app_dfl.log      → 调速策略是否执行
4. LogDump/fdm_pfae_log             → 是否有散热预告警
5. AppDump/sel.tar                  → 温度事件时间线
6. OptPme/env_web_view.dat          → 环境温度历史曲线
```

### 场景 E：固件升级失败

```
1. AppDump/UPGRADE_dfl.log          → 升级失败步骤和错误码
2. AppDump/upgrade_info             → 当前各组件版本
3. AppDump/nandflash_info.txt       → Flash 坏块是否影响写入
4. RTOSDump/df_info                 → 升级包存放空间是否足够
5. LogDump/fdm_me_log               → ME 固件是否有兼容问题
```

### 场景 F：SP 快速部署失败（H3C 特有）

```
1. SpLogDump/quickdeploy_debug.log  → 部署执行过程错误
2. SpLogDump/images.log             → 克隆镜像是否成功
3. SpLogDump/dmesg.log              → SP小系统内核报错
4. SpLogDump/ping6.log              → 网络连通性是否正常
5. SpLogDump/maintainlog.csv        → SP维护操作历史
```

---

## 七、一键健康检查脚本

```bash
#!/bin/bash
# H3C iBMC 日志健康快速诊断脚本
BASE="."   # 修改为实际解压路径

echo "=============================================="
echo "  H3C iBMC 日志健康快速诊断报告"
echo "  时间：$(date)"
echo "=============================================="

check() { [ -f "$1" ] && return 0 || echo "  [跳过] 文件不存在: $1"; return 1; }

echo ""
echo "【1. 全局告警状态】"
check "${BASE}/AppDump/current_event.txt" && \
  grep -iE "Critical|Major" ${BASE}/AppDump/current_event.txt || echo "  无 Critical/Major 告警"

echo ""
echo "【2. iBMC 重启原因（kbox）】"
check "${BASE}/RTOSDump/kbox_info" && \
  grep -iE "panic|reset|reboot|reason" ${BASE}/RTOSDump/kbox_info | tail -5 || echo "  kbox 无异常记录"

echo ""
echo "【3. CoreDump 检查】"
ls ${BASE}/CoreDump/core-* 2>/dev/null && echo "  ⚠️  存在 CoreDump 文件！" || echo "  无 CoreDump"

echo ""
echo "【4. Flash 存储健康】"
check "${BASE}/AppDump/nandflash_info.txt" && \
  grep -iE "bad block|read only" ${BASE}/AppDump/nandflash_info.txt || echo "  Flash 无坏块"

echo ""
echo "【5. iBMC 磁盘空间】"
check "${BASE}/RTOSDump/df_info" && \
  awk '$5=="100%"{print "  ⚠️  分区已满: "$0}' ${BASE}/RTOSDump/df_info || echo "  磁盘空间正常"

echo ""
echo "【6. RAID 状态】"
check "${BASE}/AppDump/RAID_Controller_Info.txt" && \
  grep -iE "Degraded|Offline|Failed" ${BASE}/AppDump/RAID_Controller_Info.txt || echo "  RAID 状态正常"

echo ""
echo "【7. 硬盘 SMART 预警】"
for f in ${BASE}/LogDump/PD_SMART_INFO_C*; do
  [ -f "$f" ] && grep -iE "Reallocated_Sector|Pending_Sector|Uncorrectable" "$f" | grep -v " 0$" | head -3
done
echo "  SMART 检查完毕"

echo ""
echo "【8. PHY 误码检查】"
for f in ${BASE}/LogDump/phy/*.log 2>/dev/null; do
  [ -f "$f" ] && grep -v " 0$" "$f" | head -3
done
echo "  PHY 检查完毕"

echo ""
echo "【9. 电源状态】"
check "${BASE}/AppDump/psu_info.txt" && \
  grep -iE "power loss|input lost|absent" ${BASE}/AppDump/psu_info.txt || echo "  电源状态正常"

echo ""
echo "【10. Apache Web 服务】"
check "${BASE}/3rdDump/error_log" && \
  grep -cE "\[error\]|\[crit\]" ${BASE}/3rdDump/error_log | \
  xargs -I{} echo "  Apache 错误数: {}" || echo "  无 Apache 日志"

echo ""
echo "【11. FDM 预告警】"
check "${BASE}/LogDump/fdm_pfae_log" && \
  cat ${BASE}/LogDump/fdm_pfae_log | grep -i "warn\|predict\|fault" | tail -5 || echo "  无 FDM 预告警"

echo ""
echo "【12. 安全审计】"
check "${BASE}/LogDump/security_log" && \
  grep -c "auth fail" ${BASE}/LogDump/security_log | \
  xargs -I{} echo "  认证失败次数: {}" || echo "  无安全日志"

echo ""
echo "=============================================="
echo "  ⚠️  请重点关注上方标注项目"
echo "  建议同步查看 OSDump/img*.jpeg 确认OS状态"
echo "=============================================="
```

---

## 八、分析优先级矩阵

| 优先级 | 文件路径 | 判断依据 |
|---|---|---|
| ⭐⭐⭐⭐⭐ | `AppDump/current_event.txt` | 存在 Critical 告警 |
| ⭐⭐⭐⭐⭐ | `LogDump/arm_fdm_log` | 输出 Fault 判定 |
| ⭐⭐⭐⭐⭐ | `RTOSDump/kbox_info` | 记录异常重启原因 |
| ⭐⭐⭐⭐⭐ | `LogDump/ps_black_box.log` | 电源故障黑匣子 |
| ⭐⭐⭐⭐ | `AppDump/sel.tar` | 硬件事件时间线 |
| ⭐⭐⭐⭐ | `AppDump/RAID_Controller_Info.txt` | RAID 降级/离线 |
| ⭐⭐⭐⭐ | `CoreDump/core-*` | iBMC 进程崩溃 |
| ⭐⭐⭐⭐ | `LogDump/PD_SMART_INFO_C*` | 硬盘健康预警 |
| ⭐⭐⭐ | `3rdDump/error_log` | Web 服务故障 |
| ⭐⭐⭐ | `LogDump/LSI_RAID_Controller_Log` | RAID 底层事件 |
| ⭐⭐⭐ | `LogDump/fdm_pfae_log` | 预防性维护告警 |
| ⭐⭐ | `LogDump/phy/` | 链路误码分析 |
| ⭐⭐ | `LogDump/security_log` | 安全事件 |
| ⭐ | `SpLogDump/` | SP 部署相关 |

---

**H3C iBMC 分析核心原则**：与华为 iBMC 相比，H3C 在存储链路（`phy/`误码、SMART、RAID串口）、Web服务（Apache）、内核黑匣子（`kbox_info`）和预告警（`fdm_pfae_log`）四个维度有显著扩展，分析时应充分利用这些 H3C 独有日志，可以在故障发生前就发现问题。`sel.tar` + `arm_fdm_log` + `kbox_info` 是三大核心定性依据。

## iBMC 日志清单（增强版）

> 新增列说明：**文件内容描述** — 文件记录的具体数据；**强相关组件** — 与哪些硬件/软件组件直接相关；**故障关键字** — 分析时重点搜索的关键词

| 模块 | 文件名称 | 收集命令 | 原始内容说明 | 文件内容描述 | 强相关组件 | 故障关键字 |
|---|---|---|---|---|---|---|
| - | dump_app_log | - | BMC收集结果列表 | 记录iBMC应用层的日志收集执行结果，确认是否收集成功 | 收集工具 | failed、error |
| - | dump_log | - | 一键收集结果列表 | 一键收集任务的总体执行状态记录 | 收集工具 | failed、timeout |
| AppDump | User_dfl.log | - | User模块管理对象的信息 | 用户管理模块日志，涉及用户添加、权限修改、认证 | 用户安全 | permission denied |
| AppDump | card_manage_dfl.log | - | Card_Manage模块管理对象的信息 | 扣卡管理模块的运行日志，记录扣卡识别、状态变化 | PCIe扣卡 | card error、init failed |
| AppDump | card_info | - | 当前服务器在位板卡的信息 | 主要是RAID卡、网卡等PCIe扣卡的在位与型号信息 | PCIe扣卡 | not present、unknown |
| AppDump | sdi_card_cpld_info | - | SDI V3卡的CPLD寄存器信息<br>说明：只有适配且已正确安装了SDI V3卡的产品支持收集此信息 | SDI V3卡的CPLD寄存器信息<br>说明：只有适配且已正确安装了SDI V3卡的产品支持收集此信息 | - | - |
| AppDump | BMC_dfl.log | - | BMC模块管理对象的信息 | iBMC核心管理模块的运行日志，涉及系统状态维护、组件协调 | iBMC核心 | error、exception、watchdog |
| AppDump | fruinfo.txt | - | FRU电子标签信息 | iBMC所在板卡的FRU信息 | FRU | - |
| AppDump | lldp_info.txt | - | LLDP配置及报文统计信息 | LLDP（链路层发现协议）邻居信息及报文统计 | 网络交换机 | no neighbor |
| AppDump | nandflash_info.txt | - | NAND flash信息 | iBMC存储芯片NAND Flash的状态、坏块信息 | iBMC存储 | bad block、read only |
| AppDump | net_info.txt | - | 网口配置信息 | iBMC管理网口的IP、MAC、VLAN等配置信息 | iBMC网络 | link down、collision |
| AppDump | ntp_info.txt | - | NTP同步失败时的错误信息 | NTP时间同步的错误日志 | NTP、时间同步 | synchronization failed、stratum too high |
| AppDump | psu_info.txt | - | 服务器上配置的电源信息 | 电源模块（PSU）的在位状态、型号、功率、序列号 | 电源(PSU) | power loss、input lost、mismatch |
| AppDump | time_zone.txt | - | BMC时区信息 | iBMC当前配置的时区 | 时间同步 | - |
| AppDump | PowerMgnt_dfl.log | - | PowerMgnt模块管理对象的信息 | 电源管理模块日志，涉及上下电控制、功率封顶 | 电源、功率控制 | power on failed、power off failed |
| AppDump | power_statistics.csv | - | 功率统计信息 | 历史功率统计数据 | 电源 | power cap hit |
| AppDump | power_bbu_info.log | - | BBU模块日志（仅针对支持BBU模块的服务器） | BBU模块日志（仅针对支持BBU模块的服务器） | - | - |
| AppDump | UPGRADE_dfl.log | - | Upgrade模块管理对象的信息 | 固件升级模块日志，记录升级过程与结果 | 固件升级 | upgrade failed、verify failed |
| AppDump | upgrade_info | - | BMC相关器件的版本信息 | iBMC管理的各组件固件版本列表 | 固件版本 | - |
| AppDump | BIOS_dfl.log | - | BIOS模块管理对象的信息 | BIOS管理模块在iBMC侧的运行日志，记录BIOS配置下发、状态监控等操作 | BIOS、iBMC | config failed、checksum error |
| AppDump | bios_info | - | BIOS配置信息 | 当前BIOS的各项配置参数值 | BIOS | - |
| AppDump | registry.json | - | BIOS的注册文件，显示所有的BIOS项信息 | BIOS支持的所有配置项及其属性描述 | BIOS | - |
| AppDump | currentvalue.json | - | 当前设置的BIOS项 | JSON格式的当前BIOS设置值 | BIOS | - |
| AppDump | setting.json | - | 通过redfish设置但尚未生效的BIOS项 | 已设置但需重启生效的BIOS配置 | BIOS | - |
| AppDump | result.json | - | 通过redfish设置的BIOS项结果 | Redfish接口下发BIOS配置的执行结果 | Redfish、BIOS | 400 Bad Request、500 Internal Server Error |
| AppDump | discovery_dfl.log | - | Discovery模块管理对象的信息 | 设备自动发现模块的运行日志 | 设备发现 | discovery failed |
| AppDump | agentless_dfl.log | - | Agentless模块管理对象的信息 | Agentless模块的运行日志，记录带外管理与OS侧的交互信息 | Agentless、OS | error、timeout、connection lost |
| AppDump | ddns_dfl.log | - | Ddns模块管理对象的信息 | 动态域名服务(DDNS)模块的运行日志 | DDNS、网络 | update failed |
| AppDump | diagnose_dfl.log | - | Diagnose模块管理对象的信息 | 诊断模块的运行日志 | 故障诊断 | - |
| AppDump | diagnose_info | - | Port 80的故障诊断信息以及IFMM模块内存占用信息<br>说明：当前暂不支持收集此项信息 | Port 80的故障诊断信息以及IFMM模块内存占用信息<br>说明：当前暂不支持收集此项信息 | - | - |
| AppDump | Snmp_dfl.log | - | Snmp模块管理对象的信息 | SNMP代理服务运行日志 | SNMP | authentication failure |
| AppDump | cooling_app_dfl.log | - | Cooling模块管理对象的信息 | 风扇调速、温度监控模块的运行日志 | 风扇、散热 | over temperature、fan fail |
| AppDump | fan_info.txt | - | 风扇型号、转速等详细信息 | 风扇转速、占空比、状态（在位/缺失/故障） | 风扇 | speed low、missing |
| AppDump | CpuMem_dfl.log | - | CpuMem模块管理对象的信息 | CPU和内存管理模块的运行日志，记录资产识别与状态监控 | CPU、内存 | error、mismatch |
| AppDump | cpu_info | - | 服务器配置的CPU参数的详细信息 | CPU型号、主频、核心数、缓存等物理信息 | CPU | - |
| AppDump | mem_info | - | 服务器配置的内存参数的详细信息 | 内存DIMM的容量、频率、厂商、序列号及在位状态 | 内存 | not present、size mismatch |
| AppDump | kvm_vmm_dfl.log | - | KVM_VMM模块管理对象的信息 | 远程KVM和虚拟媒体(Virtual Media)服务的运行日志 | KVM、虚拟媒体 | connection closed、mount failed |
| AppDump | ipmi_app_dfl.log | - | IPMI模块管理对象的信息 | IPMI协议栈处理日志，记录IPMI命令交互 | IPMI | command failed、timeout |
| AppDump | ipmbeth_info.txt | - | 管理系统的IPMI通道状态 | IPMB（智能平台管理总线）通道的通信状态 | IPMI、I2C | bus error、no response |
| AppDump | alm_protected.persist | - | License管理组件ALM的持久化文件 | License管理组件ALM的持久化文件 | - | - |
| AppDump | LicenseMgnt_dfl.log | - | 管理对象信息 | 管理对象信息 | - | - |
| AppDump | first_protected.persist | - | License管理组件ALM的持久化文件 | License管理组件ALM的持久化文件 | - | - |
| AppDump | second_protected.persist | - | License管理组件ALM的持久化文件 | License管理组件ALM的持久化文件 | - | - |
| AppDump | lm_info | - | License的状态、设备ESN等信息 | License的状态、设备ESN等信息 | - | - |
| AppDump | Dft_dfl.log | - | DFT模块管理对象的信息 | 可制造性设计(DFT)模块日志，通常涉及生产测试 | 生产测试 | test failed |
| AppDump | net_nat_dfl.log | - | Net_NAT模块管理对象的信息 | 网络NAT功能模块日志 | 网络 | - |
| AppDump | PcieSwitch_dfl.log | - | PCIeSwitch模块管理对象的信息 | PCIe交换机管理日志 | PCIe Switch | link error |
| AppDump | RetimerRegInfo | - | Retimer芯片寄存器信息 | Retimer芯片寄存器信息 | - | - |
| AppDump | pcieswitch_info | - | PCIeSwitch模块的固件版本说明 | PCIeSwitch模块的固件版本说明 | - | - |
| AppDump | sensor_alarm_dfl.log | - | Sensor_Alarm模块管理对象的信息 | 传感器告警处理模块日志 | 传感器 | threshold crossed |
| AppDump | sensor_info.txt | - | 服务器所有传感器信息列表 | 所有传感器的当前读数及状态 | 传感器 | reading unavailable |
| AppDump | current_event.txt | - | 服务器当前健康状态和告警事件 | 设备当前的健康状态概览及未清除的告警列表 | 全局健康 | Critical、Major、Minor |
| AppDump | sel.tar | - | 当前sel信息和历史sel信息打包文件 | 当前sel信息和历史sel信息打包文件 | 硬件事件 | Asserted, Deasserted |
| AppDump | sensor_alarm_sel.bin.bak | - | sel原始记录备份文件 | sel原始记录备份文件 | 硬件事件 | Asserted, Deasserted |
| AppDump | sensor_alarm_sel.bin | - | sel原始记录文件 | 原始二进制SEL数据 | 硬件事件 | Asserted, Deasserted |
| AppDump | sel.db | - | sel数据库文件 | 系统事件日志数据库文件 | 硬件事件 | Asserted, Deasserted |
| AppDump | LedInfo | - | 服务器当前LED灯的显示状态 | 前面板、UID等指示灯的当前点亮状态 | 指示灯 | blink error |
| AppDump | sensor_alarm_sel.bin.tar.gz | - | sel历史记录打包文件 | sel历史记录打包文件 | 硬件事件 | Asserted, Deasserted |
| AppDump | MaintDebug_dfl.log | - | MaintDebug模块管理对象的信息 | 维护调试模块日志 | 调试 | - |
| AppDump | mctp_info | - | MCTP配置信息 | MCTP网络的EID分配、拓扑信息 | MCTP | - |
| AppDump | MCTP_dfl.log | - | MCTP模块管理对象的信息 | MCTP（管理组件传输协议）协议栈日志 | PCIe、SMBus | packet drop、timeout |
| AppDump | FileManage_dfl.log | - | FileManage模块管理对象的信息 | 文件管理模块日志，涉及文件上传下载、存储管理 | iBMC存储 | write error、disk full |
| AppDump | switch_card_dfl.log | - | Switch_Card模块管理对象的信息 | Switch_Card模块管理对象的信息 | - | - |
| AppDump | phy_register_info | - | 后插板phy寄存器信息 | 后插板phy寄存器信息 | - | - |
| AppDump | port_adapter_info | - | 后插板接口器件信息 | 后插板接口器件信息 | - | - |
| AppDump | StorageMgnt_dfl.log | - | StorageMgnt模块管理对象的信息 | 存储管理模块日志，涉及RAID卡与硬盘纳管 | 存储 | comm lost |
| AppDump | RAID_Controller_Info.txt | - | 当前RAID控制器/逻辑盘/硬盘阵列/硬盘的信息 | RAID卡、逻辑盘(LD)、物理盘(PD)的详细属性与状态 | RAID、硬盘 | Offline、Degraded、Rebuild |
| AppDump | rimm_dfl.log | - | RIMM模块管理对象的信息 | RIMM模块管理对象的信息 | - | - |
| AppDump | redfish_dfl.log | - | Redfish模块管理对象的信息 | Redfish服务运行日志，记录API请求与处理 | Redfish API | 5xx error、4xx error |
| AppDump | component_uri.json | - | 部件URI列表 | Redfish资源树中各组件的URI映射 | Redfish | - |
| AppDump | dfm.log | - | DFM模块管理对象的信息 | 故障诊断管理(DFM)模块日志，负责故障检测与隔离 | 故障诊断 | fault detected、isolate |
| AppDump | dfm_debug_log | - | PME框架调试日志 | PME框架调试日志 | - | - |
| AppDump | dfm_debug_log.1 | - | PME框架调试日志 | PME框架调试日志 | - | - |
| 3rdDump | error_log | - | Apache错误日志 | Apache错误日志 | - | error, fail |
| 3rdDump | access_log | - | Apache访问日志 | Apache访问日志 | - | - |
| 3rdDump | error_log.1 | - | Apache错误日志备份文件 | Apache错误日志备份文件 | - | error, fail |
| 3rdDump | access_log.1 | - | Apache访问日志备份文件 | Apache访问日志备份文件 | - | - |
| 3rdDump | httpd.conf | - | Apache http配置文件 | Apache http配置文件 | - | - |
| 3rdDump | httpd-port.conf | - | Apache http端口配置文件 | Apache http端口配置文件 | - | - |
| 3rdDump | httpd-ssl.conf | - | Apache https配置文件 | Apache https配置文件 | - | - |
| 3rdDump | httpd-ssl-port.conf | - | Apache https端口配置文件 | Apache https端口配置文件 | - | - |
| 3rdDump | httpd-ssl-protocol.conf | - | Apache https协议版本配置文件 | Apache https协议版本配置文件 | - | - |
| 3rdDump | httpd-ssl-ciphersuite.conf | - | Apache https协议加密套件配置文件 | Apache https协议加密套件配置文件 | - | - |
| BMALogDump | bma_debug_log | - | iBMA日志 | iBMA日志 | - | - |
| BMALogDump | bma_debug_log.1.gz | - | iBMA日志 | iBMA日志 | - | - |
| BMALogDump | bma_debug_log.2.gz | - | iBMA日志 | iBMA日志 | - | - |
| BMALogDump | bma_debug_log.3.gz | - | iBMA日志 | iBMA日志 | - | - |
| CoreDump | core-* | - | 内存转储文件，根据系统运行情况可能产生一个或者多个文件，为应用程序core dump文件 | iBMC进程崩溃产生的Core Dump文件 | iBMC进程 | segfault、abort |
| RTOSDump | cmdline | - | BMC内核的命令行参数 | iBMC Linux内核启动参数 | iBMC内核 | - |
| RTOSDump | cpuinfo | - | BMC内核的CPU芯片信息 | iBMC SoC的CPU信息 | iBMC硬件 | - |
| RTOSDump | devices | - | BMC系统的设备信息 | BMC系统的设备信息 | - | - |
| RTOSDump | df_info | - | BMC分区空间的使用信息 | iBMC文件系统的磁盘空间使用率 | iBMC存储 | 100% usage、disk full |
| RTOSDump | diskstats | - | BMC的磁盘信息 | BMC的磁盘信息 | - | - |
| RTOSDump | filesystems | - | BMC的文件系统信息 | BMC的文件系统信息 | - | - |
| RTOSDump | free_info | - | BMC的内存使用概况 | iBMC系统的内存使用情况 | iBMC内存 | Out of memory |
| RTOSDump | interrupts | - | BMC的中断信息 | BMC的中断信息 | - | - |
| RTOSDump | ipcs_q | - | BMC的进程队列信息 | BMC的进程队列信息 | - | - |
| RTOSDump | ipcs_q_detail | - | BMC的进程队列详细信息 | BMC的进程队列详细信息 | - | - |
| RTOSDump | ipcs_s | - | BMC的进程信号量信息 | BMC的进程信号量信息 | - | - |
| RTOSDump | ipcs_s_detail | - | BMC的进程信号量详细信息 | BMC的进程信号量详细信息 | - | - |
| RTOSDump | loadavg | - | BMC系统运行负载情况 | iBMC系统的平均负载 | iBMC性能 | high load |
| RTOSDump | locks | - | BMC内核锁住的文件列表 | BMC内核锁住的文件列表 | - | - |
| RTOSDump | meminfo | - | BMC的内存占用详细信息 | iBMC系统的详细内存统计 | iBMC内存 | - |
| RTOSDump | modules | - | BMC的模块加载列表 | BMC的模块加载列表 | - | - |
| RTOSDump | mtd | - | BMC的配置分区信息 | MTD闪存分区表 | iBMC存储 | - |
| RTOSDump | partitions | - | BMC所有设备分区信息 | BMC所有设备分区信息 | - | - |
| RTOSDump | ps_info | - | BMC进程详细信息 | BMC进程详细信息 | - | - |
| RTOSDump | slabinfo | - | BMC内核内存管理slab信息 | BMC内核内存管理slab信息 | - | - |
| RTOSDump | stat | - | BMC的CPU利用率 | BMC的CPU利用率 | - | - |
| RTOSDump | top_info | - | 显示当前BMC进程运行情况 | top命令输出，显示iBMC进程资源占用 | iBMC进程 | high CPU |
| RTOSDump | uname_info | - | 显示当前BMC内核版本 | 显示当前BMC内核版本 | - | - |
| RTOSDump | uptime | - | BMC系统运行时间 | iBMC自上次启动以来的运行时长 | iBMC系统 | unexpected reboot |
| RTOSDump | version | - | BMC当前的RTOS版本 | BMC当前的RTOS版本 | - | - |
| RTOSDump | vmstat | - | BMC虚拟内存统计信息 | BMC虚拟内存统计信息 | - | - |
| RTOSDump | ibmc_revision.txt | - | BMC版本编译节点信息 | iBMC固件的详细版本与编译时间 | iBMC固件 | - |
| RTOSDump | app_revision.txt | - | BMC版本信息 | BMC版本信息 | - | - |
| RTOSDump | build_date.txt | - | BMC版本构建时间 | BMC版本构建时间 | - | - |
| RTOSDump | fruinfo.txt | - | FRU电子标签信息 | iBMC所在板卡的FRU信息 | FRU | - |
| RTOSDump | RTOS-Release | - | RTOS版本信息 | RTOS版本信息 | - | - |
| RTOSDump | RTOS-Revision | - | RTOS版本标记号 | RTOS版本标记号 | - | - |
| RTOSDump | server_config.txt | - | 服务器当前的配置信息 | 服务器当前的配置信息 | - | - |
| RTOSDump | ifconfig_info | - | 网络信息，执行ifconfig的结果 | ifconfig命令输出，显示iBMC网口IP与统计 | iBMC网络 | errors、dropped |
| RTOSDump | ipinfo_info | - | BMC配置的网络信息 | BMC配置的网络信息 | - | - |
| RTOSDump | _data_var_dhcp_dhclient.leases | - | DHCP租约文件 | DHCP租约文件 | - | - |
| RTOSDump | dhclient.leases | - | DHCP租约文件 | DHCP租约文件 | - | - |
| RTOSDump | dhclient6.leases | - | DHCP租约文件 | DHCP租约文件 | - | - |
| RTOSDump | dhclient6_eth0.leases | - | DHCP租约文件 | DHCP租约文件 | - | - |
| RTOSDump | dhclient6_eth1.leases | - | DHCP租约文件 | DHCP租约文件 | - | - |
| RTOSDump | dhclient6_eth2.leases | - | DHCP租约文件 | DHCP租约文件 | - | - |
| RTOSDump | dhclient.conf | - | DHCP配置文件 | DHCP配置文件 | - | - |
| RTOSDump | dhclient_ip.conf | - | DHCP配置文件 | DHCP配置文件 | - | - |
| RTOSDump | dhclient6.conf | - | DHCP配置文件 | DHCP配置文件 | - | - |
| RTOSDump | dhclient6_ip.conf | - | DHCP配置文件 | DHCP配置文件 | - | - |
| RTOSDump | resolv.conf | - | DNS配置文件 | DNS配置文件 | - | - |
| RTOSDump | netstat_info | - | 显示当前网络端口、连接使用情况 | netstat命令输出，显示网络连接与监听端口 | iBMC网络 | TIME_WAIT |
| RTOSDump | route_info | - | 显示当前路由信息 | 显示当前路由信息 | - | - |
| RTOSDump | services | - | 服务端口信息 | 服务端口信息 | - | - |
| RTOSDump | extern.conf | - | BMC日志文件配置 | BMC日志文件配置 | - | - |
| RTOSDump | remotelog.conf | - | syslog定制配置文件 | 远程syslog服务器配置 | 日志审计 | - |
| RTOSDump | ssh | - | SSH服务配置 | SSH服务配置 | - | - |
| RTOSDump | sshd_config | - | SSHD服务配置文件 | SSH服务配置文件 | SSH服务 | - |
| RTOSDump | logrotate.status | - | logrotate状态记录文件 | logrotate状态记录文件 | - | - |
| RTOSDump | login | - | login PAM登录规则 | login PAM登录规则 | - | - |
| RTOSDump | sshd | - | SSH PAM登录规则 | SSH PAM登录规则 | - | - |
| RTOSDump | pam_tally2 | - | 登录BMC失败的锁定规则 | 登录BMC失败的锁定规则 | - | - |
| RTOSDump | datafs_log | - | data检测日志 | data检测日志 | - | - |
| RTOSDump | ntp.conf | - | NTP服务配置 | NTP服务配置 | - | - |
| RTOSDump | vsftpd | - | FTP PAM登录规则 | FTP PAM登录规则 | - | - |
| RTOSDump | dmesg_info | - | 系统启动信息，执行dmesg的结果 | iBMC Linux内核的启动与运行消息 | iBMC内核 | error、fail、call trace |
| RTOSDump | lsmod_info | - | 当前加载驱动模块信息 | 当前加载驱动模块信息 | - | - |
| RTOSDump | kbox_info | - | kbox信息 | kbox信息 | - | - |
| RTOSDump | edma_drv_info | - | edma驱动信息 | edma驱动信息 | - | - |
| RTOSDump | cdev_drv_info | - | 字符设备驱动信息 | 字符设备驱动信息 | - | - |
| RTOSDump | veth_drv_info | - | 虚拟网卡驱动信息 | 虚拟网卡驱动信息 | - | - |
| SpLogDump | config | - | 配置导出备份文件<br>说明：SP运行过程中无法收集此日志；SP运行配置导出功能后可收集该日志 | 配置导出备份文件<br>说明：SP运行过程中无法收集此日志；SP运行配置导出功能后可收集该日志 | - | - |
| SpLogDump | deviceinfo.json | - | 服务器资产信息<br>说明：SP运行过程中无法收集此日志 | 服务器资产信息<br>说明：SP运行过程中无法收集此日志 | - | - |
| SpLogDump | diagnose | - | 硬件诊断日志<br>说明：SP运行过程中无法收集此日志；SP运行硬件诊断功能后可收集该日志 | 硬件诊断日志<br>说明：SP运行过程中无法收集此日志；SP运行硬件诊断功能后可收集该日志 | - | - |
| SpLogDump | DriveErase | - | 硬盘擦除功能日志<br>说明：SP运行过程中无法收集此日志；SP运行硬盘擦除功能后可收集该日志 | 硬盘擦除功能日志<br>说明：SP运行过程中无法收集此日志；SP运行硬盘擦除功能后可收集该日志 | - | - |
| SpLogDump | iBMALogDump | - | iBMA运行日志<br>说明：SP运行过程中无法收集此日志 | iBMA运行日志<br>说明：SP运行过程中无法收集此日志 | - | - |
| SpLogDump | dmesg.log | - | 小系统dmesg日志<br>说明：SP运行过程中无法收集此日志 | 小系统dmesg日志<br>说明：SP运行过程中无法收集此日志 | - | - |
| SpLogDump | dmesg.tar.gz | - | 小系统dmesg日志<br>说明：SP运行过程中无法收集此日志 | 小系统dmesg日志<br>说明：SP运行过程中无法收集此日志 | - | - |
| SpLogDump | filepatchup_debug.log | - | 极速部署文件打包日志<br>说明：SP运行过程中无法收集此日志；SP运行极速部署功能后可收集该日志 | 极速部署文件打包日志<br>说明：SP运行过程中无法收集此日志；SP运行极速部署功能后可收集该日志 | - | - |
| SpLogDump | images.log | - | 极速部署克隆日志<br>说明：SP运行过程中无法收集此日志；SP运行极速部署功能后可收集该日志 | 极速部署克隆日志<br>说明：SP运行过程中无法收集此日志；SP运行极速部署功能后可收集该日志 | - | - |
| SpLogDump | images_restore.log | - | 极速部署还原日志<br>说明：SP运行过程中无法收集此日志；SP运行极速部署还原功能后可收集该日志 | 极速部署还原日志<br>说明：SP运行过程中无法收集此日志；SP运行极速部署还原功能后可收集该日志 | - | - |
| SpLogDump | maintainlog.csv | - | SP维护日志<br>说明：SP运行过程中无法收集此日志 | SP维护日志<br>说明：SP运行过程中无法收集此日志 | - | - |
| SpLogDump | maintainlog.tar.gz | - | SP维护日志<br>说明：SP运行过程中无法收集此日志 | SP维护日志<br>说明：SP运行过程中无法收集此日志 | - | - |
| SpLogDump | operatelog.csv | - | SP运行日志<br>说明：SP运行过程中无法收集此日志 | SP运行日志<br>说明：SP运行过程中无法收集此日志 | - | - |
| SpLogDump | operatinglog.tar.gz | - | SP运行日志<br>说明：SP运行过程中无法收集此日志 | SP运行日志<br>说明：SP运行过程中无法收集此日志 | - | - |
| SpLogDump | ping6.log | - | 网络通信日志<br>说明：SP运行过程中无法收集此日志 | 网络通信日志<br>说明：SP运行过程中无法收集此日志 | - | - |
| SpLogDump | ping6.tar.gz | - | 网络通信日志<br>说明：SP运行过程中无法收集此日志 | 网络通信日志<br>说明：SP运行过程中无法收集此日志 | - | - |
| SpLogDump | quickdeploy_debug.log | - | 极速部署日志<br>说明：SP运行过程中无法收集此日志；SP运行极速部署功能后可收集该日志 | 极速部署日志<br>说明：SP运行过程中无法收集此日志；SP运行极速部署功能后可收集该日志 | - | - |
| SpLogDump | varmesg.log | - | 小系统信息日志<br>说明：SP运行过程中无法收集此日志 | 小系统信息日志<br>说明：SP运行过程中无法收集此日志 | - | - |
| SpLogDump | syslog.tar.gz | - | 小系统信息日志<br>说明：SP运行过程中无法收集此日志 | 小系统信息日志<br>说明：SP运行过程中无法收集此日志 | - | - |
| SpLogDump | sp_upgrade_info.log | - | SP自升级日志<br>说明：SP运行过程中无法收集此日志；SP运行自升级功能后可收集该日志 | SP自升级日志<br>说明：SP运行过程中无法收集此日志；SP运行自升级功能后可收集该日志 | - | - |
| SpLogDump | upgrade | - | SP固件升级日志<br>说明：SP运行过程中无法收集此日志 | SP固件升级日志<br>说明：SP运行过程中无法收集此日志 | - | - |
| SpLogDump | version.json | - | SP版本配置文件<br>说明：SP运行过程中无法收集此日志 | SP版本配置文件<br>说明：SP运行过程中无法收集此日志 | - | - |
| SpLogDump | version.json.*.sha | - | SP版本配置文件的校验文件<br>说明：SP运行过程中无法收集此日志 | SP版本配置文件的校验文件<br>说明：SP运行过程中无法收集此日志 | - | - |
| LogDump | netcard_info.txt | - | 网卡配置信息 | 网卡配置信息 | - | - |
| LogDump | netcard_info_bk.txt | - | 网卡配置信息 | 网卡配置信息 | - | - |
| LogDump | arm_fdm_log | - | FDM日志 | FDM日志 | - | - |
| LogDump | arm_fdm_log.tar.gz | - | FDM日志 | FDM日志 | - | - |
| LogDump | LSI_RAID_Controller_Log | - | LSI RAID控制器的日志 | LSI RAID控制器的日志 | - | - |
| LogDump | LSI_RAID_Controller_Log.1.gz | - | LSI RAID控制器的日志 | LSI RAID控制器的日志 | - | - |
| LogDump | LSI_RAID_Controller_Log.2.gz | - | LSI RAID控制器的日志 | LSI RAID控制器的日志 | - | - |
| LogDump | PD_SMART_INFO_C* | - | 硬盘的SMART日志，*为RAID控制器的编号 | 硬盘的SMART日志，*为RAID控制器的编号 | - | - |
| LogDump | linux_kernel_log | - | Linux内核日志 | iBMC OS的内核日志归档 | iBMC内核 | panic、oops |
| LogDump | linux_kernel_log.1 | - | Linux内核日志 | Linux内核日志 | - | - |
| LogDump | operate_log | - | 用户操作日志 | 用户操作日志 | - | - |
| LogDump | operate_log.tar.gz | - | 用户操作日志 | 用户操作日志 | - | - |
| LogDump | mass_operate_log | - | 用户操作日志 | 用户操作日志 | - | - |
| LogDump | mass_operate_log.tar.gz | - | 用户操作日志 | 用户操作日志 | - | - |
| LogDump | remote_log | - | syslog test操作日志、sel日志 | 远程日志测试记录 | 日志审计 | - |
| LogDump | remote_log.1.gz | - | syslog test操作日志、sel日志 | syslog test操作日志、sel日志 | - | - |
| LogDump | security_log | - | 安全日志 | 安全相关事件（认证失败、攻击检测） | 安全审计 | auth fail |
| LogDump | security_log.1 | - | 安全日志 | 安全日志 | - | - |
| LogDump | strategy_log | - | 运行日志 | 运行日志 | - | - |
| LogDump | strategy_log.tar.gz | - | 运行日志 | 运行日志 | - | - |
| LogDump | fdm.bin | - | FDM原始故障日志 | 故障诊断管理(FDM)的原始日志数据 | 硬件故障 | - |
| LogDump | fdm.bin.tar.gz | - | FDM原始故障日志 | FDM原始故障日志 | - | - |
| LogDump | fdm_me_log | - | ME运行日志 | ME运行日志 | - | - |
| LogDump | fdm_me_log.tar.gz | - | ME运行日志 | ME运行日志 | - | - |
| LogDump | fdm_pfae_log | - | FDM预告警日志 | FDM预告警日志 | - | - |
| LogDump | fdm_mmio_log | - | FDM板卡配置日志 | FDM板卡配置日志 | - | - |
| LogDump | fdm_mmio_log.tar.gz | - | FDM板卡配置日志 | FDM板卡配置日志 | - | - |
| LogDump | maintenance_log | - | 维护日志 | 用户维护操作记录（登录、重启等） | 操作审计 | - |
| LogDump | maintenance_log.tar.gz | - | 维护日志 | 维护日志 | - | - |
| LogDump | imu_log | - | IMU运行日志（仅针对支持IMU模块的服务器） | IMU运行日志（仅针对支持IMU模块的服务器） | - | - |
| LogDump | imu_log.tar.gz | - | IMU运行日志（仅针对支持IMU模块的服务器） | IMU运行日志（仅针对支持IMU模块的服务器） | - | - |
| LogDump | cpu1_m7_log | - | CPU1的M7协处理器运行日志（仅针对支持M7协处理器的服务器） | CPU1的M7协处理器运行日志（仅针对支持M7协处理器的服务器） | - | - |
| LogDump | cpu1_m7_log.tar.gz | - | CPU1的M7协处理器运行日志（仅针对支持M7协处理器的服务器） | CPU1的M7协处理器运行日志（仅针对支持M7协处理器的服务器） | - | - |
| LogDump | cpu2_m7_log | - | CPU2的M7协处理器运行日志（仅针对支持M7协处理器的服务器） | CPU2的M7协处理器运行日志（仅针对支持M7协处理器的服务器） | - | - |
| LogDump | cpu2_m7_log.tar.gz | - | CPU2的M7协处理器运行日志（仅针对支持M7协处理器的服务器） | CPU2的M7协处理器运行日志（仅针对支持M7协处理器的服务器） | - | - |
| LogDump | ipmi_debug_log | - | IPMI模块日志 | IPMI模块日志 | - | - |
| LogDump | ipmi_debug_log.tar.gz | - | IPMI模块日志 | IPMI模块日志 | - | - |
| LogDump | ipmi_mass_operate_log | - | IPMI模块运行日志 | 大量IPMI操作记录 | IPMI | - |
| LogDump | ipmi_mass_operate_log.tar.gz | - | IPMI模块运行日志 | IPMI模块运行日志 | - | - |
| LogDump | app_debug_log_all | - | 所有应用模块调试日志 | 所有应用模块调试日志 | - | - |
| LogDump | app_debug_log_all.1.gz | - | 所有应用模块调试日志 | 所有应用模块调试日志 | - | - |
| LogDump | app_debug_log_all.2.gz | - | 所有应用模块调试日志 | 所有应用模块调试日志 | - | - |
| LogDump | app_debug_log_all.3.gz | - | 所有应用模块调试日志 | 所有应用模块调试日志 | - | - |
| LogDump | agentless_driver_log | - | agentless驱动的日志文件 | agentless驱动的日志文件 | - | - |
| LogDump | agentless_driver_log.1.gz | - | agentless驱动的日志文件 | agentless驱动的日志文件 | - | - |
| LogDump | agentless_driver_log.2.gz | - | agentless驱动的日志文件 | agentless驱动的日志文件 | - | - |
| LogDump | agentless_driver_log.3.gz | - | agentless驱动的日志文件 | agentless驱动的日志文件 | - | - |
| LogDump | kvm_vmm_debug_log | - | KVM模块日志 | KVM模块日志 | - | - |
| LogDump | kvm_vmm_debug_log.tar.gz | - | KVM模块日志 | KVM模块日志 | - | - |
| LogDump | ps_black_box.log | - | 电源黑匣子日志 | 电源模块的黑匣子数据，记录故障前状态 | 电源 | power fault |
| LogDump | ps_black_box.log.1.gz | - | 电源黑匣子日志 | 电源黑匣子日志 | - | - |
| LogDump | ps_black_box.log.2.gz | - | 电源黑匣子日志 | 电源黑匣子日志 | - | - |
| LogDump | ps_black_box.log.3.gz | - | 电源黑匣子日志 | 电源黑匣子日志 | - | - |
| LogDump | third_party_file_bak.log | - | 第三方文件备份日志记录 | 第三方文件备份日志记录 | - | - |
| LogDump | *_com_log | - | RAID扣卡串口日志 | RAID扣卡串口日志 | - | - |
| LogDump | *_com_log.1.gz | - | RAID扣卡串口日志 | RAID扣卡串口日志 | - | - |
| LogDump | drivelog | - | 所有SAS和SATA硬盘的日志信息文件夹 | 所有SAS和SATA硬盘的日志信息文件夹 | - | - |
| LogDump | phy | - | 所有RAID卡和该卡下Expander的PHY误码日志信息文件夹 | 所有RAID卡和该卡下Expander的PHY误码日志信息文件夹 | - | - |
| LogDump | pciecard | - | PCIe卡日志文件夹 | PCIe卡日志文件夹 | - | - |
| LogDump | Retimer | - | Retimer日志文件夹 | Retimer日志文件夹 | - | - |
| OSDump | systemcom.tar | - | SOL串口信息 | 串口重定向(SOL)捕获的OS启动或运行日志 | OS串口日志 | console logs |
| OSDump | img*.jpeg | - | 业务侧最后一屏图像 | 业务侧（服务器OS）崩溃时的最后屏幕截图 | 故障复现 | BSOD、Kernel Panic |
| OSDump | *.rep | - | 业务侧屏幕自动录像文件 | 业务侧（服务器OS）崩溃或故障时的KVM屏幕录像 | 故障复现 | - |
| OSDump | video_caterror_rep_is_deleted.info | - | 删除过大的caterror录像的提示 | 删除过大的caterror录像的提示 | - | error, fail |
| DeviceDump | *_info | - | I2C设备的寄存器/存储区信息 | I2C设备的寄存器/存储区信息 | - | - |
| Register | cpld_reg_info | - | CPLD寄存器信息 | CPLD寄存器信息 | - | - |
| OptPme | - | - | 本文件夹的文件来源于/opt/pme/pram目录，中间文件无信息安全问题 | 本文件夹的文件来源于/opt/pme/pram目录，中间文件无信息安全问题 | - | - |
| OptPme | filelist | - | /opt/pme/pram目录下文件列表 | /opt/pme/pram目录下文件列表 | - | - |
| OptPme | BIOS_FileName | - | SMBIOS信息 | SMBIOS信息 | - | - |
| OptPme | BIOS_OptionFileName | - | BIOS配置信息 | BIOS配置信息 | - | - |
| OptPme | BMC_dhclient.conf | - | DHCP配置文件 | DHCP配置文件 | - | - |
| OptPme | BMC_dhclient6.conf | - | DHCP配置文件 | DHCP配置文件 | - | - |
| OptPme | BMC_dhclient6_ip.conf | - | DHCP配置文件 | DHCP配置文件 | - | - |
| OptPme | BMC_dhclient_ip.conf | - | DHCP配置文件 | DHCP配置文件 | - | - |
| OptPme | BMC_HOSTNAME | - | BMC主机名 | BMC主机名 | - | - |
| OptPme | CpuMem_cpu_utilise | - | 服务器CPU利用率 | 服务器CPU利用率 | - | - |
| OptPme | CpuMem_mem_utilise | - | 服务器内存利用率 | 服务器内存利用率 | - | - |
| OptPme | cpu_utilise_webview.dat | - | CPU利用率曲线数据 | CPU利用率曲线数据 | - | - |
| OptPme | env_web_view.dat | - | 环境温度曲线数据 | 环境温度曲线数据 | - | - |
| OptPme | fsync_reg.ini | - | 文件同步配置文件 | 文件同步配置文件 | - | - |
| OptPme | lost+found | - | 文件夹 | 文件夹 | - | - |
| OptPme | md_so_maintenance_log | - | 维护日志 | 维护日志 | - | - |
| OptPme | md_so_maintenance_log.tar.gz | - | 维护日志 | 维护日志 | - | - |
| OptPme | md_so_operate_log | - | 操作日志 | 操作日志 | - | - |
| OptPme | md_so_operate_log.tar.gz | - | 操作日志 | 操作日志 | - | - |
| OptPme | md_so_mass_operate_log | - | 操作日志 | 操作日志 | - | - |
| OptPme | md_so_mass_operate_log.tar.gz | - | 操作日志 | 操作日志 | - | - |
| OptPme | md_so_strategy_log | - | 策略日志 | 策略日志 | - | - |
| OptPme | md_so_strategy_log.tar.gz | - | 策略日志 | 策略日志 | - | - |
| OptPme | memory_webview.dat | - | 管理对象运行信息 | 管理对象运行信息 | - | - |
| OptPme | per_config.ini | - | BMC配置持久化文件 | iBMC的各项配置保存文件 | iBMC配置 | - |
| OptPme | per_config_permanent.ini | - | BMC配置持久化文件 | BMC配置持久化文件 | - | - |
| OptPme | per_config_reset.ini | - | BMC配置持久化文件 | BMC配置持久化文件 | - | - |
| OptPme | per_config_reset.ini.bak | - | BMC配置持久化文件 | BMC配置持久化文件 | - | - |
| OptPme | per_def_config.ini | - | BMC配置持久化文件 | BMC配置持久化文件 | - | - |
| OptPme | per_def_config_permanent.ini | - | BMC配置持久化文件 | BMC配置持久化文件 | - | - |
| OptPme | per_def_config_reset.ini | - | BMC配置持久化文件 | BMC配置持久化文件 | - | - |
| OptPme | per_def_config_reset.ini.bak | - | BMC配置持久化文件 | BMC配置持久化文件 | - | - |
| OptPme | per_power_off.ini | - | BMC配置持久化文件 | BMC配置持久化文件 | - | - |
| OptPme | per_reset.ini | - | BMC配置持久化文件 | BMC配置持久化文件 | - | - |
| OptPme | per_reset.ini.bak | - | BMC配置持久化文件 | BMC配置持久化文件 | - | - |
| OptPme | pflash_lock | - | flash文件锁 | flash文件锁 | - | - |
| OptPme | PowerMgnt_record | - | 管理对象运行信息 | 管理对象运行信息 | - | - |
| OptPme | powerview.txt | - | 功率统计文件 | 功率统计文件 | - | - |
| OptPme | proc_queue | - | 进程队列id文件夹 | 进程队列id文件夹 | - | - |
| OptPme | ps_web_view.dat | - | 管理对象运行信息 | 管理对象运行信息 | - | - |
| OptPme | sel.db | - | SEL数据库 | 系统事件日志数据库文件 | 硬件事件 | Asserted, Deasserted |
| OptPme | sel_db_sync | - | SEL数据库同步锁 | SEL数据库同步锁 | 硬件事件 | Asserted, Deasserted |
| OptPme | semid | - | 进程信号量id文件夹 | 进程信号量id文件夹 | - | - |
| OptPme | sensor_alarm_sel.bin | - | SEL原始记录文件 | 原始二进制SEL数据 | 硬件事件 | Asserted, Deasserted |
| OptPme | sensor_alarm_sel.bin.tar.gz | - | SEL历史记录打包文件 | SEL历史记录打包文件 | 硬件事件 | Asserted, Deasserted |
| OptPme | Snmp_snmpd.conf | - | Snmp配置文件 | Snmp配置文件 | - | - |
| OptPme | Snmp_http_configure | - | HTTP配置文件 | HTTP配置文件 | - | - |
| OptPme | Snmp_https_configure | - | HTTPS配置文件 | HTTPS配置文件 | - | - |
| OptPme | Snmp_https_tsl | - | HTTPS TLS配置文件 | HTTPS TLS配置文件 | - | - |
| OptPme | up_cfg | - | 升级配置文件夹 | 升级配置文件夹 | - | - |
| OptPme | User_login | - | login PAM登录规则 | login PAM登录规则 | - | - |
| OptPme | User_sshd | - | SSH PAM登录规则 | SSH PAM登录规则 | - | - |
| OptPme | User_sshd_config | - | SSH配置文件 | SSH配置文件 | - | - |
| OptPme | User_vsftp | - | FTP PAM登录规则 | FTP PAM登录规则 | - | - |
| OptPme | eo.db | - | SEL数据库 | SEL数据库 | - | - |
| OptPme | - | - | 本文件夹文件来源于/opt/pme/save目录，中间文件无信息安全问题 | 本文件夹文件来源于/opt/pme/save目录，中间文件无信息安全问题 | - | - |
| OptPme | filelist | - | /opt/pme/pram目录下文件列表 | /opt/pme/pram目录下文件列表 | - | - |
| OptPme | BIOS_FileName | - | SMBIOS信息 | SMBIOS信息 | - | - |
| OptPme | BMC_dhclient.conf.bak | - | DHCP配置备份文件 | DHCP配置备份文件 | - | - |
| OptPme | BMC_dhclient6.conf.bak | - | DHCP配置备份文件 | DHCP配置备份文件 | - | - |
| OptPme | BMC_dhclient6_ip.conf.bak | - | DHCP配置备份文件 | DHCP配置备份文件 | - | - |
| OptPme | BMC_dhclient_ip.conf.bak | - | DHCP配置备份文件 | DHCP配置备份文件 | - | - |
| OptPme | BMC_HOSTNAME.bak | - | 主机名配置备份文件 | 主机名配置备份文件 | - | - |
| OptPme | CpuMem_cpu_utilise | - | 管理对象运行信息 | 管理对象运行信息 | - | - |
| OptPme | CpuMem_mem_utilise | - | 管理对象运行信息 | 管理对象运行信息 | - | - |
| OptPme | md_so_operate_log.bak | - | 操作日志 | 操作日志 | - | - |
| OptPme | md_so_strategy_log.bak | - | 策略日志 | 策略日志 | - | - |
| OptPme | per_config.ini | - | BMC配置持久化文件 | iBMC的各项配置保存文件 | iBMC配置 | - |
| OptPme | per_config.ini.bak | - | BMC配置持久化文件 | BMC配置持久化文件 | - | - |
| OptPme | per_def_config.ini | - | BMC配置持久化文件 | BMC配置持久化文件 | - | - |
| OptPme | per_def_config.ini.bak | - | BMC配置持久化文件 | BMC配置持久化文件 | - | - |
| OptPme | per_power_off.ini | - | BMC配置持久化文件 | BMC配置持久化文件 | - | - |
| OptPme | per_power_off.ini.bak | - | BMC配置持久化文件 | BMC配置持久化文件 | - | - |
| OptPme | PowerMgnt_record | - | 管理对象运行信息 | 管理对象运行信息 | - | - |
| OptPme | sensor_alarm_sel.bin | - | SEL原始记录文件 | 原始二进制SEL数据 | 硬件事件 | Asserted, Deasserted |
| OptPme | sensor_alarm_sel.bin.bak | - | SEL原始记录文件 | SEL原始记录文件 | 硬件事件 | Asserted, Deasserted |
| OptPme | sensor_alarm_sel.bin.tar.gz | - | SEL历史记录打包文件 | SEL历史记录打包文件 | 硬件事件 | Asserted, Deasserted |
| OptPme | Snmp_http_configure.bak | - | HTTP配置备份文件 | HTTP配置备份文件 | - | - |
| OptPme | Snmp_https_configure.bak | - | HTTPS配置备份文件 | HTTPS配置备份文件 | - | - |
| OptPme | Snmp_https_tsl.bak | - | HTTPS TLS配置备份文件 | HTTPS TLS配置备份文件 | - | - |
| OptPme | Snmp_snmpd.conf.bak | - | Snmp配置备份文件 | Snmp配置备份文件 | - | - |
| OptPme | User_login.bak | - | login PAM登录规则 | login PAM登录规则 | - | - |
| OptPme | User_sshd.bak | - | SSH PAM登录规则 | SSH PAM登录规则 | - | - |
| OptPme | User_sshd_config.bak | - | SSH配置文件 | SSH配置文件 | - | - |
| OptPme | User_vsftp.bak | - | FTP PAM登录规则 | FTP PAM登录规则 | - | - |
| OptPme | eo.db | - | SEL数据库 | SEL数据库 | - | - |
| OptPme | eo.db_backup | - | SEL数据库 | SEL数据库 | - | - |
| OptPme | eo.db.sha256_backup | - | 完整性校验码 | 完整性校验码 | - | - |
</toolcall_result>
