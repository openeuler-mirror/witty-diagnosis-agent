import { z } from "zod"

/**
 * WittyConfig 的 Zod schema。
 *
 * 这是配置校验与 assets/witty-diagnosis-agent.schema.json 生成的唯一来源
 * （由 script/build-schema.ts 调用）。
 */

export const agentOverrideSchema = z.object({
  model: z.string().optional(),
  disable: z.boolean().optional(),
  extra_instructions: z.string().optional(),
})

export const reportConfigSchema = z.object({
  output_dir: z.string().default("baize/reports"),
  formats: z.array(z.enum(["md", "html"])).default(["md", "html"]),
})

export const guardsConfigSchema = z.object({
  md_only: z.boolean().default(true),
  output_truncate_chars: z.number().int().min(0).default(30000),
  compaction_preserve: z.boolean().default(true),
})

export const orchestrationConfigSchema = z.object({
  max_parallel_subagents: z.number().int().min(1).max(8).default(2),
  subagent_timeout_minutes: z.number().int().min(1).default(30),
})

export const notificationConfigSchema = z.object({
  enabled: z.boolean().default(false),
})

export const wittyConfigSchema = z.object({
  $schema: z.string().optional(),
  output_language: z.enum(["zh", "en"]).default("zh"),
  agents: z.record(z.string(), agentOverrideSchema).default({}),
  disabled_agents: z.array(z.string()).default([]),
  skills_dir: z.string().default("skills"),
  report: reportConfigSchema.prefault({}),
  guards: guardsConfigSchema.prefault({}),
  orchestration: orchestrationConfigSchema.prefault({}),
  notification: notificationConfigSchema.prefault({}),
})

export type WittyConfigInput = z.input<typeof wittyConfigSchema>
export type WittyConfigOutput = z.output<typeof wittyConfigSchema>
