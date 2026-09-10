#!/usr/bin/env node
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { createHash, timingSafeEqual } from "node:crypto";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { createNootStudyServer } from "./tools.js";
import { loadBridgeConfig, missingTokenHelp } from "./config.js";

const DEFAULT_HTTP_PORT = 42828;
const DEFAULT_HTTP_HOST = "127.0.0.1";

interface CliOptions {
  http: boolean;
  port: number;
  host: string;
  help: boolean;
}

function parseArgs(argv: string[]): CliOptions {
  const options: CliOptions = {
    http: false,
    port: DEFAULT_HTTP_PORT,
    host: DEFAULT_HTTP_HOST,
    help: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    switch (arg) {
      case "--http":
        options.http = true;
        break;
      case "--port": {
        const value = Number.parseInt(argv[index + 1] ?? "", 10);
        if (Number.isFinite(value) && value > 0 && value < 65536) {
          options.port = value;
          index += 1;
        }
        break;
      }
      case "--host": {
        const value = argv[index + 1];
        if (value !== undefined && value.length > 0) {
          options.host = value;
          index += 1;
        }
        break;
      }
      case "--help":
      case "-h":
        options.help = true;
        break;
      default:
        break;
    }
  }
  return options;
}

function usage(): string {
  return [
    "nootstudy-mcp — MCP connector for Noot Study",
    "",
    "Usage:",
    "  nootstudy-mcp                 # stdio transport (Codex CLI, Claude Desktop)",
    "  nootstudy-mcp --http          # Streamable HTTP transport (ChatGPT connectors, tunnels)",
    "  nootstudy-mcp --http --port 42828 --host 127.0.0.1",
    "",
    "Environment:",
    "  NOOTSTUDY_BRIDGE_URL          Bridge URL (default http://127.0.0.1:42827)",
    "  NOOTSTUDY_BRIDGE_TOKEN        Bearer token from Noot Study → Settings → Integrations",
    "  NOOTSTUDY_MCP_HTTP_TOKEN      Required with --http; clients must send it as Authorization: Bearer",
  ].join("\n");
}

async function runStdio(): Promise<void> {
  const config = loadBridgeConfig();
  if (config.token.length === 0) {
    console.error(`nootstudy-mcp: ${missingTokenHelp()}`);
  }
  const server = createNootStudyServer();
  await server.connect(new StdioServerTransport());
  console.error(`nootstudy-mcp: stdio ready (bridge ${config.baseUrl})`);
}

function safeTokenEqual(presented: string, expected: string): boolean {
  const presentedDigest = createHash("sha256").update(presented).digest();
  const expectedDigest = createHash("sha256").update(expected).digest();
  return timingSafeEqual(presentedDigest, expectedDigest);
}

async function handleHttpRequest(
  req: IncomingMessage,
  res: ServerResponse,
  httpToken: string,
): Promise<void> {
  const path = (req.url ?? "").split("?")[0];
  if (path !== "/mcp") {
    res.writeHead(404, { "content-type": "application/json" });
    res.end(JSON.stringify({ error: "not_found" }));
    return;
  }

  const authorization = req.headers.authorization ?? "";
  if (!safeTokenEqual(authorization, `Bearer ${httpToken}`)) {
    res.writeHead(401, { "content-type": "application/json" });
    res.end(JSON.stringify({ error: "unauthorized" }));
    return;
  }

  const server = createNootStudyServer();
  const transport = new StreamableHTTPServerTransport({
    sessionIdGenerator: undefined,
    enableJsonResponse: true,
  });
  res.on("close", () => {
    void transport.close();
    void server.close();
  });
  await server.connect(transport);
  await transport.handleRequest(req, res);
}

async function runHttp(host: string, port: number): Promise<void> {
  const httpToken = process.env.NOOTSTUDY_MCP_HTTP_TOKEN?.trim() ?? "";
  if (httpToken.length === 0) {
    console.error(
      "nootstudy-mcp: --http requires NOOTSTUDY_MCP_HTTP_TOKEN so remote clients cannot reach your study data without it.",
    );
    process.exit(1);
  }
  const config = loadBridgeConfig();
  if (config.token.length === 0) {
    console.error(`nootstudy-mcp: ${missingTokenHelp()}`);
  }

  const httpServer = createServer((req, res) => {
    handleHttpRequest(req, res, httpToken).catch((error: unknown) => {
      console.error("nootstudy-mcp: request failed", error);
      if (!res.headersSent) {
        res.writeHead(500, { "content-type": "application/json" });
      }
      res.end(JSON.stringify({ error: "internal_error" }));
    });
  });

  await new Promise<void>((resolve, reject) => {
    httpServer.once("error", reject);
    httpServer.listen(port, host, () => resolve());
  });
  console.error(`nootstudy-mcp: streamable HTTP listening on http://${host}:${port}/mcp`);
}

async function main(): Promise<void> {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    console.log(usage());
    return;
  }
  if (options.http) {
    await runHttp(options.host, options.port);
  } else {
    await runStdio();
  }
}

main().catch((error: unknown) => {
  console.error("nootstudy-mcp: fatal", error);
  process.exit(1);
});
