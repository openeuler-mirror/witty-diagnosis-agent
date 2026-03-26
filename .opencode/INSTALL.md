# Installing witty-diagnosis-agent for OpenCode

## Prerequisites

- [OpenCode.ai](https://opencode.ai) installed
- Git installed

## Installation Steps

### 1. Clone witty-diagnosis-agent

```bash
git clone https://gitcode.com/openeuler/witty-diagnosis-agent.git ~/.config/opencode/witty-diagnosis-agent
```

### 2. Register the Plugin

Create a symlink so OpenCode discovers the plugin:

```bash
mkdir -p ~/.config/opencode/plugins
rm -f ~/.config/opencode/plugins/witty-diagnosis-agent.js
ln -s ~/.config/opencode/witty-diagnosis-agent/.opencode/plugins/witty-diagnosis-agent.js ~/.config/opencode/plugins/witty-diagnosis-agent.js
```

### 3. Symlink Skills

Create a symlink so OpenCode's native skill tool discovers witty-diagnosis-agent skills:

```bash
mkdir -p ~/.config/opencode/skills
rm -rf ~/.config/opencode/skills/witty-diagnosis-agent
ln -s ~/.config/opencode/witty-diagnosis-agent/skills ~/.config/opencode/skills/witty-diagnosis-agent
```

### 4. Restart OpenCode

Restart OpenCode. The plugin will automatically inject witty-diagnosis-agent context.

Verify by asking: "do you have witty-diagnosis-agent skills?"

## Usage

### Finding Skills

Use OpenCode's native `skill` tool to list available skills:

```
use skill tool to list skills
```

### Loading a Skill

Use OpenCode's native `skill` tool to load a specific skill:

```
use skill tool to load witty-diagnosis-agent/data-collector
```

### Personal Skills

Create your own skills in `~/.config/opencode/skills/`:

```bash
mkdir -p ~/.config/opencode/skills/my-skill
```

Create `~/.config/opencode/skills/my-skill/SKILL.md`:

```markdown
---
name: my-skill
description: Use when [condition] - [what it does]
---

# My Skill

[Your skill content here]
```

### Project Skills

Create project-specific skills in `.opencode/skills/` within your project.

**Skill Priority:** Project skills > Personal skills > witty-diagnosis-agent skills

## Updating

```bash
cd ~/.config/opencode/witty-diagnosis-agent
git pull
```

## Troubleshooting

### Plugin not loading

1. Check plugin symlink: `ls -l ~/.config/opencode/plugins/witty-diagnosis-agent.js`
2. Check source exists: `ls ~/.config/opencode/witty-diagnosis-agent/.opencode/plugins/witty-diagnosis-agent.js`
3. Check OpenCode logs for errors

### Skills not found

1. Check skills symlink: `ls -l ~/.config/opencode/skills/witty-diagnosis-agent`
2. Verify it points to: `~/.config/opencode/witty-diagnosis-agent/skills`
3. Use `skill` tool to list what's discovered

### Tool mapping

When skills reference Claude Code tools:
- `TodoWrite` → `update_plan`
- `Task` with subagents → `@mention` syntax
- `Skill` tool → OpenCode's native `skill` tool
- File operations → your native tools

## Getting Help

- Report issues: https://gitcode.com/openeuler/witty-diagnosis-agent/issues
- Full documentation: https://gitcode.com/openeuler/witty-diagnosis-agent#readme