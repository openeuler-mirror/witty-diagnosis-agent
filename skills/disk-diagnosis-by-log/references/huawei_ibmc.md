# 华为 iBMC 日志深度分析指南

## 一、iBMC 日志体系全景

iBMC（intelligent Baseboard Management Controller）是华为服务器的带外管理核心，其日志体系分为**7大类**：

```
iBMC 日志体系
├── 🔴 硬件故障类    SEL、FDM、传感器、PSU黑匣子
├── 🟠 系统运行类    BMC_dfl、SysInfo、CoreDump
├── 🟡 存储类        StorageMgnt、RAID、FileManage
├── 🟢 网络类        NetConfig、ifconfig、MCTP
├── 🔵 固件配置类    BIOS、Upgrade、FruData
├── 🟣 安全审计类    User、security_log、maintenance_log
└── ⚫ OS侧类        OSDump、systemcom、agentless
```

---

## 二、错误类型全景分类

### 🔴 1. 硬件故障类（最高优先级）

| 日志文件 | 错误类型 | 关键字 | 含义 |
|---|---|---|---|
| `sel.db / sel.tar` | 硬件事件 | `Asserted` | 告警触发 |
| `sel.db / sel.tar` | 硬件恢复 | `Deasserted` | 告警解除 |
| `current_event.txt` | 全局健康 | `Critical` / `Major` | 严重/重要告警未清除 |
| `sensor_info.txt` | 传感器异常 | `reading unavailable` | 传感器无法读取 |
| `sensor_alarm_dfl.log` | 阈值越界 | `threshold crossed` | 温度/电压超阈值 |
| `fdm_output` | FDM诊断 | `Fault` | 系统检出硬件故障 |
| `ps_black_box.log` | 电源黑匣子 | `power fault` | 电源故障前快照 |
| `fan_info.txt` | 风扇故障 | `speed low` / `missing` | 风扇低速或缺失 |
| `psu_info.txt` | 电源模块 | `power loss` / `input lost` | 电源丢失 |

---

### 🟠 2. iBMC 自身系统类

| 日志文件 | 错误类型 | 关键字 | 含义 |
|---|---|---|---|
| `BMC_dfl.log` | BMC核心异常 | `exception` / `watchdog` | 看门狗超时/异常 |
| `CoreDump/core-*` | 进程崩溃 | `segfault` / `abort` | iBMC进程崩溃转储 |
| `linux_kernel_log` | 内核崩溃 | `panic` / `oops` | iBMC OS内核故障 |
| `dmesg_info` | 内核启动 | `call trace` / `error` | 驱动/内核错误 |
| `nandflash_info.txt` | 存储损坏 | `bad block` / `read only` | Flash存储介质损坏 |
| `df_info` | 磁盘满 | `100% usage` | iBMC分区空间耗尽 |
| `free_info` | 内存耗尽 | `Out of memory` | iBMC系统内存不足 |
| `loadavg` | 高负载 | `high load` | iBMC CPU过载 |
| `uptime` | 意外重启 | `unexpected reboot` | iBMC非预期重启 |

---

### 🟡 3. 存储类

| 日志文件 | 错误类型 | 关键字 | 含义 |
|---|---|---|---|
| `RAID_Controller_Info.txt` | RAID降级 | `Degraded` | RAID阵列降级运行 |
| `RAID_Controller_Info.txt` | 磁盘离线 | `Offline` | 物理盘/逻辑盘离线 |
| `RAID_Controller_Info.txt` | RAID重建 | `Rebuild` | 正在执行RAID重建 |
| `StorageMgnt_dfl.log` | 存储通信 | `comm lost` | RAID卡通信中断 |
| `card_manage_dfl.log` | 扣卡故障 | `card error` / `init failed` | 扣卡初始化失败 |

---

### 🟢 4. 网络类

| 日志文件 | 错误类型 | 关键字 | 含义 |
|---|---|---|---|
| `ifconfig_info` | 网口丢包 | `errors` / `dropped` | 网口错包/丢包 |
| `net_info.txt` | 链路故障 | `link down` | 管理口链路断开 |
| `MCTP_dfl.log` | MCTP通信 | `packet drop` / `timeout` | 管理总线丢包 |
| `lldp_info.txt` | 上联交换机 | `no neighbor` | 未发现LLDP邻居 |
| `ntp_info.txt` | 时钟同步 | `synchronization failed` | NTP同步失败 |
| `netstat_info` | 连接堆积 | `TIME_WAIT` | TCP连接未释放 |

