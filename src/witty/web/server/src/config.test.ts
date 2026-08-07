import assert from "node:assert/strict";
import path from "node:path";
import { describe, test } from "node:test";
import { getEnvFileCandidates } from "./config.js";

describe("config env discovery", () => {
  test("includes cwd and web/server fallback env paths", () => {
    const cwd = "/tmp/witty-root";
    const candidates = getEnvFileCandidates(cwd);

    assert.equal(candidates[0], path.join(cwd, ".env"));
    assert.equal(candidates[1]?.endsWith("/src/witty/web/server/.env"), true);
    assert.equal(path.isAbsolute(candidates[1] ?? ""), true);
  });
});
