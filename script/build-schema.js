#!/usr/bin/env bun
import { createWittyDiagnosisAgentJsonSchema } from "./build-schema-document";
const SCHEMA_OUTPUT_PATH = "assets/witty-diagnosis-agent.schema.json";
const DIST_SCHEMA_OUTPUT_PATH = "dist/witty-diagnosis-agent.schema.json";
async function main() {
    console.log("Generating JSON Schema...");
    const finalSchema = createWittyDiagnosisAgentJsonSchema();
    await Bun.write(SCHEMA_OUTPUT_PATH, JSON.stringify(finalSchema, null, 2));
    await Bun.write(DIST_SCHEMA_OUTPUT_PATH, JSON.stringify(finalSchema, null, 2));
    console.log(`✓ JSON Schema generated: ${SCHEMA_OUTPUT_PATH}`);
}
main();
