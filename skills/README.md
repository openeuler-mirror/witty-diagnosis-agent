# Diagnostic Skills

## Overview

This directory contains the diagnostic skills for the witty-diagnosis-agent. Each skill is a self-contained module that performs specific diagnostic functions. Skills follow a standardized interface and can be composed to perform complex diagnosis workflows.

## Skill Architecture

### Skill Structure
```
skill-name/
├── skill.json           # Skill metadata and configuration
├── skill.py             # Main skill implementation
├── requirements.txt     # Python dependencies
├── tests/               # Unit tests
│   ├── test_skill.py
│   └── __init__.py
├── docs/                # Documentation
│   ├── README.md
│   └── API.md
└── examples/            # Usage examples
    └── example_usage.py
```

### Skill Interface
```python
class DiagnosticSkill:
    def __init__(self, config):
        self.config = config
        self.name = config.get('name')
        self.version = config.get('version')

    def execute(self, context):
        """
        Execute the diagnostic skill.

        Args:
            context: Execution context containing system data and state

        Returns:
            SkillResult: Result of skill execution
        """
        pass

    def validate(self, context):
        """
        Validate if skill can be executed.

        Args:
            context: Execution context

        Returns:
            bool: True if skill can be executed
        """
        pass

    def get_requirements(self):
        """
        Get skill requirements.

        Returns:
            list: List of required skills or conditions
        """
        pass
```

## Core Skills

### 1. Data Collector
**Purpose**: Collect system data and metrics
**Dependencies**: None
**Output**: System data snapshot
**Configuration**: Collection intervals, data types

### 2. Fault Localization
**Purpose**: Detect and locate system faults
**Dependencies**: Data Collector
**Output**: Fault locations and severity
**Configuration**: Detection thresholds, fault patterns

### 3. Root Cause Analysis
**Purpose**: Identify root causes of faults
**Dependencies**: Data Collector, Fault Localization
**Output**: Root cause analysis report
**Configuration**: Analysis depth, correlation rules

### 4. Controlled Repair
**Purpose**: Execute safe repair operations
**Dependencies**: Root Cause Analysis
**Output**: Repair execution results
**Configuration**: Repair policies, safety limits

### 5. Intelligent Inspection
**Purpose**: Proactive system inspection
**Dependencies**: Data Collector
**Output**: Inspection findings and recommendations
**Configuration**: Inspection schedules, check criteria

### 6. Log Analyzer
**Purpose**: Analyze system and application logs
**Dependencies**: None
**Output**: Log analysis report
**Configuration**: Log patterns, severity levels

### 7. Metric Analyzer
**Purpose**: Analyze system metrics and trends
**Dependencies**: Data Collector
**Output**: Metric analysis report
**Configuration**: Metric thresholds, trend periods

### 8. Trace Analyzer
**Purpose**: Analyze distributed traces
**Dependencies**: Data Collector
**Output**: Trace analysis report
**Configuration**: Trace sampling, latency thresholds

### 9. Knowledge Base
**Purpose**: Reference known issues and solutions
**Dependencies**: None
**Output**: Knowledge base queries and results
**Configuration**: Knowledge sources, update intervals

### 10. Config Manager
**Purpose**: Manage and validate configurations
**Dependencies**: None
**Output**: Configuration validation report
**Configuration**: Configuration templates, validation rules

## Skill Development

### Creating a New Skill

1. **Create Skill Directory**
   ```bash
   mkdir -p skills/new-skill-name
   cd skills/new-skill-name
   ```

2. **Create Skill Configuration**
   ```json
   {
     "name": "new-skill-name",
     "version": "1.0.0",
     "description": "Description of the new skill",
     "author": "Your Name",
     "dependencies": [],
     "requirements": {
       "python": ">=3.8",
       "packages": ["package1", "package2"]
     },
     "configuration": {
       "enabled": true,
       "timeout": 60,
       "priority": 1
     }
   }
   ```

3. **Implement Skill Logic**
   ```python
   # skill.py
   from typing import Dict, Any
   from .skill_base import DiagnosticSkill, SkillResult

   class NewSkill(DiagnosticSkill):
       def execute(self, context: Dict[str, Any]) -> SkillResult:
           # Skill implementation
           result = SkillResult(
               skill_name=self.name,
               status="completed",
               data={"key": "value"},
               metrics={"execution_time": 1.5}
           )
           return result
   ```

4. **Write Tests**
   ```python
   # tests/test_skill.py
   import unittest
   from skill import NewSkill

   class TestNewSkill(unittest.TestCase):
       def test_execute(self):
           skill = NewSkill({"name": "test-skill"})
           result = skill.execute({})
           self.assertEqual(result.status, "completed")
   ```

5. **Add Documentation**
   ```markdown
   # New Skill Name

   ## Purpose
   Brief description of the skill's purpose.

   ## Usage
   ```python
   skill = NewSkill(config)
   result = skill.execute(context)
   ```

   ## Configuration
   - `enabled`: Enable/disable skill
   - `timeout`: Execution timeout
   - Other configuration options
   ```

### Skill Best Practices

1. **Idempotency**: Skills should be idempotent when possible
2. **Resource Management**: Clean up resources after execution
3. **Error Handling**: Graceful error handling and reporting
4. **Logging**: Comprehensive logging for debugging
5. **Testing**: Unit tests for all functionality
6. **Documentation**: Clear usage and configuration documentation

