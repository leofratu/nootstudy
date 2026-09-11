# nootstudy-mcp

MCP (Model Context Protocol) connector for [Noot Study](../..), the macOS IB
study workspace. It exposes the learner's study data to Codex, ChatGPT, and any
other MCP client over the app's **local integration bridge** — read and write,
both directions.

The app remains the single source of truth. This server is a thin, stateless
adapter: every tool call becomes one authenticated HTTP request to
`127.0.0.1`, where Noot Study applies it through its own engine (FSRS
scheduling, proficiency, progression) or returns live data.

```
Codex / ChatGPT / Claude
        │  MCP (stdio or streamable HTTP)
        ▼
  nootstudy-mcp  ──HTTP + bearer token──▶  Noot Study (127.0.0.1)
```

## Requirements

- Node.js 18 or later.
- Noot Study with the integration bridge enabled:
  **Settings → Integrations → Local integration bridge**. Copy the bearer token
  from that screen. The bridge is off by default and only listens on loopback.

## Quick start (stdio)

```bash
export NOOTSTUDY_BRIDGE_URL="http://127.0.0.1:42827"
export NOOTSTUDY_BRIDGE_TOKEN="<token from Settings → Integrations>"

npx -y nootstudy-mcp
```

Or from this repository:

```bash
npm install
npm run build
node dist/index.js
```

## Codex CLI

```bash
codex mcp add nootstudy \
  --env NOOTSTUDY_BRIDGE_URL=http://127.0.0.1:42827 \
  --env NOOTSTUDY_BRIDGE_TOKEN=<token> \
  -- npx -y nootstudy-mcp
```

Codex now sees the `noot_*` tools in every session. Ask it to pull the due
queue, write cards from your notes, or log a study session you did elsewhere.

> Review the command with `codex mcp -h`; flag names may change between Codex
> releases. The same command works in Codex config files under `mcpServers`.

## Claude Desktop / Claude Code

```json
{
  "mcpServers": {
    "nootstudy": {
      "command": "npx",
      "args": ["-y", "nootstudy-mcp"],
      "env": {
        "NOOTSTUDY_BRIDGE_URL": "http://127.0.0.1:42827",
        "NOOTSTUDY_BRIDGE_TOKEN": "<token>"
      }
    }
  }
}
```

## ChatGPT connectors (streamable HTTP)

ChatGPT connects to remote MCP servers over HTTPS; it cannot reach your
loopback address directly. Run the HTTP transport and expose **only that port**
through a tunnel:

```bash
export NOOTSTUDY_MCP_HTTP_TOKEN="$(openssl rand -hex 32)"   # client-facing token
export NOOTSTUDY_BRIDGE_TOKEN="<token from Settings → Integrations>"

npx -y nootstudy-mcp --http --port 42828
# then, in another terminal:
cloudflared tunnel --url http://127.0.0.1:42828
```

Add the resulting `https://<id>.trycloudflare.com/mcp` URL as a custom
connector and send `Authorization: Bearer $NOOTSTUDY_MCP_HTTP_TOKEN` on
requests. Two independent tokens protect the path: the HTTP token gates the
tunnel, the bridge token gates the app. Rotate both from the app / environment
if either leaks.

## Tool catalog

| Tool | Access | Purpose |
| --- | --- | --- |
| `noot_health` | read | Bridge connectivity. |
| `noot_get_progress` | read | XP, rank, mastery, streak, achievements. |
| `noot_list_subjects` | read | Subjects, levels, due counts, mastery. |
| `noot_list_cards` | read | Search cards by subject, text, due status. |
| `noot_get_due_cards` | read | Current spaced-repetition queue. |
| `noot_list_sessions` | read | Recorded study sessions. |
| `noot_list_plans` | read | Scheduled study plans. |
| `noot_search_memories` | read | ARIA's durable memories. |
| `noot_list_external_activity` | read | Work logged outside the app. |
| `noot_export_notebook_pack` | read | NotebookLM-ready source pack. |
| `noot_get_snapshot` | read | Full/incremental JSON snapshot. |
| `noot_create_cards` | write | Create flashcards (deduplicated). |
| `noot_record_reviews` | write | Record FSRS reviews. |
| `noot_log_study_session` | write | Log a completed session. |
| `noot_log_external_activity` | write | Queue work done elsewhere (idempotent). |
| `noot_merge_external_activity` | write | Merge queued work into history. |
| `noot_save_memory` | write | Persist a durable ARIA memory. |
| `noot_create_plan` | write | Schedule a study plan. |
| `noot_import_notebook_summary` | write | Import a NotebookLM summary as drafts. |
| `noot_sync_snapshot` | write | Merge an exported snapshot back (never deletes). |

## NotebookLM

NotebookLM has no public write API. The integration is therefore a pack
exchange: `noot_export_notebook_pack` produces a structured markdown source
(curriculum outline, Q/A corpus, weak topics, study prompts) that you upload to
a notebook, and `noot_import_notebook_summary` brings a generated summary back
as an ARIA memory plus draft flashcards.

## Environment variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `NOOTSTUDY_BRIDGE_URL` | `http://127.0.0.1:42827` | Bridge base URL. |
| `NOOTSTUDY_BRIDGE_TOKEN` | — | Bearer token from the app. Required for tool calls. |
| `NOOTSTUDY_BRIDGE_TIMEOUT_MS` | `30000` | Per-request timeout. |
| `NOOTSTUDY_MCP_HTTP_TOKEN` | — | Required with `--http`; clients must present it. |

## Security

- Both tokens are secrets. Keep them in environment variables or an MCP
  client's secret store; never commit them.
- The bridge binds to `127.0.0.1` only and validates every request.
- The HTTP transport refuses to start without `NOOTSTUDY_MCP_HTTP_TOKEN`.
- Destructive operations (delete) are intentionally **not** exposed. The only
  bulk write, `noot_sync_snapshot`, merges by UUID and never deletes.

## Development

```bash
npm install
npm test        # builds and runs the client test suite (node:test)
```
