# 链路追踪分析测试用例

## 测试目的

验证trace-analyzer技能在各种场景下的正确性、稳定性和性能表现，确保技能能够：
1. 准确解析不同格式的追踪数据
2. 正确重建服务调用链路
3. 准确识别性能瓶颈
4. 正确分析依赖关系
5. 有效定位问题根因
6. 生成正确的可视化输出
7. 优雅处理异常情况

## 测试环境

### 系统配置
- **操作系统**：欧拉OS 2.0
- **CPU**：4核 Intel Xeon
- **内存**：8GB
- **存储**：100GB SSD
- **网络**：千兆以太网

### 软件版本
- **Python**：3.9+
- **依赖库**：参见requirements.txt
- **测试框架**：pytest 7.0+
- **追踪数据生成工具**：trace-generator 1.0.0

### 测试数据
所有测试数据使用标准化工具生成，确保可重复性：
```bash
# 生成测试数据
python3 generate_test_traces.py \
  --test-case basic \
  --trace-count 100 \
  --output test_traces_basic.json
```

## 测试用例

### 测试1：基础链路重建测试

#### 测试目的
验证技能能够正确解析追踪数据并重建调用链路。

#### 测试数据
```json
// test_traces_basic.json
[
  {
    "traceId": "test-trace-001",
    "spanId": "span-1",
    "parentSpanId": null,
    "operationName": "HTTP GET /api/test",
    "startTime": "2026-02-03T10:00:00.000Z",
    "duration": 100,
    "tags": {"service.name": "service-a"}
  },
  {
    "traceId": "test-trace-001",
    "spanId": "span-2",
    "parentSpanId": "span-1",
    "operationName": "Process Request",
    "startTime": "2026-02-03T10:00:00.020Z",
    "duration": 60,
    "tags": {"service.name": "service-b"}
  },
  {
    "traceId": "test-trace-001",
    "spanId": "span-3",
    "parentSpanId": "span-2",
    "operationName": "Database Query",
    "startTime": "2026-02-03T10:00:00.040Z",
    "duration": 40,
    "tags": {"service.name": "service-c"}
  }
]
```

#### 测试步骤
1. 准备测试输入数据
2. 执行trace-analyzer技能
3. 验证输出结果

#### 执行命令
```bash
claude witty-diagnosis:trace-analyzer \
  --session-id "test-basic-001" \
  --trace-data test_traces_basic.json \
  --analysis-type latency \
  --output-format json
```

#### 预期结果
1. **状态**：`"success"`
2. **链路重建**：正确识别调用链路 `service-a → service-b → service-c`
3. **延迟计算**：总延迟100ms，各节点延迟正确
4. **服务识别**：正确识别3个唯一服务

#### 验证点
- [ ] 输出状态为success
- [ ] 调用链路重建正确
- [ ] 延迟计算准确
- [ ] 服务识别完整
- [ ] 执行时间<5秒

### 测试2：性能瓶颈识别测试

#### 测试目的
验证技能能够准确识别性能瓶颈。

#### 测试数据
```json
// test_traces_bottleneck.json
[
  {
    "traceId": "test-trace-002",
    "spanId": "span-1",
    "parentSpanId": null,
    "operationName": "API Request",
    "startTime": "2026-02-03T10:00:00.000Z",
    "duration": 1500,
    "tags": {"service.name": "gateway"}
  },
  {
    "traceId": "test-trace-002",
    "spanId": "span-2",
    "parentSpanId": "span-1",
    "operationName": "Fast Processing",
    "startTime": "2026-02-03T10:00:00.050Z",
    "duration": 100,
    "tags": {"service.name": "service-fast"}
  },
  {
    "traceId": "test-trace-002",
    "spanId": "span-3",
    "parentSpanId": "span-1",
    "operationName": "Slow Processing",
    "startTime": "2026-02-03T10:00:00.100Z",
    "duration": 1300,
    "tags": {"service.name": "service-slow"}
  }
]
```

