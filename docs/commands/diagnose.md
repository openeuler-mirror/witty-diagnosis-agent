# Diagnose Command

## Overview

The `diagnose` command initiates a comprehensive system diagnosis using all available diagnostic skills. It orchestrates the execution of multiple skills in a coordinated manner to identify system issues and provide actionable recommendations.

## Usage

```bash
# Basic diagnosis
diagnose

# Diagnose specific target
diagnose --target system
diagnose --target network
diagnose --target storage
diagnose --target security

# With specific skills
diagnose --skills data-collector,fault-localization,root-cause-analysis

# With output format
diagnose --format json
diagnose --format yaml
diagnose --format text

# With verbosity
diagnose --verbose
diagnose --quiet

# Save results to file
diagnose --output /path/to/results.json
```

## Command Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--target` | `-t` | Target system component to diagnose | `system` |
| `--skills` | `-s` | Comma-separated list of skills to use | All enabled skills |
| `--format` | `-f` | Output format (json, yaml, text) | `text` |
| `--output` | `-o` | Output file path | None (stdout) |
| `--verbose` | `-v` | Enable verbose output | `false` |
| `--quiet` | `-q` | Suppress non-essential output | `false` |
| `--timeout` | `-T` | Maximum execution time in seconds | `300` |
| `--help` | `-h` | Show help message | N/A |

## Examples

### Basic System Diagnosis
```bash
diagnose
```

This command runs a comprehensive system diagnosis using all enabled skills and displays the results in a human-readable format.

### Network-Specific Diagnosis
```bash
diagnose --target network --format json --output network_diagnosis.json
```

This command focuses on network-related issues, outputs results in JSON format, and saves them to a file.

### Quick Diagnosis with Selected Skills
```bash
diagnose --skills data-collector,log-analyzer --quiet
```

This command runs only the data collector and log analyzer skills with minimal output.

## Diagnosis Process

The diagnose command follows this workflow:

1. **Session Initialization**
   - Create diagnosis session
   - Execute session-start hooks
   - Initialize skill execution context

2. **Skill Execution**
   - Execute pre-diagnosis hooks
   - Run selected skills in optimal order
   - Collect skill outputs and metrics

3. **Result Aggregation**
   - Aggregate results from all skills
   - Correlate findings across skills
   - Generate severity assessments

4. **Recommendation Generation**
   - Generate actionable recommendations
   - Prioritize issues by severity
   - Suggest repair actions

5. **Session Cleanup**
   - Execute post-diagnosis hooks
   - Clean up temporary resources
   - Generate final report

## Skill Execution Order

Skills are executed in the following order by default:

1. **Data Collector** - Collect system data
2. **Log Analyzer** - Analyze system logs
3. **Metric Analyzer** - Analyze system metrics
4. **Trace Analyzer** - Analyze distributed traces
5. **Fault Localization** - Locate faults
6. **Root Cause Analysis** - Identify root causes
7. **Intelligent Inspection** - Proactive inspection
8. **Knowledge Base** - Reference known issues
9. **Config Manager** - Check configurations
10. **Controlled Repair** - Suggest repairs

## Output Formats

### Text Format (Default)
```
Diagnosis Report
================
Session ID: abc123
Start Time: 2026-02-03 17:30:00
Duration: 45 seconds

Summary
-------
✓ System: Healthy
⚠ Network: Minor issues detected
✗ Storage: Critical issues detected

Issues Found
------------
1. [CRITICAL] Disk /dev/sda1 at 95% capacity
   Recommendation: Clean up temporary files or expand storage

2. [WARNING] High network latency detected
   Recommendation: Check network configuration

Recommendations
---------------
1. Immediate action required for storage issue
2. Monitor network performance
```

### JSON Format
```json
{
  "session_id": "abc123",
  "start_time": "2026-02-03T17:30:00Z",
  "duration_seconds": 45,
  "status": "completed",
  "summary": {
    "system": "healthy",
    "network": "warning",
    "storage": "critical"
  },
  "issues": [
    {
      "id": "issue_001",
      "severity": "critical",
      "component": "storage",
      "description": "Disk /dev/sda1 at 95% capacity",
      "recommendation": "Clean up temporary files or expand storage"
    }
  ],
  "recommendations": [
    {
      "priority": "high",
      "action": "Clean up temporary files",
      "estimated_time": "30 minutes"
    }
  ],
  "skills_executed": [
    "data-collector",
    "log-analyzer",
    "metric-analyzer"
  ]
}
```

## Exit Codes

| Code | Description |
|------|-------------|
| 0 | Diagnosis completed successfully |
| 1 | General error |
| 2 | Invalid arguments |
| 3 | Skill execution failed |
| 4 | Timeout exceeded |
| 5 | Insufficient permissions |

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DIAGNOSIS_SESSION_ID` | Session identifier | Auto-generated |
| `DIAGNOSIS_OUTPUT_DIR` | Output directory for artifacts | `/tmp/witty-diagnosis` |
| `DIAGNOSIS_LOG_LEVEL` | Log level for diagnosis | `INFO` |
| `DIAGNOSIS_CONFIG_PATH` | Path to configuration file | `config/global.yaml` |

## Related Commands

- `collect-data` - Collect system data without analysis
- `analyze-logs` - Analyze system logs specifically
- `repair-system` - Execute repair actions
- `health-check` - Quick system health check

## Notes

- The diagnose command requires appropriate system permissions
- Some skills may require additional dependencies
- Diagnosis results are cached for performance
- Use `--verbose` flag for detailed debugging information