---

### 🔵 5. 固件/配置类

| 日志文件 | 错误类型 | 关键字 | 含义 |
|---|---|---|---|
| `BIOS_dfl.log` | BIOS下发失败 | `config failed` | BIOS配置无法下发 |
| `result.json` | Redfish配置 | `400` / `500` | API错误 |
| `UPGRADE_dfl.log` | 升级失败 | `upgrade failed` / `verify failed` | 固件升级/校验失败 |
| `mcinfo.txt` | 版本不匹配 | `version mismatch` | 固件版本不一致 |
| `FruData_dfl.log` | FRU损坏 | `checksum error` | 电子标签校验失败 |
| `CpuMem_dfl.log` | 硬件不匹配 | `mismatch` | CPU/内存型号不匹配 |
| `mem_info` | 内存缺失 | `not present` / `size mismatch` | 内存槽位异常 |

---

### 🟣 6. 安全审计类

| 日志文件 | 错误类型 | 关键字 | 含义 |
|---|---|---|---|
| `security_log` | 认证攻击 | `auth fail` | 多次认证失败 |
| `User_dfl.log` | 权限异常 | `permission denied` | 无权限操作 |
| `portal_dfl.log` | Web异常 | `login failed` / `session timeout` | Web登录失败 |
| `Snmp_dfl.log` | SNMP鉴权 | `authentication failure` | SNMP社区名错误 |
| `maintenance_log` | 操作审计 | 用户操作记录 | 非预期操作追溯 |

---

### ⚫ 7. OS侧（业务服务器）类

| 日志文件 | 错误类型 | 关键字 | 含义 |
|---|---|---|---|
| `OSDump/img*.jpeg` | OS崩溃截图 | `BSOD` / `Kernel Panic` | 操作系统崩溃现场 |
| `systemcom.tar` | SOL串口 | `console logs` | OS启动串口完整日志 |
| `agentless_dfl.log` | 带外交互 | `connection lost` / `timeout` | iBMC与OS侧通信断开 |

---

## 三、标准分析流程（SOP）

```
┌──────────────────────────────────────────────────────────────┐
│  STEP 1：全局健康评估（5分钟快速定性）                        │
│  优先查看：current_event.txt + sel.db + LedInfo              │
└──────────────────────┬───────────────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────────────┐
│  STEP 2：时间线还原（确定故障发生时间窗口）                   │
│  优先查看：maintenance_log + BMC_dfl.log + fdm_output        │
└──────────────────────┬───────────────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────────────┐
│  STEP 3：按故障类型深入分析                                   │
│  硬件→SEL/FDM  存储→RAID  网络→ifconfig  OS→OSDump          │
└──────────────────────┬───────────────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────────────┐
│  STEP 4：iBMC自身健康检查                                     │
│  CoreDump / nandflash / df_info / loadavg / uptime           │
└──────────────────────┬───────────────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────────────┐
│  STEP 5：交叉验证（多日志印证）                               │
│  sensor_info ↔ sel.db ↔ fdm_output ↔ BMC_dfl.log            │
└──────────────────────┬───────────────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────────────┐
│  STEP 6：OS侧综合分析                                        │
│  systemcom.tar + OSDump截图 + /var/log/messages              │
└──────────────────────────────────────────────────────────────┘
```

---

## 四、各阶段详细操作指导

### STEP 1：全局健康评估

```bash
# ① 查看当前未清除告警（最直接）
cat current_event.txt
# 重点关注 Critical/Major 级别告警，记录告警名称和时间戳

# ② 查看 SEL 系统事件（按时间排序）
# sel.db 通常需要 ipmitool 解析
ipmitool -f sel_raw.bin sel list
# 或查看解析好的文本版
cat sel.tar  # 解压后查看

# ③ 查看 LED 状态（快速定位故障部件）
cat LedInfo
# UID灯亮 = 工程师标记，告警灯亮 = 存在未处理故障

# ④ 查看 FDM 诊断结果（最权威的故障判定）
cat fdm_output
grep -i "fault" fdm_output
```

---

### STEP 2：时间线还原

