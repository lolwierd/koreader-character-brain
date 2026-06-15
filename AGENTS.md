# AGENTS.md — Character Brain for KOReader

> Guide for AI coding agents operating on this codebase.

## Project Overview

**Character Brain** is a spoiler-safe character lookup system for EPUB/KEPUB
books on KOReader (primarily Kobo e-readers). When a reader highlights a
character name, the system extracts only passages *before* that point in the
book, sends them to an LLM, and displays only evidence that is an **exact
quote** from those passages.

The system is split into two components that are deployed independently:

| Component | Language | Location | Runs on |
|-----------|----------|----------|---------|
| KOReader plugin | Lua 5.1 | `characterbrain.koplugin/` | Kobo / KOReader device |
| Backend server | Node.js ≥20 (ESM, zero npm deps) | `server/` | Your server (Docker) |

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Kobo / KOReader                                        │
│                                                         │
│  User highlights "Strider"                              │
│       │                                                 │
│       ▼                                                 │
│  characterbrain_extractor.lua                           │
│  ─ CREngine findAllText() for name + known aliases      │
│  ─ Discards hits ending AFTER selected XPointer         │
│  ─ Builds passage windows (55 words before, 75 after)   │
│       │                                                 │
│       ▼                                                 │
│  characterbrain_backend.lua                             │
│  ─ POST /v1/analyze with { version, query, passages }   │
│       │                                                 │
└───────┼─────────────────────────────────────────────────┘
        │ HTTPS
        ▼
┌─────────────────────────────────────────────────────────┐
│  Server (Node.js)                                       │
│                                                         │
│  app.js                                                 │
│  ─ Auth: Bearer token (timing-safe compare)             │
│  ─ validation.js: validateRequest() → sanitize input    │
│       │                                                 │
│       ▼                                                 │
│  upstream.js                                            │
│  ─ Forwards to AI_BASE_URL/chat/completions             │
│  ─ Sends system prompt (prompts.js) + user prompt       │
│  ─ Uses AI_MODEL, AI_API_KEY from env                   │
│  ─ Merges optional AI_EXTRA_BODY (JSON) into request    │
│       │                                                 │
│       ▼                                                 │
│  validation.js: validateAnalysis()                      │
│  ─ Every quote must be an exact substring of a passage  │
│  ─ Aliases/connections must cite both names in quote    │
│  ─ Rejects anything not backed by exact text            │
│       │                                                 │
└───────┼─────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────┐
│  Back on KOReader                                       │
│                                                         │
│  characterbrain_validator.lua                           │
│  ─ INDEPENDENT re-validation of every quote             │
│  ─ Same exact-substring checks as server                │
│       │                                                 │
│       ▼                                                 │
│  characterbrain_db.lua                                  │
│  ─ SQLite cache keyed by (book, query, boundary)        │
│       │                                                 │
│       ▼                                                 │
│  main.lua → KOReader native UI (TextViewer / Menu)      │
└─────────────────────────────────────────────────────────┘
```

## Critical Invariants

> **These rules MUST NOT be weakened by any code change.**

1. **XPointer boundary filtering** — The plugin MUST discard any text hit whose
   end XPointer is after the user's selection. This prevents future-spoiler
   passages from ever reaching the server.

2. **Exact-quote validation (server)** — `server/src/validation.js` →
   `validateAnalysis()` checks that every `quote` in the model response is a
   verbatim substring (after whitespace normalization) of the cited passage.
   Quotes shorter than 8 characters are rejected.

3. **Exact-quote validation (plugin)** — `characterbrain_validator.lua` →
   `Validator.validate()` performs the same check independently on the device.
   The plugin NEVER trusts the server's validation alone.

4. **Dual citation requirement** — Aliases and connections must contain BOTH the
   query name AND the alias/connection name in the exact quote.

5. **No AI-generated prose displayed** — The UI only shows text that passed
   exact-quote validation. The `rejected_count` is displayed but rejected
   content is never shown.

6. **Model selection is server-side only** — The plugin never knows which LLM is
   being used. Changing models requires only server env var changes.

## File Map

### Plugin (`characterbrain.koplugin/`)

| File | Purpose |
|------|---------|
| `_meta.lua` | Plugin metadata: name, version (`0.2.0`), description |
| `main.lua` | Entry point. UI, menu registration, highlight handler, lookup orchestration |
| `characterbrain_backend.lua` | HTTP client — builds payload, POSTs to `/v1/analyze` |
| `characterbrain_db.lua` | SQLite persistence — books table, analyses cache |
| `characterbrain_extractor.lua` | Passage extraction via CREngine `findAllText`, XPointer windowing |
| `characterbrain_updater.lua` | OTA update system — checks GitHub releases, downloads, installs |
| `characterbrain_util.lua` | Shared utilities: whitespace normalization, string dedup, SQL quoting |
| `characterbrain_validator.lua` | Client-side exact-quote validation (mirrors server logic) |

### Server (`server/`)

| File | Purpose |
|------|---------|
| `src/index.js` | Entry point — loads config, starts HTTP server on port 8787 |
| `src/app.js` | HTTP routing, auth, request parsing, error handling |
| `src/config.js` | Environment variable parsing with validation |
| `src/prompts.js` | System prompt and user prompt builder for the LLM |
| `src/upstream.js` | Forwards requests to the configured LLM provider |
| `src/validation.js` | Request validation + response validation (exact-quote enforcement) |
| `test/app.test.js` | Integration tests for the HTTP layer |
| `test/upstream.test.js` | Tests for upstream LLM communication |
| `test/validation.test.js` | Tests for validation logic |
| `Dockerfile` | Production container image (node:22-alpine, zero deps) |
| `compose.yaml` | Local dev compose |
| `.env.example` | Template for required environment variables |

### CI/CD (`.github/workflows/`)

| File | Purpose |
|------|---------|
| `release.yml` | On `v*` tags: verify version match, zip plugin, create GitHub Release |
| `docker-publish.yml` | On push to `main`/tags: build Docker image, push to GHCR |

### Other

| File | Purpose |
|------|---------|
| `docker-compose.prod.yml` | Production compose: pulls from GHCR, includes Watchtower |
| `dist/characterbrain.koplugin.zip` | Pre-built plugin archive |
| `spec/` | Lua plugin tests (Busted framework) |

## Environment Variables (Server)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `PORT` | No | `8787` | HTTP listen port |
| `CHARACTER_BRAIN_TOKEN` | **Yes** | — | Bearer token for plugin auth |
| `AI_BASE_URL` | **Yes** | — | OpenAI-compatible API base URL |
| `AI_API_KEY` | No | `""` | Provider API key |
| `AI_MODEL` | **Yes** | — | Model identifier |
| `AI_SITE_URL` | No | `""` | OpenRouter `HTTP-Referer` header |
| `AI_APP_NAME` | No | `"Character Brain"` | OpenRouter `X-Title` header |
| `AI_MAX_TOKENS` | No | `1800` | Max response tokens |
| `AI_TIMEOUT_MS` | No | `45000` | Upstream request timeout |
| `AI_EXTRA_BODY` | No | `{}` | JSON object merged into the chat completions request body (for provider-specific params like NVIDIA thinking mode) |

## Testing

### Server (Node.js)

```bash
cd server
npm test          # runs node --test
```

Tests use Node's built-in test runner — no npm install needed. The server has
**zero npm dependencies**.

### Plugin (Lua)

```bash
# Requires Busted (Lua 5.1 test framework)
busted spec/
```

Plugin tests mock KOReader APIs. See `spec/fixtures/` for test data.

## Development Workflow

### Modifying the server

1. Edit files in `server/src/`
2. Run `cd server && npm test`
3. Test locally: `PORT=8787 CHARACTER_BRAIN_TOKEN=dev AI_BASE_URL=... AI_API_KEY=... AI_MODEL=... node src/index.js`
4. Push to `main` — CI builds and pushes Docker image to GHCR
5. Watchtower on the server auto-pulls within 5 minutes

### Modifying the plugin

1. Edit files in `characterbrain.koplugin/`
2. Run `busted spec/` if you have Busted installed
3. To release: bump version in `_meta.lua`, push tag `v0.x.y`
4. CI creates a GitHub Release with the plugin zip
5. KOReader devices will see the update notification

### Adding a new LLM provider

No code changes needed. Just set the env vars:

```bash
AI_BASE_URL=https://new-provider.com/v1
AI_API_KEY=new-key
AI_MODEL=new-model
# Optional: provider-specific request body fields
AI_EXTRA_BODY={"custom_field": "value"}
```

## Deployment Architecture

```
Internet → Caddy (TLS via Cloudflare DNS-01)
              │
              ▼ reverse_proxy localhost:8787
         Docker: character-brain (ghcr.io/lolwierd/koreader-character-brain:latest)
              │
              ▼ AI_BASE_URL
         NVIDIA / OpenRouter / Gemini / any OpenAI-compatible API

         Docker: Watchtower (polls GHCR every 5 min, restarts on new image)
