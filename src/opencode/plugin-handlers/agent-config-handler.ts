import { createBuiltinAgents } from "../agents";
import type { WittyDiagnosisAgentConfig } from "../config";
import { log, migrateAgentConfig } from "../shared";
import { AGENT_NAME_MAP } from "../shared/migration";
import { getAgentDisplayName } from "../shared/agent-display-names";
import {
  discoverConfigSourceSkills,
  discoverOpencodeGlobalSkills,
  discoverOpencodeProjectSkills,
  discoverProjectClaudeSkills,
  discoverUserClaudeSkills,
} from "../features/opencode-skill-loader";
import { loadProjectAgents, loadUserAgents } from "../features/claude-code-agent-loader";
import type { PluginComponents } from "./plugin-components-loader";
import { reorderAgentsByPriority } from "./agent-priority-order";
import { remapAgentKeysToDisplayNames } from "./agent-key-remapper";
import { applyUiAgentVisibility } from "./ui-agent-visibility";
import { buildFuxiAgentConfig } from "./fuxi-agent-config-builder";
import { buildFuxiSubAgentConfig } from "./fuxi-sub-agent-config-builder";
import { buildDayuAgentConfig } from "./dayu-agent-config-builder";
import { buildXuanyuanAgentConfig } from "./xuanyuan-agent-config-builder";
import { buildKuafuAgentConfig } from "./kuafu-agent-config-builder";
import { buildBaizeAgentConfig } from "./baize-agent-config-builder";
import { buildNuwaAgentConfig } from "./nuwa-agent-config-builder";
import { buildNuwaSubAgentConfig } from "./nuwa-sub-agent-config-builder";

type AgentConfigRecord = Record<string, Record<string, unknown> | undefined> & {
  build?: Record<string, unknown>;
  plan?: Record<string, unknown>;
};

function getConfiguredDefaultAgent(config: Record<string, unknown>): string | undefined {
  const defaultAgent = config.default_agent;
  if (typeof defaultAgent !== "string") return undefined;

  const trimmedDefaultAgent = defaultAgent.trim();
  return trimmedDefaultAgent.length > 0 ? trimmedDefaultAgent : undefined;
}

