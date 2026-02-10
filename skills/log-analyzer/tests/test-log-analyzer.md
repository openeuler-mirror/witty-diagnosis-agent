# 日志分析器测试用例

## 测试概述

本文档定义了log-analyzer技能的测试用例，用于验证技能的功能完整性、性能表现和错误处理能力。测试覆盖从基本功能到高级分析的各个方面。

## 测试环境

### 硬件配置
- CPU：4核以上
- 内存：8GB以上
- 存储：50GB可用空间
- 网络：稳定网络连接

### 软件环境
- 操作系统：欧拉OS 2.0
- Python版本：3.8+
- 依赖库：按技能要求安装
- 测试工具：pytest, curl, jq

### 测试数据
- 测试日志文件：位于`/tmp/test-logs/`
- 样本数据大小：从1KB到100MB不等
- 日志格式：syslog, JSON, CSV, 自定义格式
- 时间范围：覆盖不同时间段

## 测试用例

### 测试1：基本日志解析功能测试

#### 测试目的
验证log-analyzer技能能够正确解析不同格式的日志数据。

#### 测试环境
- 测试数据：包含syslog、JSON、CSV格式的混合日志文件
- 数据大小：约1MB，包含1000条日志条目
- 测试配置：默认分析参数

#### 测试步骤
1. 准备测试数据：
   ```bash
   # 创建测试日志数据
   mkdir -p /tmp/test-logs
   cat > /tmp/test-logs/syslog-test.log << 'EOF'
   Feb  3 10:15:30 server-01 kernel: Disk I/O error on /dev/sda1
   Feb  3 10:16:45 server-01 sshd[1234]: Accepted password for user admin
   Feb  3 10:17:20 server-01 nginx: 502 Bad Gateway
   EOF

   cat > /tmp/test-logs/json-test.log << 'EOF'
   {"timestamp": "2026-02-03T10:15:30Z", "level": "ERROR", "service": "app", "message": "Database connection failed"}
   {"timestamp": "2026-02-03T10:16:45Z", "level": "INFO", "service": "auth", "message": "User login successful"}
   {"timestamp": "2026-02-03T10:17:20Z", "level": "WARN", "service": "api", "message": "High response time detected"}
   EOF
   ```

2. 执行基本解析测试：
   ```bash
   claude witty-diagnosis:log-analyzer \
     --session-id test-parsing-001 \
     --log-data @/tmp/test-logs/syslog-test.log \
     --log-format syslog \
     --analysis-types parsing \
     --output-format json
   ```

3. 验证解析结果：
   ```bash
   # 检查输出状态
   echo $?

   # 检查输出格式
   jq '.status' output.json
   jq '.results.parsing_results.format_detected' output.json
   jq '.results.parsing_results.parsing_success_rate' output.json
   ```

#### 预期结果
- 状态：`success`
- 格式检测：正确识别日志格式
- 解析成功率：>95%
- 字段提取：正确提取时间戳、级别、消息等字段
- 执行时间：<5秒

#### 验证点
- [ ] 正确识别syslog格式
- [ ] 正确识别JSON格式
- [ ] 字段提取准确率>95%
- [ ] 错误处理机制正常
- [ ] 输出格式符合规范

### 测试2：异常检测准确性测试

#### 测试目的
验证异常检测模块的准确性和召回率。

#### 测试环境
- 测试数据：包含已知异常模式的合成日志
- 异常类型：错误频率异常、罕见事件、模式偏离
- 数据大小：约5MB，包含5000条日志条目
- 已知异常：预先标记的50个异常事件

