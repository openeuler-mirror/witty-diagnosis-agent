export type OutputLanguage = "zh" | "en"

type LocalizedString = {
  zh: string
  en: string
}

export function l(str: LocalizedString | string, lang: OutputLanguage): string {
  if (typeof str === "string") return str
  return str[lang] ?? str.zh
}

export const AGENT_LOCALIZATION: Record<string, { name: LocalizedString; description: LocalizedString }> = {
  xuanyuan: {
    name: {
      zh: "轩辕 (Xuanyuan)",
      en: "Xuanyuan",
    },
    description: {
      zh: "Xuanyuan (Controller) — Phase 0 \"轩辕 / Xuanyuan - 总控\" agent for the Intelligent O&M System. Acts as the primary interface, coordinates diagnostic planning (Fuxi), execution (Dayu/Kuafu), and analysis (Baize). Operates fully autonomously. (Xuanyuan - WittyDiagnosisAgent)",
      en: "Xuanyuan (Controller) — Phase 0 \"Xuanyuan - Controller\" agent for the Intelligent O&M System. Acts as the primary interface, coordinates diagnostic planning (Fuxi), execution (Dayu/Kuafu), and analysis (Baize). Operates fully autonomously. (Xuanyuan - WittyDiagnosisAgent)",
    },
  },
  fuxi: {
    name: {
      zh: "伏羲 (Fuxi)",
      en: "Fuxi",
    },
    description: {
      zh: "Fuxi (Diagnostic Planner) — Phase 1 \"伏羲 / Fuxi - 诊断方案规划\" agent for the Intelligent O&M System. Clarifies fault symptoms and generates structured diagnostic plans (Dayu tasks). (Fuxi - WittyDiagnosisAgent)",
      en: "Fuxi (Diagnostic Planner) — Phase 1 \"Fuxi - Diagnostic Planner\" agent for the Intelligent O&M System. Clarifies fault symptoms and generates structured diagnostic plans (Dayu tasks). (Fuxi - WittyDiagnosisAgent)",
    },
  },
  "fuxi-sub": {
    name: {
      zh: "伏羲-子模块 (Fuxi-Sub)",
      en: "Fuxi-Sub",
    },
    description: {
      zh: "Fuxi 子模块。使用关联规则自动补全故障模式。",
      en: "Fuxi sub-agent. Auto-completes failure modes using correlation rules.",
    },
  },
  dayu: {
    name: {
      zh: "大禹 (Dayu)",
      en: "Dayu",
    },
    description: {
      zh: "Dayu (Scheduler) — Phase 1.2 \"大禹 / Dayu - 诊断任务调度\" agent for the Intelligent O&M System. Translates Fuxi's plan into concrete steps, spawns Kuafu agents for evidence collection, and delegates to Baize for final reporting. (Dayu - WittyDiagnosisAgent)",
      en: "Dayu (Scheduler) — Phase 1.2 \"Dayu - Task Scheduler\" agent for the Intelligent O&M System. Translates Fuxi's plan into concrete steps, spawns Kuafu agents for evidence collection, and delegates to Baize for final reporting. (Dayu - WittyDiagnosisAgent)",
    },
  },
  kuafu: {
    name: {
      zh: "夸父 (Kuafu)",
      en: "Kuafu",
    },
    description: {
      zh: "Kuafu (Executor) — Phase 1.3 \"夸父 / Kuafu - 诊断排查执行\" agent for the Intelligent O&M System. Specialized worker that executes diagnostic tasks (reading logs, querying metrics) via tools, based on Dayu's scheduling. Saves finding artifacts to ~/.witty-diagnosis-agent/dayu/. (Kuafu - WittyDiagnosisAgent)",
      en: "Kuafu (Executor) — Phase 1.3 \"Kuafu - Diagnostic Executor\" agent for the Intelligent O&M System. Specialized worker that executes diagnostic tasks (reading logs, querying metrics) via tools, based on Dayu's scheduling. Saves finding artifacts to ~/.witty-diagnosis-agent/dayu/. (Kuafu - WittyDiagnosisAgent)",
    },
  },
  baize: {
    name: {
      zh: "白泽 (Baize)",
      en: "Baize",
    },
    description: {
      zh: "Baize (Analysis & Report) — Phase 1.4 \"白泽 / Baize - 分析与报告\" agent for the Intelligent O&M System. Dynamically loads skills based on scenarios (Fault Diagnosis, Health Inspection, etc.). Reads upstream reports, aggregates evidence, performs core analysis according to the loaded skill, and writes final structured reports to ~/.witty-diagnosis-agent/baize/reports/. (Baize - WittyDiagnosisAgent)",
      en: "Baize (Analysis & Report) — Phase 1.4 \"Baize - Analysis & Report\" agent for the Intelligent O&M System. Dynamically loads skills based on scenarios (Fault Diagnosis, Health Inspection, etc.). Reads upstream reports, aggregates evidence, performs core analysis according to the loaded skill, and writes final structured reports to ~/.witty-diagnosis-agent/baize/reports/. (Baize - WittyDiagnosisAgent)",
    },
  },
  nuwa: {
    name: {
      zh: "女娲 (Nuwa)",
      en: "Nuwa",
    },
    description: {
      zh: "Nuwa (Self-healing Expert) — Phase 2/3 \"女娲 / Nuwa - 自愈修复核心\" agent for the Intelligent O&M System. Suggests, validates, and executes repair operations based on Baize's RCA report. (Nuwa - WittyDiagnosisAgent)",
      en: "Nuwa (Self-healing Expert) — Phase 2/3 \"Nuwa - Self-Healing Core\" agent for the Intelligent O&M System. Suggests, validates, and executes repair operations based on Baize's RCA report. (Nuwa - WittyDiagnosisAgent)",
    },
  },
  "multimodal-looker": {
    name: {
      zh: "多模态观察员 (Multimodal Looker)",
      en: "Multimodal Looker",
    },
    description: {
      zh: "分析无法直接作为纯文本读取的媒体文件（PDF、图像、图表）。提取特定信息或总结文档内容，描述视觉内容。当需要分析或提取的数据而非原始内容时使用。 (Multimodal-Looker - WittyDiagnosisAgent)",
      en: "Analyze media files (PDFs, images, diagrams) that require interpretation beyond raw text. Extracts specific information or summaries from documents, describes visual content. Use when you need analyzed/extracted data rather than literal file contents. (Multimodal-Looker - WittyDiagnosisAgent)",
    },
  },
}
