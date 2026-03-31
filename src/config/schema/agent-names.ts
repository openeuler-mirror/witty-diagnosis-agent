import { z } from "zod"

export const BuiltinAgentNameSchema = z.enum([
  "baize",
  "xuanyuan",
  "fuxi",
  "dayu",
  "kuafu",
  "multimodal-looker",
])

export const BuiltinSkillNameSchema = z.enum([
  "playwright",
  "agent-browser",
  "dev-browser",
  "frontend-ui-ux",
  "git-master",
])

export const OverridableAgentNameSchema = z.enum([
  "build",
  "plan",
  "baize",
  "xuanyuan",
  "fuxi",
  "dayu",
  "kuafu",
  "multimodal-looker",
])

export const AgentNameSchema = BuiltinAgentNameSchema
export type AgentName = z.infer<typeof AgentNameSchema>

export type BuiltinSkillName = z.infer<typeof BuiltinSkillNameSchema>
