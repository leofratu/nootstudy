import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { BridgeClient, BridgeError } from "./client.js";

const qualityScale = z
  .union([z.literal(0), z.literal(2), z.literal(3), z.literal(5)])
  .describe("FSRS recall quality: 0 = Again, 2 = Hard, 3 = Good, 5 = Easy.");

const cardInput = z.object({
  subjectName: z.string().min(1).describe("Existing subject name (case-insensitive)."),
  topicName: z.string().min(1).describe("Curriculum topic the card belongs to."),
  subtopic: z.string().optional(),
  front: z.string().min(1),
  back: z.string().min(1).describe("Self-contained answer; never an instruction."),
  hint: z.string().optional(),
  difficulty: z.enum(["Foundation", "Standard", "Exam", "Stretch"]).optional(),
  cognitiveSkill: z.enum(["Recall", "Explain", "Apply", "Analyze", "Evaluate"]).optional(),
  cardStyle: z.enum(["basic", "cloze", "multiple_choice"]).optional(),
  choices: z
    .array(z.string())
    .optional()
    .describe("For multiple_choice: 3-4 unique options; exactly one must equal back."),
  source: z.string().optional().describe("Where the card came from, e.g. 'codex'."),
});

const reviewInput = z.object({
  cardID: z.string().describe("Card UUID from noot_list_cards / noot_get_due_cards."),
  quality: qualityScale,
  timestamp: z.string().optional().describe("ISO 8601; defaults to now."),
  durationSeconds: z.number().int().min(0).optional(),
});

const sessionInput = z.object({
  subjectName: z.string().min(1),
  topicsCovered: z.array(z.string()).optional(),
  subtopicsCovered: z.array(z.string()).optional(),
  startDate: z.string().describe("ISO 8601."),
  endDate: z.string().describe("ISO 8601."),
  cardsReviewed: z.number().int().min(0).default(0),
  correctCount: z.number().int().min(0).default(0),
  notes: z.string().optional(),
});

const activityInput = z.object({
  externalID: z
    .string()
    .min(1)
    .describe("Stable id from the source tool; repeating it is idempotent."),
  source: z.string().min(1).describe("Origin, e.g. 'codex', 'chatgpt', 'manual'."),
  kind: z.enum(["review", "study", "notes"]).default("study"),
  subjectName: z.string().optional(),
  topicName: z.string().optional(),
  minutes: z.number().int().min(0).default(0),
  cardsReviewed: z.number().int().min(0).default(0),
  correctCount: z.number().int().min(0).default(0),
  occurredAt: z.string().describe("ISO 8601."),
  details: z.string().optional(),
});

function stringify(value: unknown): string {
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
}

function textResult(value: unknown) {
  return { content: [{ type: "text" as const, text: stringify(value) }] };
}

function errorResult(error: unknown) {
  const message =
    error instanceof BridgeError
      ? error.message
      : error instanceof Error
        ? error.message
        : String(error);
  const code = error instanceof BridgeError ? error.code : "error";
  return {
    content: [{ type: "text" as const, text: `${code}: ${message}` }],
    isError: true,
  };
}

async function run(handler: () => Promise<unknown>) {
  try {
    return textResult(await handler());
  } catch (error) {
    return errorResult(error);
  }
}

export interface ServerOptions {
  client?: BridgeClient;
}

/**
 * Builds the Noot Study MCP server with its full tool catalog.
 */