```

## Common Agent Tasks

### "Change the LLM model"
Only modify `.env` on the server (or `docker-compose.prod.yml` env section).
No code changes. Restart the container.

### "Add a new evidence kind"
1. Add to `ALLOWED_KINDS` in `server/src/validation.js`
2. Add to `allowed_evidence_kinds` in `characterbrain.koplugin/characterbrain_validator.lua`
3. Add display title in `evidence_kind_titles` in `characterbrain.koplugin/main.lua`

### "Change the system prompt"
Edit `server/src/prompts.js`. The prompt is not a security boundary — the
exact-quote validation is. But keep the no-spoilers instructions as defense
in depth.

### "Modify validation rules"
Both `server/src/validation.js` AND `characterbrain_validator.lua` implement
the same logic. Changes must be mirrored in both or the plugin will reject
server-accepted results (or vice versa).

## Gotchas

- **Zero npm dependencies** — The server uses only Node.js built-ins (`http`,
  `crypto`) and the Fetch API. Do not add npm packages without strong
  justification.
- **Lua 5.1** — KOReader uses LuaJIT/Lua 5.1. No Lua 5.3+ features.
- **No streaming** — The server makes a non-streaming request to the upstream
  LLM, even if the provider supports streaming. The full response is validated
  before returning.
- **Passage IDs are sequential** — IDs must match `p<number>` format starting
  from `p1`. The extractor reassigns IDs after sorting.
- **SQLite on Kobo** — The plugin uses SQLite via `lua-ljsqlite3`. WAL mode
  is used when the device supports it.
