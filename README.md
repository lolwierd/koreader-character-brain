# Character Brain for KOReader

Character Brain is a spoiler-safe character lookup system for EPUB and KEPUB
books. It targets KOReader 2026.03 and consists of:

- A KOReader plugin that extracts and validates evidence.
- A small server that owns model selection and AI-provider credentials.

The Kobo never calls OpenAI, OpenRouter, Gemini, or another model provider
directly.

## Architecture

```text
KOReader plugin
  -> POST /v1/analyze on your server
     -> server-selected OpenAI-compatible model
     -> server validates exact quotes
  <- structured evidence
  -> plugin validates exact quotes again
  -> native KOReader UI
```

The plugin sends:

```json
{
  "version": 1,
  "query": "Strider",
  "passages": [
    {"id": "p1", "text": "Earlier book text containing Strider..."}
  ]
}
```

The server chooses the model using environment variables. Changing providers or
models requires no plugin update.

## Spoiler Enforcement

1. CREngine searches locally for the selected name and verified aliases.
2. The plugin discards every match ending after the selected word's XPointer.
3. Only allowed passages are sent to the server.
4. The server rejects output without an exact quote from an allowed passage.
5. The plugin independently repeats that validation.
6. The UI displays exact book quotes, never AI-generated story prose.

The model also receives a strict no-spoilers system prompt, but prompts are not
treated as a security boundary. XPointer filtering and exact-quote validation
are the enforcement mechanisms.

## Plugin Installation

Copy `characterbrain.koplugin` into:

```text
koreader/plugins/
```

Restart KOReader and open:

```text
Tools > Character Brain > Backend settings
```

Enter:

- Your server URL, such as `https://character-brain.example.com`
- The shared backend access token

The plugin appends `/v1/analyze` unless the complete endpoint is entered.
The access token is stored unencrypted in KOReader's settings directory.

## Server Configuration

The server requires Node.js 20 or newer and has no npm dependencies:

```bash
cd server
cp .env.example .env
```

Set:

```text
CHARACTER_BRAIN_TOKEN=a-long-random-secret
AI_BASE_URL=https://openrouter.ai/api/v1
AI_API_KEY=your-provider-key
AI_MODEL=provider/model-name
```

Then run:

```bash
set -a
. ./.env
set +a
npm start
```

Health check:

```text
GET /health
```

### Docker

```bash
cd server
cp .env.example .env
docker compose up -d --build
```

### Provider Examples

OpenRouter:

```text
AI_BASE_URL=https://openrouter.ai/api/v1
AI_MODEL=provider/model-name
```

Gemini's OpenAI-compatible API:

```text
AI_BASE_URL=https://generativelanguage.googleapis.com/v1beta/openai
AI_MODEL=gemini-model-name
```

Any service implementing OpenAI-compatible `/chat/completions` can be used.

## Privacy

Before its first request, the plugin displays the exact JSON payload and asks
for consent. The server does not log passage content. Reverse-proxy access logs
should also be configured not to record request bodies.

## Testing

```bash
cd server
npm test
```

Plugin tests live in `spec/` and use Busted under Lua 5.1.