#### 测试步骤
1. 准备带标签的测试数据：
   ```bash
   # 创建包含已知异常的测试数据
   python3 << 'EOF'
   import json
   import random
   from datetime import datetime, timedelta

   logs = []
   base_time = datetime(2026, 2, 3, 10, 0, 0)
   anomaly_indices = random.sample(range(1000), 50)  # 50个已知异常

   for i in range(1000):
       timestamp = (base_time + timedelta(seconds=i*10)).isoformat() + "Z"

       if i in anomaly_indices:
           # 异常日志：错误频率异常
           level = "ERROR"
           message = f"Critical error detected: ANOMALY-{i:04d}"
           is_anomaly = True
       elif random.random() < 0.05:
           # 正常错误日志
           level = "ERROR"
           message = f"Normal error: {random.choice(['timeout', 'connection failed', 'permission denied'])}"
           is_anomaly = False
       else:
           # 正常日志
           level = random.choice(["INFO", "DEBUG"])
           message = f"Normal operation: {random.choice(['request processed', 'user logged in', 'data saved'])}"
           is_anomaly = False

       logs.append({
           "timestamp": timestamp,
           "level": level,
           "service": "test-service",
           "message": message,
           "is_anomaly": is_anomaly  # 标签字段
       })

   with open('/tmp/test-logs/anomaly-test.json', 'w') as f:
       for log in logs:
           f.write(json.dumps(log) + '\n')

   # 保存标签用于验证
   with open('/tmp/test-logs/anomaly-labels.json', 'w') as f:
       json.dump({
           "total_logs": 1000,
           "anomaly_count": 50,
           "anomaly_indices": anomaly_indices
       }, f, indent=2)
   EOF
   ```

2. 执行异常检测测试：
   ```bash
   claude witty-diagnosis:log-analyzer \
     --session-id test-anomaly-001 \
     --log-data @/tmp/test-logs/anomaly-test.json \
     --log-format json \
     --analysis-types anomaly \
     --pattern-threshold 0.7 \
     --detailed-analysis true \
     --output-format json \
     --output-file anomaly-results.json
   ```

3. 计算检测指标：
   ```bash
   # 提取检测结果
   detected_anomalies=$(jq '.results.anomaly_detection.anomalies | length' anomaly-results.json)
   true_positives=0
   false_positives=0

   # 与真实标签比较（简化示例）
   python3 << 'EOF'
   import json

   with open('anomaly-results.json') as f:
       results = json.load(f)

   with open('/tmp/test-logs/anomaly-labels.json') as f:
       labels = json.load(f)

   detected = results['results']['anomaly_detection']['anomalies']
   true_anomalies = set(labels['anomaly_indices'])

   tp = 0
   fp = 0

   for anomaly in detected:
       # 简化匹配逻辑
       if 'ANOMALY-' in anomaly.get('description', ''):
           tp += 1
       else:
           fp += 1

   precision = tp / (tp + fp) if (tp + fp) > 0 else 0
   recall = tp / len(true_anomalies) if true_anomalies else 0
   f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0

   print(f"True Positives: {tp}")
   print(f"False Positives: {fp}")
   print(f"Precision: {precision:.3f}")
   print(f"Recall: {recall:.3f}")
   print(f"F1 Score: {f1:.3f}")
   EOF
   ```

#### 预期结果
- 检测准确率：精度>80%，召回率>75%
- F1分数：>0.75
- 误报率：<25%
- 严重性评估：与异常严重性匹配
- 执行时间：<30秒

#### 验证点
- [ ] 检测到大部分已知异常（召回率>75%）
- [ ] 误报率在可接受范围内（<25%）
- [ ] 严重性评估合理
- [ ] 提供有用的异常描述
- [ ] 包含修复建议

### 测试3：模式识别能力测试

#### 测试目的
验证模式识别模块发现日志模式的能力。

#### 测试环境
- 测试数据：包含重复模式和序列的合成日志
- 模式类型：频繁项集、序列模式、时间模式
- 数据大小：约10MB，包含10000条日志条目
- 已知模式：预先定义的5种模式类型

