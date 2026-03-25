#!/usr/bin/env bun
import fs from "node:fs"
import { createOhMyOpenCodeJsonSchema } from "./build-schema-document"

const SCHEMA_OUTPUT_PATH = "assets/witty-diagnosis-agent.schema.json"
const DIST_SCHEMA_OUTPUT_PATH = "dist/witty-diagnosis-agent.schema.json"

async function main() {
  console.log("Generating JSON Schema...")

  const finalSchema = createOhMyOpenCodeJsonSchema()

  fs.writeFileSync(SCHEMA_OUTPUT_PATH, JSON.stringify(finalSchema, null, 2))
  fs.writeFileSync(DIST_SCHEMA_OUTPUT_PATH, JSON.stringify(finalSchema, null, 2))

  console.log(`✓ JSON Schema generated: ${SCHEMA_OUTPUT_PATH}`)
}

main()
