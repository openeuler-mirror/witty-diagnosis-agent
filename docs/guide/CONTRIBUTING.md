# 扩展开发指南 (Extension Development Guide)

**Witty Diagnosis Agent** 采用模块化设计，支持开发者通过编写 **Skill** (技能) 来扩展其能力。

## 什么是 Skill？

Skill 是 Agent 的原子能力单元。一个 Skill 可以封装一个 Shell 命令、一个 Python 脚本、一次 API 调用，甚至是一段复杂的逻辑。

例如：
- `check_cpu_usage`: 封装 `top` 命令。
- `analyze_mysql_slow_log`: 封装对 MySQL 慢查询日志的解析逻辑。

## 开发流程

### 1. 创建 Skill 目录
在 `skills/` 目录下创建一个新的子目录，例如 `skills/my-custom-skill/`。

### 2. 定义 Skill 元数据 (skill.yaml)
每个 Skill 必须包含一个 `skill.yaml` 文件，描述其输入、输出和用途。

```yaml
name: check_disk_usage
description: 检查磁盘空间使用率
version: 1.0.0
inputs:
  path:
    type: string
    description: 要检查的目录路径，默认为 /
    required: false
outputs:
  usage:
    type: string
    description: 磁盘使用率百分比
```

### 3. 实现执行逻辑 (index.ts / script.py)
您可以选择使用 TypeScript 或 Python/Shell 实现具体逻辑。

**TypeScript 示例 (index.ts):**

```typescript
import { SkillContext } from '@witty/sdk';

export async function run(ctx: SkillContext) {
  const path = ctx.inputs.path || '/';
  // 执行 df -h 命令
  const result = await ctx.exec(`df -h ${path}`);
  return { usage: parseDfOutput(result.stdout) };
}
```

### 4. 注册 Skill
在 `src/skills/registry.ts` 中注册您的新 Skill，使其对 Agent 可见。

## 最佳实践

1.  **原子性**: 一个 Skill 只做一件事，保持功能单一。
2.  **鲁棒性**: 处理好各种异常情况（如命令不存在、权限不足）。
3.  **标准化输出**: 尽量返回结构化的 JSON 数据，便于下游 Agent 解析。
4.  **无状态**: Skill 应尽量设计为无状态的，不依赖外部持久化存储。

## 调试与测试

您可以使用 CLI 工具单独测试 Skill：

```bash
# 测试 Skill
witty-cli run-skill check_disk_usage --path /home
```

更多详细 API 文档，请参考 [SDK Reference](../reference/sdk.md)。
