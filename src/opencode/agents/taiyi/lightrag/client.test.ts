import assert from "node:assert/strict";
import { afterEach, describe, test } from "node:test";
import { createLightragClient } from "./client.js";

const originalFetch = globalThis.fetch;

afterEach(() => {
  globalThis.fetch = originalFetch;
});

describe("RestLightragClient", () => {
  test("maps LightRAG /query response and request fields", async () => {
    let requestUrl = "";
    let requestInit: RequestInit | undefined;

    globalThis.fetch = async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
      requestUrl = typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;
      requestInit = init;
      return new Response(
        JSON.stringify({
          response: "firewalld reload 会清空 Docker 注入的规则链。",
          references: [
            {
              reference_id: "1",
              file_path: "/documents/network/firewalld-docker.md",
              content: ["当 firewalld reload 时，Docker 规则链会被重建覆盖。"],
            },
            {
              reference_id: "2",
              file_path: "https://kb.example/incidents/INC-1001",
              content: ["重启 docker 后容器网络恢复。"],
            },
          ],
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    };

    const client = createLightragClient({
      mock: false,
      endpoint: "http://localhost:9621/",
      apiKey: "lightrag01234",
      apiKeyHeader: "X-API-Key",
      defaultMode: "mix",
      responseType: "Multiple Paragraphs",
      includeChunkContent: true,
    });

    const result = await client.query({
      question: "firewalld reload 后 docker 容器网络中断怎么办",
      mode: "hybrid",
    });

    assert.equal(requestUrl, "http://localhost:9621/query");
    assert.equal(requestInit?.method, "POST");
    assert.deepEqual(requestInit?.headers, {
      "Content-Type": "application/json",
      "X-API-Key": "lightrag01234",
    });
    assert.deepEqual(JSON.parse(String(requestInit?.body)), {
      query: "firewalld reload 后 docker 容器网络中断怎么办",
      mode: "hybrid",
      stream: false,
      include_references: true,
      include_chunk_content: true,
      response_type: "Multiple Paragraphs",
    });

    assert.match(result.answer_context, /firewalld reload/);
    assert.equal(result.sources.length, 2);
    assert.deepEqual(result.sources[0], {
      id: 1,
      type: "kb",
      badge: "LightRAG",
      title: "firewalld-docker.md",
      origin: "/documents/network/firewalld-docker.md",
      url: "/documents/network/firewalld-docker.md",
      excerpt: "当 firewalld reload 时，Docker 规则链会被重建覆盖。",
      entities: [],
      relations: [],
      rel: 0,
    });
    assert.equal(result.sources[1].id, 2);
    assert.equal(result.sources[1].title, "INC-1001");
    assert.equal(result.sources[1].origin, "kb.example");
    assert.equal(result.sources[1].url, "https://kb.example/incidents/INC-1001");
    assert.equal(result.empty, false);
  });

  test("falls back to X-API-Key when Authorization bearer gets 401", async () => {
    const requests: Array<{ url: string; init?: RequestInit }> = [];

    globalThis.fetch = async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
      const url = typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;
      requests.push({ url, init });

      const headers = new Headers(init?.headers);
      if (headers.get("Authorization") === "Bearer lightrag01234") {
        return new Response(JSON.stringify({ detail: "invalid bearer token" }), {
          status: 401,
          headers: { "Content-Type": "application/json" },
        });
      }
      return new Response(
        JSON.stringify({
          response: "通过 X-API-Key 回退命中知识库。",
          references: [],
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    };

    const client = createLightragClient({
      mock: false,
      endpoint: "http://localhost:9621/",
      apiKey: "lightrag01234",
      apiKeyHeader: "Authorization",
      defaultMode: "mix",
      responseType: "Multiple Paragraphs",
      includeChunkContent: true,
    });

    const result = await client.query({
      question: "查询知识库",
      mode: "mix",
    });

    assert.equal(requests.length, 2);
    assert.equal(requests[0]?.url, "http://localhost:9621/query");
    assert.equal(requests[1]?.url, "http://localhost:9621/query");
    assert.equal(new Headers(requests[0]?.init?.headers).get("Authorization"), "Bearer lightrag01234");
    assert.equal(new Headers(requests[1]?.init?.headers).get("X-API-Key"), "lightrag01234");
    assert.equal(result.answer_context, "通过 X-API-Key 回退命中知识库。");
  });
});