```bash
# ① 查看用户操作历史（排除人为变更）
cat maintenance_log
# 格式通常：时间戳 | 用户 | 操作类型 | 结果

# ② 查看 BMC 核心运行日志（按时间找异常点）
grep -iE "error|exception|watchdog|reset" BMC_dfl.log | tail -100

# ③ 检查 iBMC 是否发生意外重启
cat uptime
# 对比当前时间，若运行时间异常短则发生过重启

# ④ SEL 时间线（关键）
grep -E "Asserted|Deasserted" sel_decoded.txt | sort
# 找到最早的 Asserted 事件 = 故障起点
```

---

### STEP 3：硬件故障深入分析

#### 3A：传感器 & 温度分析

```bash
# 查看所有传感器当前值
cat sensor_info.txt
# 关注：温度传感器是否超阈值、电压是否异常

# 查看风扇状态
cat fan_info.txt
# 正常转速：通常 5000-15000 RPM，占空比 30-100%
grep -iE "fail|missing|speed low|0 RPM" fan_info.txt

# 查看散热模块日志
grep -iE "over temperature|fan fail|cooling" cooling_app_dfl.log
```

#### 3B：存储 RAID 分析

```bash
# 查看 RAID 全局状态
cat RAID_Controller_Info.txt
grep -iE "Degraded|Offline|Rebuild|Failed" RAID_Controller_Info.txt

# 分析示例输出：
# Logical Drive 0: RAID5, Status=Degraded ← 阵列降级！
# Physical Drive 2: Status=Offline       ← 2号盘离线

# 查看存储管理日志
grep -iE "comm lost|error|fail" StorageMgnt_dfl.log | tail -50
```

#### 3C：电源分析

```bash
# 查看 PSU 状态
cat psu_info.txt
grep -iE "power loss|input lost|mismatch|absent" psu_info.txt

# 查看电源黑匣子（故障前历史状态）
cat ps_black_box.log
# 关注：故障前电压/电流波形是否异常

# 查看功率历史统计
cat power_statistics.csv
# 分析是否有功率突增/骤降的时间点
```

#### 3D：CPU / 内存分析

```bash
# 查看 CPU 信息（确认在位和型号）
cat cpu_info

# 查看内存 DIMM 在位状态
cat mem_info
grep -iE "not present|mismatch|fail|error" mem_info

# 查看 CpuMem 模块日志
grep -iE "error|mismatch|uncorrectable" CpuMem_dfl.log
```

---

### STEP 4：iBMC 自身健康检查

```bash
# ① 检查是否有进程崩溃（CoreDump）
ls -la CoreDump/
# 有 core-* 文件 = iBMC 有进程崩溃，记录文件时间戳

# ② 检查 Flash 存储健康
cat nandflash_info.txt
grep -iE "bad block|read only|error" nandflash_info.txt
# bad block 过多 = 需要更换 iBMC 模块

# ③ 检查磁盘空间
cat df_info
# 任何分区 Use% = 100% 都需要立即处理

# ④ 检查内存使用
cat free_info
# 可用内存 < 10% 需关注

# ⑤ 检查系统负载
cat loadavg
# 格式：1分钟 5分钟 15分钟 运行进程/总进程
# 超过 CPU 核心数的 2 倍 = 高负载

# ⑥ 检查进程资源占用
cat top_info
# 找 CPU/内存占用异常高的 iBMC 进程
```

---

### STEP 5：交叉验证（多源印证）

```bash
# iBMC 日志交叉分析矩阵：
# 
# sensor_info.txt (温度超阈值)
#       ↓ 对应
# sel.db (Temp Threshold Exceeded Asserted)
#       ↓ 触发
# cooling_app_dfl.log (风扇调速记录)
#       ↓ 若散热不足
# fdm_output (Fault: Thermal throttling detected)
#       ↓ 可能导致
# BMC_dfl.log (system performance degraded)

# 验证命令：
grep "temperature" sensor_info.txt
grep -i "thermal\|temp" sel_decoded.txt
grep -i "fan\|speed" cooling_app_dfl.log | tail -30
grep -i "fault\|thermal" fdm_output
```

---

### STEP 6：OS 侧综合分析

