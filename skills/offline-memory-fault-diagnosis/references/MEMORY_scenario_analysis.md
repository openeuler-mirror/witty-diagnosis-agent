# 内存故障场景专项分析指南

## 概述

本指南提供了七种内存故障场景的专项分析流程。当 Step 1 确定故障场景后，应根据对应的场景执行专项分析。

---

## 1. 内存ECC错误分析 (MEMORY_ECC_ERROR)

### 1.1 核心日志文件
- `ibmc_logs/sel.db` / `sel.tar` - iBMC系统事件日志 (硬件GPIO/ECC错误)
- `infocollect_logs/system/dmesg.txt` - 内核MCE/hwpoison日志
- `messages/messages` - 系统级致命错误 (SIGBUS/OOM) 日志

### 1.2 四大故障指纹 (Fault Fingerprints)

| 类型 | 诊断特征 | 典型 T0 传导链 | 关键核验证据 |
| :--- | :--- | :--- | :--- |
| **P1: GPIO FATAL** | BIOS 隔离导致内存总量突减 | `[颗粒失效(T0)] -> [GPIO FATAL] -> [系统Reset] -> [BIOS隔离] -> [OS内存变少]` | `iBMC SEL: Fatal Error`, `MemTotal` 显著减少 |
| **P2: GPIO CE** | CE 风暴引起的高频中断 | `[老化(T0)] -> [高频CE] -> [GPIO IRQ] -> [rasdaemon记录] -> [CE风暴]` | `dmesg: EDAC CE`, `messages: burst detected` |
| **P3: Idle Page UCE** | hwpoison 页面静默隔离 | `[UCE(T0)] -> [巡检发现] -> [MCE] -> [hwpoison] -> [页面下线]` | `dmesg: Memory failure: ... Isolated` |
| **P4: Used Page UCE** | SIGBUS 导致关键进程被杀 | `[UCE(T0)] -> [进程访问] -> [MCE] -> [SIGBUS] -> [进程中止并隔离]` | `messages: killed by SIGBUS`, `dmesg: Recovered` |

### 1.3 分析命令
```bash
python3 scripts/diagnose_ibmc.py <log_dir> -k "ECC" "DIMM" "FATAL"
python3 scripts/diagnose_messages.py <log_dir> -k "SIGBUS" "MCE"
python3 scripts/diagnose_memory.py <log_dir> --ecc
```

---

## 2. 内存不足分析 (MEMORY_OOM_KILLER)

### 2.1 核心日志文件
- `messages/messages` - 系统 OOM 触发日志
- `infocollect_logs/system/meminfo.txt` - 内存瞬时分配数据
- `infocollect_logs/system/ps.txt` - 进程内存快照

### 2.2 关键项
- **关键字**: `Out of memory`, `Kill process`, `oom_reaper`
- **定位**: 寻找 `oom_score` 最高的被杀进程

### 2.3 分析命令
```bash
python3 scripts/diagnose_messages.py <log_dir> -k "Out of memory" "Kill process"
python3 scripts/diagnose_memory.py <log_dir> --oom
```

---

## 3. 内存泄漏分析 (MEMORY_LEAK)

### 3.1 核心日志文件
- `infocollect_logs/system/meminfo.txt` - 查看 Slab/SUnreclaim 增长
- `infocollect_logs/system/slabinfo.txt` - 细分 Slab 分配器使用情况

### 3.2 传导链示范
- **时序**: `[业务启动] -> [进程/内核模块申请内存未释放] -> [MemAvailable 线性下降] -> [SUnreclaim 持续上涨] -> [系统卡顿]`

### 3.3 分析命令
```bash
python3 scripts/diagnose_memory.py <log_dir> --leak
```

---

## 4. 执行验证铁律
1. **孤证不立**: 必须同时有 OS 层和 硬件层(iBMC/MCE) 证据。
2. **逻辑闭环**: 结论必须符合 T0 到最终症状的传导逻辑。
3. **精准定位**: 必须精确到具体的物理 DIMM 或 进程 PID。