export async function applyAgentConfig(params: {
  config: Record<string, unknown>;
  pluginConfig: WittyDiagnosisAgentConfig;
  ctx: { directory: string; client?: any };
  pluginComponents: PluginComponents;
}): Promise<Record<string, unknown>> {
  const migratedDisabledAgents = (params.pluginConfig.disabled_agents ?? []).map(
    (agent) => {
      return AGENT_NAME_MAP[agent.toLowerCase()] ?? AGENT_NAME_MAP[agent] ?? agent;
    },
  ) as typeof params.pluginConfig.disabled_agents;

  const includeClaudeSkillsForAwareness = params.pluginConfig.claude_code?.skills ?? true;
  const [
    discoveredConfigSourceSkills,
    discoveredUserSkills,
    discoveredProjectSkills,
    discoveredOpencodeGlobalSkills,
    discoveredOpencodeProjectSkills,
  ] = await Promise.all([
    discoverConfigSourceSkills({
      config: params.pluginConfig.skills,
      configDir: params.ctx.directory,
    }),
    includeClaudeSkillsForAwareness ? discoverUserClaudeSkills() : Promise.resolve([]),
    includeClaudeSkillsForAwareness
       ? discoverProjectClaudeSkills(params.ctx.directory)
       : Promise.resolve([]),
    discoverOpencodeGlobalSkills(),
    discoverOpencodeProjectSkills(params.ctx.directory),
  ]);

  const allDiscoveredSkills = [
    ...discoveredConfigSourceSkills,
    ...discoveredOpencodeProjectSkills,
    ...discoveredProjectSkills,
    ...discoveredOpencodeGlobalSkills,
    ...discoveredUserSkills,
  ];

  const browserProvider =
    params.pluginConfig.browser_automation_engine?.provider ?? "playwright";
  const currentModel = params.config.model as string | undefined;
  const disabledSkills = new Set<string>(params.pluginConfig.disabled_skills ?? []);
  const useTaskSystem = params.pluginConfig.experimental?.task_system ?? false;
  const disableWittyEnv = params.pluginConfig.experimental?.disable_witty_env ?? false;

  const outputLanguage = params.pluginConfig.output_language ?? "zh";

  const builtinAgents = await createBuiltinAgents(
    migratedDisabledAgents,
    params.pluginConfig.agents,
    params.ctx.directory,
    currentModel,
    params.pluginConfig.categories,
    params.pluginConfig.git_master,
    allDiscoveredSkills,
    params.ctx.client,
    browserProvider,
    currentModel,
    disabledSkills,
    useTaskSystem,
    disableWittyEnv,
    outputLanguage
  );

  const includeClaudeAgents = params.pluginConfig.claude_code?.agents ?? true;
  const userAgents = includeClaudeAgents ? loadUserAgents() : {};
  const projectAgents = includeClaudeAgents ? loadProjectAgents(params.ctx.directory) : {};

  const rawPluginAgents = params.pluginComponents.agents;
  const pluginAgents = Object.fromEntries(
    Object.entries(rawPluginAgents).map(([key, value]) => [
      key,
      value ? migrateAgentConfig(value as Record<string, unknown>) : value,
    ]),
  );

  const disabledAgentNames = new Set(
    (migratedDisabledAgents ?? []).map(a => a.toLowerCase())
  );

  const filterDisabledAgents = (agents: Record<string, unknown>) =>
    Object.fromEntries(
      Object.entries(agents).filter(([name]) => !disabledAgentNames.has(name.toLowerCase()))
    );

  const plannerEnabled = true;
  const replacePlan = false;
  const shouldDemotePlan = plannerEnabled && replacePlan;
  const configuredDefaultAgent = getConfiguredDefaultAgent(params.config);

  const configAgent = params.config.agent as AgentConfigRecord | undefined;

  if (configuredDefaultAgent) {
    (params.config as { default_agent?: string }).default_agent =
      getAgentDisplayName(configuredDefaultAgent);
  } else {
    (params.config as { default_agent?: string }).default_agent =
      getAgentDisplayName("xuanyuan");
  }

  const agentConfig: Record<string, unknown> = {};

  if (plannerEnabled) {
    const fuxiOverride = params.pluginConfig.agents?.["fuxi"] as
      | (Record<string, unknown> & { prompt_append?: string })
      | undefined;

    agentConfig["fuxi"] = await buildFuxiAgentConfig({
      configAgentPlan: configAgent?.plan,
      pluginFuxiOverride: fuxiOverride,
      userCategories: params.pluginConfig.categories,
      currentModel,
      outputLanguage,
    });

    const fuxiSubOverride = params.pluginConfig.agents?.["fuxi-sub"] as
      | (Record<string, unknown> & { prompt_append?: string })
      | undefined;

    agentConfig["fuxi-sub"] = await buildFuxiSubAgentConfig({
      configAgentPlan: configAgent?.plan,
      pluginFuxiSubOverride: fuxiSubOverride,
      userCategories: params.pluginConfig.categories,
      currentModel,
      outputLanguage,
    });

    const xuanyuanOverride = params.pluginConfig.agents?.["xuanyuan"] as
      | (Record<string, unknown> & { prompt_append?: string })
      | undefined;

    agentConfig["xuanyuan"] = await buildXuanyuanAgentConfig({
      configAgentPlan: configAgent?.plan,
      pluginXuanyuanOverride: xuanyuanOverride,
      userCategories: params.pluginConfig.categories,
      currentModel,
      outputLanguage,
    });

    const dayuOverride = params.pluginConfig.agents?.["dayu"] as
      | (Record<string, unknown> & { prompt_append?: string })
      | undefined;

    agentConfig["dayu"] = await buildDayuAgentConfig({
      configAgentPlan: configAgent?.plan,
      pluginDayuOverride: dayuOverride,
      userCategories: params.pluginConfig.categories,
      currentModel,
      outputLanguage,
    });

    const baizeOverride = params.pluginConfig.agents?.["baize"];

    agentConfig["baize"] = await buildBaizeAgentConfig({
      pluginBaizeOverride: baizeOverride,
      currentModel,
      outputLanguage,
    });

    const nuwaOverride = params.pluginConfig.agents?.["nuwa"] as
      | (Record<string, unknown> & { prompt_append?: string })
      | undefined;

    agentConfig["nuwa"] = await buildNuwaAgentConfig({
      configAgentPlan: configAgent?.plan,
      pluginNuwaOverride: nuwaOverride,
      userCategories: params.pluginConfig.categories,
      currentModel,
      outputLanguage,
    });

    const nuwaSubOverride = params.pluginConfig.agents?.["nuwa-sub"] as
      | (Record<string, unknown> & { prompt_append?: string })
      | undefined;

    agentConfig["nuwa-sub"] = await buildNuwaSubAgentConfig({
      configAgentPlan: configAgent?.plan,
      pluginNuwaSubOverride: nuwaSubOverride,
      userCategories: params.pluginConfig.categories,
      currentModel,
      outputLanguage,
    });
  }

  const kuafuOverride = params.pluginConfig.agents?.["kuafu"] as
    | (Record<string, unknown> & { prompt_append?: string })
    | undefined;

  agentConfig["kuafu"] = await buildKuafuAgentConfig({
    pluginKuafuOverride: kuafuOverride,
    currentModel,
    outputLanguage,
  });

  const filteredConfigAgents = configAgent
    ? Object.fromEntries(
        Object.entries(configAgent)
          .filter(([key]) => {
            if (key === "build") return false;
            if (key === "plan" && shouldDemotePlan) return false;
            if (key in builtinAgents) return false;
            return true;
          })
          .map(([key, value]) => [
            key,
            value ? migrateAgentConfig(value as Record<string, unknown>) : value,
          ]),
      )
    : {};

  const migratedBuild = configAgent?.build
    ? migrateAgentConfig(configAgent.build as Record<string, unknown>)
    : {};

  params.config.agent = {
    ...agentConfig,
    ...builtinAgents,
    ...filterDisabledAgents(userAgents),
    ...filterDisabledAgents(projectAgents),
    ...filterDisabledAgents(pluginAgents),
    ...filteredConfigAgents,
    build: { ...migratedBuild, mode: "primary" },
  };

  if (params.config.agent) {
    const uiScopedAgents = applyUiAgentVisibility(
      params.config.agent as Record<string, unknown>,
    );

    params.config.agent = remapAgentKeysToDisplayNames(
      uiScopedAgents as Record<string, unknown>,
    );
    params.config.agent = reorderAgentsByPriority(
      params.config.agent as Record<string, unknown>,
    );
  }

  const agentResult = params.config.agent as Record<string, unknown>;
  log("[config-handler] agents loaded", { agentKeys: Object.keys(agentResult) });
  return agentResult;
}
