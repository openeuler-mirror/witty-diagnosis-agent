# OpenRCA 场景背景参考

## 1. 场景概述
OpenRCA 是一个基于 Kubernetes 微服务架构的根因分析基准环境。主要用于模拟和分析云原生应用中的常见故障。

## 2. 候选组件范围 (Candidate Entities)
- **Web/Proxy**: `apache01`, `apache02`
- **Application**: `Tomcat01`, `Tomcat02`, `Tomcat03`, `Tomcat04`
- **Database**: `Mysql01`, `Mysql02`
- **Cache**: `Redis01`, `Redis02`
- **Gateway/Ingress**: `MG01`, `MG02`, `IG01`, `IG02`

## 3. 核心指标范围 (Core Metrics)
- **CPU**: 使用率、负载。
- **内存 (Memory)**: 使用率、Swap。
- **磁盘 (Disk)**:
  - I/O: `DSKRead`, `DSKWrite`。
  - 空间: `Disk Space`。
- **JVM**:
  - `GC` (垃圾回收)。
  - `Heap`/`NoHeap` 内存。
  - `ThreadCount`。
- **数据库 (Database)**:
  - `Connections` (连接数)。
  - `Lock Wait` (锁等待)。
  - `Buffer Pool` (缓冲池)。
- **网络 (Network)**:
  - 流量: `Packets`, `KB`。
  - TCP 状态: `CLOSE-WAIT`, `FIN-WAIT`。
- **应用层 (Application)**:
  - `MRT` (响应时间)。
  - `Error Count` / `SR` (错误率)。

## 4. 数据集限制与提示 (Dataset Limitations & Hints)
- **网络指标**: 数据集可能不包含直接的网络延迟 (Ping) 或丢包率指标。请结合 TCP 连接状态、网络包量变化及应用层响应时间/错误日志进行推断。
- **应用指标**: 应用层指标 (ServiceTest) 反映整体健康度，但可能无法直接关联调用链 (Trace)。定位时请主要依赖组件级指标 (Tomcat/MySQL 等)。
- **时区**: **UTC+8**。

## 5. 日志策略
- **无需单独下载**: 本场景通常不需要使用 `log_fetcher.py` 下载日志，日志与指标通常集成在统一数据源中。
