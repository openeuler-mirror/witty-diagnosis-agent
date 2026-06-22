import { describe, expect, it } from "bun:test";
import {
  createTaiyiAgent,
  OPS_QA_KB_TOOL_NAME,
} from "./qa-agent";

describe("createTaiyiAgent", () => {
  it("allows retrieval tools plus web retrieval when enabled", () => {
    const agent = createTaiyiAgent("gpt-test", "zh");

    expect(agent.permission).toEqual({
      "*": "deny",
      "lightrag*": "allow",
      "websearch*": "allow",
      webfetch: "allow",
    });
  });

  it("keeps the prompt aligned with runtime tool names and fallback behavior in zh", () => {
    const agent = createTaiyiAgent("gpt-test", "zh");
    const prompt = String(agent.prompt);

    expect(prompt).toContain(OPS_QA_KB_TOOL_NAME);
    expect(prompt).toContain("websearch_web_search_exa");
    expect(prompt).toContain("只使用其中真实存在的工具名");
    expect(prompt).toContain("当前环境未启用知识库检索");
    expect(prompt).not.toContain("web_search / webfetch");
  });

  it("keeps the prompt aligned with runtime tool names and fallback behavior in en", () => {
    const agent = createTaiyiAgent("gpt-test", "en");
    const prompt = String(agent.prompt);

    expect(prompt).toContain(OPS_QA_KB_TOOL_NAME);
    expect(prompt).toContain("websearch_web_search_exa");
    expect(prompt).toContain("actual tool list available in the session");
    expect(prompt).toContain("knowledge-base retrieval tool is unavailable");
    expect(prompt).not.toContain("web_search / webfetch");
  });

  it("can force offline mode without web tools", () => {
    const agent = createTaiyiAgent("gpt-test", "zh", { enableWebSearch: false });

    expect(agent.permission).toEqual({
      "*": "deny",
      "lightrag*": "allow",
    });
  });

  it("uses an offline-only prompt when web retrieval is disabled in zh", () => {
    const agent = createTaiyiAgent("gpt-test", "zh", { enableWebSearch: false });
    const prompt = String(agent.prompt);

    expect(prompt).toContain("当前已关闭联网检索");
    expect(prompt).toContain("不要调用任何 `websearch*` 工具或 `webfetch`");
    expect(prompt).not.toContain("当环境配置了联网检索时");
  });

  it("uses an offline-only prompt when web retrieval is disabled in en", () => {
    const agent = createTaiyiAgent("gpt-test", "en", { enableWebSearch: false });
    const prompt = String(agent.prompt);

    expect(prompt).toContain("Web retrieval is disabled for this agent");
    expect(prompt).toContain("Do not call any `websearch*` tool or `webfetch`");
    expect(prompt).not.toContain("When web retrieval is configured");
  });
});