```bash
# ① 查看 OS 崩溃截图
# 打开 OSDump/img*.jpeg
# 关键判断：是否显示 Kernel Panic / BSOD 字样

# ② 分析 SOL 串口日志（最完整的OS启动日志）
tar -xf systemcom.tar
cat systemcom/*.log | grep -iE "panic|error|fail|crash"

# ③ Agentless 通信状态
grep -iE "connection lost|timeout|error" agentless_dfl.log | tail -50
# 若 connection lost = iBMC 与 OS 带内代理断开

# ④ 结合 openEuler /var/log/messages（OS侧日志）
# 与 SEL 时间戳对比，确认 OS 层和硬件层故障的因果关系
```

---

## 五、典型故障场景速查

### 场景 A：服务器突然宕机

```
分析路径：
1. OSDump/img*.jpeg → 确认是否 Kernel Panic
2. current_event.txt → 是否有 Critical 告警
3. sel.db → 找宕机时间点前的 Asserted 事件
4. ps_black_box.log → 确认是否电源故障导致
5. sensor_info.txt → 温度/电压是否超限
6. systemcom.tar → SOL 日志里的 OS panic 堆栈
```

### 场景 B：RAID 降级告警

```
分析路径：
1. RAID_Controller_Info.txt → 确认哪块盘离线
2. sel.db → 找硬盘离线的时间和事件
3. StorageMgnt_dfl.log → 存储通信是否中断
4. sensor_info.txt → 背板电压/温度是否异常
5. fdm_output → FDM是否给出硬盘故障判断
```

### 场景 C：iBMC 无法登录

```
分析路径：
1. net_info.txt → 管理口 IP 和链路状态
2. ifconfig_info → 网口 errors/dropped 统计
3. portal_dfl.log → Web 服务是否正常运行
4. df_info → 分区是否满（导致服务异常）
5. BMC_dfl.log → 是否有 watchdog 复位
6. security_log → 是否因暴力破解被锁定
```

### 场景 D：服务器温度告警

```
分析路径：
1. sensor_info.txt → 哪个传感器超阈值
2. fan_info.txt → 风扇是否正常运转
3. cooling_app_dfl.log → 调速逻辑是否执行
4. sel.db → 温度告警事件时间线
5. cpu_info → CPU 型号/TDP（确认配置是否正确）
6. fdm_output → 是否判定为散热故障
```

### 场景 E：固件升级失败

```
分析路径：
1. UPGRADE_dfl.log → 升级失败的具体步骤和错误码
2. upgrade_info → 当前各组件固件版本
3. mcinfo.txt → 辅助芯片版本是否兼容
4. nandflash_info.txt → Flash 是否有坏块影响写入
5. df_info → 空间是否足够存放升级包
```

---

## 六、一键健康检查脚本

```bash
#!/bin/bash
# iBMC 日志健康快速检查脚本
# 假设已解压 iBMC dump 到当前目录

DUMP_DIR="./dump/dump_info"

echo "============================================"
echo "  华为 iBMC 日志健康快速诊断报告"
echo "  $(date)"
echo "============================================"

echo ""
echo "【1. 全局告警状态】"
grep -iE "Critical|Major" ${DUMP_DIR}/SensorAlarm/current_event.txt 2>/dev/null \
  || echo "  无 Critical/Major 告警"

echo ""
echo "【2. iBMC 自身异常】"
grep -iE "error|exception|watchdog" ${DUMP_DIR}/BMC/BMC_dfl.log 2>/dev/null | tail -5

echo ""
echo "【3. CoreDump 检查】"
ls ${DUMP_DIR}/CoreDump/core-* 2>/dev/null && echo "  ⚠️  存在 CoreDump 文件！" \
  || echo "  无 CoreDump"

echo ""
echo "【4. Flash 存储健康】"
grep -iE "bad block|read only" ${DUMP_DIR}/BMC/nandflash_info.txt 2>/dev/null \
  || echo "  Flash 无坏块"

echo ""
echo "【5. iBMC 磁盘空间】"
grep "100%" ${DUMP_DIR}/SysInfo/df_info 2>/dev/null && echo "  ⚠️  存在分区已满！" \
  || echo "  磁盘空间正常"

echo ""
echo "【6. RAID 状态】"
grep -iE "Degraded|Offline|Failed" ${DUMP_DIR}/StorageMgnt/RAID_Controller_Info.txt 2>/dev/null \
  || echo "  RAID 状态正常"

echo ""
echo "【7. 电源状态】"
grep -iE "power loss|input lost|absent" ${DUMP_DIR}/BMC/psu_info.txt 2>/dev/null \
  || echo "  电源状态正常"

echo ""
echo "【8. 风扇状态】"
grep -iE "fail|missing|0 RPM" ${DUMP_DIR}/Cooling/fan_info.txt 2>/dev/null \
  || echo "  风扇状态正常"

echo ""
echo "【9. FDM 故障判定】"
grep -i "Fault" ${DUMP_DIR}/LogDump/fdm_output 2>/dev/null \
  || echo "  FDM 未检出故障"

echo ""
echo "【10. 安全告警】"
grep -iE "auth fail|brute force" ${DUMP_DIR}/LogDump/security_log 2>/dev/null | tail -5 \
  || echo "  无安全告警"

echo ""
echo "============================================"
echo "  检查完成，请重点关注上方 ⚠️ 项"
echo "============================================"
```

