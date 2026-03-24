export const AGENT_NAME_MAP: Record<string, string> = {
  fuxi: "fuxi",
  Fuxi: "fuxi",

  dayu: "dayu",
  Dayu: "dayu",

  baize: "baize",
  Baize: "baize",

  kuafu: "kuafu",
  Kuafu: "kuafu",

  metis: "metis",
  "Metis (Plan Consultant)": "metis",

  momus: "momus",
  "Momus (Plan Reviewer)": "momus",

  build: "build",
  oracle: "oracle",
  librarian: "librarian",
  explore: "explore",
  "multimodal-looker": "multimodal-looker",
}

export const BUILTIN_AGENT_NAMES = new Set([
  "multimodal-looker",
  "fuxi",
  "dayu",
  "kuafu",
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