#### 测试步骤
1. 准备模式测试数据：
   ```bash
   # 创建包含已知模式的测试数据
   python3 << 'EOF'
   import json
   import random
   from datetime import datetime, timedelta

   logs = []
   base_time = datetime(2026, 2, 3, 12, 0, 0)

   # 定义已知模式
   patterns = [
       ["User login", "Database query", "Cache update"],
       ["API request", "External service call", "Response sent"],
       ["File upload", "Virus scan", "File saved"],
       ["Error detected", "Retry attempt", "Success"],
       ["Session start", "Multiple requests", "Session end"]
   ]

   pattern_count = 0

   for i in range(5000):
       timestamp = (base_time + timedelta(seconds=i*2)).isoformat() + "Z"

       # 每100条日志插入一个模式
       if i % 100 == 0 and pattern_count < len(patterns):
           pattern = patterns[pattern_count]
           for j, event in enumerate(pattern):
               pattern_time = (base_time + timedelta(seconds=(i+j)*2)).isoformat() + "Z"
               logs.append({
                   "timestamp": pattern_time,
                   "level": "INFO",
                   "service": f"pattern-service-{pattern_count}",
                   "message": event,
                   "pattern_id": f"PATTERN-{pattern_count:02d}",
                   "pattern_step": j
               })
           pattern_count += 1
       else:
           # 随机日志
           level = random.choice(["INFO", "DEBUG", "WARN"])
           service = random.choice(["web", "db", "cache", "auth"])
           message = f"Random event {i}: {random.choice(['processing', 'checking', 'validating'])}"
           logs.append({
               "timestamp": timestamp,
               "level": level,
               "service": service,
               "message": message
           })

   with open('/tmp/test-logs/pattern-test.json', 'w') as f:
       for log in logs:
           f.write(json.dumps(log) + '\n')

   # 保存模式定义用于验证
   with open('/tmp/test-logs/pattern-definitions.json', 'w') as f:
       json.dump({
           "total_patterns": len(patterns),
           "patterns": patterns,
           "pattern_ids": [f"PATTERN-{i:02d}" for i in range(len(patterns))]
       }, f, indent=2)
   EOF
   ```

2. 执行模式识别测试：
   ```bash
   claude witty-diagnosis:log-analyzer \
     --session-id test-pattern-001 \
     --log-data @/tmp/test-logs/pattern-test.json \
     --log-format json \
     --analysis-types pattern \
     --pattern-threshold 0.6 \
     --detailed-analysis true \
     --output-format json \
     --output-file pattern-results.json
   ```

3. 验证模式识别结果：
   ```bash
   # 检查识别的模式
   jq '.results.pattern_recognition.patterns | length' pattern-results.json
   jq '.results.pattern_recognition.patterns[].description' pattern-results.json
   jq '.results.pattern_recognition.patterns[].confidence' pattern-results.json

   # 计算模式识别准确率
   python3 << 'EOF'
   import json

   with open('pattern-results.json') as f:
       results = json.load(f)

   with open('/tmp/test-logs/pattern-definitions.json') as f:
       definitions = json.load(f)

   detected_patterns = results['results']['pattern_recognition']['patterns']
   expected_patterns = definitions['patterns']

   matched = 0
   for detected in detected_patterns:
       desc = detected.get('description', '').lower()
       for expected in expected_patterns:
           # 简化匹配：检查是否包含模式关键词
           if any(keyword.lower() in desc for keyword in expected):
               matched += 1
               break

   accuracy = matched / len(expected_patterns) if expected_patterns else 0
   print(f"Expected patterns: {len(expected_patterns)}")
   print(f"Matched patterns: {matched}")
   print(f"Pattern recognition accuracy: {accuracy:.3f}")
   EOF
   ```

#### 预期结果
- 模式识别准确率：>70%
- 模式置信度：>0.6
- 模式描述：清晰准确
- 模式支持度：合理反映出现频率
- 执行时间：<60秒

#### 验证点
- [ ] 识别出大部分已知模式（准确率>70%）
- [ ] 模式置信度合理
- [ ] 模式描述清晰有用
- [ ] 支持度和出现频率匹配
- [ ] 无明显的错误模式

### 测试4：关联分析功能测试

#### 测试目的
验证关联分析模块发现日志事件之间关系的能力。

#### 测试环境
- 测试数据：包含相关事件的合成日志
- 关联类型：时间关联、因果关联、跨服务关联
- 数据大小：约8MB，包含8000条日志条目
- 已知关联：预先定义的10组关联事件

