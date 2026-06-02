import { findAvailablePort as findAvailablePortShared } from "../../shared/port-utils"

const DEFAULT_PORT = 19877
const TIMEOUT_MS = 5 * 60 * 1000

export type OAuthCallbackResult = {
  code: string
  state: string
}

export type CallbackServer = {
  port: number
  waitForCallback: () => Promise<OAuthCallbackResult>
  close: () => void
}

const SUCCESS_HTML = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>OAuth Authorized</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: #0a0a0a; color: #fafafa; }
    .container { text-align: center; }
    h1 { font-size: 1.5rem; margin-bottom: 0.5rem; }
    p { color: #888; }
  </style>
</head>
<body>
  <div class="container">
    <h1>Authorization successful</h1>
    <p>You can close this window and return to your terminal.</p>
  </div>
</body>
</html>`

export async function findAvailablePort(startPort: number = DEFAULT_PORT): Promise<number> {
  return findAvailablePortShared(startPort)
}

import * as http from "http"
export async function startCallbackServer(startPort: number = DEFAULT_PORT): Promise<CallbackServer> {
  const port = await findAvailablePort(startPort)

  let resolveCallback: ((result: OAuthCallbackResult) => void) | null = null
  let rejectCallback: ((error: Error) => void) | null = null

  const callbackPromise = new Promise<OAuthCallbackResult>((resolve, reject) => {
    resolveCallback = resolve
    rejectCallback = reject
  })

  const timeoutId = setTimeout(() => {
    rejectCallback?.(new Error("OAuth callback timed out after 5 minutes"))
    server.close()
  }, TIMEOUT_MS)

  const server = http.createServer((req, res) => {
    const url = new URL(req.url || "/", `http://${req.headers.host || '127.0.0.1'}`)
    if (url.pathname !== "/oauth/callback") {
      res.writeHead(404); res.end("Not Found"); return;
    }
    const oauthError = url.searchParams.get("error")
    if (oauthError) {
      const description = url.searchParams.get("error_description") ?? oauthError
      clearTimeout(timeoutId)
      rejectCallback?.(new Error(`OAuth authorization failed: ${description}`))
      setTimeout(() => server.close(), 100)
      res.writeHead(400); res.end(`Authorization failed: ${description}`); return;
    }
    const code = url.searchParams.get("code")
    const state = url.searchParams.get("state")
    if (!code || !state) {
      clearTimeout(timeoutId)
      rejectCallback?.(new Error("OAuth callback missing code or state parameter"))
      setTimeout(() => server.close(), 100)
      res.writeHead(400); res.end("Missing code or state parameter"); return;
    }
    resolveCallback?.({ code, state })
    clearTimeout(timeoutId)
    setTimeout(() => server.close(), 100)
    res.writeHead(200, { "content-type": "text/html; charset=utf-8" })
    res.end(SUCCESS_HTML)
  })
  server.listen(port, "127.0.0.1")

  return {
    port,
    waitForCallback: () => callbackPromise,
    close: () => {
      clearTimeout(timeoutId)
      server.close()
    },
  }
}
