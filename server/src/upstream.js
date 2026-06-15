import { SYSTEM_PROMPT, buildUserPrompt } from "./prompts.js";

function chatCompletionsUrl(baseUrl) {
  const normalized = baseUrl.replace(/\/+$/u, "");
  return normalized.endsWith("/chat/completions")
    ? normalized
    : `${normalized}/chat/completions`;
}

function extractJsonObject(content) {
  const stripped = String(content ?? "")
    .replace(/^\s*```[\w-]*\s*/u, "")
    .replace(/\s*```\s*$/u, "");
  const start = stripped.indexOf("{");
  const end = stripped.lastIndexOf("}");
  return start >= 0 && end >= start
    ? stripped.slice(start, end + 1)
    : stripped;
}

export async function analyzeWithUpstream(config, query, passages) {
  const headers = {
    "content-type": "application/json",
    accept: "application/json",
  };
  if (config.apiKey) {
    headers.authorization = `Bearer ${config.apiKey}`;
  }
  if (config.siteUrl) {
    headers["http-referer"] = config.siteUrl;
  }
  if (config.appName) {
    headers["x-title"] = config.appName;
  }

  const response = await fetch(chatCompletionsUrl(config.baseUrl), {
    method: "POST",
    headers,
    body: JSON.stringify({
      model: config.model,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: buildUserPrompt(query, passages) },
      ],
      temperature: 0,
      max_tokens: config.maxTokens,
    }),
    signal: AbortSignal.timeout(config.timeoutMs),
  });

  const rawBody = await response.text();
  if (!response.ok) {
    throw new Error(
      `Upstream returned ${response.status}: ${rawBody.slice(0, 500)}`,
    );
  }

  let envelope;
  try {
    envelope = JSON.parse(rawBody);
  } catch {
    throw new Error("Upstream response was not valid JSON.");
  }
  const content = envelope?.choices?.[0]?.message?.content;
  if (typeof content !== "string") {
    throw new Error(
      "Upstream response did not contain choices[0].message.content.",
    );
  }

  try {
    return JSON.parse(extractJsonObject(content));
  } catch {
    throw new Error("Model response was not valid JSON.");
  }
}
