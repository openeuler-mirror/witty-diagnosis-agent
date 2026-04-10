export const AGENT_NAME_MAP: Record<string, string> = {
  fuxi: "fuxi",
  Fuxi: "fuxi",
  "fuxi-sub": "fuxi-sub",
  "Fuxi-Sub": "fuxi-sub",

  xuanyuan: "xuanyuan",
  Xuanyuan: "xuanyuan",

  dayu: "dayu",
  Dayu: "dayu",

  baize: "baize",
  Baize: "baize",

  kuafu: "kuafu",
  Kuafu: "kuafu",
  
  nuwa: "nuwa",
  Nuwa: "nuwa",
  "nuwa-sub": "nuwa-sub",
  "Nuwa-Sub": "nuwa-sub",

  build: "build",
  "multimodal-looker": "multimodal-looker",
}

export const BUILTIN_AGENT_NAMES = new Set([
  "multimodal-looker",
  "xuanyuan",
  "fuxi",
  "fuxi-sub",
  "dayu",
  "kuafu",
  "nuwa",
  "nuwa-sub",
  "build",
])

export function migrateAgentNames(
  agents: Record<string, unknown>
): { migrated: Record<string, unknown>; changed: boolean } {
  const migrated: Record<string, unknown> = {}
  let changed = false

  for (const [key, value] of Object.entries(agents)) {
    const newKey = AGENT_NAME_MAP[key.toLowerCase()] ?? AGENT_NAME_MAP[key] ?? key
    if (newKey !== key) {
      changed = true
    }
    migrated[newKey] = value
  }

  return { migrated, changed }
}
