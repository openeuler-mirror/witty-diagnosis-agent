# 配置格式规范

## 概述

本规范定义了witty-diagnosis-agent项目的配置格式标准。统一的配置格式确保系统配置的一致性、可维护性和可扩展性。

## 1. 配置层级结构

### 1.1 配置层级
```
config/
├── global.yaml              # 全局配置（最高优先级）
├── environment/
│   ├── development.yaml     # 开发环境配置
│   ├── staging.yaml         # 预发环境配置
│   └── production.yaml      # 生产环境配置
├── skills/
│   ├── data-collector.yaml  # 技能特定配置
│   ├── log-analyzer.yaml    # 技能特定配置
│   └── ...                  # 其他技能配置
├── commands/
│   ├── diagnose.yaml        # 命令特定配置
│   └── collect-data.yaml    # 命令特定配置
└── agents/
    ├── diagnosis-agent.yaml # 代理特定配置
    └── ...                  # 其他代理配置
```

### 1.2 配置优先级
配置按以下顺序加载，后加载的覆盖先加载的：
1. 默认配置（代码中硬编码）
2. 全局配置（`config/global.yaml`）
3. 环境配置（`config/environment/`）
4. 技能/命令/代理特定配置
5. 用户自定义配置（`~/.witty-diagnosis/config.yaml`）
6. 命令行参数（最高优先级）

## 2. 配置格式标准

### 2.1 YAML格式规范

#### 基本规则
- 使用YAML 1.2标准
- 使用2个空格缩进（不使用Tab）
- 字符串使用双引号，除非包含特殊字符
- 布尔值使用`true`/`false`
- 空值使用`null`

#### 示例配置
```yaml
# 注释：这是一个示例配置
global:
  # 字符串值
  project_name: "witty-diagnosis-agent"

  # 数字值
  version: 1.0.0

  # 布尔值
  enabled: true

  # 数组
  supported_environments:
    - "development"
    - "staging"
    - "production"

  # 对象
  logging:
    level: "info"
    format: "json"

  # 多行字符串
  description: |
    This is a multi-line
    description of the project.

  # 内联数组
  tags: ["diagnosis", "automation", "euler-os"]
```

### 2.2 JSON格式规范（备选）

```json
{
  "$schema": "https://witty-diagnosis-agent/schemas/config-v1.0.0.json",
  "global": {
    "project_name": "witty-diagnosis-agent",
    "version": "1.0.0",
    "enabled": true,
    "supported_environments": ["development", "staging", "production"],
    "logging": {
      "level": "info",
      "format": "json"
    }
  }
}
```

## 3. 全局配置格式

### 3.1 全局配置结构

```yaml
# config/global.yaml
global:
  # 项目信息
  project:
    name: "witty-diagnosis-agent"
    version: "1.0.0"
    description: "欧拉OS智能诊断技能集合"

  # 环境配置
  environment:
    name: "development"  # development|staging|production
    debug: true
    feature_flags:
      experimental_features: false
      advanced_analytics: true

  # 日志配置
  logging:
    level: "info"  # debug|info|warn|error
    format: "json"  # json|text
    output:
      console: true
      file:
        enabled: true
        path: "/var/log/witty-diagnosis/agent.log"
        max_size_mb: 100
        max_files: 10
        compress: true
    metrics:
      enabled: true
      interval_seconds: 60

  # 性能配置
  performance:
    max_concurrent_sessions: 10
    session_timeout_seconds: 3600
    cache:
      enabled: true
      ttl_seconds: 300
      max_size_mb: 100
    rate_limiting:
      enabled: true
      requests_per_minute: 60

  # 安全配置
  security:
    encryption:
      enabled: true
      algorithm: "AES-256-GCM"
    authentication:
      enabled: false  # 默认禁用，生产环境启用
      method: "jwt"
    authorization:
      enabled: false
      roles: ["admin", "operator", "viewer"]
    audit:
      enabled: true
      log_all_operations: false

  # 网络配置
  network:
    proxy: null  # http://proxy.example.com:8080
    timeout:
      connect_seconds: 30
      read_seconds: 60
      write_seconds: 60
    retry:
      max_attempts: 3
      backoff_ms: 1000

  # 存储配置
  storage:
    data_directory: "/var/lib/witty-diagnosis"
    temp_directory: "/tmp/witty-diagnosis"
    cleanup:
      enabled: true
      interval_hours: 24
      max_age_days: 7
    limits:
      max_disk_usage_percent: 80
      max_file_size_mb: 10

  # 监控配置
  monitoring:
    enabled: true
    metrics:
      collection_interval_seconds: 30
      export:
        prometheus:
          enabled: true
          port: 9090
    health_check:
      enabled: true
      interval_seconds: 60
      timeout_seconds: 10

  # 通知配置
  notifications:
    enabled: false
    providers:
      email:
        enabled: false
        smtp_server: "smtp.example.com"
        from_address: "noreply@example.com"
      webhook:
        enabled: false
        url: "https://hooks.example.com/diagnosis"
      slack:
        enabled: false
        webhook_url: "https://hooks.slack.com/services/..."
```

