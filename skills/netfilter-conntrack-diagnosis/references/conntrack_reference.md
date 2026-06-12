# Conntrack 内核机制速查手册

## 一、conntrack 架构概览

```
                    ┌─────────────────────────┐
                    │    nf_conntrack 核心      │
                    │   (连接跟踪引擎)           │
                    └──────────┬──────────────┘
                               │
          ┌────────────────────┼────────────────────┐
          ▼                    ▼                    ▼
  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
  │ nf_conntrack │    │  nf_nat      │    │   helper     │
  │   协议层      │    │  (NAT 引擎)   │    │  (ALG 辅助)   │
  │ tcp/udp/icmp │    │ SNAT/DNAT    │    │ ftp/sip/tftp │
  └──────────────┘    └──────────────┘    └──────────────┘
```

### 核心数据结构

```
nf_conn (conntrack 条目)
  ├── tuplehash[2]      # 二元组（原始方向 + 回复方向）
  │   ├── tuple.src     # 源 IP、端口、协议
  │   └── tuple.dst     # 目的 IP、端口、协议
  ├── status            # IPS_* 状态位
  ├── timeout           # 超时时间 (jiffies)
  ├── mark              # ctmark
  ├── zone              # conntrack zone (namespace)
  ├── nat               # NAT 转换信息
  └── helper            # ALG helper 信息
```

## 二、conntrack 状态机

### TCP 状态迁移

```
CLOSED
   │
   ▼
SYN_SENT ─────────► SYN_RECV
   │                    │
   │                    ▼
   │              ESTABLISHED
   │                    │
   │              ┌─────┴─────┐
   │              ▼           ▼
   │         FIN_WAIT      CLOSE_WAIT
   │              │           │
   │              ▼           ▼
   │         TIME_WAIT     LAST_ACK
   │              │           │
   │              └────┬──────┘
   │                   ▼
   │               CLOSED (已删除)
   │
   └──► 任何异常 → INVALID
```

### conntrack 条目生命周期

```
  分配 nf_conn
      │
      ▼
  INIT (tuple 初始化)
      │
      ▼
  NEW (收到第一个包，创建 entry)
      │
      ├── 收到回包 → ESTABLISHED/REPLIED
      │
      ├── 超时无回包 → UNREPLIED(只看到单向) → timeout → 删除
      │
      ├── TCP 状态迁移 → 各 TCP 子状态
      │
      ├── 收到 RST → 立即标记 CLOSE 并缩短 timeout
      │
      └── 状态机异常 → INVALID → DROP
```

## 三、关键内核参数速查

### 容量相关

| 参数 | 默认值 | 含义 | 调整建议 |
|------|--------|------|---------|
| `net.netfilter.nf_conntrack_max` | 262144 | 最大连接跟踪条目数 | 根据并发连接数设置，通常 1048576+ |
| `net.netfilter.nf_conntrack_buckets` | 65536 | 哈希表桶数 | 建议 = nf_conntrack_max / 4 |
| `net.netfilter.nf_conntrack_count` | (只读) | 当前连接数 | 与 max 比对计算使用率 |

### 超时相关 (TCP)

| 参数 | 默认值(s) | 含义 | 调整建议 |
|------|-----------|------|---------|
| `tcp_timeout_established` | 432000 (5天) | 已建立连接超时 | 长连接场景 604800+ |
| `tcp_timeout_time_wait` | 120 | TIME_WAIT 状态超时 | 通常保持默认 |
| `tcp_timeout_syn_recv` | 60 | SYN_RECV 半连接超时 | DDoS 保护可缩短至 30 |
| `tcp_timeout_syn_sent` | 120 | SYN_SENT 超时 | 通常保持默认 |
| `tcp_timeout_fin_wait` | 120 | FIN_WAIT 超时 | 通常保持默认 |
| `tcp_timeout_close_wait` | 60 | CLOSE_WAIT 超时 | 应用不及时 close 时可缩短 |
| `tcp_timeout_last_ack` | 30 | LAST_ACK 超时 | 通常保持默认 |
| `tcp_be_liberal` | 0 | TCP window 宽松模式 | 1=宽松(window violation 不标记 INVALID) |
| `tcp_loose` | 1 | TCP conntrack 宽松模式 | 0=严格(需按状态机) |

