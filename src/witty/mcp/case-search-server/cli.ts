#!/usr/bin/env node
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js"
import { loadCaseSearchConfig } from "./config"
import { CaseSearchClient } from "./client"
import { createCaseSearchServer } from "./index"

/**
 * stdio entry point for the case-search MCP server.
 *
 * Launched by OpenCode via:
 *   command: ["node", "dist/mcp/case-search-server/cli.js"]
 */
async function main(): Promise<void> {
  const config = loadCaseSearchConfig()
  const client = new CaseSearchClient(config)
  const server = createCaseSearchServer(client)
  const transport = new StdioServerTransport()
  await server.connect(transport)
}

main().catch((err) => {
  console.error("[case-search-mcp] fatal:", err)
  process.exit(1)
})
