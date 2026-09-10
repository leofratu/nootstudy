/**
 * Bridge connection settings.
 *
 * The MCP server never reads the Noot Study store directly. It talks to the
 * app's loopback HTTP bridge, which owns the data and enforces bearer auth.
 */
export interface BridgeConfig {
  /** Base URL of the Noot Study integration bridge. */
  baseUrl: string;
  /** Bearer token issued by Noot Study → Settings → Integrations. */
  token: string;
  /** Per-request timeout in milliseconds. */
  timeoutMs: number;
}

export const DEFAULT_BRIDGE_URL = "http://127.0.0.1:42827";
export const DEFAULT_TIMEOUT_MS = 30_000;

export function loadBridgeConfig(env: NodeJS.ProcessEnv = process.env): BridgeConfig {
  const rawUrl = env.NOOTSTUDY_BRIDGE_URL?.trim();
  const rawToken = env.NOOTSTUDY_BRIDGE_TOKEN?.trim();
  const rawTimeout = Number.parseInt(env.NOOTSTUDY_BRIDGE_TIMEOUT_MS ?? "", 10);

  return {
    baseUrl: (rawUrl && rawUrl.length > 0 ? rawUrl : DEFAULT_BRIDGE_URL).replace(/\/+$/, ""),
    token: rawToken ?? "",
    timeoutMs: Number.isFinite(rawTimeout) && rawTimeout > 0 ? rawTimeout : DEFAULT_TIMEOUT_MS,
  };
}

export function missingTokenHelp(): string {
  return [
    "NOOTSTUDY_BRIDGE_TOKEN is not set.",
    "Open Noot Study → Settings → Integrations, enable the local integration bridge,",
    "copy the token, and expose it to this server as NOOTSTUDY_BRIDGE_TOKEN.",
  ].join(" ");
}