#### 测试步骤
1. 准备关联测试数据：
   ```bash
   # 创建包含已知关联的测试数据
   python3 << 'EOF'
   import json
   import random
   from datetime import datetime, timedelta

   logs = []
   base_time = datetime(2026, 2, 3, 14, 0, 0)

   # 定义已知关联
   correlations = [
       {
           "type": "temporal",
           "events": [
               {"service": "load-balancer", "event": "High traffic detected"},
               {"service": "web-server", "event": "CPU usage spike"},
               {"service": "database", "event": "Slow queries"}
           ],
           "time_lag": [0, 30, 60]  # 秒
       },
       {
           "type": "causal",
           "events": [
               {"service": "auth-service", "event": "Login failure"},
               {"service": "security", "event": "Account locked"},
               {"service": "admin", "event": "Alert sent"}
           ],
           "time_lag": [0, 5, 10]
       }
   ]

   correlation_id = 0

   for i in range(2000):
       timestamp = (base_time + timedelta(seconds=i*3)).isoformat() + "Z"

       # 每200条日志插入一个关联模式
       if i % 200 == 0 and correlation_id < len(correlations):
           corr = correlations[correlation_id]
           for j, event in enumerate(corr["events"]):
               event_time = (base_time + timedelta(seconds=(i + corr["time_lag"][j])*3)).isoformat() + "Z"
               logs.append({
                   "timestamp": event_time,
                   "level": "INFO",
                   "service": event["service"],
                   "message": event["event"],
                   "correlation_id": f"CORR-{correlation_id:02d}",
                   "correlation_step": j
               })
           correlation_id += 1
       else:
           # 随机日志
           level = random.choice(["INFO", "DEBUG"])
           service = random.choice(["monitoring", "backup", "scheduler"])
           message = f"Regular operation {i}"
           logs.append({
               "timestamp": timestamp,
               "level": level,
               "service": service,
               "message": message
           })

   with open('/tmp/test-logs/correlation-test.json', 'w') as f:
       for log in logs:
           f.write(json.dumps(log) + '\n')

   # 保存关联定义用于验证
   with open('/tmp/test-logs/correlation-definitions.json', 'w') as f:
       json.dump({
           "total_correlations": len(correlations),
           "correlations": correlations
       }, f, indent=2)
   EOF
   ```

2. 执行关联分析测试：
   ```bash
   claude witty-diagnosis:log-analyzer \
     --session-id test-correlation-001 \
     --log-data @/tmp/test-logs/correlation-test.json \
     --log-format json \
     --analysis-types correlation \
     --correlation-window 300 \
     --detailed-analysis true \
     --output-format json \
     --output-file correlation-results.json
   ```

3. 验证关联分析结果：
   ```bash
   # 检查发现的关联
   jq '.results.correlation_analysis.correlations | length' correlation-results.json
   jq '.results.correlation_analysis.correlations[].description' correlation-results.json
   jq '.results.correlation_analysis.correlations[].confidence' correlation-results.json

   # 计算关联发现准确率
   python3 << 'EOF'
   import json

   with open('correlation-results.json') as f:
       results = json.load(f)

   with open('/tmp/test-logs/correlation-definitions.json') as f:
       definitions = json.load(f)

   detected_corrs = results['results']['correlation_analysis']['correlations']
   expected_corrs = definitions['correlations']

   matched = 0
   for detected in detected_corrs:
       desc = detected.get('description', '').lower()
       for expected in expected_corrs:
           # 检查是否包含关键服务名
           services = [event['service'] for event in expected['events']]
           if any(service.lower() in desc for service in services):
               matched += 1
               break

   accuracy = matched / len(expected_corrs) if expected_corrs else 0
   print(f"Expected correlations: {len(expected_corrs)}")
   print(f"Matched correlations: {matched}")
   print(f"Correlation discovery accuracy: {accuracy:.3f}")
   EOF
   ```

#### 预期结果
- 关联发现准确率：>65%
- 关联置信度：>0.7
- 关联描述：清晰说明事件关系
- 时间窗口：正确应用关联窗口
- 执行时间：<45秒

#### 验证点
- [ ] 发现大部分已知关联（准确率>65%）
- [ ] 关联置信度合理
- [ ] 关联描述清晰有用
- [ ] 时间关联分析正确
- [ ] 跨服务关联识别

### 测试5：性能基准测试

#### 测试目的
验证log-analyzer技能在不同数据规模下的性能表现。

#### 测试环境
- 测试数据：不同规模的合成日志数据
- 数据规模：1MB, 10MB, 50MB, 100MB
- 硬件监控：CPU、内存、IO使用率
- 性能指标：执行时间、内存峰值、CPU使用率

