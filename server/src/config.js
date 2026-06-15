function required(name) {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`${name} is required.`);
  }
  return value;
}

function positiveInteger(name, fallback) {
  const value = Number.parseInt(process.env[name] ?? String(fallback), 10);
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new Error(`${name} must be a positive integer.`);
  }
  return value;
}

function parseExtraBody(raw) {
  if (!raw || !raw.trim()) {
    return {};
  }
  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("AI_EXTRA_BODY must be a JSON object.");
    }
    return parsed;
  } catch (error) {
    throw new Error(`AI_EXTRA_BODY is not valid JSON: ${error.message}`);
  }
}

export function loadConfig() {
  return {
    port: positiveInteger("PORT", 8787),
    accessToken: required("CHARACTER_BRAIN_TOKEN"),
    upstream: {
      baseUrl: required("AI_BASE_URL"),
      apiKey: process.env.AI_API_KEY?.trim() ?? "",
      model: required("AI_MODEL"),
      siteUrl: process.env.AI_SITE_URL?.trim() ?? "",
      appName: process.env.AI_APP_NAME?.trim() ?? "Character Brain",
      maxTokens: positiveInteger("AI_MAX_TOKENS", 1800),
      timeoutMs: positiveInteger("AI_TIMEOUT_MS", 45_000),
      extraBody: parseExtraBody(process.env.AI_EXTRA_BODY),
    },
  };
}
