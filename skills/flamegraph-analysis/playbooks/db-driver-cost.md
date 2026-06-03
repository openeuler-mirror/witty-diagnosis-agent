# DB Driver Cost - 数据库驱动层分析剧本

## 触发条件

用户问题包含以下关键词：
- "数据库慢"、"DB 慢"
- "SQL 执行慢"、"慢查询"
- "连接池"、"connection pool"
- "HikariCP"、"Druid"、"c3p0"
- "JDBC"、"MySQL"、"PostgreSQL"、"Oracle"
- "SQLException"、"事务慢"
- "executeQuery" / "executeUpdate"

## 场景说明

数据库调用是绝大多数业务应用的**主路径**，火焰图中的 DB 驱动栈往往揭示：
- **驱动层开销**：网络往返、协议解析、结果集映射
- **连接池等待**：业务等不到连接（与 [lock-contention.md](lock-contention.md) 联动）
- **慢 SQL**：执行时间占比高（需结合 DB 端 profiling）
- **ORM 反模式**：Hibernate/MyBatis 生成的低效 SQL

典型症状：
- 火焰图中 `Statement.execute` / `sendQueryPacket` / `pq_exec` 占比 > 5%
- 连接池活跃连接长期打满
- 接口 P99 在 SQL 执行时尖刺
- DB 机器 CPU/IO 不高但应用侧觉得慢（说明是应用侧问题）

## 分析流程

### Step 1: 数据准备

1. 转换为折叠栈格式
2. 识别 ORM/驱动类型（MyBatis / Hibernate / JPA / JDBC 直连 / Go database/sql / GORM）

### Step 2: 数据库模式检测

```bash
python scripts/analyzers/pattern_match.py --input folded.folded --json
```

重点匹配（来自 `analysis-patterns.md` 第 9 类）：

| 模式 | 特征函数/符号 | 权重 |
|------|-------------|------|
| SQL 执行 | `execQuery`, `Statement.execute`, `PreparedStatement.execute`, `pq_exec`, `mysql_query` | 0.8 |
| 事务 | `beginTransaction`, `commit`, `rollback`, `setAutoCommit`, `Tx.Commit` | 0.7 |
| 连接获取 | `getConnection`, `DataSource.getConnection`, `HikariCP.getConnection` | 0.6 |
| 缓存未命中 | `cache_miss`, `LookupAccountSid`, `DiskCache` | 0.8 |
| ORM 反射 | `BeanInfo.getPropertyDescriptors`, `Introspector` | 0.7 |
| MyBatis | `BaseExecutor.query`, `SimpleExecutor.doQuery`, `MappedStatement` | 0.8 |
| Hibernate | `SessionImpl.fireLoader`, `Loader.executeQueryStatement` | 0.8 |
| GORM | `gorm.Query`, `Find`, `Where` | 0.7 |
| MySQL 驱动 | `MysqlIO.send`, `sendQueryPacket`, `MySQL_Protocol` | 0.8 |
| PostgreSQL 驱动 | `PgConnection.execSQL`, `PgProtocol` | 0.8 |
| Oracle 驱动 | `OracleStatement.doExecute`, `T4CConnection` | 0.8 |

### Step 3: 数据库热点分析

```bash
python scripts/analyzers/hotspot.py --input folded.folded --top 30 --json
```

按"叶帧是 SQL 执行函数"聚合：
- 哪些业务方法在做 DB 调用
- 单次调用耗时（通过样本数 / 调用次数估算）
- 是否在循环内做 DB（典型 N+1 问题）

### Step 4: 连接池等待检测

```bash
python scripts/analyzers/offcpu_classifier.py --input folded.folded --json
```

如果 `HikariCP.getConnection` / `DruinDataSource.getConnection` 出现在等待栈：
- 等待类型：`await` / `park` / `LockSupport.park`
- 等待时间：需配合 Off-CPU 数据

### Step 5: 慢 SQL 定位

火焰图只反映"在哪条路径上慢"，不直接给出 SQL。需结合：
- DB 端慢日志（`slow_query_log`）
- `EXPLAIN` 执行计划
- ORM 框架日志

## 输出结构