#### 测试步骤
1. 准备不同规模的测试数据：
   ```bash
   # 生成1MB测试数据（约1000条日志）
   python3 << 'EOF'
   import json
   import random
   from datetime import datetime, timedelta

   base_time = datetime(2026, 2, 3, 16, 0, 0)

   with open('/tmp/test-logs/perf-1mb.json', 'w') as f:
       for i in range(1000):
           timestamp = (base_time + timedelta(seconds=i)).isoformat() + "Z"
           log = {
               "timestamp": timestamp,
               "level": random.choice(["INFO", "DEBUG", "WARN", "ERROR"]),
               "service": random.choice(["web", "db", "cache", "auth", "api"]),
               "message": f"Log entry {i}: {random.choice(['request', 'query', 'update', 'check'])}"
           }
           f.write(json.dumps(log) + '\n')
   EOF

   # 类似方法生成10MB, 50MB, 100MB数据
   ```

2. 执行性能测试：
   ```bash
   # 测试1MB数据
   /usr/bin/time -v claude witty-diagnosis:log-analyzer \
     --session-id perf-test-1mb \
     --log-data @/tmp/test-logs/perf-1mb.json \
     --analysis-types parsing anomaly \
     --output-format json \
     --output-file /dev/null \
     2> perf-1mb-stats.txt

   # 提取性能指标
   grep -E "Elapsed|Maximum resident|CPU" perf-1mb-stats.txt

   # 类似方法测试其他规模数据
   ```

3. 分析性能趋势：
   ```bash
   # 收集所有测试结果
   python3 << 'EOF'
   import re

   results = []
   sizes = ['1mb', '10mb', '50mb', '100mb']

   for size in sizes:
       with open(f'perf-{size}-stats.txt') as f:
           content = f.read()

       # 提取时间
       time_match = re.search(r'Elapsed \(wall clock\) time \(h:mm:ss or m:ss\): (\d+):(\d+\.\d+)', content)
       if time_match:
           minutes = int(time_match.group(1))
           seconds = float(time_match.group(2))
           total_seconds = minutes * 60 + seconds
       else:
           total_seconds = 0

       # 提取内存
       mem_match = re.search(r'Maximum resident set size \(kbytes\): (\d+)', content)
       memory_mb = int(mem_match.group(1)) / 1024 if mem_match else 0

       # 提取CPU
       cpu_match = re.search(r'Percent of CPU this job got: (\d+)%', content)
       cpu_percent = int(cpu_match.group(1)) if cpu_match else 0

       results.append({
           'size': size,
           'time_seconds': total_seconds,
           'memory_mb': memory_mb,
           'cpu_percent': cpu_percent
       })

   # 打印结果
   print("Performance Test Results:")
   print("Size\tTime(s)\tMemory(MB)\tCPU(%)")
   for r in results:
       print(f"{r['size']}\t{r['time_seconds']:.1f}\t{r['memory_mb']:.1f}\t\t{r['cpu_percent']}")

   # 计算 scalability
   if len(results) >= 2:
       small = results[0]
       large = results[-1]
       time_ratio = large['time_seconds'] / small['time_seconds']
       size_ratio = 100  # 假设从1MB到100MB
       scalability = size_ratio / time_ratio
       print(f"\nScalability: {scalability:.2f} (理想值接近1.0)")
   EOF
   ```

#### 预期结果
- 执行时间：与数据规模成近似线性关系
- 内存使用：可预测且可控
- CPU使用率：高效利用多核
- 可扩展性：>0.7（时间增长慢于数据增长）
- 无内存泄漏：内存使用稳定

#### 验证点
- [ ] 执行时间与数据规模合理相关
- [ ] 内存使用在预期范围内
- [ ] CPU使用率高效
- [ ] 无内存泄漏迹象
- [ ] 大规模数据处理稳定

### 测试6：错误处理测试

#### 测试目的
验证log-analyzer技能对错误输入和异常情况的处理能力。

#### 测试环境
- 测试数据：各种错误和异常情况的输入
- 错误类型：格式错误、数据损坏、权限问题、资源不足
- 测试配置：各种边界条件和极端情况

