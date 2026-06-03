# Serialization Cost - 序列化/反序列化分析剧本

## 触发条件

用户问题包含以下关键词：
- "序列化慢"、"反序列化慢"
- "JSON 解析"、"JSON 慢"
- "Protobuf"、"Thrift"、"Avro"
- "XML 解析"
- "Marshalling"、"Unmarshalling"
- "RPC 慢"、"编解码慢"
- "Jackson"、"Gson"、"Fastjson"
- "ObjectInputStream"

## 场景说明

序列化是分布式系统的"隐形税"：
- **CPU 税**：解析文本、反射、装箱拆箱消耗大量 CPU
- **分配税**：每次解析产生大量短命对象，推高 GC（与 [why-mem-high.md](why-mem-high.md) 联动）
- **延迟税**：在 RPC 路径上常占接口 P50-P90 时间的 20-50%

典型症状：
- 火焰图中 JSON/XML/protobuf 解析库占大片宽度
- 序列化/反序列化 > 5% 总 CPU
- GC 频繁但 on-CPU 也高（双重压力）

## 分析流程

### Step 1: 数据准备

1. 转换为折叠栈格式
2. 提取 RPC 入口/出口函数名（如 `onMessage` / `invoke` / `dispatch`）

### Step 2: 序列化模式检测

```bash
python scripts/analyzers/pattern_match.py --input folded.folded --json
```

重点匹配（来自 `analysis-patterns.md` 第 6 类）：

| 格式 | 特征函数/符号 | 权重 |
|------|-------------|------|
| JSON | `json.Unmarshal`, `json.Marshal`, `Jackson`, `Gson`, `Fastjson`, `ObjectMapper.writeValue` | 0.8 |
| Protobuf | `protobuf.Unmarshal`, `ParseFrom`, `MarshalTo`, `CodedInputStream` | 0.8 |
| Thrift | `TProtocol`, `TJsonProtocol`, `TBinaryProtocol` | 0.8 |
| Avro | `Decoder`, `Encoder`, `GenericDatumReader` | 0.7 |
| XML | `xml.Unmarshal`, `SAXParser`, `DOM`, `DocumentBuilder` | 0.7 |
| Java 序列化 | `ObjectInputStream`, `ObjectOutputStream`, `readObject`, `writeObject` | 0.9 |
| MessagePack | `MessagePack`, `Pack.unpack` | 0.7 |
| 压缩 | `deflate`, `inflate`, `compress`, `gzip`, `zstd` | 0.6 |
| Base64 | `Base64.encode`, `Base64.decode` | 0.5 |

### Step 3: 序列化热点分析

```bash
python scripts/analyzers/hotspot.py --input folded.folded --top 30 --json
```

按"叶帧是序列化库的栈"聚合，识别：
- 序列化库版本（Jackson 2.x vs 1.x 性能差异巨大）
- 解析模式：反射 vs 字节码生成 vs 编译期生成
- 数据规模：大对象 vs 小对象批处理

### Step 4: 反射开销检测

如果火焰图中出现 `Method.invoke` / `NativeMethodAccessorImpl` 在序列化路径上，需要单独标记：

| 信号 | 含义 |
|------|------|
| `Method.invoke` 占比 > 2% | 反射调用开销明显 |
| `ReflectionAccessor.getValue` 出现在序列化栈 | Jackson/Gson 走反射 |
| `BeanSerializer` 频繁出现 | 反射模式（非字节码生成） |

## 输出结构

```
## 序列化分析

### 序列化总占比
- 序列化函数合计: XX%
- 反序列化函数合计: XX%
- 格式分类: JSON 30% / Protobuf 15% / Java 序列化 5%

### 序列化热点栈
| 格式 | 入口 | 库 | 占比 | 备注 |
|------|------|----|------|------|
| JSON | onMessage | Jackson 2.13 | 25% | 反射模式 |
| Protobuf | parseRequest | protoc-gen | 5% | 正常 |
| Java | readObject | ObjectInputStream | 3% | 反序列化漏洞风险 |

### 反射开销
- 反射调用占比: XX%
- 涉及对象: [Top 3 频繁反射的类]

### 建议
- 启用字节码生成: Jackson Blackbird / GsonEx
- 切换格式: JSON → Protobuf
- 移除 Java 原生序列化
```

## 阈值标准

| 指标 | 阈值 | 严重度 |
|------|------|--------|
| 序列化总占比 | > 5% | 中（可优化点） |
| 序列化总占比 | > 20% | 高（首要看点） |
| 序列化总占比 | > 40% | 严重（业务计算被掩盖） |
| 单次序列化耗时 | > 10ms | 中（响应延迟贡献） |
| 单次序列化耗时 | > 100ms | 高（瓶颈路径） |
| 反射调用占比 | > 2% | 高（确认未启用字节码生成） |

## 典型场景

### 场景 1: Jackson 反射模式

**症状**：
- 火焰图：`BeanSerializer` → `BeanPropertyWriter.serializeAsField` → `Method.invoke`
- 反射栈占总 CPU 5%+

**根因**：
Jackson 默认对未配置 `@JsonComponent` 的类走反射路径。

**修复**：
- 升级到 Jackson 2.12+，注册 `BlackbirdModule` 启用字节码生成
  ```java
  ObjectMapper mapper = new ObjectMapper();
  mapper.registerModule(new BlackbirdModule());
  ```
