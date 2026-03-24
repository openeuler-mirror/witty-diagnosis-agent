import { z } from "zod"

export const BuiltinAgentNameSchema = z.enum([
  "baize",
  "fuxi",
  "dayu",
  "kuafu",
  "oracle",
  "librarian",
  "explore",
  "multimodal-looker",
  "metis",
  "momus",
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
  "sisyphus",
  "baize",
  "sisyphus-junior",
  "OpenCode-Builder",
  "fuxi",
  "dayu",
  "kuafu",
  "multimodal-looker",
])

export const AgentNameSchema = BuiltinAgentNameSchema
export type AgentName = z.infer<typeof AgentNameSchema>

export type BuiltinSkillName = z.infer<typeof BuiltinSkillNameSchema>