export function createNootStudyServer(options: ServerOptions = {}): McpServer {
  const client = options.client ?? new BridgeClient();
  const server = new McpServer({
    name: "nootstudy-mcp",
    version: "1.0.0",
  });

  // ---- Read tools -----------------------------------------------------------

  server.registerTool(
    "noot_health",
    {
      title: "Noot Study bridge health",
      description:
        "Check connectivity to the Noot Study macOS app's local integration bridge. " +
        "Call this first when another tool reports that the bridge is unreachable.",
      inputSchema: {},
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    () => run(() => client.health()),
  );

  server.registerTool(
    "noot_get_progress",
    {
      title: "Get study progress",
      description:
        "Current XP, rank and tier, blended mastery, streak, and achievements from Noot Study.",
      inputSchema: {},
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    () => run(() => client.progress()),
  );

  server.registerTool(
    "noot_list_subjects",
    {
      title: "List subjects",
      description:
        "All Noot Study subjects with level (HL/SL), exam date, card count, due count, and mastery.",
      inputSchema: {},
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    () => run(() => client.listSubjects()),
  );

  server.registerTool(
    "noot_list_cards",
    {
      title: "List or search flashcards",
      description:
        "Search Noot Study flashcards by subject, free text, or due status. " +
        "Use the returned card IDs with noot_record_reviews.",
      inputSchema: {
        subject: z.string().optional(),
        query: z.string().optional().describe("Matches card front or back text."),
        dueOnly: z.boolean().optional(),
        limit: z.number().int().min(1).max(500).optional(),
        offset: z.number().int().min(0).optional(),
      },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    (args) => run(() => client.listCards(args)),
  );

  server.registerTool(
    "noot_get_due_cards",
    {
      title: "Get cards due now",
      description:
        "The learner's current spaced-repetition queue (cards due now), optionally scoped to one subject.",
      inputSchema: {
        subject: z.string().optional(),
        limit: z.number().int().min(1).max(500).optional(),
      },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    (args) =>
      run(() => client.listCards({ subject: args.subject, dueOnly: true, limit: args.limit ?? 50 })),
  );

  server.registerTool(
    "noot_list_sessions",
    {
      title: "List study sessions",
      description: "Recent recorded study sessions in Noot Study.",
      inputSchema: { limit: z.number().int().min(1).max(500).optional() },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    (args) => run(() => client.listSessions(args.limit)),
  );

  server.registerTool(
    "noot_list_plans",
    {
      title: "List study plans",
      description: "Scheduled study plans, optionally within an ISO 8601 date window.",
      inputSchema: { from: z.string().optional(), to: z.string().optional() },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    (args) => run(() => client.listPlans(args)),
  );

  server.registerTool(
    "noot_search_memories",
    {
      title: "Search ARIA memories",
      description: "Search durable memories stored by the Noot Study AI assistant (ARIA).",
      inputSchema: {
        query: z.string().optional(),
        limit: z.number().int().min(1).max(200).optional(),
      },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    (args) => run(() => client.listMemories(args)),
  );

  server.registerTool(
    "noot_list_external_activity",
    {
      title: "List external activity",
      description:
        "Work recorded outside the app (pushed through this connector or added manually) " +
        "that is waiting to be merged into Noot Study's history.",
      inputSchema: { status: z.enum(["pending", "all"]).optional() },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    (args) => run(() => client.listActivity(args.status ?? "pending")),
  );

  server.registerTool(
    "noot_export_notebook_pack",
    {
      title: "Export NotebookLM pack",
      description:
        "Build a NotebookLM-ready study pack (structured markdown source + card corpus) for a subject. " +
        "NotebookLM has no public API, so upload the returned markdown as a notebook source.",
      inputSchema: {
        subject: z.string().min(1),
        topic: z.string().optional(),
      },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    (args) => run(() => client.exportNotebookPack(args)),
  );

  server.registerTool(
    "noot_get_snapshot",
    {
      title: "Get data snapshot",
      description:
        "Full or incremental JSON snapshot of the learner's Noot Study data " +
        "(subjects, cards, reviews, sessions, grades, plans, activity). " +
        "Use since to fetch only items changed after an ISO 8601 timestamp.",
      inputSchema: { since: z.string().optional() },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    (args) => run(() => client.snapshot(args.since)),
  );

  // ---- Write tools ----------------------------------------------------------

  server.registerTool(
    "noot_create_cards",
    {
      title: "Create flashcards",
      description:
        "Create flashcards in Noot Study. Duplicates (normalized front) are skipped and reported. " +
        "Subjects must already exist; check noot_list_subjects first.",
      inputSchema: { cards: z.array(cardInput).min(1).max(100) },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false },
    },
    (args) => run(() => client.createCards(args.cards)),
  );

  server.registerTool(
    "noot_record_reviews",
    {
      title: "Record flashcard reviews",
      description:
        "Record spaced-repetition reviews (FSRS). This updates scheduling, proficiency, XP, and review history.",
      inputSchema: { reviews: z.array(reviewInput).min(1).max(200) },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false },
    },
    (args) => run(() => client.recordReviews(args.reviews)),
  );

  server.registerTool(
    "noot_log_study_session",
    {
      title: "Log a study session",
      description: "Record a completed study session with topics, duration window, and card counts.",
      inputSchema: { sessions: z.array(sessionInput).min(1).max(50) },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false },
    },
    (args) => run(() => client.createSessions(args.sessions)),
  );

  server.registerTool(
    "noot_log_external_activity",
    {
      title: "Log work done outside Noot Study",
      description:
        "Push work that happened elsewhere (a Codex/ChatGPT session, offline study) into Noot Study's " +
        "pending activity queue. Idempotent per source+externalID. Merge it into history with " +
        "noot_merge_external_activity.",
      inputSchema: { activities: z.array(activityInput).min(1).max(100) },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true },
    },
    (args) => run(() => client.importActivity(args.activities)),
  );

  server.registerTool(
    "noot_merge_external_activity",
    {
      title: "Merge external activity into history",
      description:
        "Merge pending external activity into Noot Study study sessions. " +
        "Merging is idempotent: re-merging the same ids returns the existing session.",
      inputSchema: { ids: z.array(z.string()).min(1).max(200) },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true },
    },
    (args) => run(() => client.mergeActivity(args.ids)),
  );

  server.registerTool(
    "noot_save_memory",
    {
      title: "Save an ARIA memory",
      description:
        "Persist a durable note for the Noot Study assistant (preference, goal, or context).",
      inputSchema: {
        content: z.string().min(1),
        category: z.string().optional(),
        subjectName: z.string().optional(),
      },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false },
    },
    (args) => run(() => client.saveMemory(args)),
  );

  server.registerTool(
    "noot_create_plan",
    {
      title: "Create a study plan",
      description: "Schedule a study plan in Noot Study.",
      inputSchema: {
        subjectName: z.string().min(1),
        topicNames: z.array(z.string()).min(1),
        scheduledDate: z.string().describe("ISO 8601."),
        durationMinutes: z.number().int().min(5).max(600),
        notes: z.string().optional(),
      },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false },
    },
    (args) => run(() => client.createPlan(args)),
  );

  server.registerTool(
    "noot_import_notebook_summary",
    {
      title: "Import a NotebookLM summary",
      description:
        "Import a markdown summary produced from a NotebookLM notebook. It is stored as an ARIA memory; " +
        "extracted question/answer pairs are returned as draft cards (pass saveDrafts=true to create them).",
      inputSchema: {
        title: z.string().min(1),
        markdown: z.string().min(1),
        saveDrafts: z.boolean().optional(),
      },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false },
    },
    (args) => run(() => client.importNotebookSummary(args)),
  );

  server.registerTool(
    "noot_sync_snapshot",
    {
      title: "Sync a data snapshot back",
      description:
        "Merge a previously exported snapshot back into Noot Study. " +
        "Merge-by-UUID: existing records are updated, unknown records are added, nothing is deleted.",
      inputSchema: {
        datasets: z
          .record(z.string(), z.unknown())
          .describe("Dataset map from noot_get_snapshot, e.g. {cards:[...],grades:[...]}."),
        version: z.number().int().optional(),
      },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true },
    },
    (args) => run(() => client.importSnapshot(args.datasets, args.version ?? 1)),
  );

  return server;
}