---

## 七、分析优先级速查矩阵

| 优先级 | 日志文件 | 判断依据 |
|---|---|---|
| ⭐⭐⭐⭐⭐ 最高 | `current_event.txt` | 当前存在 Critical 告警 |
| ⭐⭐⭐⭐⭐ 最高 | `fdm_output` | FDM 判定有 Fault |
| ⭐⭐⭐⭐⭐ 最高 | `ps_black_box.log` | 电源故障黑匣子 |
| ⭐⭐⭐⭐ 高 | `sel.db` | 硬件事件时间线 |
| ⭐⭐⭐⭐ 高 | `RAID_Controller_Info.txt` | RAID 降级/离线 |
| ⭐⭐⭐⭐ 高 | `CoreDump/core-*` | iBMC 进程崩溃 |
| ⭐⭐⭐ 中 | `BMC_dfl.log` | iBMC 运行异常 |
| ⭐⭐⭐ 中 | `OSDump/img*.jpeg` | OS 崩溃截图 |
| ⭐⭐ 一般 | `security_log` | 安全事件 |
| ⭐ 参考 | `maintenance_log` | 操作审计回溯 |

---

**核心原则**：iBMC 日志分析要遵循"**硬件先行、时间线优先、多源交叉验证**"。`fdm_output` 和 `sel.db` 是最权威的故障定性依据，`ps_black_box.log` 是电源类故障的不可替代证据，`OSDump` 是 OS 侧故障现场的第一手资料。

## iBMC 日志清单（增强版）

> 新增列说明：**文件内容描述** — 文件记录的具体数据；**强相关组件** — 与哪些硬件/软件组件直接相关；**故障关键字** — 分析时重点搜索的关键词

