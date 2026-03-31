import { getAgentDisplayName } from "../shared/agent-display-names";

// 显示用 key（已经过 remapAgentKeysToDisplayNames）里，要优先展示的核心诊断 Agent。
// 要求：Fuxi 最前，然后 Dayu / Kuafu / Baize，所有 plan / build 相关的放在最后。
const CORE_FIRST_ORDER: string[] = [
  getAgentDisplayName("fuxi"),
  getAgentDisplayName("xuanyuan"),
  getAgentDisplayName("dayu"),
  getAgentDisplayName("kuafu"),
  getAgentDisplayName("baize"),
];

// 一组典型的 plan/build 样式 key，用于精确匹配。
const PLAN_BUILD_KEYS = ["plan", "build", "OpenCode-Builder"];

const isPlanOrBuildKey = (key: string): boolean => {
  const lower = key.toLowerCase();
  if (PLAN_BUILD_KEYS.some((k) => k.toLowerCase() === lower)) return true;

  // 宽松匹配：名字里包含 plan / build / builder 的，都视为「规划 / 构建」类 Agent。
  return (
    lower.includes("plan") ||
    lower.includes("build") ||
    lower.includes("builder")
  );
};

export function reorderAgentsByPriority(
  agents: Record<string, unknown>,
): Record<string, unknown> {
  const ordered: Record<string, unknown> = {};
  const seen = new Set<string>();

  // 1）核心诊断 Agent 优先（Fuxi / Dayu / Kuafu / Baize）
  for (const key of CORE_FIRST_ORDER) {
    if (!key) continue;
    if (Object.prototype.hasOwnProperty.call(agents, key)) {
      ordered[key] = agents[key];
      seen.add(key);
    }
  }

  // 2）普通 Agent（排除 plan/build 类），保持原来的出现顺序
  for (const [key, value] of Object.entries(agents)) {
    if (seen.has(key)) continue;
    if (isPlanOrBuildKey(key)) continue;
    ordered[key] = value;
    seen.add(key);
  }

  // 3）最后把所有 plan/build 相关 Agent 统一追加在末尾（也是按原顺序）
  for (const [key, value] of Object.entries(agents)) {
    if (seen.has(key)) continue;
    if (!isPlanOrBuildKey(key)) continue;
    ordered[key] = value;
    seen.add(key);
  }

  return ordered;
}
