#!/usr/bin/env bun
// script/build-binaries.ts
// Build platform-specific binaries for CLI distribution

import { $ } from "bun";
import { existsSync, mkdirSync, writeFileSync, readFileSync } from "node:fs";
import { join } from "node:path";

interface PlatformTarget {
  dir: string;
  target: string;
  binary: string;
  description: string;
  pkgName: string;
}

const PKG_ROOT = process.cwd();
const PKG_JSON = JSON.parse(readFileSync(join(PKG_ROOT, "package.json"), "utf-8"));
const VERSION = PKG_JSON.version;

export const PLATFORMS: PlatformTarget[] = [
  { dir: "darwin-arm64", target: "bun-darwin-arm64", binary: "witty-diagnosis-agent", description: "macOS ARM64", pkgName: "witty-diagnosis-agent-darwin-arm64" },
  { dir: "darwin-x64", target: "bun-darwin-x64", binary: "witty-diagnosis-agent", description: "macOS x64", pkgName: "witty-diagnosis-agent-darwin-x64" },
  { dir: "linux-x64", target: "bun-linux-x64", binary: "witty-diagnosis-agent", description: "Linux x64 (glibc)", pkgName: "witty-diagnosis-agent-linux-x64" },
  { dir: "windows-x64", target: "bun-windows-x64", binary: "witty-diagnosis-agent.exe", description: "Windows x64", pkgName: "witty-diagnosis-agent-windows-x64" },
];

const ENTRY_POINT = "src/cli/index.ts";

async function buildPlatform(platform: PlatformTarget): Promise<boolean> {
  const pkgDir = join("packages", platform.dir);
  const binDir = join(pkgDir, "bin");
  const outfile = join(binDir, platform.binary);

  console.log(`\n📦 Building ${platform.description}...`);
  console.log(`   Target: ${platform.target}`);
  console.log(`   Output: ${outfile}`);

  try {
    // Ensure directories exist
    mkdirSync(binDir, { recursive: true });

    await $`bun build --compile --minify --sourcemap --bytecode --target=${platform.target} ${ENTRY_POINT} --outfile=${outfile}`;

    // Copy skills directory to platform package
    const skillsSrc = join(PKG_ROOT, "skills");
    const skillsDest = join(pkgDir, "skills");
    if (existsSync(skillsSrc)) {
      console.log(`   📂 Copying skills to ${skillsDest}...`);
      await $`cp -r ${skillsSrc} ${pkgDir}`;
    }

    // Verify binary exists
    if (!existsSync(outfile)) {
      console.error(`   ❌ Binary not found after build: ${outfile}`);
      return false;
    }

    // Generate package.json for the platform package
    const pkgJson = {
      name: platform.pkgName,
      version: VERSION,
      description: `Witty Diagnosis Agent binary for ${platform.description}`,
      os: [platform.dir.split("-")[0] === "windows" ? "win32" : platform.dir.split("-")[0]],
      cpu: [platform.dir.split("-")[1]],
      main: `bin/${platform.binary}`,
      bin: {
        "witty-diagnosis-agent": `bin/${platform.binary}`
      },
      files: [
        "bin",
        "skills"
      ],
      license: "MIT",
      repository: {
        type: "git",
        url: "git+https://github.com/witty-integration/witty-diagnosis-agent.git"
      }
    };

    writeFileSync(join(pkgDir, "package.json"), JSON.stringify(pkgJson, null, 2));

    // Generate README.md
    const readme = `# ${platform.pkgName}

This is the platform-specific binary package for Witty Diagnosis Agent on ${platform.description}.

It is intended to be used as an optional dependency of the main \`witty-diagnosis-agent\` package.
`;
    writeFileSync(join(pkgDir, "README.md"), readme);

    // Verify binary with file command (skip on Windows host for non-Windows targets)
    if (process.platform !== "win32") {
      const fileInfo = await $`file ${outfile}`.text();
      console.log(`   ✓ ${fileInfo.trim()}`);
    } else {
      console.log(`   ✓ Binary created successfully`);
    }

    return true;
  } catch (error) {
    console.error(`   ❌ Build failed: ${error}`);
    return false;
  }
}

async function main() {
  console.log("🔨 Building witty-diagnosis-agent platform binaries");
  console.log(`   Entry point: ${ENTRY_POINT}`);
  console.log(`   Platforms: ${PLATFORMS.length}`);
  console.log(`   Version: ${VERSION}`);

  // Verify entry point exists
  if (!existsSync(ENTRY_POINT)) {
    console.error(`\n❌ Entry point not found: ${ENTRY_POINT}`);
    process.exit(1);
  }

  const results: { platform: string; success: boolean }[] = [];

  for (const platform of PLATFORMS) {
    const success = await buildPlatform(platform);
    results.push({ platform: platform.description, success });
  }

  // Summary
  console.log("\n" + "=".repeat(50));
  console.log("Build Summary:");
  console.log("=".repeat(50));

  const succeeded = results.filter(r => r.success).length;
  const failed = results.filter(r => !r.success).length;

  for (const result of results) {
    const icon = result.success ? "✓" : "✗";
    console.log(`  ${icon} ${result.platform}`);
  }

  console.log("=".repeat(50));
  console.log(`Total: ${succeeded} succeeded, ${failed} failed`);

  if (failed > 0) {
    process.exit(1);
  }

  console.log("\n✅ All platform binaries built successfully!\n");
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