### 超时相关 (UDP/ICMP)

| 参数 | 默认值(s) | 含义 | 调整建议 |
|------|-----------|------|---------|
| `udp_timeout` | 30 | UDP 连接超时 | DNS 场景 60+ |
| `udp_timeout_stream` | 180 | UDP 流超时 | VoIP 场景 180+ |
| `icmp_timeout` | 30 | ICMP 超时 | 通常保持默认 |

### 其他关键参数

| 参数 | 默认值 | 含义 | 说明 |
|------|--------|------|------|
| `nf_conntrack_helper` | 0 (新内核) / 1 (旧内核) | 自动 helper 分配 | 建议关闭(0)，显式使用 `-m helper` |
| `nf_conntrack_checksum` | 1 | 检查包校验和 | 关闭(0)可减少 INVALID 但降低安全性 |
| `nf_conntrack_timestamp` | 0 | 启用时间戳 | 1=启用(会增加内存开销) |

## 四、/proc/net/stat/nf_conntrack 字段全解

```
字段名              含义                          正常值    告警阈值
─────────────────────────────────────────────────────────────
found               查找命中次数                 持续增长   无
searched            查找总次数                   持续增长   无
new                 新建连接数                   持续增长   无
invalid             无效包计数                   低或无    持续增长
delete              删除条目数                   持续增长   无
delete_list         批量删除数                   正常       异常波动
insert              insert 成功数                持续增长   无
insert_failed       insert 失败数                0          > 0
drop                丢弃包数                     0          > 0
early_drop          因表满提前丢弃               0          > 0
icmp_error          ICMP 错误数                  低         > 100/s
expect_new          期望连接新建                  低        异常波动
expect_create       期望连接创建                  低        异常波动
expect_delete       期望连接删除                  低        异常波动
search_restart      哈希表搜索重启                0          > 0/s (哈希表太小)
```

## 五、conntrack 常见故障模式

### 5.1 表满溢出 (nf_conntrack: table full)

**症状**:
- `dmesg` 出现 `nf_conntrack: table full, dropping packet`
- `/proc/net/stat/nf_conntrack` 中 `drop`、`early_drop`、`insert_failed` 增长
- 新连接无法建立，已有连接不受影响

**根因**:
1. `nf_conntrack_max` 太小，不足以承载实际并发连接数
2. conntrack 条目未及时释放（TIME_WAIT 过多或超时配置过长）
3. 哈希表太小导致冲突链过长（`search_restart` 增长）

**排查命令**:
```bash
# 检查容量
cat /proc/sys/net/netfilter/nf_conntrack_count
cat /proc/sys/net/netfilter/nf_conntrack_max
# 查看内核日志
dmesg -T | grep "table full"
# 查看丢包计数
cat /proc/net/stat/nf_conntrack | awk '{print "insert_failed=" $8 " drop=" $9 " early_drop=" $10}'
```

**修复方向**:
- 增大 `nf_conntrack_max` 和 `nf_conntrack_buckets`
- 缩短各协议 timeout（特别是 TIME_WAIT 和 ESTABLISHED）
- 排查异常连接增长源（DDoS、应用 bug、TIME_WAIT 堆积）

### 5.2 INVALID 状态丢包

**症状**:
- conntrack 中出现大量 `INVALID` 条目
- `ct state invalid drop` 规则命中计数增长
- 连接间歇性中断

**根因**:
1. TCP 状态机异常（RST 后收到数据、SYN 后收到非 SYN）
2. 校验和错误（硬件 offload 异常）
3. 报文长度异常（分片重组失败）
4. window violation（窗口缩放不一致）
5. 缺 NEW 直接收到 ESTABLISHED 包