#### 测试步骤
1. 准备包含明显瓶颈的测试数据
2. 设置延迟阈值500ms
3. 执行瓶颈分析
4. 验证瓶颈识别结果

#### 执行命令
```bash
claude witty-diagnosis:trace-analyzer \
  --session-id "test-bottleneck-001" \
  --trace-data test_traces_bottleneck.json \
  --analysis-type latency \
  --latency-threshold-ms 500 \
  --output-format json
```

#### 预期结果
1. **瓶颈识别**：正确识别service-slow为主要瓶颈
2. **延迟贡献**：service-slow贡献度>80%
3. **阈值检查**：标记超过阈值的节点
4. **建议生成**：提供合理的优化建议

#### 验证点
- [ ] 准确识别主要瓶颈
- [ ] 正确计算延迟贡献度
- [ ] 阈值检查功能正常
- [ ] 提供具体优化建议
- [ ] 执行时间<5秒

### 测试3：依赖关系分析测试

#### 测试目的
验证技能能够正确分析服务依赖关系。

#### 测试数据
```json
// test_traces_dependency.json
[
  // 多个trace，展示复杂依赖关系
  {
    "traceId": "trace-dep-001",
    "spanId": "span-a1",
    "parentSpanId": null,
    "operationName": "Request A",
    "startTime": "2026-02-03T10:00:00.000Z",
    "duration": 200,
    "tags": {"service.name": "service-a"}
  },
  {
    "traceId": "trace-dep-001",
    "spanId": "span-b1",
    "parentSpanId": "span-a1",
    "operationName": "Call B",
    "startTime": "2026-02-03T10:00:00.050Z",
    "duration": 100,
    "tags": {"service.name": "service-b"}
  },
  {
    "traceId": "trace-dep-001",
    "spanId": "span-c1",
    "parentSpanId": "span-b1",
    "operationName": "Call C",
    "startTime": "2026-02-03T10:00:00.100Z",
    "duration": 50,
    "tags": {"service.name": "service-c"}
  },
  {
    "traceId": "trace-dep-002",
    "spanId": "span-a2",
    "parentSpanId": null,
    "operationName": "Request A",
    "startTime": "2026-02-03T10:00:10.000Z",
    "duration": 300,
    "tags": {"service.name": "service-a"}
  },
  {
    "traceId": "trace-dep-002",
    "spanId": "span-c2",
    "parentSpanId": "span-a2",
    "operationName": "Call C",
    "startTime": "2026-02-03T10:00:10.050Z",
    "duration": 200,
    "tags": {"service.name": "service-c"}
  }
]
```

#### 测试步骤
1. 准备包含复杂依赖关系的测试数据
2. 执行依赖关系分析
3. 验证依赖关系提取结果
4. 检查可视化输出

#### 执行命令
```bash
claude witty-diagnosis:trace-analyzer \
  --session-id "test-dependency-001" \
  --trace-data test_traces_dependency.json \
  --analysis-type dependency \
  --dependency-depth 3 \
  --visualization-format mermaid \
  --output-format json
```

#### 预期结果
1. **依赖关系**：正确提取 `a→b→c` 和 `a→c` 两种依赖
2. **调用频率**：正确统计各依赖的调用次数
3. **依赖强度**：计算合理的依赖强度值
4. **可视化**：生成正确的Mermaid图

#### 验证点
- [ ] 正确提取所有依赖关系
- [ ] 准确统计调用频率
- [ ] 依赖强度计算合理
- [ ] 可视化输出格式正确
- [ ] 执行时间<10秒

### 测试4：根因定位测试

#### 测试目的
验证技能能够有效定位问题根因。