- 或在编译期使用 `jackson-jr` / `DSL-JSON` 生成无反射的序列化器
- 给热点 DTO 加 `@JsonComponent` 自定义序列化器

### 场景 2: 大量小对象反序列化

**症状**：
- 火焰图底层是 `ObjectInputStream.readObject` / `JSON.parse` / `ParseFrom`
- 每次解析产生数十万短命对象
- 配合 [gc-pressure.md](gc-pressure.md) 的 GC 压力

**根因**：
高频 RPC，每次请求都解析一次。

**修复**：
- 合并请求（batch RPC）
- 复用反序列化器（线程局部）
- 改用零拷贝格式：FlatBuffers / Cap'n Proto / Protobuf
- 对热点类启用对象池

### 场景 3: Java 原生序列化

**症状**：
- 火焰图含 `ObjectInputStream.readObject` / `ObjectOutputStream.writeObject`
- 业务使用 `implements Serializable`

**问题**：
- 性能差（每对象一次反射+反射元数据）
- **安全风险**：反序列化漏洞（RCE）

**修复**：
- 立即停止使用 Java 原生序列化
- 改用 Protobuf / Kryo（白名单模式）/ Jackson

### 场景 4: XML 解析

**症状**：
- 火焰图含 `SAXParser` / `DocumentBuilder` / `xml.Unmarshal`
- 解析大 XML 文件或频繁解析

**修复**：
- 改用 JSON 或二进制格式
- 必要时用流式解析（StAX）
- 避免 DOM 解析大文件

### 场景 5: 字符串拼接 / 模板

**症状**：
- 火焰图底层 `StringBuilder.append` 反复出现
- 业务代码手动拼接 JSON

**修复**：
- 用标准库的 `Marshal` 函数
- 字符串模板预编译

## 关键识别表

| 框架 | 序列化函数 | 反序列化函数 | 优化方向 |
|------|-----------|-------------|---------|
| Jackson | `ObjectMapper.writeValue` | `ObjectMapper.readValue` | 启用 Blackbird / 预生成 |
| Gson | `Gson.toJson` | `Gson.fromJson` | 替换 TypeToken / 用 GsonEx |
| Fastjson | `JSON.toJSONString` | `JSON.parseObject` | 注意 autotype 漏洞 |
| Protobuf | `Message.toByteArray` | `Message.parseFrom` | 复用 Builder |
| Thrift | `TProtocol.write` | `TProtocol.read` | 切换 TCompactProtocol |
| Java IO | `ObjectOutputStream.writeObject` | `ObjectInputStream.readObject` | 立刻替换 |
| Go | `json.Marshal` | `json.Unmarshal` | 用 easyjson / ffjson |
| Python | `json.dumps` | `json.loads` | 用 ujson / orjson |

## 与其他剧本的协同

| 关联剧本 | 协同方式 |
|---------|---------|
| [gc-pressure.md](gc-pressure.md) | 序列化产生大量短命对象 → 推高 GC |
| [reflection-overhead.md](#)（若存在） | 序列化反射是反射热点的主要来源 |
| [io-wait.md](io-wait.md) | RPC 序列化后立即发网络，串行延迟叠加 |
| [why-mem-high.md](why-mem-high.md) | 大对象序列化驻留内存 |

## 优化建议

### 1. 选择高效格式

| 格式 | 速度 | 大小 | 可读性 | 跨语言 |
|------|------|------|--------|--------|
| Protobuf | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ❌ | ⭐⭐⭐⭐⭐ |
| FlatBuffers | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ❌ | ⭐⭐⭐⭐ |
| MessagePack | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ❌ | ⭐⭐⭐⭐ |
| JSON | ⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| XML | ⭐ | ⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Java Serializable | ⭐ | ⭐⭐⭐ | ❌ | ❌ |

**建议**：内部 RPC 用 Protobuf / FlatBuffers，对外 API 仍可用 JSON。

### 2. 启用字节码生成

- **Jackson**：注册 `BlackbirdModule`（2.12+）
- **Gson**：使用 `GsonEx` 或替换为 Jackson
- **Go**：用 `easyjson` / `ffjson` 预生成

### 3. 复用对象

- 复用 `ObjectMapper` / `Gson`（不要每次 `new`）
- 复用 Builder
- 复用 byte buffer（带 `clear()` 复用）

### 4. 流式与零拷贝

- 大消息用流式 API
- 零拷贝格式：FlatBuffers / Cap'n Proto
- 避免中间字符串

### 5. 安全

- **禁止使用 Java 原生序列化**（反序列化 RCE 风险）
- Fastjson 关闭 `autoType`
- Jackson 开启 `FAIL_ON_UNKNOWN_PROPERTIES=false` + 严格白名单

## 配套工具命令

```bash
# Java 火焰图中的序列化函数
perf record -e cpu-cycles -g -p <pid> sleep 30
perf script | grep -E "(Jackson|Gson|ObjectInputStream|writeObject|readObject)"

# Go pprof（看序列化是否在热点）
go tool pprof -top http://host/debug/pprof/profile

# Protobuf 字段统计
protoc --decode_raw < message.bin
```

## 常见误判

- **"JSON 慢" 不一定换格式**：如果业务需要可读性，启用字节码生成更划算
- **"反序列化慢" 不一定是库问题**：可能是消息本身大，先看消息大小分布
- **"序列化是瓶颈" 可能是误诊**：需结合 P99 延迟分解，确认序列化在关键路径上
