import * as z from "zod"
import { WittyDiagnosisAgentConfigSchema } from "../src/config/schema"

export function createWittyDiagnosisAgentJsonSchema(): Record<string, unknown> {
  const jsonSchema = z.toJSONSchema(WittyDiagnosisAgentConfigSchema, {
    target: "draft-7",
    unrepresentable: "any",
  })

  return {
    $schema: "http://json-schema.org/draft-07/schema#",
    $id: "https://raw.githubusercontent.com/witty-diagnosis-agent/witty-diagnosis-agent/main/assets/witty-diagnosis-agent.schema.json",
    title: "Witty Diagnosis Agent Configuration",
    description: "JSON Schema for ~/.witty-diagnosis-agent/config.json",
    ...jsonSchema,
  }
}
