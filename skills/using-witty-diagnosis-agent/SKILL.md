---
name: using-witty-diagnosis-agent
description: Use when performing system diagnosis on EulerOS - establishes how to find and use witty-diagnosis-agent skills for intelligent system diagnosis
---

<EXTREMELY-IMPORTANT>
If you are performing system diagnosis, troubleshooting, or monitoring on EulerOS (or other Linux systems), you MUST use witty-diagnosis-agent skills.

The witty-diagnosis-agent provides a comprehensive set of intelligent diagnostic skills for EulerOS systems, including data collection, log analysis, metric monitoring, fault localization, root cause analysis, and controlled repair operations.

IF A WITTY-DIAGNOSIS-AGENT SKILL APPLIES TO YOUR TASK, YOU DO NOT HAVE A CHOICE. YOU MUST USE IT.
</EXTREMELY-IMPORTANT>

## How to Access Skills

**In Claude Code:** Use the `Skill` tool. When you invoke a skill, its content is loaded and presented to you—follow it directly. Never use the Read tool on skill files.

**In other environments:** Check your platform's documentation for how skills are loaded.

# Using witty-diagnosis-agent Skills

## The Rule

**Invoke relevant witty-diagnosis-agent skills BEFORE any response or action when dealing with system diagnosis.** Even a 1% chance a skill might apply means that you should invoke the skill to check. If an invoked skill turns out to be wrong for the situation, you don't need to use it.

## Skill Categories

witty-diagnosis-agent provides 10 core diagnostic skills organized into logical categories:

### 1. Data Collection & Monitoring
- **data-collector** - Multi-source system data collection from EulerOS (logs, metrics, processes, network, config)
- **metric-analyzer** - Performance metric monitoring, threshold detection, trend analysis, and alert generation
- **log-analyzer** - Intelligent log analysis with multi-format parsing, anomaly detection, pattern recognition
- **trace-analyzer** - Distributed tracing analysis for service call chain reconstruction and performance bottleneck analysis

### 2. Fault Diagnosis & Analysis
- **fault-localization** - Fault impact scope analysis, identification of affected services and components
- **root-cause-analysis** - Root cause determination using multiple algorithms and reasoning techniques
- **intelligent-inspection** - Proactive system inspection for potential issues, anomaly pattern recognition, inspection reports

### 3. System Management & Repair
- **controlled-repair** - Safe and controlled repair operations on EulerOS with safety controls, rollback mechanisms, and risk assessment
- **config-manager** - System configuration management for unified configuration management, version control, distribution, validation, and rollback
- **knowledge-base** - Fault knowledge base management for storage, retrieval, update, validation, and correlation of fault knowledge

## Diagnosis Workflow

Follow this typical workflow for comprehensive system diagnosis:

1. **Start with data-collector** - Gather comprehensive system data as baseline
2. **Use log-analyzer and metric-analyzer** - Analyze collected data for anomalies
3. **Apply fault-localization** - Determine affected components and services
4. **Perform root-cause-analysis** - Identify underlying causes
5. **Execute controlled-repair** - Safely implement fixes with rollback capability
6. **Update knowledge-base** - Store findings for future reference

## Skill Priority

When multiple skills could apply, use this order:

1. **Data collection skills first** (data-collector, log-analyzer, metric-analyzer) - Gather evidence before analysis
2. **Analysis skills second** (fault-localization, root-cause-analysis, trace-analyzer) - Analyze collected data
3. **Action skills last** (controlled-repair, config-manager) - Implement changes after diagnosis confirmed

"System is slow" → data-collector first, then metric-analyzer, then root-cause-analysis.
"Service is failing" → log-analyzer first, then fault-localization, then controlled-repair.

## Platform Considerations

### EulerOS Specific Features
- Skills are optimized for EulerOS but work on other Linux distributions
- Some configuration paths and service names may differ
- Check skill documentation for EulerOS-specific notes

### Security and Permissions
- Many skills require appropriate system permissions
- controlled-repair requires careful authorization and risk assessment
- Always follow security guidelines in each skill

## Red Flags

These thoughts mean STOP—you're rationalizing:

| Thought | Reality |
|---------|---------|
| "This is just a simple system check" | System checks are diagnosis tasks. Check for skills. |
| "I need more context first" | Skill check comes BEFORE clarifying questions. Use data-collector first. |
| "Let me check logs manually" | Use log-analyzer skill instead for systematic analysis. |
| "I can run a few commands to diagnose" | Skills provide structured diagnosis workflows. Use them. |
| "This doesn't need a formal diagnosis skill" | If a skill exists, use it for consistent results. |
| "I remember how to diagnose this" | Skills evolve. Read current version and follow best practices. |
| "The skill is overkill for this simple issue" | Simple issues can have complex root causes. Use the skills. |

## Integration with Other Skill Systems

witty-diagnosis-agent skills complement other skill systems like superpowers:
- Use superpowers skills for development workflows (brainstorming, TDD, planning)
- Use witty-diagnosis-agent skills for system diagnosis and operations
- When building diagnostic tools or monitoring systems, combine both skill sets

## Getting Help

- Skill documentation: Each skill has comprehensive documentation in its SKILL.md
- Project documentation: https://gitcode.com/openeuler/witty-diagnosis-agent
- Report issues: https://gitcode.com/openeuler/witty-diagnosis-agent/issues