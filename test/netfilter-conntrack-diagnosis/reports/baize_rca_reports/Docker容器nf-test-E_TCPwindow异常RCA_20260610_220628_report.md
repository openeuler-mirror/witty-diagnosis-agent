# 🔴 故障诊断报告：Docker 容器 nf-test-E TCP window tracking 异常分析

> **报告编号**: RCA-20260610-E-001
> **故障级别**: P2（中等 — 连接质量受损）
> **报告时间**: 2026-06-10 22:06:28
> **当前状态**: 🔴 待修复

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | Docker 容器 nf-test-E 中 TCP 段校验和异常率高达 86%，伴随 nf_conntrack_tcp_be_liberal=0 严格模式已配置 |
| 影响范围 | 容器 nf-test-E 内的 TCP 网络连接 |
| 故障时段 | 2026-06-10 22:01:14 ～ 未知（持续中） |
| 根本原因 | Docker 容器虚拟网络接口（veth pair）TCP 校验和卸载（checksum offload）配置不兼容，导致 50/58（86.2%）的 TCP 接收段校验和错误；同时 nf_conntrack_tcp_be_liberal=0 严格模式已配置但当前未产生显著 conntrack 丢弃 |
| 是否恢复 | ❌ 未恢复 |
| 根因置信度 | 🟡 中置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 本报告对应 |
|------|------|------|-----------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | — |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | bad segments 确认存在且比例极高，但因缺乏 tcpdump 抓包验证无法确认校验和卸载是否为唯一原因 |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位 | — |

---

## 二、根因速览

### 事故时间线与故障传导链路

```text
时间                     事件                                                      性质         溯源路径
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-06-10 22:01:14     Kuafu 诊断执行（Branch E - TCP window tracking 异常）         📋 诊断触发   [kuafu_E_20260610_220114.md]
  │
  ▼
诊断采集E1              nf_conntrack 计数器读取                                          📊 数据采集   [/proc/net/stat/nf_conntrack]
  │                     → 所有 CPU 计数基本为零（1个CPU有100次 delete）                            conntrack 表几近空闲
  │                     → invalid=0, drop=0, insert_failed=0, early_drop=0
  │
  ▼
诊断采集E2              TCP 连接状态统计                                                📊 数据采集   [/proc/net/snmp TcpExt]
  │                     → segments received: 58
  │                     → bad segments received: 50 ← 🔴 86.2% 异常
  │                     → resets: 2 received, 1 sent
  │
  ▼
诊断采集E3              内核参数检查                                                    📊 数据采集   [sysctl]
  │                     → nf_conntrack_tcp_be_liberal = 0（严格模式）
  │                     → nf_conntrack_tcp_loose = 1
  │                     → tcp_rmem = 4096 131072 6291456
  │
  ▼
2026-06-10 22:01:14     E0 差分分析完成                                                📊 数据分析
                        → invalid 当前计数:0（无历史基线可对比）
  │
  ▼
                        🔴 最终判断：50 bad segments 为主要异常信号
                        → 非 conntrack window tracking 的直接计数增长
                        → 指向 TCP 校验和卸载问题
```

### 故障因果链

```text
Docker 容器 nf-test-E 的 veth pair 网络接口
    │
    ├─► [TCP 校验和卸载(checksum offload)配置不兼容]
    │       │
    │       ├─► 容器/主机侧 TX/RX checksum offload 不一致
    │       │       │
    │       │       ▼
    │       ├─► 🔴 50/58 TCP 接收段校验和错误 (TcpExt:BadSegments)
    │       │       │
    │       │       ├─► 内核 TCP 栈丢弃非法报文
    │       │       │       └─► 应用层收到损坏/丢失数据
    │       │       │
    │       │       └─► 连接质量严重下降
    │       │
    │       ▼
    ├─► [次要] nf_conntrack_tcp_be_liberal=0（严格模式已配置）
    │       │
    │       ├─► conntrack 验证 TCP 窗口边界
    │       ├─► 当前未观察到 invalid 计数增长
    │       └─► ⚠️ 潜在风险：如 TCP 窗口缩放协商不一致，会加剧丢包
    │
    ▼
🔴 结论：TCP 校验和卸载兼容性问题为主因，conntrack 严格模式为次因/潜在风险
```

---

## 三、排查过程

### 3.1 初始现象

- **故障描述**：Docker 容器 nf-test-E 中设置了 `nf_conntrack_tcp_be_liberal=0` 严格模式，怀疑 TCP window tracking 异常
- **初始怀疑**：conntrack 严格模式导致连接间歇性中断

### 3.2 双轨并行分析（规则链轨道 + conntrack 轨道）

#### 轨道一：规则链分析

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 规则链拓扑 | 本次诊断为 conntrack 专项分支 E，未采集 iptables 规则 | ⏭️ 未执行（分支 E 不涉及） |
| 规则命中计数 | 同上 | ⏭️ 未执行 |