## 4. 技能配置格式

### 4.1 技能通用配置

```yaml
# config/skills/data-collector.yaml
skill:
  # 基本信息
  name: "data-collector"
  version: "1.0.0"
  enabled: true
  category: "core"  # core|analysis|support

  # 执行配置
  execution:
    timeout_seconds: 300
    max_retries: 3
    retry_delay_seconds: 10
    concurrency_limit: 5

  # 资源限制
  resources:
    memory_limit_mb: 512
    cpu_limit_percent: 50
    disk_space_mb: 100

  # 输入验证
  validation:
    required_parameters:
      - "session_id"
      - "target"
    parameter_constraints:
      timeout_seconds:
        min: 1
        max: 3600
        default: 300
      target:
        allowed_values:
          - "system"
          - "network"
          - "storage"
          - "security"

  # 输出配置
  output:
    default_format: "json"
    supported_formats:
      - "json"
      - "yaml"
      - "text"
    compression:
      enabled: true
      algorithm: "gzip"
      min_size_kb: 10

  # 依赖配置
  dependencies:
    skills:
      - name: "system-info"
        required: false
      - name: "network-scanner"
        required: true
    commands:
      - "top"
      - "free"
      - "df"
      - "ping"
    libraries:
      - "psutil>=5.8.0"
      - "requests>=2.25.0"

  # 缓存配置
  cache:
    enabled: true
    ttl_seconds: 300
    strategy: "per_session"  # per_session|global|none
    storage: "memory"  # memory|disk|redis

  # 监控配置
  monitoring:
    metrics_enabled: true
    detailed_metrics: false
    log_level: "info"
    performance_thresholds:
      execution_time_ms:
        warning: 5000
        error: 10000
      memory_usage_mb:
        warning: 400
        error: 500

  # 数据源配置
  data_sources:
    system_metrics:
      enabled: true
      collection_interval_seconds: 30
      metrics:
        - "cpu"
        - "memory"
        - "disk"
        - "network"
    logs:
      enabled: true
      paths:
        - "/var/log/messages"
        - "/var/log/syslog"
      patterns:
        - "error"
        - "exception"
        - "failed"
    configurations:
      enabled: true
      files:
        - "/etc/hosts"
        - "/etc/resolv.conf"

  # 高级配置
  advanced:
    sampling_rate: 1.0  # 0.0-1.0
    data_retention_days: 30
    privacy_mode: false
    experimental_features: false
```

### 4.2 技能特定配置示例

```yaml
# config/skills/log-analyzer.yaml
skill:
  name: "log-analyzer"

  # 日志分析特定配置
  log_analysis:
    # 日志格式支持
    formats:
      syslog:
        enabled: true
        pattern: "%{SYSLOGTIMESTAMP:timestamp} %{SYSLOGHOST:hostname} %{DATA:program}(?:\[%{POSINT:pid}\])?: %{GREEDYDATA:message}"
      json:
        enabled: true
      custom:
        enabled: false

    # 分析规则
    rules:
      error_detection:
        enabled: true
        patterns:
          - "error"
          - "exception"
          - "failed"
          - "critical"
        severity_mapping:
          error: ["error", "failed", "critical"]
          warning: ["warning", "deprecated"]

      performance_issues:
        enabled: true
        thresholds:
          response_time_ms: 1000
          error_rate_percent: 1.0

    # 关联分析
    correlation:
      enabled: true
      time_window_seconds: 300
      max_correlation_distance: 10

  # 机器学习配置（可选）
  machine_learning:
    enabled: false
    model_path: "/models/log-anomaly-detector"
    training:
      enabled: false
      interval_days: 7
      sample_size: 10000
```