```
## 数据库分析

### DB 相关总占比
- 驱动层: XX%
- 协议层: XX%
- 缓存未命中: XX%
- 连接池等待: XX%
- 合计: XX%

### DB 调用热点
| 业务方法 | 驱动 | 占比 | 调用频次 | 备注 |
|---------|------|------|----------|------|
| UserService.findById | JDBC | 25% | 1k/s | 主键查询，正常 |
| OrderRepository.list | MyBatis | 15% | 100/s | 见疑似 N+1 |
| StatsService.summary | Hibernate | 8% | 10/s | 复杂聚合 |

### 连接池状态
- 活跃连接数: XX
- 最大连接数: XX
- 等待获取连接的请求数: XX
- 等待占比: XX%

### 协议层开销
| 操作 | 占比 | 备注 |
|------|------|------|
| sendQueryPacket | 10% | 网络往返 |
| ResultSet.next | 5% | 大结果集 |
| Object Mapping | 8% | ORM 反射 |

### 疑似 N+1 查询
[在循环内做单条查询的栈]
```

## 阈值标准

| 指标 | 阈值 | 严重度 |
|------|------|--------|
| DB 调用总占比 | > 10% | 中（正常业务，但可优化） |
| DB 调用总占比 | > 30% | 高（接口几乎全在等 DB） |
| 单次 DB 调用 | > 10ms | 中（响应延迟贡献） |
| 单次 DB 调用 | > 100ms | 高（必查慢 SQL） |
| 连接池等待占比 | > 5% | 中（连接数不足） |
| 连接池等待占比 | > 20% | 高（pool 打满） |
| N+1 模式 | 检测到 | 高（架构问题） |

## 典型场景

### 场景 1: N+1 查询

**症状**：
- 火焰图中 `findById` 反复出现，根栈是 `for` 循环
- 一次"查询列表"实际触发了 1+N 次 SQL

**根因**：
ORM 默认懒加载。例：查 100 个 Order，每个 Order 触发一次 `findUser`。

**修复**：
- **MyBatis**：`@One` / `@Many` 配置 `fetchType=EAGER`，或 `<collection select=...>` 改用 JOIN
- **Hibernate**：`@EntityGraph` / `@Fetch(FetchMode.JOIN)` / `join fetch`
- **JPA**：`JOIN FETCH` 一次性查
- **Go GORM**：`db.Preload("User")`
- **根治**：业务层用单条 JOIN 查询替代循环

### 场景 2: 大结果集加载

**症状**：
- 火焰图 `ResultSet.next` / `Rows.Next` 占比 > 5%
- `Object Mapping` 同步占比高（反射转换）

**根因**：
- 单次 SQL 返回百万行
- ORM 把整张表加载到内存

**修复**：
- 分页：`LIMIT/OFFSET` 或 `Keyset` 分页
- 流式 API：`Statement.setFetchSize` / `db.Query` 流式迭代
- 改用 `scroll` cursor
- 评估是否真的需要全部数据

### 场景 3: 连接池配置不当

**症状**：
- `HikariCP.getConnection` 在等待栈中频繁出现
- Off-CPU 中 `LockSupport.park` 在连接获取路径上

**根因**：
- `maximumPoolSize` 过小
- 连接泄漏（用完没关闭）
- 连接持有时间过长（如慢 SQL 持有连接）

**修复**：
- 调大 poolSize（但不应超过 DB 端 `max_connections` 的 70%）
- 检查连接泄漏：`HikariCP.leakDetectionThreshold=30000`
- 优化慢 SQL，缩短持有时间
- 用 `awaitTimeout` 主动超时，避免无限等

### 场景 4: ORM 反射开销

**症状**：
- 火焰图 `BeanInfo.getPropertyDescriptors` / `Introspector` 出现
- 大量 `setter` 调用

**根因**：
- ORM 通过反射调用 setter
- 每次查询都做反射

**修复**：
- **MyBatis**：默认不反射，性能好
- **Hibernate**：用 `@Entity` 编译期字节码增强（maven 插件）
- **通用**：考虑用 JPA + `hibernate-enhance-maven-plugin` 生成字节码

### 场景 5: 频繁提交/回滚事务

**症状**：
- `Transaction.commit` / `setAutoCommit` 占比 > 3%
- 每个 DAO 方法都开新事务

**根因**：
- `@Transactional` 粒度过细
- 每个 SQL 一个事务

**修复**：
- 一个业务方法一个事务
- 批量操作合并事务
- 关闭自动提交，批量提交

### 场景 6: 慢 SQL 在应用侧不显著

**症状**：
- DB 端慢日志显示慢 SQL
- 但应用火焰图中 `Statement.execute` 不高

**说明**：
- 应用和 DB 之间的网络延迟主导
- 慢 SQL 已经优化但协议层开销大

