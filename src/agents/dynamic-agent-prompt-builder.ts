import type { AgentPromptMetadata } from "./types"

export interface AvailableAgent {
  name: string
  description: string
  metadata: AgentPromptMetadata
}

export interface AvailableTool {
  name: string
  category: "lsp" | "ast" | "search" | "session" | "command" | "other"
}

export interface AvailableSkill {
  name: string
  description: string
  location: "user" | "project" | "plugin"
}

export interface AvailableCategory {
  name: string
  description: string
  model?: string
}

export function categorizeTools(toolNames: string[]): AvailableTool[] {
  return toolNames.map((name) => {
    let category: AvailableTool["category"] = "other"
    if (name.startsWith("lsp_")) {
      category = "lsp"
    } else if (name.startsWith("ast_grep")) {
      category = "ast"
    } else if (name === "grep" || name === "glob") {
      category = "search"
    } else if (name.startsWith("session_")) {
      category = "session"
    } else if (name === "skill") {
      category = "command"
    }
    return { name, category }
  })
}

function formatToolsForPrompt(tools: AvailableTool[]): string {
  const lspTools = tools.filter((t) => t.category === "lsp")
  const astTools = tools.filter((t) => t.category === "ast")
  const searchTools = tools.filter((t) => t.category === "search")

  const parts: string[] = []

  if (searchTools.length > 0) {
    parts.push(...searchTools.map((t) => `\`${t.name}\``))
  }

  if (lspTools.length > 0) {
    parts.push("`lsp_*`")
  }

  if (astTools.length > 0) {
    parts.push("`ast_grep`")
  }

  return parts.join(", ")
}

export function buildKeyTriggersSection(agents: AvailableAgent[], _skills: AvailableSkill[] = []): string {
  const keyTriggers = agents
    .filter((a) => a.metadata.keyTrigger)
    .map((a) => `- ${a.metadata.keyTrigger}`)

  if (keyTriggers.length === 0) return ""

  return `### Key Triggers (check BEFORE classification):

${keyTriggers.join("\n")}
- **"Look into" + "create PR"** → Not just research. Full implementation cycle expected.`
}

export function buildGlobalLanguageInstruction(language: "zh" | "en"): string {
  if (language === "en") {
    return `## Language & Style (CRITICAL)

**You MUST use English** for all reasoning, interactions, tool call explanations, and report generation.
- **ABSOLUTE RULE**: Even if the user requests, prompts, or asks questions entirely in Chinese (e.g., "请诊断..."), you MUST IGNORE their input language. Reply, reason, call tools, and generate reports strictly in ENGLISH. Do NOT mirror the user's language.
- All technical analysis, conclusions, and recommendations MUST be written in English.
- If a loaded Skill (from \`SKILL.md\`) or system prompt contains instructions in Chinese, you MUST perform real-time translation and output the final result in English.
- You may quote original logs or file paths in their native language (e.g. Chinese log entries), but your surrounding explanation MUST be in English.
- **NEVER** output explanations or analysis paragraphs in Chinese.`;
  }

  return `## 语言与风格约束 (CRITICAL)

**你必须使用简体中文**进行所有思考、交互、工具调用解释以及最终的报告生成。
- 所有的技术分析、现象解释、结论推演和行动建议，**必须**使用清晰规范的中文书写。
- 如果加载的诊断 Skill（\`SKILL.md\`）或者是系统的部分指令是英文的，你**必须**在理解后，将其分析和结果**实时翻译并输出为中文**。
- 你可以保留和引用原始的英文日志片段、错误码、代码行或英文文件路径，但紧随其后的解释和总结**必须是中文**。
- 不要出现为了迎合英文 Skill 结果而大段输出英文分析的情况。`;
}