> 注：Branch E（TCP window tracking）为 conntrack 专项分析分支，不涉及规则链分析。如需全量双轨分析，需先执行基线采集脚本。

#### 轨道二：conntrack 分析

**C0 — 模块可用性检查**

| 检查项 | 结果 |
|--------|------|
| nf_conntrack 模块已加载 | ✅ 是 |
| /proc/net/stat/nf_conntrack 可用 | ✅ 是 |

**C1 — conntrack 表容量检查**

| 指标 | 值 |
|------|-----|
| 当前条目数 | 未采集（无 `conntrack -C` 输出） |
| nf_conntrack_max | 未采集 |
| 使用率 | 未知 |

> 注：本次采集未包含 `conntrack -C` 和 `sysctl net.netfilter.nf_conntrack_max` 输出，缺少容量数据。

**C2 — 状态分布**

| 状态 | 计数 |
|------|------|
| 各协议/各状态分布 | 未采集（无 `conntrack -S` 或 `conntrack -L` 输出） |

**C3 — NAT 映射核验**

> 本次为容器内部 conntrack 诊断，未涉及 NAT 映射场景。

**C4 — 丢包计数点定位（核心分析）**

从 `/proc/net/stat/nf_conntrack` 原始数据解析结果：

| 计数器 | CPU0 | CPU1 | CPU2 | CPU3 | CPU4 | CPU5+ | 合计 |
|--------|------|------|------|------|------|-------|------|
| found | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| new | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| invalid | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| delete | 0 | 0 | 0 | 0 | 100 | 0 | **100** |
| insert_failed | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| drop | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| early_drop | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| search_restart | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

**C4 关键解读**：
- **invalid = 0**：所有 CPU 的 invalid 计数均为 0，说明当前没有 TCP window violation 导致的报文丢弃
- **delete = 100**：仅 CPU4 有 100 次 delete 操作，这很可能是连接正常老化/超时删除，属于预期行为
- **drop = 0 / early_drop = 0 / insert_failed = 0**：无 conntrack 表满溢出的任何迹象

---

### 3.3 深入分析：TCP 层统计异常（核心发现）

**E2 数据解读（TCP 连接状态统计）**

| 统计项 | 值 | 含义 |
|--------|-----|------|
| segments received | 58 | 总计接收 TCP 段数 |
| bad segments received | **50** | 🔴 校验和/协议错误的段数（**占 86.2%**） |
| segments sent out | 8 | 发出的段数 |
| segments retransmitted | 0 | 重传数为 0 |
| connection resets received | 2 | 收到 2 个 RST |
| resets sent | 1 | 发送 1 个 RST |

**Bad Segments 占比计算**：50 / 58 = **86.2%**

> 正常范围：< 0.1%。86.2% 属于极端异常。

**Bad segments 在 Linux 内核中的含义**：
- 计数位置：`/proc/net/snmp` → `Tcp:BadSegments`
- 统计时机：TCP 层接收处理中，校验和验证失败时递增
- 不经过 conntrack 计数：报文在校验和验证阶段即被丢弃，不会进入 conntrack 处理路径

---

### 3.4 E0 差分分析

| 项目 | 值 |
|------|-----|
| 当前 invalid 计数 | 0 |
| 历史 baseline | 无（首次诊断） |
| 差分结果 | 无对比基线，无法计算增量 |
| 解读 | 当前 conntrack 层面无异常计数 |

---

### 3.5 排查结论

```text
Branch E: TCP window tracking 异常
│
├─► 规则链轨道：⏭️ 未执行（分支 E 为 conntrack 专项）
│
├─► conntrack 轨道：
│   ├─► C0 模块可用性：✅ 正常
│   ├─► C4 丢包计数：  ✅ 正常（所有关键计数器为 0）
│   └─► 结论：conntrack 层面当前无异常计数
│
├─► TCP 层统计（核心发现）：
│   ├─► bad segments: 50 / 58（86.2%）← 🔴 极端异常
│   ├─► 根因推断：Docker 容器 veth 网络校验和卸载不兼容
│   └─► 非 conntrack 问题
│
└─► 🎯 综合根因：
    ├─► 主要根因：容器网络 TCP 校验和卸载不兼容
    │             → 50/58 TCP 段校验和错误
    │             → 严重影响连接质量
    │
    └─► 次要风险：nf_conntrack_tcp_be_liberal=0
                  → 当前未触发丢弃
                  → 但存在潜在风险（窗口违规时丢包）
```

---

## 四、修复方案

### 4.1 应急处置

