import { test } from "node:test";
import assert from "node:assert/strict";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { BridgeClient, BridgeError } from "../client.js";
import type { BridgeConfig } from "../config.js";

interface RecordedRequest {
  method: string;
  path: string;
  authorization: string | undefined;
  body: string;
  query: URLSearchParams;
}

function startStub(
  handler: (req: RecordedRequest) => { status: number; body: unknown },
): Promise<{ server: Server; port: number; requests: RecordedRequest[] }> {
  const requests: RecordedRequest[] = [];
  const server = createServer((req, res) => {
    const chunks: Buffer[] = [];
    req.on("data", (chunk: Buffer) => chunks.push(chunk));
    req.on("end", () => {
      const url = new URL(req.url ?? "/", "http://127.0.0.1");
      const recorded: RecordedRequest = {
        method: req.method ?? "GET",
        path: url.pathname,
        authorization: req.headers.authorization,
        body: Buffer.concat(chunks).toString("utf8"),
        query: url.searchParams,
      };
      requests.push(recorded);
      const result = handler(recorded);
      res.writeHead(result.status, { "content-type": "application/json" });
      res.end(JSON.stringify(result.body));
    });
  });
  return new Promise((resolve) => {
    server.listen(0, "127.0.0.1", () => {
      resolve({ server, port: (server.address() as AddressInfo).port, requests });
    });
  });
}

function clientFor(port: number, token = "test-token"): BridgeClient {
  const config: BridgeConfig = {
    baseUrl: `http://127.0.0.1:${port}`,
    token,
    timeoutMs: 2_000,
  };
  return new BridgeClient(config);
}

test("client sends bearer auth and decodes health", async () => {
  const { server, port, requests } = await startStub(() => ({
    status: 200,
    body: { ok: true, app: "Noot Study", apiVersion: 1 },
  }));
  try {
    const result = (await clientFor(port).health()) as { ok: boolean; app: string };
    assert.equal(result.ok, true);
    assert.equal(result.app, "Noot Study");
    assert.equal(requests.length, 1);
    assert.equal(requests[0]?.authorization, "Bearer test-token");
    assert.equal(requests[0]?.path, "/v1/health");
  } finally {
    server.close();
  }
});

test("client maps bridge error envelopes", async () => {
  const { server, port } = await startStub(() => ({
    status: 401,
    body: { error: { code: "unauthorized", message: "bad token" } },
  }));
  try {
    await assert.rejects(
      () => clientFor(port).progress(),
      (error: unknown) => {
        assert.ok(error instanceof BridgeError);
        assert.equal(error.code, "unauthorized");
        assert.equal(error.status, 401);
        assert.match(error.message, /bad token/);
        return true;
      },
    );
  } finally {
    server.close();
  }
});

test("client serializes query parameters and json bodies", async () => {
  const { server, port, requests } = await startStub((req) => {
    if (req.path === "/v1/cards" && req.method === "GET") {
      return { status: 200, body: { cards: [], total: 0 } };
    }
    return { status: 200, body: { created: [], skipped: [] } };
  });
  try {
    const client = clientFor(port);
    await client.listCards({ dueOnly: true, limit: 25, subject: "Biology HL" });
    const listRequest = requests[0];
    assert.equal(listRequest?.path, "/v1/cards");
    assert.equal(listRequest?.query.get("dueOnly"), "true");
    assert.equal(listRequest?.query.get("limit"), "25");
    assert.equal(listRequest?.query.get("subject"), "Biology HL");

    await client.createCards([{ subjectName: "Biology HL", front: "Q", back: "A" }]);
    const createRequest = requests[1];
    assert.equal(createRequest?.method, "POST");
    assert.equal(createRequest?.path, "/v1/cards");
    const parsed = JSON.parse(createRequest?.body ?? "{}") as { cards: unknown[] };
    assert.equal(parsed.cards.length, 1);
  } finally {
    server.close();
  }
});

test("client reports an actionable error when the bridge is unreachable", async () => {
  const probe = await startStub(() => ({ status: 200, body: {} }));
  const port = probe.port;
  await new Promise<void>((resolve) => probe.server.close(() => resolve()));

  await assert.rejects(
    () => clientFor(port).health(),
    (error: unknown) => {
      assert.ok(error instanceof BridgeError);
      assert.equal(error.code, "unreachable");
      assert.match(error.message, /Settings → Integrations/);
      return true;
    },
  );
});