## Skill Execution

### Execution Context
```python
context = {
    "session_id": "session-123",
    "system_data": {...},
    "previous_results": [...],
    "configuration": {...},
    "environment": {...}
}
```

### Skill Result
```python
result = {
    "skill_name": "skill-name",
    "status": "completed",  # or "failed", "skipped"
    "timestamp": "2026-02-03T17:30:00Z",
    "execution_time": 1.5,
    "data": {...},          # Skill-specific data
    "metrics": {...},       # Performance metrics
    "errors": [],           # List of errors if any
    "warnings": [],         # List of warnings
    "recommendations": []   # Actionable recommendations
}
```

## Skill Configuration

### Global Skill Configuration
```yaml
skills:
  enabled: true
  auto_discovery: true
  default_timeout: 60
  max_retries: 3
  execution_mode: "sequential"  # or "parallel"
```

### Individual Skill Configuration
```yaml
skills:
  data-collector:
    enabled: true
    timeout: 120
    priority: 1
    configuration:
      collection_interval: 1
      data_types: ["system", "network", "storage"]

  log-analyzer:
    enabled: true
    timeout: 180
    priority: 2
    configuration:
      log_files: ["/var/log/syslog", "/var/log/messages"]
      patterns:
        - pattern: "ERROR"
          severity: "error"
        - pattern: "WARN"
          severity: "warning"
```

## Skill Dependencies

### Dependency Types
1. **Hard Dependencies**: Required for skill execution
2. **Soft Dependencies**: Optional but enhance functionality
3. **Data Dependencies**: Require specific data from other skills
4. **Resource Dependencies**: Require specific system resources

### Dependency Resolution
```python
# Skill declares dependencies
dependencies = ["data-collector", "log-analyzer"]

# Agent resolves and executes dependencies
execution_order = resolve_dependencies(skills, dependencies)
```

## Skill Registry

### Automatic Discovery
```python
class SkillRegistry:
    def discover_skills(self, skill_dir):
        # Scan skill directories
        # Load skill configurations
        # Validate skill implementations
        # Register skills in registry
```

### Manual Registration
```python
registry = SkillRegistry()
registry.register_skill(DataCollector(config))
registry.register_skill(LogAnalyzer(config))
```

## Testing Skills

### Unit Testing
```bash
# Run skill tests
cd skills/skill-name
pytest tests/

# Run all skill tests
find skills -name "test_*.py" -exec pytest {} \;
```

### Integration Testing
```python
# Test skill integration
def test_skill_integration():
    skill1 = DataCollector(config)
    skill2 = LogAnalyzer(config)

    # Execute skill chain
    result1 = skill1.execute(context)
    context["system_data"] = result1.data
    result2 = skill2.execute(context)

    assert result2.status == "completed"
```

### Performance Testing
```python
# Test skill performance
def test_skill_performance():
    skill = Skill(config)
    start_time = time.time()

    for _ in range(100):
        skill.execute(context)

    execution_time = time.time() - start_time
    assert execution_time < 10.0  # 10 seconds max
```

## Skill Versioning

### Version Format
```
MAJOR.MINOR.PATCH
- MAJOR: Breaking changes
- MINOR: New features, backward compatible
- PATCH: Bug fixes, backward compatible
```

### Version Compatibility
```python
# Check skill compatibility
def check_compatibility(skill_version, agent_version):
    # Parse versions
    # Check compatibility rules
    # Return compatibility status
```

## Security Considerations

### Skill Sandboxing
```python
# Execute skill in sandbox
sandbox = SkillSandbox(skill)
result = sandbox.execute(context)
```

### Permission Checking
```python
# Check skill permissions
def check_permissions(skill, user):
    required_perms = skill.get_required_permissions()
    user_perms = user.get_permissions()
    return all(perm in user_perms for perm in required_perms)
```

### Data Validation
```python
# Validate skill input/output
def validate_data(data, schema):
    # Validate against JSON schema
    # Check for malicious content
    # Sanitize if necessary
```

## Monitoring and Metrics

### Skill Metrics
```python
metrics = {
    "execution_count": Counter,
    "execution_time": Histogram,
    "success_rate": Gauge,
    "error_count": Counter,
    "resource_usage": Summary
}
```

### Health Checks
```python
# Skill health check
def health_check(skill):
    return {
        "status": "healthy",
        "version": skill.version,
        "dependencies_met": check_dependencies(skill),
        "last_execution": get_last_execution_time(skill)
    }
```

## Troubleshooting

### Common Issues
1. **Skill Not Found**: Check skill registration
2. **Dependency Errors**: Verify skill dependencies
3. **Permission Denied**: Check file permissions
4. **Timeout Errors**: Adjust timeout configuration
5. **Memory Errors**: Monitor resource usage

### Debugging
```bash
# Enable debug logging
diagnose --verbose --skill skill-name

# Check skill status
skill-status skill-name

# View skill logs
tail -f /var/log/witty-diagnosis-agent/skill-name.log
```

## Contributing Skills

### Contribution Guidelines
1. Follow skill structure and interface
2. Include comprehensive tests
3. Provide clear documentation
4. Handle errors gracefully
5. Optimize for performance
6. Consider security implications

### Review Process
1. Code review by maintainers
2. Integration testing
3. Performance benchmarking
4. Security assessment
5. Documentation review