import * as z from "zod"
import { wittyConfigSchema } from "../src/witty/config/schema"

export function createWittyDiagnosisAgentJsonSchema(): Record<string, unknown> {
  const jsonSchema = z.toJSONSchema(wittyConfigSchema, {
    target: "draft-7",
    unrepresentable: "any",
  })

  return {
    $schema: "http://json-schema.org/draft-07/schema#",
    $id: "https://raw.gitcode.com/openeuler/witty-diagnosis-agent/raw/master/assets/witty-diagnosis-agent.schema.json",
    title: "Witty Diagnosis Agent Configuration",
    description: "Configuration schema for witty-diagnosis-agent plugin",
    ...jsonSchema,
  }
}