| 步骤 | 操作 | 风险等级 | 效果预期 |
|------|------|----------|----------|
| 1 | 在容器内执行 `ethtool -K eth0 tx off rx off` 关闭 TCP 校验和卸载 | 🟢 **低危** | 立即消除校验和错误，验证是否是卸载问题 |
| 2 | 若容器内无法执行，在主机侧对 veth 接口执行 `ethtool -K vethXXX tx off rx off` | 🟡 **中危** | 从主机侧修复校验和卸载问题 |
| 3 | 设置 `sysctl -w net.netfilter.nf_conntrack_tcp_be_liberal=1` 放宽 TCP window 跟踪 | 🟡 **中危** | 消除 conntrack 严格窗口跟踪的潜在风险 |

**步骤1 具体命令**：
```bash
# 容器内执行：
docker exec nf-test-E ethtool -K eth0 tx off rx off

# 验证：
docker exec nf-test-E ethtool -k eth0 | grep checksum
# 预期输出：tx-checksumming: off, rx-checksumming: off
```

**步骤3 具体命令**：
```bash
# 容器内（需特权模式或 --cap-add=NET_ADMIN）：
docker exec nf-test-E sysctl -w net.netfilter.nf_conntrack_tcp_be_liberal=1

# 或主机侧对容器 namespace 执行：
nsenter -t $(docker inspect nf-test-E --format '{{.State.Pid}}') -n sysctl -w net.netfilter.nf_conntrack_tcp_be_liberal=1
```

### 4.2 永久修复计划

| 修复措施 | 风险等级 | 说明 |
|---------|----------|------|
| 在 Docker Compose/K8s Pod 中配置容器关闭校验和卸载 | 🟢 低危 | 验证有效后固化到配置中 |
| 评估是否有必要保持 nf_conntrack_tcp_be_liberal=0 | 🟡 中危 | 若业务不需要严格窗口验证，建议设为 1 |
| 排查主机 Docker 网络驱动配置（overlay/macvlan/bridge） | 🟢 低危 | 确认是否存在已知的校验和卸载 bug |
| 升级 Docker/containerd 版本 | 🟡 中危 | 新版可能修复了 veth checksum offload 问题 |

### 4.3 回滚方案（针对高危操作）

| 操作 | 回滚命令 |
|------|---------|
| 关闭校验和卸载后如导致性能下降 | `ethtool -K eth0 tx on rx on` |
| 设置 be_liberal=1 后如担心安全 | `sysctl -w net.netfilter.nf_conntrack_tcp_be_liberal=0` |

---

## 五、验证建议

### 5.1 根因验证

| 验证项 | 方法 | 预期结果 |
|--------|------|---------|
| 确认校验和卸载状态 | `ethtool -k eth0 \| grep checksum` | 查看 tx/rx checksumming 是否开启 |
| 抓包确认校验和 | `tcpdump -i eth0 -n -v 'tcp'` | 观察 checksum 字段是否为 0 或错误值 |
| 校验 csum 错误计数 | `nstat -az TcpExt\|grep BadSegments` | 确认 bad segments 持续增长速率 |

### 5.2 修复验证

| 验证项 | 方法 | 预期结果 |
|--------|------|---------|
| 关闭 offload 后 bad segments | `nstat -az TcpExt \| grep BadSegments` | 不再增长或接近 0 |
| conntrack 状态 | `cat /proc/net/stat/nf_conntrack` | invalid 计数仍为 0 |
| 业务连通性 | 实际业务测试 | 连接稳定，无异常中断 |

---

## 六、关键排除项

| 排除假设 | 排除依据 |
|---------|---------|
| ❌ nf_conntrack 表已满导致丢包 | `drop=0, insert_failed=0, early_drop=0` 全部为零 |
| ❌ TCP window violation 导致 conntrack 丢弃 | `invalid=0` 所有 CPU 均无计数 |
| ❌ 网络硬件层面物理损坏 | 50 bad segments 集中在容器内部，更指向虚拟化层问题 |
| ❌ TCP 重传风暴 | `segments retransmitted = 0` |
| ❌ conntrack tcp_loose=0 导致丢包 | `tcp_loose=1` 实际为宽松模式 |

---

## 七、证据索引

| 证据项 | 来源文件 | 行号 |
|--------|---------|------|
| E1: nf_conntrack 全量计数器 | `kuafu_E_20260610_220114.md` | L23-L38 |
| E1: 重点关注字段（parsed） | `kuafu_E_20260610_220114.md` | L41-L185 |
| E2: TCP 连接状态统计 | `kuafu_E_20260610_220114.md` | L188-L195 |
| E3: 内核参数配置 | `kuafu_E_20260610_220114.md` | L198-L201 |
| E4: TCP window tracking 异常指南 | `kuafu_E_20260610_220114.md` | L204-L227 |
| E0: 差分分析 | `kuafu_E_20260610_220114.md` | L231-L232 |