## 5. 命令配置格式

### 5.1 命令通用配置

```yaml
# config/commands/diagnose.yaml
command:
  # 基本信息
  name: "diagnose"
  description: "执行系统诊断"
  enabled: true

  # 参数配置
  parameters:
    target:
      description: "诊断目标"
      type: "string"
      required: false
      default: "system"
      allowed_values:
        - "system"
        - "network"
        - "storage"
        - "security"

    skills:
      description: "要使用的技能列表"
      type: "array"
      required: false
      default: ["data-collector", "log-analyzer", "fault-localization"]

    format:
      description: "输出格式"
      type: "string"
      required: false
      default: "text"
      allowed_values:
        - "text"
        - "json"
        - "yaml"
        - "html"

    verbose:
      description: "详细输出模式"
      type: "boolean"
      required: false
      default: false

    timeout:
      description: "超时时间（秒）"
      type: "integer"
      required: false
      default: 300
      min: 1
      max: 3600

  # 技能执行配置
  skill_execution:
    order: "sequential"  # sequential|parallel|smart
    dependency_resolution: true
    failure_handling: "stop_on_error"  # stop_on_error|continue|skip_failed

  # 输出配置
  output:
    default_destination: "stdout"
    file:
      enabled: true
      default_name: "diagnosis-report-{timestamp}.{format}"
      directory: "./reports"
    email:
      enabled: false
    webhook:
      enabled: false

  # 报告配置
  report:
    template: "default"
    sections:
      - "summary"
      - "issues"
      - "recommendations"
      - "details"
    severity_filter:
      min_severity: "info"  # info|warning|error|critical
    include_raw_data: false

  # 缓存配置
  cache:
    enabled: true
    ttl_seconds: 600
    key_strategy: "parameters_hash"

  # 历史记录
  history:
    enabled: true
    max_entries: 100
    retention_days: 30
```

## 6. 代理配置格式

### 6.1 代理通用配置

```yaml
# config/agents/diagnosis-agent.yaml
agent:
  # 基本信息
  name: "diagnosis-agent"
  type: "coordinator"  # coordinator|worker|specialized
  enabled: true

  # 运行配置
  runtime:
    mode: "daemon"  # daemon|oneshot|scheduled
    restart_policy: "always"  # always|on-failure|never
    health_check_interval_seconds: 30

  # 调度配置
  scheduling:
    enabled: true
    triggers:
      - type: "cron"
        expression: "0 */6 * * *"  # 每6小时执行一次
      - type: "event"
        event_type: "SYSTEM_HEALTH_DEGRADED"
      - type: "manual"

  # 技能管理
  skill_management:
    auto_discovery: true
    skill_directory: "./skills"
    blacklist:
      - "experimental-*"
    whitelist: []

  # 工作流配置
  workflows:
    default:
      - "data-collector"
      - "log-analyzer"
      - "metric-analyzer"
      - "fault-localization"
      - "root-cause-analysis"

    quick:
      - "data-collector"
      - "fault-localization"

    detailed:
      - "data-collector"
      - "log-analyzer"
      - "metric-analyzer"
      - "trace-analyzer"
      - "fault-localization"
      - "root-cause-analysis"
      - "knowledge-base"

  # 通信配置
  communication:
    http:
      enabled: true
      port: 8080
      host: "0.0.0.0"
    grpc:
      enabled: false
    message_queue:
      enabled: false

  # 集群配置（如果适用）
  cluster:
    enabled: false
    mode: "standalone"  # standalone|leader|follower
    discovery:
      method: "static"  # static|consul|etcd|kubernetes
      nodes: []
```

## 7. 环境特定配置

### 7.1 开发环境配置

```yaml
# config/environment/development.yaml
environment: "development"

global:
  logging:
    level: "debug"
    output:
      console: true
      file: false

  performance:
    cache:
      enabled: false

  security:
    encryption:
      enabled: false

  monitoring:
    enabled: false

skills:
  data-collector:
    execution:
      timeout_seconds: 60
    monitoring:
      detailed_metrics: true

commands:
  diagnose:
    output:
      file:
        enabled: false
```

### 7.2 生产环境配置

