# Elasticsearch mmap 专项指南

## 概述

Elasticsearch 是 mmap 相关故障的重灾区。ES 大量使用 mmap 管理 Lucene 索引文件（.cfs、.fdt、.fdx、.nvd、.dvd 等），每个索引分片（shard）会打开多个 mmap。在索引较多、分片数较大的场景下，极易触发 vm.max_map_count 耗尽。

本指南专门针对 Elasticsearch 场景提供 mmap 故障分析和调优指导。

---

## ES mmap 使用场景

| 组件 | 用途 | 涉及文件 | 影响 |
|------|------|---------|------|
| Lucene 索引读取 | 通过 MMapDirectory 映射索引文件 | `*.cfs`, `*.fdt`, `*.fdx`, `*.nvd`, `*.dvd`, `*.tim`, `*.tip`, `*.dac`, `*.pos`, `*.pay` | 每个分片多个文件映射 |
| translog | 事务日志 | `translog-*` | 少量 mmap |
| 段合并 | NRT 合并时映射多个段文件 | 同上 | 峰值 VMA 更高 |
| 聚合/排序 | 字段数据缓存 | 文件映射 | 取决于字段数量 |

---

## 指标评估

### VMA 数量估算公式

```
每个 ES 进程 VMA ≈ 索引数量 × 分片数(主+副本) × 每分片映射文件数 + 系统基础映射

通常每个分片：40-100 个 mmap（取决于字段数量和段数量）
系统基础映射：100-300（JVM + 库映射等）
```

### 示例计算

| 索引数 | 分片数(主+副本) | 每分片映射 | 总 VMA 估算 | 需要 max_map_count |
|--------|----------------|-----------|------------|-------------------|
| 10     | 5 + 5 = 10    | 60        | 10×10×60+200=6,200 | 65530 (默认 OK) |
| 50     | 5 + 5 = 10    | 60        | 50×10×60+200=30,200 | 65530 (默认 OK) |
| 100    | 5 + 5 = 10    | 60        | 100×10×60+200=60,200 | 65530 (接近上限) |
| 500    | 3 + 3 = 6     | 40        | 500×6×40+200=120,200 | 262144 (需调整) |
| 1000   | 1 + 1 = 2     | 40        | 1000×2×40+200=80,200 | 262144 (需调整) |

> 建议：在 ES 部署时直接将 `vm.max_map_count` 设置为 262144（ES 官方推荐值）。

---

## 典型故障场景

### 场景 1：ES 启动失败 — vm.max_map_count 不足

**现象**：
```log
[2024-01-15T14:30:00,000][WARN ][o.e.bootstrap.Security] 
  max file descriptors [4096] for elasticsearch process is too low, increase to at least [65535]
[2024-01-15T14:30:01,000][WARN ][o.e.bootstrap.Startup] 
  max virtual memory areas vm.max_map_count [65530] is too low, increase to at least [262144]
```

**诊断**：
```bash
# 确认当前值
cat /proc/sys/vm/max_map_count

# 修改
sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" >> /etc/sysctl.conf
```

### 场景 2：ES 运行时 mmap 失败导致查询/写入异常

**现象**：
```log
java.io.IOException: mmap of 16777216 bytes failed: Cannot allocate memory
    at org.apache.lucene.store.MMapIndexInput.<init>(MMapIndexInput.java:64)
```

**诊断**：
```bash
# 检查 ES 进程 VMA 数量
ES_PID=$(pgrep -f elasticsearch | head -1)
cat /proc/$ES_PID/maps | wc -l
cat /proc/sys/vm/max_map_count

# 如果 VMA 数量 > 0.9 * max_map_count，需要立即处理
```

### 场景 3：ES mlockall 失败

**现象**：
```log
[1]: memory locking requested but [MEMLOCK] is too low
# 或
java.lang.RuntimeException: can not run elasticsearch as root
```

**诊断**：
```bash
# 检查 ES 进程 memlock 限制
ES_PID=$(pgrep -f elasticsearch | head -1)
cat /proc/$ES_PID/limits | grep "max locked memory"

# 检查系统限制
ulimit -H -l
ulimit -l

# 检查 systemd 配置
systemctl show elasticsearch --property=LimitMEMLOCK
```

---

## 配置调优

### 1. vm.max_map_count

```bash
# 临时（立即生效）
sysctl -w vm.max_map_count=262144

# 永久
echo "vm.max_map_count=262144" >> /etc/sysctl.conf
sysctl -p
```

### 2. ES 锁内存（bootstrap.memory_lock）

```yaml
# elasticsearch.yml
bootstrap.memory_lock: true
```

对应的系统配置：
```bash
# /etc/security/limits.conf
elasticsearch  soft  memlock  unlimited
elasticsearch  hard  memlock  unlimited

# 或 systemd 配置
# /etc/systemd/system/elasticsearch.service.d/override.conf
[Service]
LimitMEMLOCK=infinity
```

### 3. 减少 ES VMA 使用

```yaml
# elasticsearch.yml — 关键调优参数

# 减少每个分片的 mmap: 使用 NIOFSDirectory 替代 MMapDirectory（影响性能）
index.store.type: niofs

# 减少索引分片数
index.number_of_shards: 3  # 按需调整
index.number_of_replicas: 1

# 控制打开的文件句柄（间接影响 mmap）
indices.fielddata.cache.size: 20%
```

---

## 监控与告警

### 建议的告警指标

| 指标 | 告警阈值 | 说明 |
|------|---------|------|
| VMA 数量 / max_map_count | > 80% | 提前告警即将耗尽 |
| ES 日志中 mmap 错误 | 任意出现 | 立即告警 |
| mlock 状态 | 检查失败 | ES bootstrap check 失败 |
| 进程 VmLck | 接近 ulimit -l | mlock 即将超限 |
| 共享内存段数 | > 90% shmmni | 共享内存即将耗尽 |

### 监控命令示例

```bash
# 定期检查 VMA 使用率 (cron)
VMA_COUNT=$(cat /proc/$(pgrep -f elasticsearch | head -1)/maps | wc -l)
MAX_MAP=$(cat /proc/sys/vm/max_map_count)
USAGE=$((VMA_COUNT * 100 / MAX_MAP))
echo "VMA usage: $USAGE% ($VMA_COUNT/$MAX_MAP)"
[ "$USAGE" -gt 80 ] && echo "WARNING: VMA usage > 80%"

# 检查 mlock 状态
grep "bootstrap.memory_lock" /etc/elasticsearch/elasticsearch.yml

# ES API 检查节点状态
curl -s "http://localhost:9200/_nodes/stats/process" | jq '.nodes[].process'
```
