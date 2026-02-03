# Witty Diagnosis Agent

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-0.1.0-blue.svg)](https://gitcode.com/openeuler/witty-diagnosis-agent)

> **AI-Powered Diagnostic Skill Collection for EulerOS**

## Overview

**Witty Diagnosis Agent** is a comprehensive collection of intelligent diagnostic skills for **EulerOS** systems, designed as a Claude Code plugin. This project provides 10 modular, composable skills that enable automated system troubleshooting, analysis, and controlled repair through natural language interactions with AI assistants.

Built on the **superpowers project architecture**, this skill collection follows the standardized documentation format for AI-powered tools, making it compatible with Claude Code, Codex, and other AI development platforms.

### Key Capabilities

- **Intelligent Multi-Source Data Collection** - Gather logs, metrics, processes, and configuration data
- **Advanced Fault Localization** - Identify affected components and propagation paths
- **Root Cause Analysis** - AI-powered reasoning to determine underlying issues
- **Controlled Repair Operations** - Safe, approval-required system fixes
- **Proactive System Inspection** - Regular health checks and anomaly detection
- **Comprehensive Log Analysis** - Pattern recognition and correlation analysis
- **Performance Metric Monitoring** - Real-time metrics collection and trend analysis
- **Distributed Trace Analysis** - Service dependency and bottleneck identification
- **Knowledge Base Management** - Historical failure patterns and solutions
- **Configuration Management** - System config versioning and validation

## Installation

### Prerequisites

- **Claude Code** or compatible AI development platform
- **EulerOS** or compatible Linux system (for actual diagnosis)
- **Git** for repository management

### Installation for Different Platforms

**Note:** Installation differs by platform. Claude Code has a built-in plugin system. Codex and OpenCode require manual setup.

#### Claude Code (via GitCode Repository)

In Claude Code, register the repository as a marketplace first:

```bash
/plugin marketplace add https://gitcode.com/openeuler/witty-diagnosis-agent.git
```

Then install the plugin from this marketplace:

```bash
/plugin install witty-diagnosis-agent@witty-diagnosis-agent
```

##### Alternative: Local Installation

1. **Clone the repository**:
   ```bash
   git clone https://gitcode.com/openeuler/witty-diagnosis-agent.git
   cd witty-diagnosis-agent
   ```

2. **Configure as Claude Plugin**:
   - The `.claude-plugin/` directory contains all necessary configuration
   - Claude Code will automatically detect the plugin structure
   - No additional installation required

3. **Verify Plugin Detection**:
   ```bash
   # In Claude Code, check if plugin is detected
   claude --list-plugins
   ```

#### Codex

Tell Codex:

```
Fetch and follow instructions from https://raw.gitcode.com/openeuler/witty-diagnosis-agent/raw/master/.codex/INSTALL.md
```


#### OpenCode

Tell OpenCode:

```
Fetch and follow instructions from https://raw.gitcode.com/openeuler/witty-diagnosis-agent/raw/master/.opencode/INSTALL.md
```


### Quick Start

#### Using Skills Directly

```bash
# Example: Run a complete diagnosis workflow
claude witty-diagnosis:diagnose --target system --scope full

# Example: Collect system data
claude witty-diagnosis:collect-data --type all --output json

# Example: Analyze system logs
claude witty-diagnosis:analyze-logs --files "/var/log/*.log" --time-window "24h"

# Example: Perform system repair (dry-run first)
claude witty-diagnosis:repair-system --action restart-service --target nginx --dry-run
```

#### Skill Pipeline Example

```bash
# Chain multiple skills for comprehensive analysis
claude witty-diagnosis:collect-data --type logs,metrics | \
claude witty-diagnosis:fault-localization --method topology | \
claude witty-diagnosis:root-cause-analysis --history 7d | \
claude witty-diagnosis:controlled-repair --dry-run --require-approval
```

## Project Architecture

### Modular Skill-Based Design

```
witty-diagnosis-agent/
├── .claude-plugin/                    # Claude plugin configuration
│   ├── plugin.json                    # Plugin manifest
│   └── marketplace.json               # Marketplace listing
├── commands/                          # Command definitions for Claude
│   ├── diagnose.md                    # Full diagnosis workflow
│   ├── collect-data.md                # Data collection commands
│   ├── analyze-logs.md                # Log analysis commands
│   └── repair-system.md               # System repair commands
├── skills/                            # Core diagnostic skills (10 skills)
│   ├── data-collector/                # Multi-source data collection
│   ├── fault-localization/            # Fault scope identification
│   ├── root-cause-analysis/           # Root cause investigation
│   ├── controlled-repair/             # Safe repair operations
│   ├── intelligent-inspection/        # Proactive system checks
│   ├── log-analyzer/                  # Log parsing and analysis
│   ├── metric-analyzer/               # Performance metrics analysis
│   ├── trace-analyzer/                # Distributed tracing analysis
│   ├── knowledge-base/                # Failure knowledge management
│   └── config-manager/                # Configuration management
├── docs/                              # Documentation
│   ├── plans/                         # Implementation plans
│   ├── standards/                     # Format standards
│   └── architecture/                  # Architecture design
├── templates/                         # Development templates
├── agents/                            # Agent definitions
├── lib/                               # Shared libraries
├── config/                            # Configuration files
├── hooks/                             # Hook scripts
└── tests/                             # Test suites
```

### Skill Layer Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Intelligent Diagnosis                  │
├─────────────────────────────────────────────────────────┤
│   Core Diagnostic Layer (5 skills):                      │
│   data-collector → fault-localization →                 │
│   root-cause-analysis → controlled-repair →             │
│   intelligent-inspection                                │
├─────────────────────────────────────────────────────────┤
│   Analysis Support Layer (3 skills):                    │
│   log-analyzer + metric-analyzer + trace-analyzer       │
├─────────────────────────────────────────────────────────┤
│   Management Support Layer (2 skills):                  │
│   knowledge-base + config-manager                       │
└─────────────────────────────────────────────────────────┘
```

## Core Skills

### 1. **data-collector**
**Purpose**: Collect multi-source system data including logs, metrics, processes, and network status
**Category**: Core Diagnostic
**Input**: Collection parameters, data source specifications
**Output**: Structured JSON data for analysis
**Related Skills**: log-analyzer, metric-analyzer

### 2. **fault-localization**
**Purpose**: Determine fault impact scope and affected components
**Category**: Core Diagnostic
**Input**: Collected data, system topology
**Output**: Fault scope analysis, impact assessment
**Related Skills**: data-collector, root-cause-analysis

### 3. **root-cause-analysis**
**Purpose**: Identify underlying causes using AI reasoning and pattern matching
**Category**: Core Diagnostic
**Input**: Fault scope, historical data, knowledge base
**Output**: Root cause identification, confidence scores
**Related Skills**: fault-localization, knowledge-base

### 4. **controlled-repair**
**Purpose**: Execute safe repair operations with approval requirements
**Category**: Core Diagnostic
**Input**: Repair actions, validation rules, backup requirements
**Output**: Repair execution results, verification status
**Related Skills**: root-cause-analysis, config-manager

### 5. **intelligent-inspection**
**Purpose**: Perform proactive system health checks and anomaly detection
**Category**: Core Diagnostic
**Input**: Inspection schedules, check criteria
**Output**: Inspection reports, anomaly alerts
**Related Skills**: data-collector, metric-analyzer

### 6. **log-analyzer**
**Purpose**: Analyze system logs for patterns, anomalies, and correlations
**Category**: Analysis Support
**Input**: Log data, analysis parameters
**Output**: Anomaly detection, pattern recognition, correlation analysis
**Related Skills**: data-collector, trace-analyzer

### 7. **metric-analyzer**
**Purpose**: Monitor and analyze system performance metrics
**Category**: Analysis Support
**Input**: Metric data, baseline references
**Output**: Performance analysis, trend detection, capacity planning
**Related Skills**: data-collector, intelligent-inspection

### 8. **trace-analyzer**
**Purpose**: Analyze distributed service traces and dependencies
**Category**: Analysis Support
**Input**: Trace data, service topology
**Output**: Dependency analysis, bottleneck identification
**Related Skills**: log-analyzer, fault-localization

### 9. **knowledge-base**
**Purpose**: Manage historical failure patterns and solution knowledge
**Category**: Management Support
**Input**: Failure cases, solutions, best practices
**Output**: Knowledge retrieval, pattern matching, solution recommendations
**Related Skills**: root-cause-analysis, config-manager

### 10. **config-manager**
**Purpose**: Manage system configurations with version control and validation
**Category**: Management Support
**Input**: Configuration files, validation rules
**Output**: Configuration status, compliance reports, change history
**Related Skills**: controlled-repair, intelligent-inspection


## Skill Documentation Format

Each skill follows the **superpowers project documentation standard**:

### SKILL.md Structure
```yaml
---
name: "skill-name"
description: "Brief description of skill purpose"
version: "1.0.0"
author: "Witty Diagnosis Team"
category: "core-diagnosis|analysis-support|management-support"
prerequisites: []
related_skills: ["skill1", "skill2"]
---
# Skill Name - Detailed Description

## Overview
[Purpose and high-level functionality]

## When to Use
[Scenarios where this skill should/shouldn't be used]

## Input Requirements
[Required input data format and parameters]

## Execution Steps
[Detailed step-by-step process]

## Output Format
[Standardized output format]

## Examples
[Practical usage examples]

## Testing
[Test cases and validation methods]

## Notes and Limitations
[Important considerations and constraints]
```

### Data Format Standards

**Input Format** (JSON):
```json
{
  "session_id": "unique-session-id",
  "parameters": {
    "target": "system|service|component",
    "scope": "full|partial|custom",
    "time_range": "last_1_hour|last_24_hours|custom"
  },
  "data": {
    // Skill-specific input data
  }
}
```

**Output Format** (JSON):
```json
{
  "status": "success|error|partial",
  "session_id": "unique-session-id",
  "results": {
    // Skill-specific analysis results
  },
  "metadata": {
    "skill": "skill-name",
    "version": "1.0.0",
    "execution_time": 123.45,
    "timestamp": "2026-02-03T10:30:00Z"
  }
}
```

## Development

### Adding New Skills

1. **Create Skill Directory**:
   ```bash
   mkdir -p skills/new-skill-name/{examples,tests}
   ```

2. **Create SKILL.md**:
   - Use `templates/skill-template.md` as starting point
   - Follow YAML frontmatter format
   - Include complete execution steps

3. **Add Examples and Tests**:
   - Create at least 2 usage examples in `examples/`
   - Create test cases in `tests/`

4. **Update Documentation**:
   - Add skill to README.md
   - Update relevant command definitions
   - Update skill dependencies

### Testing Skills

```bash
# Run skill documentation validation
claude witty-diagnosis:validate-skill --skill data-collector

# Test skill execution flow
claude witty-diagnosis:test-skill --skill log-analyzer --test-case basic

# Run integration tests
claude witty-diagnosis:test-integration --skills data-collector,log-analyzer
```

## Configuration

### Plugin Configuration (`.claude-plugin/`)

**plugin.json** - Main plugin manifest:
```json
{
  "name": "witty-diagnosis-agent",
  "version": "0.1.0",
  "description": "Intelligent diagnostic skills for EulerOS",
  "main": "index.js",
  "keywords": ["diagnosis", "troubleshooting", "euleros", "ai-agent"]
}
```

**marketplace.json** - Marketplace listing:
```json
{
  "name": "Witty Diagnosis Agent",
  "slug": "witty-diagnosis-agent",
  "version": "0.1.0",
  "description": "AI-powered diagnostic agent for EulerOS",
  "features": [
    {"name": "Intelligent Diagnosis", "description": "Automated system diagnosis"},
    {"name": "Root Cause Analysis", "description": "AI-powered root cause identification"},
    {"name": "Controlled Repair", "description": "Safe system repair operations"}
  ]
}
```

### Global Configuration (`config/`)

- `global.yaml` - Global agent settings
- `skills/` - Skill-specific configurations
- `euler-os/` - EulerOS-specific configurations

## Contributing

We welcome contributions to improve the Witty Diagnosis Agent!

### Contribution Guidelines

1. **Fork the Repository**
2. **Create a Feature Branch**:
   ```bash
   git checkout -b feature/new-diagnostic-skill
   ```
3. **Follow Documentation Standards**:
   - Use existing skill templates
   - Maintain consistent formatting
   - Include comprehensive examples
4. **Add Tests**:
   - Create test cases for new functionality
   - Update existing tests if needed
5. **Submit Pull Request**:
   - Describe the feature or fix
   - Reference related issues
   - Include test results

### Code Review Process

1. **Documentation Review** - Skill documentation completeness
2. **Format Validation** - Adherence to standards
3. **Integration Testing** - Compatibility with existing skills
4. **Performance Assessment** - Execution efficiency
5. **Security Review** - Safe operation validation

## License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

## Support

- **Documentation**: [docs/](docs/)
- **Issues**: [GitCode Issues](https://gitcode.com/openeuler/witty-diagnosis-agent/issues)
- **Email**: support@huawei.com
- **Skill Development Guide**: [docs/standards/skill-documentation-format.md](docs/standards/skill-documentation-format.md)

## Acknowledgments

- **Superpowers Project** - For the skill architecture and documentation standards
- **Claude Code Community** - For plugin system and development tools
- **EulerOS Team** - For system insights and testing support
- **All Contributors** - For improving diagnostic capabilities

## Roadmap

### Phase 1: Core Skills (✅ Completed)
- [x] 10 core diagnostic skills with complete documentation
- [x] Standardized skill format and interfaces
- [x] Basic command definitions

### Phase 2: Integration & Testing
- [ ] Complete command definitions for all skills
- [ ] Agent definitions for automated workflows
- [ ] Skill integration testing suite
- [ ] Performance benchmarking

### Phase 3: Advanced Features
- [ ] Machine learning enhanced analysis
- [ ] Real-time monitoring integration
- [ ] Multi-system coordination
- [ ] Advanced visualization tools

### Phase 4: Ecosystem Expansion
- [ ] Additional specialized diagnostic skills
- [ ] Cloud platform integrations
- [ ] Third-party tool integrations
- [ ] Community skill marketplace

---

*Last Updated: 2026-02-03*
*Project Version: 0.1.0*
*Skill Count: 10 Core Diagnostic Skills*