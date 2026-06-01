import { promises as fsPromises } from "fs";
import { chmodSync, existsSync, mkdirSync, unlinkSync } from "node:fs";
import * as path from "node:path";
import { spawn } from "node:child_process";
import { extractZip } from "./zip-extractor";

export function getCachedBinaryPath(cacheDir: string, binaryName: string): string | null {
  const binaryPath = path.join(cacheDir, binaryName);
  return existsSync(binaryPath) ? binaryPath : null;
}

export function ensureCacheDir(cacheDir: string): void {
  if (!existsSync(cacheDir)) {
    mkdirSync(cacheDir, { recursive: true });
  }
}

export async function downloadArchive(downloadUrl: string, archivePath: string): Promise<void> {
  const response = await fetch(downloadUrl, { redirect: "follow" });
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${response.statusText}`);
  }

  const arrayBuffer = await response.arrayBuffer();
  await fsPromises.writeFile(archivePath, Buffer.from(arrayBuffer));
}

export async function extractTarGz(
  archivePath: string,
  destDir: string,
  options?: { args?: string[]; cwd?: string }
): Promise<void> {
  const args = options?.args ?? ["tar", "-xzf", archivePath, "-C", destDir];
  const [cmd, ...cmdArgs] = args;
  const proc = spawn(cmd, cmdArgs, {
    cwd: options?.cwd,
    stdio: ["pipe", "pipe", "pipe"],
  });

  const exitCode = await new Promise<number | null>((resolve) => proc.on("exit", resolve));
  if (exitCode !== 0) {
    const stderr = await new Promise<string>((resolve) => {
      let data = "";
      proc.stderr?.on("data", (chunk) => data += chunk);
      proc.stderr?.on("end", () => resolve(data));
    });
    throw new Error(`tar extraction failed (exit ${exitCode}): ${stderr}`);
  }
}

export async function extractZipArchive(archivePath: string, destDir: string): Promise<void> {
  await extractZip(archivePath, destDir);
}

export function cleanupArchive(archivePath: string): void {
  if (existsSync(archivePath)) {
    unlinkSync(archivePath);
  }
}

export function ensureExecutable(binaryPath: string): void {
  if (process.platform !== "win32" && existsSync(binaryPath)) {
    chmodSync(binaryPath, 0o755);
  }
}
