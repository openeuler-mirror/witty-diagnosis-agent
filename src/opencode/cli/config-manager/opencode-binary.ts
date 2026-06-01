import { join } from "node:path"
import { homedir } from "node:os"
import type { OpenCodeBinaryType } from "../../shared/opencode-config-dir-types"
import { spawnWithWindowsHide } from "../../shared/spawn-with-windows-hide"
import { initConfigContext } from "./config-context"

const OPENCODE_BINARIES = ["opencode", "opencode-desktop"] as const

interface OpenCodeBinaryResult {
  binary: OpenCodeBinaryType
  version: string
}

function getFallbackPaths(binaryName: string): string[] {
  const isWindows = process.platform === "win32"
  const bin = isWindows ? `${binaryName}.cmd` : binaryName
  const exe = isWindows ? `${binaryName}.exe` : binaryName

  if (isWindows) {
    return [
      join(process.env.APPDATA || "", "npm", bin),
      join(process.env.USERPROFILE || "", ".opencode", "bin", exe),
    ]
  }

  return [
    join(homedir(), ".opencode", "bin", bin),
    join(homedir(), ".npm-global", "bin", bin),
    join("/usr/local/bin", bin),
    join("/opt/homebrew/bin", bin),
  ]
}

async function findOpenCodeBinaryWithVersion(): Promise<OpenCodeBinaryResult | null> {
  for (const binary of OPENCODE_BINARIES) {
    const pathsToCheck = [binary, ...getFallbackPaths(binary)]
    for (const binPath of pathsToCheck) {
      try {
        const proc = spawnWithWindowsHide([binPath, "--version"], {
          stdout: "pipe",
          stderr: "pipe",
        })
        const output = await new Response(proc.stdout).text()
        await proc.exited
        if (proc.exitCode === 0) {
          const version = output.trim()
          initConfigContext(binary, version)
          return { binary, version }
        }
      } catch {
        continue
      }
    }
  }
  return null
}

export async function isOpenCodeInstalled(): Promise<boolean> {
  const result = await findOpenCodeBinaryWithVersion()
  return result !== null
}

export async function getOpenCodeVersion(): Promise<string | null> {
  const result = await findOpenCodeBinaryWithVersion()
  return result?.version ?? null
}