#### 测试数据
```json
// test_traces_rootcause.json
[
  // 包含错误传播的追踪数据
  {
    "traceId": "trace-rc-001",
    "spanId": "span-root",
    "parentSpanId": null,
    "operationName": "User Request",
    "startTime": "2026-02-03T10:00:00.000Z",
    "duration": 1200,
    "tags": {
      "service.name": "frontend",
      "http.status_code": 500,
      "error": "true"
    },
    "logs": [
      {
        "timestamp": "2026-02-03T10:00:01.200Z",
        "fields": {"event": "request_failed", "error": "downstream_error"}
      }
    ]
  },
  {
    "traceId": "trace-rc-001",
    "spanId": "span-middle",
    "parentSpanId": "span-root",
    "operationName": "Process Data",
    "startTime": "2026-02-03T10:00:00.100Z",
    "duration": 1000,
    "tags": {
      "service.name": "middleware",
      "error": "true"
    },
    "logs": [
      {
        "timestamp": "2026-02-03T10:00:01.100Z",
        "fields": {"event": "processing_failed", "error": "database_error"}
      }
    ]
  },
  {
    "traceId": "trace-rc-001",
    "spanId": "span-leaf",
    "parentSpanId": "span-middle",
    "operationName": "Database Query",
    "startTime": "2026-02-03T10:00:00.200Z",
    "duration": 800,
    "tags": {
      "service.name": "database",
      "db.error": "connection_timeout",
      "error": "true"
    }
  }
]
```

#### 测试步骤
1. 准备包含错误传播链的测试数据
2. 执行根因定位分析
3. 验证根因识别结果
4. 检查置信度评估

#### 执行命令
```bash
claude witty-diagnosis:trace-analyzer \
  --session-id "test-rootcause-001" \
  --trace-data test_traces_rootcause.json \
  --analysis-type root-cause \
  --confidence-threshold 0.7 \
  --output-format json
```

#### 预期结果
1. **根因定位**：正确识别database为根因
2. **传播路径**：正确分析错误传播路径 `database → middleware → frontend`
3. **置信度**：根因置信度>0.8
4. **证据**：提供充分的定位证据

#### 验证点
- [ ] 准确识别问题根因
- [ ] 正确分析错误传播
- [ ] 置信度评估合理
- [ ] 提供充分证据
- [ ] 执行时间<8秒

### 测试5：数据格式兼容性测试

#### 测试目的
验证技能支持多种追踪数据格式。

#### 测试数据
准备不同格式的测试数据：
1. **Jaeger格式**：test_traces_jaeger.json
2. **Zipkin格式**：test_traces_zipkin.json
3. **SkyWalking格式**：test_traces_skywalking.json
4. **OpenTelemetry格式**：test_traces_otel.json

#### 测试步骤
1. 为每种格式准备相同的调用链路数据
2. 分别使用自动检测和明确指定格式执行分析
3. 验证分析结果的一致性
4. 检查格式转换的正确性

#### 执行命令
```bash
# 自动格式检测
claude witty-diagnosis:trace-analyzer \
  --session-id "test-format-auto-001" \
  --trace-data test_traces_jaeger.json \
  --analysis-type latency \
  --trace-format auto

# 明确指定格式
claude witty-diagnosis:trace-analyzer \
  --session-id "test-format-jaeger-001" \
  --trace-data test_traces_jaeger.json \
  --analysis-type latency \
  --trace-format jaeger
```

#### 预期结果
1. **格式检测**：自动检测正确识别格式
2. **解析成功**：所有格式都能正确解析
3. **结果一致**：不同格式相同数据得到一致分析结果
4. **错误处理**：无效格式提供清晰错误信息

#### 验证点
- [ ] 自动格式检测准确
- [ ] 所有支持格式解析成功
- [ ] 分析结果跨格式一致
- [ ] 无效格式优雅处理
- [ ] 执行时间每种格式<5秒

### 测试6：大规模数据处理测试

#### 测试目的
验证技能处理大规模追踪数据的性能。

#### 测试数据
生成大规模测试数据：
- **数据量**：10,000个trace，约100,000个span
- **时间范围**：24小时
- **服务数量**：50个唯一服务
- **调用深度**：最大深度8层

#### 测试步骤
1. 生成大规模测试数据
2. 执行全面分析
3. 监控资源使用情况
4. 验证分析结果的正确性

