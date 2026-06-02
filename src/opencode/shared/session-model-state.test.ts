import { describe, expect, test } from "bun:test"
import {
  clearPinnedSessionModel,
  clearSessionModel,
  getPinnedSessionModel,
  getSessionModel,
  setPinnedSessionModel,
  setSessionModel,
} from "./session-model-state"

describe("session-model-state", () => {
  test("stores and retrieves a session model", () => {
    //#given
    const sessionID = "ses_test"

    //#when
    setSessionModel(sessionID, { providerID: "github-copilot", modelID: "gpt-4.1" })

    //#then
    expect(getSessionModel(sessionID)).toEqual({
      providerID: "github-copilot",
      modelID: "gpt-4.1",
    })
  })

  test("clears a session model", () => {
    //#given
    const sessionID = "ses_clear"
    setSessionModel(sessionID, { providerID: "anthropic", modelID: "gpt-5.3-codex" })

    //#when
    clearSessionModel(sessionID)

    //#then
    expect(getSessionModel(sessionID)).toBeUndefined()
  })

  test("stores and clears a pinned session model", () => {
    //#given
    const sessionID = "ses_pin"

    //#when
    setPinnedSessionModel(sessionID, { providerID: "deepseek", modelID: "deepseek-chat" })

    //#then
    expect(getPinnedSessionModel(sessionID)).toEqual({
      providerID: "deepseek",
      modelID: "deepseek-chat",
    })

    //#when
    clearPinnedSessionModel(sessionID)

    //#then
    expect(getPinnedSessionModel(sessionID)).toBeUndefined()
  })
})
