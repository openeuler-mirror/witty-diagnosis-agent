# 🔴 故障诊断报告

> **报告编号**：RCA-20260610-220115-F
> **故障级别**：P2（配置隐患）
> **报告时间**：2026-06-10 22:15:00
> **当前状态**：🟡 观察中（配置异常已确认，尚未引发实际丢包）

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | Docker 容器 nf-test-F 中 nf_conntrack 超时参数配置异常 |
| 影响范围 | Docker 容器 nf-test-F 内部所有通过 conntrack 跟踪的网络连接 |
| 故障时段 | 配置生效时起（持续存在）— 当前尚未引发 conntrack 丢包 |
| 根本原因 | conntrack 内核参数 `tcp_timeout_established=10`、`tcp_timeout_time_wait=5`、`udp_timeout=5` 等远超低于推荐阈值，属人为配置错误 |
| 是否恢复 | ❌ 未恢复（配置仍为异常值） |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 本场景适用性 |
|------|------|------|-------------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | ✅ Kuafu 诊断已直接 dump 出所有 sysctl 参数值，并与推荐值逐项对比，证据确凿 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                         事件                                                            性质          溯源路径
──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
[未知]                       Docker 容器 nf-test-F 被创建或启动时，conntrack 超时参数被错误配置               🔧 配置引入   手动或启动脚本设置了 sysctl 参数
                              ├── net.netfilter.nf_conntrack_tcp_timeout_established = 10
                              ├── net.netfilter.nf_conntrack_tcp_timeout_time_wait = 5
                              └── net.netfilter.nf_conntrack_udp_timeout = 5
                              │
                              ▼
[持续存在]                    容器内业务建立的 TCP 长连接在空闲 >10s 后被 conntrack 自动拆除                        ⚠️ 隐患      [/home/win11/.witty-diagnosis-agent/dayu/report/kuafu_F_20260610_220115.md:44-53]
                              │
                              ▼
[潜在风险]                    NAT/masquerade 场景下，返回报文因 conntrack 表项已过期被丢弃                        🔴 故障预期   [/home/win11/.witty-diagnosis-agent/dayu/report/kuafu_F_20260610_220115.md:77-87]
                              ├── TCP 长连接中断 → HTTP 请求失败 / 数据库连接池报错
                              ├── UDP 服务（DNS 等）状态丢失 → 频繁重查
                              └── Time_wait 状态连接快速回收可能导致端口重用冲突
                              │
                              ▼
[2026-06-10 22:01:15]        Kuafu 诊断执行，确认超时配置异常（F5 自动比对）                                    📋 确认       [/home/win11/.witty-diagnosis-agent/dayu/report/kuafu_F_20260610_220115.md:124-138]
                              ├── tcp_timeout_established: 10 vs 推荐 432000  → 仅 0.002% ❌
                              ├── tcp_timeout_time_wait:        5 vs 推荐 120     → 仅 4% ❌
                              └── udp_timeout:                  5 vs 推荐 30      → 仅 17% ❌
```

### 故障因果链

```text
人为配置错误（sysctl 参数写入异常值）
    └─► net.netfilter.nf_conntrack_tcp_timeout_established = 10（推荐 432000 = 5天）
    │       └─► TCP 长连接空闲 >10秒即被 conntrack 表项驱逐
    │               └─► NAT 回程报文无法关联原连接 → 丢包
    │                       └─► HTTP keep-alive / DB 长连接中断
    │
    ├─► net.netfilter.nf_conntrack_tcp_timeout_time_wait = 5（推荐 120）
    │       └─► TIME_WAIT 连接过早回收
    │               └─► 可能引发端口重用冲突（旧报文干扰新连接）
    │
    └─► net.netfilter.nf_conntrack_udp_timeout = 5（推荐 30）
            └─► UDP 报文间间隔 >5秒即丢失状态
                    └─► DNS 解析 / VoIP / 其他 UDP 服务频繁中断
