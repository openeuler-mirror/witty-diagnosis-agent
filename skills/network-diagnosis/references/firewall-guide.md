# 防火墙规则解读指南

本文档提供 iptables 和 nftables 规则的解读方法，用于网络故障诊断时判断防火墙是否导致丢包。

## iptables 规则解读

### 输出示例

`iptables -L -n -v` 输出示例：

```
Chain INPUT (policy ACCEPT 4862K packets, 1587M bytes)
 pkts bytes target     prot opt in     out     source               destination         
 4779 1570K DROP       0    --  enp4s0 *       0.0.0.0/0            0.0.0.0/0
 ^^^^ ^^^^  ^^^^       ^         ^^^^^^
 命中  数据量  动作              目标接口
 计数
```

### 字段含义

| 字段 | 含义 | 判断方法 |
|------|------|----------|
| `pkts` | 规则命中计数 | `pkts > 0` 表示规则**已生效**（有数据包被此规则处理） |
| `bytes` | 匹配数据量 | 累计匹配的字节数 |
| `target` | 处理动作 | `DROP` 表示数据包被**丢弃**；`REJECT` 表示数据包被**拒绝**（通常会返回 ICMP 不可达） |
| `prot` | 协议 | `0` 表示所有协议；`tcp`/`udp`/`icmp` 表示特定协议 |
| `in` | 入站接口 | 表示针对该接口的**入站流量** |
| `out` | 出站接口 | 表示针对该接口的**出站流量** |
| `source` | 源地址 | 匹配的源 IP/网段 |
| `destination` | 目的地址 | 匹配的目的 IP/网段 |

### 判断规则是否生效

规则生效的判断条件：
1. `pkts > 0` — 规则已被触发
2. `target = DROP` 或 `REJECT` — 动作是丢弃或拒绝
3. `in = <目标接口>` — 针对故障接口

满足以上条件时，防火墙规则是导致网络不通的可能原因之一。

---

## nftables 规则解读

### 输出示例

`nft list ruleset` 输出示例：

```
table inet firewalld {
    chain filter_INPUT {
        type filter hook input priority filter + 10; policy accept;
        
        ct state established,related accept
        iifname "enp4s0" drop
        ...
    }
}
```

### 关键关注点

| 关键字 | 含义 |
|--------|------|
| `drop` | 数据包被丢弃（无响应） |
| `reject` | 数据包被拒绝（通常返回 ICMP 不可达） |
| `iifname` | 入站接口名称匹配 |
| `oifname` | 出站接口名称匹配 |
| `counter` | 计数器（需查看 packets/bytes） |

### 查看规则命中计数

```bash
nft list ruleset -a
```

输出中会显示 `counter packets X bytes Y`，其中：
- `packets X` 表示命中次数
- `bytes Y` 表示匹配数据量

---

## 常见误判警示

### 虚拟网卡 ethtool 输出

虚拟机环境（virtio 网卡）的 ethtool 输出可能显示：
- `Speed: Unknown!`
- `Duplex: Unknown!`

这是**正常现象**，不应误判为物理链路故障。

### 防火墙规则命中

防火墙规则命中（`pkts > 0` 且 `target = DROP/REJECT`）是明确的故障信号，需结合其他证据综合判断：
- 检查该规则是否为预期配置
- 检查是否有其他规则在之前已处理了流量
- 对比正常接口的规则差异

---

## 相关命令

```bash
# 查看 iptables 规则（带计数器）
iptables -L -n -v

# 查看 iptables 规则（带行号）
iptables -L -n -v --line-numbers

# 查看 iptables NAT 规则
iptables -t nat -L -n -v

# 查看 nftables 规则
nft list ruleset

# 查看 nftables 规则（带 handle）
nft list ruleset -a

# 查看 nftables 计数器
nft list counters
```