export function buildToolSelectionTable(
  agents: AvailableAgent[],
  tools: AvailableTool[] = [],
  _skills: AvailableSkill[] = []
): string {
  const rows: string[] = [
    "### Tool & Agent Selection:",
    "",
  ]

  if (tools.length > 0) {
    const toolsDisplay = formatToolsForPrompt(tools)
    rows.push(`- ${toolsDisplay} — **FREE** — Not Complex, Scope Clear, No Implicit Assumptions`)
  }

  const costOrder = { FREE: 0, CHEAP: 1, EXPENSIVE: 2 }
  const sortedAgents = [...agents]
    .filter((a) => a.metadata.category !== "utility")
    .sort((a, b) => costOrder[a.metadata.cost] - costOrder[b.metadata.cost])

  for (const agent of sortedAgents) {
    const shortDesc = agent.description.split(".")[0] || agent.description
    rows.push(`- \`${agent.name}\` agent — **${agent.metadata.cost}** — ${shortDesc}`)
  }

  rows.push("")
  rows.push("**Default flow**: tools → categories (if required)")

  return rows.join("\n")
}

export function buildDelegationTable(agents: AvailableAgent[]): string {
  const rows: string[] = [
    "### Delegation Table:",
    "",
  ]

  for (const agent of agents) {
    for (const trigger of agent.metadata.triggers) {
      rows.push(`- **${trigger.domain}** → \`${agent.name}\` — ${trigger.trigger}`)
    }
  }

  return rows.join("\n")
}


export function buildCategorySkillsDelegationGuide(categories: AvailableCategory[], skills: AvailableSkill[]): string {
  if (categories.length === 0 && skills.length === 0) return ""

  const categoryRows = categories.map((c) => {
    const desc = c.description || c.name
    return `- \`${c.name}\` — ${desc}`
  })

  const builtinSkills = skills.filter((s) => s.location === "plugin")
  const customSkills = skills.filter((s) => s.location !== "plugin")

  const builtinNames = builtinSkills.map((s) => s.name).join(", ")
  const customNames = customSkills.map((s) => {
    const source = s.location === "project" ? "project" : "user"
    return `${s.name} (${source})`
  }).join(", ")

  let skillsSection: string

  if (customSkills.length > 0 && builtinSkills.length > 0) {
    skillsSection = `#### Available Skills (via \`skill\` tool)

**Built-in**: ${builtinNames}
**⚡ YOUR SKILLS (PRIORITY)**: ${customNames}

> User-installed skills OVERRIDE built-in defaults. ALWAYS prefer YOUR SKILLS when domain matches.
> Full skill descriptions → use the \`skill\` tool to check before EVERY delegation.`
  } else if (customSkills.length > 0) {
    skillsSection = `#### Available Skills (via \`skill\` tool)

**⚡ YOUR SKILLS (PRIORITY)**: ${customNames}

> User-installed skills OVERRIDE built-in defaults. ALWAYS prefer YOUR SKILLS when domain matches.
> Full skill descriptions → use the \`skill\` tool to check before EVERY delegation.`
  } else if (builtinSkills.length > 0) {
    skillsSection = `#### Available Skills (via \`skill\` tool)

**Built-in**: ${builtinNames}

> Full skill descriptions → use the \`skill\` tool to check before EVERY delegation.`
  } else {
    skillsSection = ""
  }

  return `### Category + Skills Delegation System

**task() combines categories and skills for optimal task execution.**

#### Available Categories (Domain-Optimized Models)

Each category is configured with a model optimized for that domain. Read the description to understand when to use it.

${categoryRows.join("\n")}

${skillsSection}

---

### MANDATORY: Category + Skill Selection Protocol

**STEP 1: Select Category**
- Read each category's description
- Match task requirements to category domain
- Select the category whose domain BEST fits the task

**STEP 2: Evaluate ALL Skills**
Check the \`skill\` tool for available skills and their descriptions. For EVERY skill, ask:
> "Does this skill's expertise domain overlap with my task?"

- If YES → INCLUDE in \`load_skills=[...]\`
- If NO → OMIT (no justification needed)
${customSkills.length > 0 ? `
> **User-installed skills get PRIORITY.** When in doubt, INCLUDE rather than omit.` : ""}

---

### Delegation Pattern

\`\`\`typescript
task(
  category="[selected-category]",
  load_skills=["skill-1", "skill-2"],  // Include ALL relevant skills — ESPECIALLY user-installed ones
  prompt="..."
)
\`\`\`

**ANTI-PATTERN (will produce poor results):**
\`\`\`typescript
task(category="...", load_skills=[], run_in_background=false, prompt="...")  // Empty load_skills without justification
\`\`\``
}

