import { describe, it, expect, beforeEach, afterEach } from "bun:test";
import { join } from "node:path";
import { existsSync, writeFileSync, mkdirSync, rmSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

const TEST_DIR = join(process.cwd(), "test_temp");
// Code uses join(XDG_CONFIG_HOME, "opencode")
const OPENCODE_CONFIG_DIR = join(TEST_DIR, "opencode");
const OPENCODE_CONFIG_PATH = join(OPENCODE_CONFIG_DIR, "config.json");

describe("Installation Process", () => {
  beforeEach(() => {
    if (existsSync(TEST_DIR)) {
      rmSync(TEST_DIR, { recursive: true, force: true });
    }
    mkdirSync(OPENCODE_CONFIG_DIR, { recursive: true });
    writeFileSync(OPENCODE_CONFIG_PATH, JSON.stringify({ plugins: [] }, null, 2));
  });

  afterEach(() => {
    if (existsSync(TEST_DIR)) {
      rmSync(TEST_DIR, { recursive: true, force: true });
    }
    // Clean up local config if created
    if (existsSync("witty-diagnosis.jsonc")) {
        rmSync("witty-diagnosis.jsonc");
    }
  });

  it("should install successfully in CLI mode", () => {
    const binPath = join(process.cwd(), "bin", "witty-diagnosis-agent.js");
    
    // Set XDG_CONFIG_HOME to TEST_DIR
    const env = { ...process.env, XDG_CONFIG_HOME: TEST_DIR };

    const result = spawnSync("bun", [binPath, "install", "--no-tui"], {
      env,
      encoding: "utf-8",
    });

    if (result.status !== 0) {
        console.error("Test failed stdout:", result.stdout);
        console.error("Test failed stderr:", result.stderr);
    }

    expect(result.status).toBe(0);
    expect(result.stdout).toContain("Installation Complete");

    // Verify config update
    const configContent = JSON.parse(readFileSync(OPENCODE_CONFIG_PATH, "utf-8"));
    expect(configContent.plugins).toContain("witty-diagnosis-agent@latest");

    // Verify local config creation
    expect(existsSync("witty-diagnosis.jsonc")).toBe(true);
  });
  
  it("should create OpenCode config if missing", () => {
      // Remove config file
      rmSync(OPENCODE_CONFIG_PATH);
      
      const binPath = join(process.cwd(), "bin", "witty-diagnosis-agent.js");
      const env = { ...process.env, XDG_CONFIG_HOME: TEST_DIR };
  
      const result = spawnSync("bun", [binPath, "install", "--no-tui"], {
        env,
        encoding: "utf-8",
      });
  
      expect(result.status).toBe(0);
      expect(result.stdout).toContain("Installation Complete");
      
      // Verify config was created
      expect(existsSync(OPENCODE_CONFIG_PATH)).toBe(true);
      const configContent = JSON.parse(readFileSync(OPENCODE_CONFIG_PATH, "utf-8"));
      expect(configContent.plugins).toContain("witty-diagnosis-agent@latest");
  });
});
