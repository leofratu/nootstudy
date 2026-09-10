import { loadBridgeConfig, type BridgeConfig } from "./config.js";

export class BridgeError extends Error {
  readonly code: string;
  readonly status?: number;

  constructor(message: string, code: string, status?: number) {
    super(message);
    this.name = "BridgeError";
    this.code = code;
    this.status = status;
  }
}

interface RequestOptions {
  method?: "GET" | "POST";
  path: string;
  query?: Record<string, string | number | boolean | undefined>;
  body?: unknown;
}

interface ErrorEnvelope {
  error?: { code?: string; message?: string };
}

/**
 * Typed client for the Noot Study integration bridge (API v1).
 */
export class BridgeClient {
  readonly config: BridgeConfig;

  constructor(config: BridgeConfig = loadBridgeConfig()) {
    this.config = config;
  }

  get baseUrl(): string {
    return this.config.baseUrl;
  }

  async request<T>(options: RequestOptions): Promise<T> {
    const url = new URL(`${this.config.baseUrl}${options.path}`);
    for (const [key, value] of Object.entries(options.query ?? {})) {
      if (value !== undefined) {
        url.searchParams.set(key, String(value));
      }
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.config.timeoutMs);
    let response: Response;
    try {
      response = await fetch(url, {
        method: options.method ?? "GET",
        headers: {
          Authorization: `Bearer ${this.config.token}`,
          Accept: "application/json",
          ...(options.body === undefined ? {} : { "Content-Type": "application/json" }),
        },
        body: options.body === undefined ? undefined : JSON.stringify(options.body),
        signal: controller.signal,
      });
    } catch (error) {
      const isAbort = error instanceof Error && error.name === "AbortError";
      if (isAbort) {
        throw new BridgeError(
          `Noot Study did not answer within ${this.config.timeoutMs} ms.`,
          "timeout",
        );
      }
      throw new BridgeError(
        `Cannot reach the Noot Study bridge at ${this.config.baseUrl}. ` +
          "Open Noot Study → Settings → Integrations, enable the local integration bridge, " +
          "and confirm the port and token.",
        "unreachable",
      );
    } finally {
      clearTimeout(timer);
    }

    const text = await response.text();
    let payload: unknown;
    try {
      payload = text.length > 0 ? JSON.parse(text) : {};
    } catch {
      throw new BridgeError(
        `Bridge returned a non-JSON response (HTTP ${response.status}).`,
        "invalid_response",
        response.status,
      );
    }

    if (!response.ok) {
      const envelope = payload as ErrorEnvelope;
      throw new BridgeError(
        envelope.error?.message ?? `Bridge request failed with HTTP ${response.status}.`,
        envelope.error?.code ?? "http_error",
        response.status,
      );
    }

    return payload as T;
  }

  health(): Promise<unknown> {
    return this.request({ path: "/v1/health" });
  }

  snapshot(since?: string): Promise<unknown> {
    return this.request({ path: "/v1/snapshot", query: { since } });
  }

  listCards(params: {
    subject?: string;
    query?: string;
    dueOnly?: boolean;
    limit?: number;
    offset?: number;
  }): Promise<unknown> {
    return this.request({ path: "/v1/cards", query: params });
  }

  createCards(cards: unknown[]): Promise<unknown> {
    return this.request({ method: "POST", path: "/v1/cards", body: { cards } });
  }

  recordReviews(reviews: unknown[]): Promise<unknown> {
    return this.request({ method: "POST", path: "/v1/reviews", body: { reviews } });
  }

  listSessions(limit?: number): Promise<unknown> {
    return this.request({ path: "/v1/sessions", query: { limit } });
  }

  createSessions(sessions: unknown[]): Promise<unknown> {
    return this.request({ method: "POST", path: "/v1/sessions", body: { sessions } });
  }

  listSubjects(): Promise<unknown> {
    return this.request({ path: "/v1/subjects" });
  }

  progress(): Promise<unknown> {
    return this.request({ path: "/v1/progress" });
  }

  listPlans(range: { from?: string; to?: string }): Promise<unknown> {
    return this.request({ path: "/v1/plans", query: range });
  }

  createPlan(plan: unknown): Promise<unknown> {
    return this.request({ method: "POST", path: "/v1/plans", body: plan });
  }

  listMemories(params: { query?: string; limit?: number }): Promise<unknown> {
    return this.request({ path: "/v1/memories", query: params });
  }

  saveMemory(memory: unknown): Promise<unknown> {
    return this.request({ method: "POST", path: "/v1/memories", body: memory });
  }

  importActivity(activities: unknown[]): Promise<unknown> {
    return this.request({ method: "POST", path: "/v1/activity", body: { activities } });
  }

  listActivity(status?: "pending" | "all"): Promise<unknown> {
    return this.request({ path: "/v1/activity", query: { status } });
  }

  mergeActivity(ids: string[]): Promise<unknown> {
    return this.request({ method: "POST", path: "/v1/activity/merge", body: { ids } });
  }

  exportNotebookPack(params: { subject: string; topic?: string }): Promise<unknown> {
    return this.request({ path: "/v1/notebook/export", query: params });
  }

  importNotebookSummary(params: {
    title: string;
    markdown: string;
    saveDrafts?: boolean;
  }): Promise<unknown> {
    return this.request({ method: "POST", path: "/v1/notebook/import", body: params });
  }

  importSnapshot(datasets: Record<string, unknown>, version = 1): Promise<unknown> {
    return this.request({
      method: "POST",
      path: "/v1/import/snapshot",
      body: { version, datasets },
    });
  }
}