**排查命令**:
```bash
# 查看 INVALID 条目
conntrack -L --state INVALID
# 关闭校验和检查（排查用）
sysctl -w net.netfilter.nf_conntrack_checksum=0
```

### 5.3 UNREPLIED 条目堆积

**症状**:
- 大量 UNREPLIED 状态条目
- 对端无响应或回包未到达

**根因**:
1. 对端不可达/无响应
2. 回包被防火墙丢弃（未配置 ESTABLISHED,RELATED 放行）
3. 回包路径与发起路径不一致（非对称路由）
4. SNAT/DNAT 映射错误导致回包无法匹配

**排查命令**:
```bash
# 查看 UNREPLIED 条目
conntrack -L --state UNREPLIED
# 按 SYN_SENT 过滤（正常发起连接）
conntrack -L --state UNREPLIED | grep SYN_SENT
# 检查是否有非 SYN_SENT 的 UNREPLIED（异常）
conntrack -L --state UNREPLIED | grep -v SYN_SENT
```

### 5.4 NAT 映射异常

**症状**:
- 出站 SNAT 后源地址错误
- 入站 DNAT 未到达目标
- `conntrack -L -n` 中的 NAT 映射与预期不符

**根因**:
1. NAT 规则顺序错误（DNAT 应在 SNAT 之前）
2. MASQUERADE 依赖的接口 IP 发生变化
3. conntrack 条目被提前删除（timeout 太短）又重建
4. NAT 环回问题（hairpin NAT）

**排查命令**:
```bash
# 查看 NAT 映射
conntrack -L -n
# 按 SNAT/DNAT 过滤
conntrack -L -n | grep "SNAT"
conntrack -L -n | grep "DNAT"
# 查看 NAT 规则
iptables -t nat -L -n -v
```

### 5.5 helper/ALG 问题

**症状**:
- FTP 数据通道无法建立
- SIP 通话单向音频
- TFTP 传输失败

**根因**:
1. helper 模块未加载（`nf_conntrack_ftp` 等）
2. `nf_conntrack_helper=0` 且规则中未显式使用 `-m helper`
3. 防火墙未放行 RELATED 流量
4. NAT 环境下 ALG 未正确处理地址转换

**排查命令**:
```bash
# 查看已加载 helper
lsmod | grep nf_conntrack
# 查看 helper 配置
cat /proc/sys/net/netfilter/nf_conntrack_helper
# 显式加载 helper
modprobe nf_conntrack_ftp
```

### 5.6 TCP window tracking 问题

**症状**: 连接建立后数据传输异常，`invalid` 计数增长
**根因**: `tcp_be_liberal=0` 严格模式下窗口缩放不匹配
**缓解**: 设置 `sysctl -w net.netfilter.nf_conntrack_tcp_be_liberal=1`

---

## 六、conntrack 工具命令速查

| 命令 | 用途 | 示例 |
|------|------|------|
| `conntrack -L` | 列出所有条目 | `conntrack -L` |
| `conntrack -L -p tcp` | 按协议过滤 | `conntrack -L -p tcp` |
| `conntrack -L --state INVALID` | 按状态过滤 | `conntrack -L --state INVALID` |
| `conntrack -L --orig-src X.X.X.X` | 按源 IP 过滤 | `conntrack -L --orig-src 10.0.0.1` |
| `conntrack -L -n` | 只显示 NAT 转换 | `conntrack -L -n` |
| `conntrack -C` | 条目总数 | `conntrack -C` |
| `conntrack -S` | 汇总统计 | `conntrack -S` |
| `conntrack -D --state INVALID` | 删除所有 INVALID | 🔴 高危: 谨慎使用 |
| `conntrack -E` | 事件监控(实时) | `conntrack -E -p tcp` |

### /proc 替代方案（无 conntrack 工具时）

```bash
# 总条目数
wc -l /proc/net/nf_conntrack
# 按状态统计
awk '{print $4}' /proc/net/nf_conntrack | sort | uniq -c | sort -rn
# 查看 NAT 映射
grep -E "SNAT|DNAT" /proc/net/nf_conntrack
```