#### 执行命令
```bash
claude witty-diagnosis:trace-analyzer \
  --session-id "test-scale-001" \
  --trace-data large_traces.json \
  --analysis-type comprehensive \
  --timeout 600 \
  --output-format json \
  --verbosity info
```

#### 预期结果
1. **执行成功**：在超时时间内完成分析
2. **资源可控**：内存使用<2GB，CPU使用合理
3. **结果正确**：分析结果与抽样验证一致
4. **性能可接受**：执行时间<300秒

#### 验证点
- [ ] 大规模数据处理成功
- [ ] 资源使用在限制范围内
- [ ] 分析结果抽样验证正确
- [ ] 执行时间可接受
- [ ] 无内存泄漏

### 测试7：异常数据处理测试

#### 测试目的
验证技能对异常数据的处理能力。

#### 测试数据
包含各种异常情况的测试数据：
1. **缺失字段**：缺少必要字段的span
2. **格式错误**：JSON格式错误
3. **时间异常**：负时长、时间倒序
4. **关系异常**：循环引用、无效parent
5. **数据损坏**：部分数据损坏

#### 测试步骤
1. 准备包含各种异常的测试数据
2. 执行分析并观察处理行为
3. 验证错误处理和恢复机制
4. 检查输出中的警告和错误信息

#### 执行命令
```bash
claude witty-diagnosis:trace-analyzer \
  --session-id "test-error-001" \
  --trace-data error_traces.json \
  --analysis-type latency \
  --output-format json \
  --verbosity debug
```

#### 预期结果
1. **优雅处理**：不因异常数据而崩溃
2. **错误报告**：提供清晰的错误信息和警告
3. **部分成功**：有效数据部分仍能分析
4. **建议提供**：给出数据修复建议

#### 验证点
- [ ] 异常数据不导致崩溃
- [ ] 提供清晰的错误信息
- [ ] 有效数据部分成功分析
- [ ] 给出数据质量建议
- [ ] 执行时间<10秒

### 测试8：可视化输出测试

#### 测试目的
验证技能生成的可视化输出正确性。

#### 测试数据
使用标准测试数据，包含复杂调用关系。

#### 测试步骤
1. 准备测试数据
2. 生成不同格式的可视化输出
3. 验证输出格式正确性
4. 检查可视化内容准确性

#### 执行命令
```bash
# 生成Mermaid格式
claude witty-diagnosis:trace-analyzer \
  --session-id "test-viz-mermaid-001" \
  --trace-data test_traces_viz.json \
  --analysis-type dependency \
  --visualization-format mermaid

# 生成DOT格式
claude witty-diagnosis:trace-analyzer \
  --session-id "test-viz-dot-001" \
  --trace-data test_traces_viz.json \
  --analysis-type dependency \
  --visualization-format dot

# 生成JSON格式
claude witty-diagnosis:trace-analyzer \
  --session-id "test-viz-json-001" \
  --trace-data test_traces_viz.json \
  --analysis-type dependency \
  --visualization-format json
```

#### 预期结果
1. **格式正确**：输出符合指定格式规范
2. **内容准确**：可视化正确反映调用关系
3. **可读性好**：输出易于理解和解析
4. **兼容性强**：不同格式输出一致

#### 验证点
- [ ] 输出格式符合规范
- [ ] 可视化内容准确
- [ ] 不同格式输出一致
- [ ] 可读性好
- [ ] 执行时间每种格式<5秒

## 测试执行计划

### 测试周期
- **每日构建**：执行测试1-4（快速测试）
- **每周回归**：执行所有测试（完整测试）
- **版本发布**：执行扩展性能测试

### 测试环境准备
```bash
# 准备测试环境脚本
#!/bin/bash
# prepare_test_env.sh

echo "1. 清理旧测试数据..."
rm -rf test_data/*.json

echo "2. 生成测试数据..."
python3 generate_test_traces.py --all

echo "3. 验证测试数据..."
python3 validate_test_data.py

echo "4. 准备测试配置..."
cp test_configs/*.json config/

echo "测试环境准备完成！"
```

