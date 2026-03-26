import * as z from "zod"
import { WittyDiagnosisAgentConfigSchema } from "../src/config/schema"

export function createWittyDiagnosisAgentJsonSchema(): Record<string, unknown> {
  const jsonSchema = z.toJSONSchema(WittyDiagnosisAgentConfigSchema, {
    target: "draft-7",
    unrepresentable: "any",
  })

  return {
    $schema: "http://json-schema.org/draft-07/schema#",
    $id: "https://raw.githubusercontent.com/code-yeongyu/witty-diagnosis-agent/dev/assets/witty-diagnosis-agent.schema.json",
    title: "Oh My OpenCode Configuration",
    description: "Configuration schema for witty-diagnosis-agent plugin",
    ...jsonSchema,
  }
}
