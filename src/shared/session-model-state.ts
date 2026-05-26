export type SessionModel = { providerID: string; modelID: string }

const sessionModels = new Map<string, SessionModel>()
const pinnedSessionModels = new Map<string, SessionModel>()

export function setSessionModel(sessionID: string, model: SessionModel): void {
  sessionModels.set(sessionID, model)
}

export function getSessionModel(sessionID: string): SessionModel | undefined {
  return sessionModels.get(sessionID)
}

export function clearSessionModel(sessionID: string): void {
  sessionModels.delete(sessionID)
}

export function setPinnedSessionModel(sessionID: string, model: SessionModel): void {
  pinnedSessionModels.set(sessionID, model)
}

export function getPinnedSessionModel(sessionID: string): SessionModel | undefined {
  return pinnedSessionModels.get(sessionID)
}

export function clearPinnedSessionModel(sessionID: string): void {
  pinnedSessionModels.delete(sessionID)
}
