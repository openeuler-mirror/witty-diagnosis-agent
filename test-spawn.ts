import { spawnWithWindowsHide } from "./src/shared/spawn-with-windows-hide.ts"
console.log("testing spawn");
try {
  const proc = spawnWithWindowsHide(["node", "--version"], { stdout: "pipe" });
  proc.exited.then((code) => {
    console.log("exit code", code);
  });
  console.log("spawned!");
} catch (e) {
  console.error("error!", e);
}