| 模块 | 文件名称 | 原始内容说明 | 文件内容描述 | 强相关组件 | 故障关键字 |
|---|---|---|---|---|---|
| 公共 | dump\dump_info | dump\dump_info | iBMC一键收集的基础信息目录，包含版本、配置、状态等核心数据 | iBMC系统 | - |
| 公共 | dump_app_log | iBMC收集结果列表 | 记录iBMC应用层的日志收集执行结果，确认是否收集成功 | 收集工具 | failed、error |
| 公共 | dump_log | 一键收集结果列表 | 一键收集任务的总体执行状态记录 | 收集工具 | failed、timeout |
| AppDump | dump\dump_info\AppDump | dump\dump_info\AppDump | 包含iBMC各个应用模块（如BIOS、BMC、Cooling等）的详细运行日志和配置信息 | iBMC应用模块 | - |
| agentless | agentless_dfl.log | Agentless模块管理对象的信息 | Agentless模块的运行日志，记录带外管理与OS侧的交互信息 | Agentless、OS | error、timeout、connection lost |
| BIOS | BIOS_dfl.log | BIOS模块管理对象的信息 | BIOS管理模块在iBMC侧的运行日志，记录BIOS配置下发、状态监控等操作 | BIOS、iBMC | config failed、checksum error |
| BIOS | bios_info | BIOS配置信息 | 当前BIOS的各项配置参数值 | BIOS | - |
| BIOS | currentvalue.json | 当前设置的BIOS项 | JSON格式的当前BIOS设置值 | BIOS | - |
| BIOS | registry.json | BIOS的注册文件 | BIOS支持的所有配置项及其属性描述 | BIOS | - |
| BIOS | result.json | 通过redfish设置的BIOS项结果 | Redfish接口下发BIOS配置的执行结果 | Redfish、BIOS | 400 Bad Request、500 Internal Server Error |
| BIOS | setting.json | 待生效BIOS项 | 已设置但需重启生效的BIOS配置 | BIOS | - |
| BMC | BMC_dfl.log | iBMC模块管理对象的信息 | iBMC核心管理模块的运行日志，涉及系统状态维护、组件协调 | iBMC核心 | error、exception、watchdog |
| BMC | mcinfo.txt | iBMC辅助固件信息 | iBMC及相关辅助芯片（如CPLD）的固件版本信息 | iBMC固件 | version mismatch |
| BMC | nandflash_info.txt | NAND flash信息 | iBMC存储芯片NAND Flash的状态、坏块信息 | iBMC存储 | bad block、read only |
| BMC | net_info.txt | 网口配置信息 | iBMC管理网口的IP、MAC、VLAN等配置信息 | iBMC网络 | link down、collision |
| BMC | ntp_info.txt | NTP同步失败错误信息 | NTP时间同步的错误日志 | NTP、时间同步 | synchronization failed、stratum too high |
| BMC | psu_info.txt | 电源信息 | 电源模块（PSU）的在位状态、型号、功率、序列号 | 电源(PSU) | power loss、input lost、mismatch |
| BMC | time_zone.txt | iBMC时区信息 | iBMC当前配置的时区 | 时间同步 | - |
| CardManage | card_info | 扣卡信息 | 主要是RAID卡、网卡等PCIe扣卡的在位与型号信息 | PCIe扣卡 | not present、unknown |
| CardManage | card_manage_dfl.log | Card_Manage模块日志 | 扣卡管理模块的运行日志，记录扣卡识别、状态变化 | PCIe扣卡 | card error、init failed |
| Cooling | cooling_app_dfl.log | Cooling模块日志 | 风扇调速、温度监控模块的运行日志 | 风扇、散热 | over temperature、fan fail |
| Cooling | fan_info.txt | 风扇详细信息 | 风扇转速、占空比、状态（在位/缺失/故障） | 风扇 | speed low、missing |
| CpuMem | cpu_info | CPU详细信息 | CPU型号、主频、核心数、缓存等物理信息 | CPU | - |
| CpuMem | CpuMem_dfl.log | CpuMem模块日志 | CPU和内存管理模块的运行日志，记录资产识别与状态监控 | CPU、内存 | error、mismatch |
| CpuMem | mem_info | 内存详细信息 | 内存DIMM的容量、频率、厂商、序列号及在位状态 | 内存 | not present、size mismatch |
| DataSync | data_sync2_dfl | data_sync2模块信息 | 数据同步模块的运行状态信息（主备iBMC或模块间同步） | iBMC高可用 | sync failed |
| Ddns | ddns_dfl.log | Ddns模块日志 | 动态域名服务(DDNS)模块的运行日志 | DDNS、网络 | update failed |
| Dfm | dfm.log | DFM模块日志 | 故障诊断管理(DFM)模块日志，负责故障检测与隔离 | 故障诊断 | fault detected、isolate |
| Dft | Dft_dfl.log | DFT模块日志 | 可制造性设计(DFT)模块日志，通常涉及生产测试 | 生产测试 | test failed |
| Diagnose | diagnose_dfl.log | Diagnose模块日志 | 诊断模块的运行日志 | 故障诊断 | - |
| Discovery | discovery_dfl.log | Discovery模块日志 | 设备自动发现模块的运行日志 | 设备发现 | discovery failed |
| FileManage | FileManage_dfl.log | FileManage模块日志 | 文件管理模块日志，涉及文件上传下载、存储管理 | iBMC存储 | write error、disk full |
| FruData | FruData_dfl.log | FruData模块日志 | FRU（现场可替换单元）数据管理模块日志 | FRU | checksum error |
| FruData | fruinfo.txt | FRU电子标签信息 | 机箱、主板、背板等部件的电子标签数据（序列号、资产标签） | FRU | invalid format |
| IPMI | ipmbeth_info.txt | IPMI通道状态 | IPMB（智能平台管理总线）通道的通信状态 | IPMI、I2C | bus error、no response |
| IPMI | ipmi_app_dfl.log | IPMI模块日志 | IPMI协议栈处理日志，记录IPMI命令交互 | IPMI | command failed、timeout |
| KVM | kvm_vmm_dfl.log | KVM_VMM模块日志 | 远程KVM和虚拟媒体(Virtual Media)服务的运行日志 | KVM、虚拟媒体 | connection closed、mount failed |
| MaintDebug | MaintDebug_dfl.log | MaintDebug模块日志 | 维护调试模块日志 | 调试 | - |
| MCTP | MCTP_dfl.log | MCTP模块日志 | MCTP（管理组件传输协议）协议栈日志 | PCIe、SMBus | packet drop、timeout |
| MCTP | mctp_info | MCTP配置信息 | MCTP网络的EID分配、拓扑信息 | MCTP | - |
| NetNAT | net_nat_dfl.log | Net_NAT模块日志 | 网络NAT功能模块日志 | 网络 | - |
| NetConfig | lldp_info.txt | LLDP信息 | LLDP（链路层发现协议）邻居信息及报文统计 | 网络交换机 | no neighbor |
| NetConfig | NetConfig_dfl.log | NetConfig模块日志 | 网络配置管理模块日志，涉及IP、VLAN等配置变更 | 网络 | config failed |
| Payload | Payload_dfl.log | Payload模块日志 | 负载管理模块日志 | - | - |
| Portal | portal_dfl.log | Portal模块日志 | Web门户服务日志，记录用户Web访问会话 | Web UI | login failed、session timeout |
| PcieSwitch | PcieSwitch_dfl.log | PCIeSwitch模块日志 | PCIe交换机管理日志 | PCIe Switch | link error |
| PowerMgnt | power_statistics.csv | 功率统计信息 | 历史功率统计数据 | 电源 | power cap hit |
| PowerMgnt | PowerMgnt_dfl.log | PowerMgnt模块日志 | 电源管理模块日志，涉及上下电控制、功率封顶 | 电源、功率控制 | power on failed、power off failed |
| Redfish | component_uri.json | 部件URI列表 | Redfish资源树中各组件的URI映射 | Redfish | - |
| Redfish | event_sender_info.log | 事件订阅失败日志 | Redfish事件订阅推送失败的记录 | Redfish事件 | connection refused |
| Redfish | redfish_dfl.log | Redfish模块日志 | Redfish服务运行日志，记录API请求与处理 | Redfish API | 5xx error、4xx error |
| SensorAlarm | current_event.txt | 当前健康状态和告警 | 设备当前的健康状态概览及未清除的告警列表 | 全局健康 | Critical、Major、Minor |
| SensorAlarm | LedInfo | LED灯状态 | 前面板、UID等指示灯的当前点亮状态 | 指示灯 | blink error |
| SensorAlarm | sel.db / sel.tar | SEL数据库 | 系统事件日志(SEL)数据库及打包文件 | 硬件故障 | Asserted、Deasserted |
| SensorAlarm | sensor_alarm_dfl.log | Sensor_Alarm模块日志 | 传感器告警处理模块日志 | 传感器 | threshold crossed |
| SensorAlarm | sensor_info.txt | 传感器列表 | 所有传感器的当前读数及状态 | 传感器 | reading unavailable |
| Snmp | Snmp_dfl.log | Snmp模块日志 | SNMP代理服务运行日志 | SNMP | authentication failure |
| StorageMgnt | RAID_Controller_Info.txt | RAID信息 | RAID卡、逻辑盘(LD)、物理盘(PD)的详细属性与状态 | RAID、硬盘 | Offline、Degraded、Rebuild |
| StorageMgnt | StorageMgnt_dfl.log | StorageMgnt模块日志 | 存储管理模块日志，涉及RAID卡与硬盘纳管 | 存储 | comm lost |
| Upgrade | UPGRADE_dfl.log | Upgrade模块日志 | 固件升级模块日志，记录升级过程与结果 | 固件升级 | upgrade failed、verify failed |
| Upgrade | upgrade_info | 版本信息 | iBMC管理的各组件固件版本列表 | 固件版本 | - |
| User | User_dfl.log | User模块日志 | 用户管理模块日志，涉及用户添加、权限修改、认证 | 用户安全 | permission denied |
| BMA | bma_debug_log* | iBMA日志 | iBMA（带内管理代理）的调试日志 | iBMA | - |
| CoreDump | core-* | 内存转储文件 | iBMC进程崩溃产生的Core Dump文件 | iBMC进程 | segfault、abort |
| SysInfo | cmdline | 内核命令行 | iBMC Linux内核启动参数 | iBMC内核 | - |
| SysInfo | cpuinfo | CPU芯片信息 | iBMC SoC的CPU信息 | iBMC硬件 | - |
| SysInfo | df_info | 分区空间使用 | iBMC文件系统的磁盘空间使用率 | iBMC存储 | 100% usage、disk full |
| SysInfo | free_info | 内存使用概况 | iBMC系统的内存使用情况 | iBMC内存 | Out of memory |
| SysInfo | loadavg | 系统负载 | iBMC系统的平均负载 | iBMC性能 | high load |
| SysInfo | meminfo | 内存详细信息 | iBMC系统的详细内存统计 | iBMC内存 | - |
| SysInfo | mtd | 配置分区信息 | MTD闪存分区表 | iBMC存储 | - |
| SysInfo | top_info | 进程运行情况 | top命令输出，显示iBMC进程资源占用 | iBMC进程 | high CPU |
| SysInfo | uptime | 系统运行时间 | iBMC自上次启动以来的运行时长 | iBMC系统 | unexpected reboot |
| Version | ibmc_revision.txt | iBMC版本编译信息 | iBMC固件的详细版本与编译时间 | iBMC固件 | - |
| Version | fruinfo.txt | FRU电子标签 | iBMC所在板卡的FRU信息 | FRU | - |
| Network | ifconfig_info | 网络信息 | ifconfig命令输出，显示iBMC网口IP与统计 | iBMC网络 | errors、dropped |
| Network | netstat_info | 端口连接情况 | netstat命令输出，显示网络连接与监听端口 | iBMC网络 | TIME_WAIT |
| Other | remotelog.conf | syslog配置文件 | 远程syslog服务器配置 | 日志审计 | - |
| Other | sshd_config | SSHD配置 | SSH服务配置文件 | SSH服务 | - |
| Driver | dmesg_info | dmesg信息 | iBMC Linux内核的启动与运行消息 | iBMC内核 | error、fail、call trace |
| DeviceDump | i2c_info | I2C信息 | I2C总线设备信息 | I2C总线 | timeout |
| LogDump | running_log.bin | 巡检日志 | 网卡等组件的巡检日志 | 网卡 | - |
| LogDump | app_debug_log_all* | 应用调试日志 | iBMC各应用模块的详细调试日志汇总 | iBMC应用 | error、exception |
| LogDump | fdm.bin | FDM原始故障日志 | 故障诊断管理(FDM)的原始日志数据 | 硬件故障 | - |
| LogDump | fdm_output | FDM故障诊断日志 | 解析后的FDM诊断结果 | 硬件故障 | Fault |
| LogDump | ipmi_mass_operate_log | IPMI运行日志 | 大量IPMI操作记录 | IPMI | - |
| LogDump | linux_kernel_log | Linux内核日志 | iBMC OS的内核日志归档 | iBMC内核 | panic、oops |
| LogDump | maintenance_log | 用户操作日志 | 用户维护操作记录（登录、重启等） | 操作审计 | - |
| LogDump | ps_black_box.log | 电源黑匣子日志 | 电源模块的黑匣子数据，记录故障前状态 | 电源 | power fault |
| LogDump | remote_log | syslog test操作日志 | 远程日志测试记录 | 日志审计 | - |
| LogDump | security_log | 安全日志 | 安全相关事件（认证失败、攻击检测） | 安全审计 | auth fail |
| OptPme | pram | pram目录文件 | iBMC运行时持久化数据 | iBMC数据 | - |
| OptPme | sel.db | SEL数据库 | 系统事件日志数据库文件 | 硬件事件 | - |
| Save | per_config.ini | 配置持久化文件 | iBMC的各项配置保存文件 | iBMC配置 | - |
| Save | sensor_alarm_sel.bin | SEL原始记录 | 原始二进制SEL数据 | 硬件事件 | - |
| OSDump | *.rep | 屏幕录像 | 业务侧（服务器OS）崩溃或故障时的KVM屏幕录像 | 故障复现 | - |
| OSDump | img*.jpeg | 最后一屏图像 | 业务侧（服务器OS）崩溃时的最后屏幕截图 | 故障复现 | BSOD、Kernel Panic |
| OSDump | systemcom.tar | SOL串口信息 | 串口重定向(SOL)捕获的OS启动或运行日志 | OS串口日志 | console logs |