```

---

## 三、排查过程

### 3.1 初始现象

据 Kuafu 诊断报告，在 Docker 容器 `nf-test-F` 内执行 conntrack 超时参数检查，发现：

- **关键 TCP 超时异常**：
  - `tcp_timeout_established = 10` — 正常应设为 432000（5 天）
  - `tcp_timeout_time_wait = 5` — 正常应设为 120
- **关键 UDP 超时异常**：
  - `udp_timeout = 5` — 正常应设为 30
  - `udp_timeout_stream = 120` — 正常应设为 180
- **当前 conntrack 表状态**：条目数为 0，使用率 0%，`drop`/`early_drop`/`insert_failed` 计数均为 0

### 3.2 假设驱动排查

#### 假设 A：容器内业务负载低，conntrack 尚未产生压力 ✅ 部分确认

| 检查项 | 操作 | 结论 |
|--------|------|------|
| conntrack 当前条目数 | 读取 `/proc/net/stat/nf_conntrack` 统计 | ✅ 当前条目数 = 0，使用率 = 0% |
| 丢包计数 | 检查 `drop`/`early_drop`/`insert_failed` 字段 | ✅ 所有计数均为 0 |

**说明**：当前环境下表未满、无丢包，但这**不代表配置是安全的**。一旦业务流量接入，极短超时将立刻导致连接中断。

#### 假设 B：conntrack 超时配置异常源于人为错误 ✅ 确认为根因

> 🧪 假设：系统管理员或启动脚本设置了过低的 conntrack 超时参数

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 超时参数读取 | sysctl 命令导出所有 `net.netfilter.nf_conntrack_*` 参数 | ✅ 20+ 个参数中，tcp_established / tcp_time_wait / udp_timeout 显著异常 |
| 自动比对（F5） | F5 模块执行推荐值对比 | ✅ 明确识别 3 个 ⚠️ 告警标记 |
| 业务场景匹配（F3） | 对比 HTTP/DB/DNS 等业务与超时配置匹配度 | ✅ 所有长连接场景均不兼容当前配置 |

**✅ 结论**：容器内部 `nf_conntrack` 超时参数被设置为不合理低值，严重偏离标准推荐值。这是明确的**人为配置错误**。

### 3.3 排查结论

```text
conntrack 超时参数检查发现 4 项异常
├─► 假设 A：当前无业务压力 → ✅ 确认（表空，无丢包）
│       └─► 这是暂时的，不能说明配置安全
│
└─► 假设 B：配置被人为错误设定 → ✅ 确认根因
        ├─► tcp_timeout_established = 10（推荐 432000）— 仅 0.002%
        ├─► tcp_timeout_time_wait = 5（推荐 120）     — 仅 4%
        ├─► udp_timeout = 5（推荐 30）                — 仅 17%
        └─► udp_timeout_stream = 120（推荐 180）      — 仅 67%
                └─► 🎯 根因确认：超时参数过低
```

---

## 四、修复方案

### 4.1 应急处置

当前 conntrack 表未出现丢包，暂无紧急止损的必要。但建议尽快按以下方式修复配置，防止后续业务上线后出现连接中断问题。

### 4.2 永久修复计划

| 修复措施 | 操作命令 | 负责人 | 完成时间 |
|---------|---------|--------|---------|
| 修复 TCP established 超时 | `sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=432000` | 系统管理员 | 尽快 |
| 修复 TCP time_wait 超时 | `sysctl -w net.netfilter.nf_conntrack_tcp_timeout_time_wait=120` | 系统管理员 | 尽快 |
| 修复 UDP 超时 | `sysctl -w net.netfilter.nf_conntrack_udp_timeout=30` | 系统管理员 | 尽快 |
| 修复 UDP stream 超时 | `sysctl -w net.netfilter.nf_conntrack_udp_timeout_stream=180` | 系统管理员 | 尽快 |
| 持久化配置 | 将上述参数写入 `/etc/sysctl.d/90-conntrack.conf` 或容器启动脚本 | 系统管理员 | 尽快 |
| 配置溯源 | 调查这些异常值是由哪个部署脚本/镜像层引入 | 系统管理员 | 尽快 |