### 自动化测试脚本
```bash
#!/bin/bash
# run_trace_analyzer_tests.sh

echo "开始执行trace-analyzer测试套件..."
echo "======================================"

# 测试1：基础链路重建
echo "测试1：基础链路重建测试"
claude witty-diagnosis:trace-analyzer \
  --session-id "auto-test-1" \
  --trace-data test_data/basic.json \
  --analysis-type latency \
  --output-format json > results/test1.json
check_test_result results/test1.json "basic"

# 测试2：性能瓶颈识别
echo "测试2：性能瓶颈识别测试"
claude witty-diagnosis:trace-analyzer \
  --session-id "auto-test-2" \
  --trace-data test_data/bottleneck.json \
  --analysis-type latency \
  --latency-threshold-ms 500 \
  --output-format json > results/test2.json
check_test_result results/test2.json "bottleneck"

# 测试3：依赖关系分析
echo "测试3：依赖关系分析测试"
claude witty-diagnosis:trace-analyzer \
  --session-id "auto-test-3" \
  --trace-data test_data/dependency.json \
  --analysis-type dependency \
  --output-format json > results/test3.json
check_test_result results/test3.json "dependency"

# 更多测试...

echo "所有测试执行完成！"
echo "查看详细结果：cat results/summary.txt"
```

## 测试结果评估

### 通过标准
1. **功能正确性**：所有验证点通过
2. **性能要求**：执行时间在预期范围内
3. **资源使用**：内存和CPU使用符合限制
4. **错误处理**：异常情况处理得当
5. **输出质量**：输出格式正确，内容准确

### 结果记录格式
```json
{
  "test_id": "test-001",
  "test_name": "基础链路重建测试",
  "execution_time": "2026-02-03T10:00:00Z",
  "duration_seconds": 4.2,
  "status": "passed",
  "verification_points": [
    {"point": "输出状态", "result": "passed", "details": "status: success"},
    {"point": "链路重建", "result": "passed", "details": "正确识别3层调用"},
    {"point": "延迟计算", "result": "passed", "details": "总延迟100ms正确"},
    {"point": "执行时间", "result": "passed", "details": "4.2s < 5s"}
  ],
  "resource_usage": {
    "memory_mb": 256,
    "cpu_percent": 45.2
  },
  "issues": [],
  "suggestions": []
}
```

### 测试报告生成
```bash
# 生成测试报告
python3 generate_test_report.py \
  --results-dir results/ \
  --output report.html \
  --format html

# 发送测试通知
send_test_notification \
  --report report.html \
  --recipients "team@example.com"
```

## 问题跟踪和修复

### 问题分类
1. **严重问题**：功能失效，数据损坏
2. **主要问题**：功能不完整，性能不达标
3. **次要问题**：界面问题，文档错误
4. **优化建议**：性能优化，体验改进

### 问题处理流程
1. **发现问题**：测试执行中识别问题
2. **记录问题**：创建详细问题报告
3. **分配处理**：指定负责人和截止时间
4. **修复验证**：修复后重新执行相关测试
5. **关闭问题**：验证通过后关闭问题

### 回归测试
每次代码变更后执行：
```bash
# 执行回归测试
./run_regression_tests.sh \
  --changed-files "skills/trace-analyzer/*" \
  --test-level "affected"
```

## 总结

本测试用例文档为trace-analyzer技能提供了全面的测试覆盖，确保技能在各种场景下都能正确、稳定、高效地运行。通过定期执行这些测试，可以：

1. **保证质量**：确保技能功能符合设计要求
2. **预防问题**：及早发现潜在问题和性能瓶颈
3. **支持迭代**：为功能增强和优化提供验证基础
4. **建立信心**：通过自动化测试建立发布信心

测试用例将随着技能功能的增强而持续更新，确保测试覆盖始终与功能发展同步。