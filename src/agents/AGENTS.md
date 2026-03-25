# src/agents/ — 4 Agent Definitions

**Updated:** 2026-03-25

## OVERVIEW

The intelligent O&M pipeline consists of four main agents:

## AGENT INVENTORY

| Agent | Purpose | Description |
|-------|---------|-------------|
| **Fuxi (伏羲)** | Diagnostic Planner | Creates diagnostic plans and templates for troubleshooting. |
| **Dayu (大禹)** | Diagnostic Orchestrator | Orchestrates diagnostic tasks, interviews users, and delegates. |
| **Kuafu (夸父)** | Diagnostic Executor | Executes tasks, uses tools (bash, read, grep) to collect evidence. |
| **Baize (白泽)** | Root Cause Analysis | Analyzes diagnostic reports to find the root cause of issues. |

## STRUCTURE

```
agents/
├── fuxi/           # Diagnostic Planner (伏羲)
├── dayu/           # Diagnostic Orchestrator (大禹)
├── kuafu/          # General Diagnostic Executor (夸父)
├── baize/          # Root Cause Analysis Agent (白泽)
├── index.ts        # Exports
├── types.ts        # Types
└── utils.ts        # Utilities
```
