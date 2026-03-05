#!/usr/bin/env node
// bin/witty-diagnosis-agent.js
// Wrapper script that detects platform and spawns the correct binary

import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));

function main() {
  const { platform, arch } = process;
  const os = platform === "win32" ? "windows" : platform;

  // Construct path to locally built binary
  const binaryPath = resolve(__dirname, `../packages/${os}-${arch}/bin/witty-diagnosis-agent${platform === "win32" ? ".exe" : ""}`);

  if (existsSync(binaryPath)) {
    const result = spawnSync(binaryPath, process.argv.slice(2), {
      stdio: "inherit",
    });
    process.exit(result.status ?? 0);
    return;
  }

  console.error("❌ Unsupported platform or missing binary.");
  console.error(`   witty-diagnosis-agent does not have a binary for ${os}-${arch}`);
  console.error(`   Looked for binary at: ${binaryPath}`);
  process.exit(1);
}

main();