#### 测试步骤
1. 测试无效格式处理：
   ```bash
   # 创建格式错误的日志数据
   echo "This is not a valid log entry" > /tmp/test-logs/invalid-format.log
   echo '{"timestamp": "invalid-time", "level": "ERROR"}' >> /tmp/test-logs/invalid-format.log

   claude witty-diagnosis:log-analyzer \
     --session-id error-test-format \
     --log-data @/tmp/test-logs/invalid-format.log \
     --log-format auto \
     --output-format json \
     2> error-output.txt

   # 验证错误处理
   grep -i "error" error-output.txt
   ```

2. 测试数据损坏处理：
   ```bash
   # 创建损坏的JSON数据
   echo '{"timestamp": "2026-02-03T18:00:00Z", "level": "INFO", "message": "Valid entry"}' > /tmp/test-logs/corrupted.json
   echo 'CORRUPTED_DATA_NOT_JSON' >> /tmp/test-logs/corrupted.json
   echo '{"timestamp": "2026-02-03T18:00:01Z", "level": "ERROR", "message": "Another valid entry"}' >> /tmp/test-logs/corrupted.json

   claude witty-diagnosis:log-analyzer \
     --session-id error-test-corrupt \
     --log-data @/tmp/test-logs/corrupted.json \
     --log-format json \
     --output-format json

   # 检查部分成功处理
   jq '.status' output.json
   jq '.results.parsing_results.parsing_errors' output.json
   ```

3. 测试资源不足处理：
   ```bash
   # 使用ulimit模拟内存限制
   (ulimit -v 100000;  # 限制虚拟内存为100MB
    claude witty-diagnosis:log-analyzer \
      --session-id error-test-memory \
      --log-data @/tmp/test-logs/perf-100mb.json \
      --analysis-types parsing \
      --output-format json \
      --output-file /dev/null) 2> memory-error.txt

   # 验证优雅失败
   grep -i "memory\|out of memory\|resource" memory-error.txt
   ```

4. 测试超时处理：
   ```bash
   # 设置很短的超时时间
   claude witty-diagnosis:log-analyzer \
     --session-id error-test-timeout \
     --log-data @/tmp/test-logs/perf-50mb.json \
     --timeout 5 \
     --analysis-types pattern \
     --output-format json \
     2> timeout-error.txt

   # 检查超时处理
   grep -i "timeout\|timed out" timeout-error.txt
   ```

#### 预期结果
- 格式错误：提供清晰的错误信息和修复建议
- 数据损坏：优雅处理，部分成功或适当错误
- 资源不足：优雅失败，清理资源
- 超时处理：在超时前停止，提供有意义的信息
- 错误恢复：不影响后续操作

#### 验证点
- [ ] 无效格式得到适当处理
- [ ] 数据损坏时优雅降级
- [ ] 资源不足时安全退出
- [ ] 超时机制正常工作
- [ ] 错误信息清晰有用

### 测试7：集成测试

#### 测试目的
验证log-analyzer技能与其他技能的集成能力。

#### 测试环境
- 集成组件：data-collector, metric-analyzer, knowledge-base
- 测试流程：端到端的日志分析流程
- 数据流：从收集到分析到存储的完整流程

#### 测试步骤
1. 执行端到端集成测试：
   ```bash
   # 步骤1：使用data-collector收集日志
   claude witty-diagnosis:data-collector \
     --session-id integration-collect \
     --target system \
     --data-sources logs \
     --log-sources /var/log/messages \
     --time-range "last 1 hour" \
     --output-format json \
     --output-file /tmp/integration-logs.json

   # 步骤2：使用log-analyzer分析日志
   claude witty-diagnosis:log-analyzer \
     --session-id integration-analyze \
     --log-data @/tmp/integration-logs.json \
     --analysis-types anomaly pattern \
     --detailed-analysis true \
     --output-format json \
     --output-file /tmp/analysis-results.json

   # 步骤3：验证分析结果
   jq '.status' /tmp/analysis-results.json
   jq '.results.summary' /tmp/analysis-results.json

   # 步骤4：存储到knowledge-base（模拟）
   echo "Integration test completed successfully" > /tmp/integration-test.log
   ```