**修复**：
- 部署到 DB 同可用区（同 AZ）
- 启用 prepared statement 缓存
- 用 `MySQL` 的 `useServerPrepStmts=true`（驱动参数）
- 考虑读写分离

## 关键识别表

| 框架 | 连接获取 | 查询执行 | 结果映射 | 事务 |
|------|---------|---------|---------|------|
| JDBC | `DataSource.getConnection` | `Statement.execute` | `ResultSet.next` | `connection.commit` |
| MyBatis | `SqlSession` | `BaseExecutor.query` | `ResultSetHandler` | `SqlSession.commit` |
| Hibernate | `Session` | `SessionImpl.fireLoader` | `EntityLoader` | `Transaction.commit` |
| Spring JPA | `EntityManager` | `Query.getResultList` | `EntityManager.refresh` | `JpaTransactionManager` |
| Go database/sql | `db.Query` | `driver.Query` | `rows.Next` | `Tx.Commit` |
| GORM | `db.Find` | `Query.callback` | `Scan` | `db.Transaction` |
| MySQL JDBC | `MysqlIO.send` | `sendQueryPacket` | `ResultSetRow` | - |
| PG JDBC | `PgConnection.execSQL` | `PgProtocol` | `PgResultSet` | - |

## 与其他剧本的协同

| 关联剧本 | 协同方式 |
|---------|---------|
| [lock-contention.md](lock-contention.md) | 连接池等待本质是锁竞争 |
| [io-wait.md](io-wait.md) | 协议层网络 I/O |
| [serialization-cost.md](serialization-cost.md) | ORM 反射做 Bean 映射 |
| [why-mem-high.md](why-mem-high.md) | 大结果集 / 缓存驻留内存 |
| [gc-pressure.md](gc-pressure.md) | ORM 反射 + 结果映射产生大量临时对象 |
| [joint-on-off-cpu.md](joint-on-off-cpu.md) | DB 调用是典型 on + off 混合（执行 vs 等待响应） |

## 优化建议

### 1. SQL 优化

- 加索引（看 `EXPLAIN`）
- 避免 `SELECT *`
- 避免深分页（`LIMIT 100000, 10` → 改 cursor 分页）
- 避免 `IN` 子查询 + 临时表
- 警惕类型转换（`WHERE varchar_field = int_value`）

### 2. 减少调用次数

- 合并查询
- 批量插入/更新（`executeBatch` / `COPY`）
- 缓存读多写少的数据（Redis / Caffeine）
- 预加载常用关联

### 3. 优化 ORM

- 关闭反射（编译期生成）
- 关闭 N+1（JOIN FETCH）
- 关闭自动脏检查（`@DynamicUpdate`）
- 二级缓存配置合理

### 4. 连接池调优

- `maximumPoolSize` 根据 DB 容量设置
- `connectionTimeout` 防止无限等
- `leakDetectionThreshold` 排查泄漏
- 启用 `keepaliveTime`（防中间设备断开）

### 5. 架构层

- 读写分离
- 分库分表
- 引入 Proxy（ShardingSphere / Vitess）
- 引入缓存层
- 异步化（CDC / 消息队列）

### 6. 协议优化

- 用 prepared statement（减少解析）
- 启用压缩（`useCompression=true`）
- 调整 `fetchSize`
- 用 cursor 流式

## 配套工具命令

```bash
# MySQL 慢日志
SHOW VARIABLES LIKE 'slow_query_log';
SHOW VARIABLES LIKE 'long_query_time';
SHOW VARIABLES LIKE 'slow_query_log_file';

# EXPLAIN
EXPLAIN ANALYZE SELECT ...;

# HikariCP 监控
JMX: HikariPool-*.getActiveConnections()
JMX: HikariPool-*.getThreadsAwaitingConnection()

# Go pprof 看 DB 调用
go tool pprof -top http://host/debug/pprof/profile
# 然后 (pprof) peek func db.Query

# Java async-profiler 配合 JFR
./asprof -e jdbc -f db.html <pid>
```

## 常见误判

- **"DB 慢" 不一定是 SQL 慢**：可能是网络、连接池、ORM 反射
- **"连接池打满" 不一定扩 pool**：可能 SQL 慢导致连接持有长，先优化 SQL
- **"加索引就快" 是过度简化**：复杂查询可能需要改写
- **"N+1 慢" 改 JOIN 不一定最快**：JOIN 过多反而慢，需看实际执行计划