```yaml
# config/environment/production.yaml
environment: "production"

global:
  logging:
    level: "info"
    output:
      console: false
      file: true

  performance:
    max_concurrent_sessions: 50
    cache:
      enabled: true
      ttl_seconds: 600

  security:
    encryption:
      enabled: true
    authentication:
      enabled: true
    audit:
      log_all_operations: true

  monitoring:
    enabled: true
    metrics:
      export:
        prometheus:
          enabled: true

skills:
  data-collector:
    execution:
      timeout_seconds: 600
    resources:
      memory_limit_mb: 1024
    cache:
      enabled: true

commands:
  diagnose:
    cache:
      enabled: true
      ttl_seconds: 300
    history:
      max_entries: 1000
```

## 8. 配置验证

### 8.1 JSON Schema验证

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://witty-diagnosis-agent/schemas/global-config-v1.0.0.json",
  "title": "全局配置",
  "description": "witty-diagnosis-agent全局配置格式",
  "type": "object",
  "required": ["global"],
  "properties": {
    "global": {
      "type": "object",
      "required": ["project", "environment"],
      "properties": {
        "project": {
          "type": "object",
          "required": ["name", "version"],
          "properties": {
            "name": {
              "type": "string",
              "pattern": "^[a-zA-Z0-9_-]+$"
            },
            "version": {
              "type": "string",
              "pattern": "^\\d+\\.\\d+\\.\\d+$"
            }
          }
        }
      }
    }
  }
}
```

### 8.2 配置验证规则

```yaml
validation_rules:
  # 类型检查
  - rule: "type_check"
    enabled: true

  # 范围检查
  - rule: "range_check"
    enabled: true
    parameters:
      timeout_seconds:
        min: 1
        max: 3600

  # 依赖检查
  - rule: "dependency_check"
    enabled: true

  # 环境特定规则
  - rule: "environment_specific"
    enabled: true
    rules:
      production:
        - path: "global.security.encryption.enabled"
          must_be: true
        - path: "global.logging.level"
          allowed_values: ["info", "warn", "error"]

  # 性能约束
  - rule: "performance_constraints"
    enabled: true
    constraints:
      max_memory_per_skill_mb: 2048
      max_total_concurrent_sessions: 100
```

## 9. 配置管理

### 9.1 配置加载策略

```yaml
config_loading:
  strategy: "merge"  # merge|override|environment_specific
  merge_rules:
    arrays: "replace"  # replace|append|merge_unique
    objects: "deep_merge"

  # 配置源
  sources:
    - type: "file"
      path: "config/global.yaml"
      required: true
      priority: 10

    - type: "file"
      path: "config/environment/{env}.yaml"
      required: false
      priority: 20

    - type: "file"
      path: "config/skills/{skill}.yaml"
      required: false
      priority: 30

    - type: "environment"
      prefix: "WITTY_DIAGNOSIS_"
      required: false
      priority: 40

    - type: "command_line"
      required: false
      priority: 50

  # 配置重载
  reload:
    enabled: true
    method: "signal"  # signal|watch|manual
    watch_interval_seconds: 30
```

### 9.2 配置版本控制

```yaml
config_versioning:
  enabled: true
  current_version: "1.0.0"
  migration:
    enabled: true
    scripts_directory: "config/migrations"

  # 版本兼容性
  compatibility:
    backward_compatible: true
    supported_versions:
      - "1.0.0"
      - "0.9.0"

  # 配置备份
  backup:
    enabled: true
    directory: "config/backups"
    max_backups: 10
    retention_days: 30
```

## 10. 最佳实践

### 10.1 配置组织最佳实践

1. **分层配置**：使用全局→环境→特定的分层结构
2. **最小配置**：只配置需要覆盖的项，使用合理的默认值
3. **环境隔离**：不同环境使用不同的配置文件
4. **敏感信息**：敏感信息使用环境变量或密钥管理服务
5. **版本控制**：配置文件纳入版本控制，但排除敏感信息

### 10.2 安全最佳实践

1. **权限控制**：配置文件只读权限，运行时用户最小权限
2. **敏感数据**：密码、密钥等不存储在配置文件中
3. **配置验证**：加载时验证配置的完整性和安全性
4. **审计日志**：记录配置变更和访问

### 10.3 维护最佳实践

1. **文档化**：每个配置项都有清晰的文档
2. **默认值**：提供合理的默认值，减少必要配置
3. **向后兼容**：配置变更保持向后兼容性
4. **迁移工具**：提供配置迁移工具和指南

---

*文档版本：1.0.0*
*创建日期：2026-02-03*
*更新日期：2026-02-03*
