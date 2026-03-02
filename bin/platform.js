// bin/platform.js
// Shared platform detection module

export function getPlatformPackage({ platform, arch }) {
  // Map platform names: win32 -> windows (for package name)
  const os = platform === "win32" ? "windows" : platform;
  return `witty-diagnosis-agent-${os}-${arch}`;
}

export function getBinaryPath(pkg, platform) {
  const ext = platform === "win32" ? ".exe" : "";
  return `${pkg}/bin/witty-diagnosis-agent${ext}`;
}
