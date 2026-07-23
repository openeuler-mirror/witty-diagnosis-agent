const DEFAULT_SERVER_PORT = 4096
const MAX_PORT_ATTEMPTS = 20

import * as http from "http"
export async function isPortAvailable(port: number, hostname: string = "127.0.0.1"): Promise<boolean> {
  try {
    return new Promise((resolve) => {
      const server = http.createServer()
      server.once('error', () => resolve(false))
      server.listen(port, hostname, () => {
        server.close()
        resolve(true)
      })
    })
  } catch {
    return false
  }
}

export async function findAvailablePort(
  startPort: number = DEFAULT_SERVER_PORT,
  hostname: string = "127.0.0.1"
): Promise<number> {
  for (let attempt = 0; attempt < MAX_PORT_ATTEMPTS; attempt++) {
    const port = startPort + attempt
    if (await isPortAvailable(port, hostname)) {
      return port
    }
  }
  throw new Error(`No available port found in range ${startPort}-${startPort + MAX_PORT_ATTEMPTS - 1}`)
}

export interface AutoPortResult {
  port: number
  wasAutoSelected: boolean
}

export async function getAvailableServerPort(
  preferredPort: number = DEFAULT_SERVER_PORT,
  hostname: string = "127.0.0.1"
): Promise<AutoPortResult> {
  if (await isPortAvailable(preferredPort, hostname)) {
    return { port: preferredPort, wasAutoSelected: false }
  }

  const port = await findAvailablePort(preferredPort + 1, hostname)
  return { port, wasAutoSelected: true }
}

export { DEFAULT_SERVER_PORT }
