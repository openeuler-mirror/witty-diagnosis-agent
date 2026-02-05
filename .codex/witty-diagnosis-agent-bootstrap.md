# witty-diagnosis-agent Bootstrap for Codex

<EXTREMELY_IMPORTANT>
You have witty-diagnosis-agent skills for intelligent system diagnosis.

**Tool for running skills:**
- `~/.codex/witty-diagnosis-agent/.codex/witty-diagnosis-agent-codex use-skill <skill-name>`

**Tool Mapping for Codex:**
When skills reference tools you don't have, substitute your equivalent tools:
- `TodoWrite` → `update_plan` (your planning/task tracking tool)
- `Task` tool with subagents → Use Codex collab `spawn_agent` + `wait` when available; if collab is disabled, state that and proceed sequentially
- `Subagent` / `Agent` tool mentions → Map to `spawn_agent` (collab) or sequential fallback when collab is disabled
- `Skill` tool → `~/.codex/witty-diagnosis-agent/.codex/witty-diagnosis-agent-codex use-skill` command (already available)
- `Read`, `Write`, `Edit`, `Bash` → Use your native tools with similar functions

**Skills naming:**
- witty-diagnosis-agent skills: `witty-diagnosis-agent:skill-name` (from ~/.codex/witty-diagnosis-agent/skills/)
- Personal skills: `skill-name` (from ~/.codex/skills/)
- Personal skills override witty-diagnosis-agent skills when names match

**Critical Rules:**
- Before ANY system diagnosis task, review the skills list (shown below)
- If a relevant witty-diagnosis-agent skill exists, you MUST use `~/.codex/witty-diagnosis-agent/.codex/witty-diagnosis-agent-codex use-skill` to load it
- Announce: "I've read the [Skill Name] skill and I'm using it to [purpose]"
- Skills with checklists require `update_plan` todos for each item
- NEVER skip mandatory diagnosis workflows (data collection before analysis, controlled repair with rollback)

**Skills location:**
- witty-diagnosis-agent skills: ~/.codex/witty-diagnosis-agent/skills/
- Personal skills: ~/.codex/skills/ (override witty-diagnosis-agent when names match)

**Diagnosis Workflow:**
1. Start with data-collector to gather system data
2. Use log-analyzer and metric-analyzer to identify anomalies
3. Apply fault-localization to determine affected components
4. Perform root-cause-analysis to identify underlying causes
5. Execute controlled-repair with safety controls
6. Update knowledge-base with findings

IF A WITTY-DIAGNOSIS-AGENT SKILL APPLIES TO YOUR TASK, YOU DO NOT HAVE A CHOICE. YOU MUST USE IT.
</EXTREMELY_IMPORTANT>