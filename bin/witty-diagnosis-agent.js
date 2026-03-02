#!/usr/bin/env node
// bin/witty-diagnosis-agent.js
// Wrapper script that detects platform and spawns the correct binary

import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));

function main() {
  // Check if we are running from source (development mode)
  const distEntry = resolve(__dirname, "../dist/cli/index.js");
  const srcEntry = resolve(__dirname, "../src/cli/index.ts");

  // If bun is available, we prefer running the source or dist with bun
  const hasBun = spawnSync("bun", ["--version"]).status === 0;

  if (hasBun && (existsSync(srcEntry) || existsSync(distEntry))) {
    // Development mode: use Bun to run source or dist
    const entry = existsSync(srcEntry) ? srcEntry : distEntry;
    // console.log(`⚡ Running in development mode with Bun: ${entry}`);
    
    const result = spawnSync("bun", [entry, ...process.argv.slice(2)], {
      stdio: "inherit",
    });
    
    process.exit(result.status ?? 0);
    return;
  }

  // Production mode: try to find the binary
  // In a real scenario, we would look into node_modules for platform-specific packages
  // For this local setup, we check the locally built packages folder
  const { platform, arch } = process;
  const os = platform === "win32" ? "windows" : platform;
  
  // Construct path to locally built binary
  const binaryPath = resolve(__dirname, `../packages/${os}-${arch}/bin/witty-diagnosis-agent${platform === "win32" ? ".exe" : ""}`);
  
  if (existsSync(binaryPath)) {
    // console.log(`⚡ Running binary: ${binaryPath}`);
    const result = spawnSync(binaryPath, process.argv.slice(2), {
      stdio: "inherit",
    });
    process.exit(result.status ?? 0);
    return;
  }

  // Fallback to node if dist exists
  if (existsSync(distEntry)) {
    // console.log(`⚡ Fallback to Node.js: ${distEntry}`);
    const result = spawnSync("node", [distEntry, ...process.argv.slice(2)], {
      stdio: "inherit",
    });
    process.exit(result.status ?? 0);
    return;
  }

  console.error("❌ Could not find a way to run witty-diagnosis-agent.");
  console.error("   Please ensure you have built the project with 'bun run build'.");
  process.exit(1);
}

main();