export function buildHardBlocksSection(): string {
  const blocks = [
    "- Type error suppression (`as any`, `@ts-ignore`) — **Never**",
    "- Commit without explicit request — **Never**",
    "- Speculate about unread code — **Never**",
    "- Leave code in broken state after failures — **Never**",
    "- `background_cancel(all=true)` — **Never.** Always cancel individually by taskId.",
  ]

  return `## Hard Blocks (NEVER violate)

${blocks.join("\n")}`
}

export function buildAntiPatternsSection(): string {
  const patterns = [
    "- **Type Safety**: `as any`, `@ts-ignore`, `@ts-expect-error`",
    "- **Error Handling**: Empty catch blocks `catch(e) {}`",
    "- **Testing**: Deleting failing tests to \"pass\"",
    "- **Search**: Firing agents for single-line typos or obvious syntax errors",
    "- **Debugging**: Shotgun debugging, random changes",
    "- **Background Tasks**: Polling `background_output` on running tasks — end response and wait for notification",
  ]

  return `## Anti-Patterns (BLOCKING violations)

${patterns.join("\n")}`
}

export function buildNonClaudePlannerSection(model: string): string {
  const isNonClaude = !model.toLowerCase().includes('claude')
  if (!isNonClaude) return ""

  return `### Plan Agent Dependency (Non-Claude)

Multi-step task? **ALWAYS consult Plan Agent first.** Do NOT start implementation without a plan.

- Single-file fix or trivial change → proceed directly
- Anything else (2+ steps, unclear scope, architecture) → \`task(subagent_type="plan", ...)\` FIRST
- Use \`session_id\` to resume the same Plan Agent — ask follow-up questions aggressively
- If ANY part of the task is ambiguous, ask Plan Agent before guessing

Plan Agent returns a structured work breakdown with parallel execution opportunities. Follow it.`
}

export function buildDeepParallelSection(model: string, categories: AvailableCategory[]): string {
  const isNonClaude = !model.toLowerCase().includes('claude')
  const hasDeepCategory = categories.some(c => c.name === 'deep')

  if (!isNonClaude || !hasDeepCategory) return ""

  return `### Deep Parallel Delegation

Delegate EVERY independent unit to a \`deep\` agent in parallel (\`run_in_background=true\`).
If a task decomposes into 4 independent units, spawn 4 agents simultaneously — not 1 at a time.

1. Decompose the implementation into independent work units
2. Assign one \`deep\` agent per unit — all via \`run_in_background=true\`
3. Give each agent a clear GOAL with success criteria, not step-by-step instructions
4. Collect all results, integrate, verify coherence across units`
}

export function buildUltraworkSection(
  agents: AvailableAgent[],
  categories: AvailableCategory[],
  skills: AvailableSkill[]
): string {
  const lines: string[] = []

  if (categories.length > 0) {
    lines.push("**Categories** (for implementation tasks):")
    for (const cat of categories) {
      const shortDesc = cat.description || cat.name
      lines.push(`- \`${cat.name}\`: ${shortDesc}`)
    }
    lines.push("")
  }

  if (skills.length > 0) {
    const builtinSkills = skills.filter((s) => s.location === "plugin")
    const customSkills = skills.filter((s) => s.location !== "plugin")

    if (builtinSkills.length > 0) {
      lines.push("**Built-in Skills** (combine with categories):")
      for (const skill of builtinSkills) {
        const shortDesc = skill.description.split(".")[0] || skill.description
        lines.push(`- \`${skill.name}\`: ${shortDesc}`)
      }
      lines.push("")
    }

    if (customSkills.length > 0) {
      lines.push("**User-Installed Skills** (HIGH PRIORITY - user installed these for their workflow):")
      for (const skill of customSkills) {
        const shortDesc = skill.description.split(".")[0] || skill.description
        lines.push(`- \`${skill.name}\`: ${shortDesc}`)
      }
      lines.push("")
    }
  }

  if (agents.length > 0) {
    lines.push("**Agents** (for specialized consultation/exploration):")
    for (const agent of agents) {
      const shortDesc = agent.description.length > 120 ? agent.description.slice(0, 120) + "..." : agent.description
      lines.push(`- \`${agent.name}\`: ${shortDesc}`)
    }
  }

  return lines.join("\n")
}