2. 验证数据流完整性：
   ```bash
   # 检查各步骤输出
   ls -la /tmp/integration-*.json

   # 验证数据格式兼容性
   python3 << 'EOF'
   import json

   # 检查收集的数据格式
   with open('/tmp/integration-logs.json') as f:
       collect_data = json.load(f)

   # 检查分析的数据格式
   with open('/tmp/analysis-results.json') as f:
       analysis_data = json.load(f)

   # 验证关键字段存在
   required_fields = ['session_id', 'status', 'results']
   for field in required_fields:
       if field not in analysis_data:
           print(f"ERROR: Missing field {field} in analysis results")
           exit(1)

   print("Integration test passed: data formats compatible")
   EOF
   ```

3. 测试错误传播：
   ```bash
   # 模拟data-collector失败
   echo '{"status": "error", "error_message": "Simulated collection failure"}' > /tmp/failed-collection.json

   claude witty-diagnosis:log-analyzer \
     --session-id integration-error \
     --log-data @/tmp/failed-collection.json \
     --output-format json \
     2> integration-error.txt

   # 验证错误处理
   grep -i "error\|invalid" integration-error.txt
   ```

#### 预期结果
- 端到端流程：完整执行无错误
- 数据兼容性：各技能间数据格式兼容
- 错误传播：适当处理上游错误
- 性能表现：集成流程性能可接受
- 资源管理：正确清理临时资源

#### 验证点
- [ ] 端到端流程完整执行
- [ ] 数据格式兼容
- [ ] 错误适当传播和处理
- [ ] 性能在可接受范围内
- [ ] 资源正确管理

## 测试报告

### 测试执行摘要

| 测试用例 | 状态 | 执行时间 | 通过标准 | 实际结果 |
|----------|------|----------|----------|----------|
| 基本解析功能 | [ ] | - | 解析成功率>95% | - |
| 异常检测准确性 | [ ] | - | F1分数>0.75 | - |
| 模式识别能力 | [ ] | - | 准确率>70% | - |
| 关联分析功能 | [ ] | - | 准确率>65% | - |
| 性能基准测试 | [ ] | - | 可扩展性>0.7 | - |
| 错误处理测试 | [ ] | - | 所有错误类型适当处理 | - |
| 集成测试 | [ ] | - | 端到端流程成功 | - |

### 性能指标汇总

| 数据规模 | 执行时间(秒) | 内存使用(MB) | CPU使用率(%) | 备注 |
|----------|--------------|--------------|--------------|------|
| 1MB | - | - | - | - |
| 10MB | - | - | - | - |
| 50MB | - | - | - | - |
| 100MB | - | - | - | - |

### 问题记录

| 问题ID | 测试用例 | 问题描述 | 严重性 | 状态 | 解决方案 |
|--------|----------|----------|--------|------|----------|
| - | - | - | - | - | - |

### 测试结论

基于测试结果，log-analyzer技能：

1. **功能完整性**：[ ] 通过 [ ] 部分通过 [ ] 未通过
   - 所有核心功能按设计工作
   - 分析结果准确可靠
   - 输出格式符合规范

2. **性能表现**：[ ] 通过 [ ] 部分通过 [ ] 未通过
   - 执行时间在预期范围内
   - 内存使用可控
   - 可扩展性良好

3. **健壮性**：[ ] 通过 [ ] 部分通过 [ ] 未通过
   - 错误处理适当
   - 边界条件处理正确
   - 资源管理安全

4. **集成能力**：[ ] 通过 [ ] 部分通过 [ ] 未通过
   - 与其他技能兼容
   - 数据流完整
   - 错误传播适当

**总体评价**：[ ] 推荐发布 [ ] 需要改进 [ ] 不推荐发布

## 测试维护

### 测试数据管理
- 测试数据应定期更新以反映真实场景
- 敏感数据必须脱敏处理
- 测试数据版本应与技能版本匹配

### 测试自动化
- 建议实现自动化测试流水线
- 测试结果应自动收集和报告
- 性能测试应定期执行建立基线

### 测试扩展
- 随着技能功能扩展，测试用例应相应更新
- 添加新的分析类型需要新的测试用例
- 性能基准应随硬件升级而更新

---

*测试文档版本：1.0.0*
*最后更新：2026-02-03*
*测试负责人：witty-diagnosis-team*