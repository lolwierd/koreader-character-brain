import { createServer } from "node:http";
import { timingSafeEqual } from "node:crypto";

import { analyzeWithUpstream } from "./upstream.js";
import { validateAnalysis, validateRequest } from "./validation.js";

const MAX_REQUEST_BYTES = 80_000;

function sendJson(response, status, value) {
  const body = JSON.stringify(value);
  response.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(body),
    "cache-control": "no-store",
  });
  response.end(body);
}

function authorized(header, expectedToken) {
  if (typeof header !== "string" || !header.startsWith("Bearer ")) {
    return false;
  }
  const supplied = Buffer.from(header.slice(7));
  const expected = Buffer.from(expectedToken);
  return supplied.length === expected.length &&
    timingSafeEqual(supplied, expected);
}

async function readJson(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > MAX_REQUEST_BYTES) {
      throw new Error("Request body is too large.");
    }
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw new Error("Request body is not valid JSON.");
  }
}

export function createApp(config, dependencies = {}) {
  const analyze = dependencies.analyze ?? analyzeWithUpstream;

  return createServer(async (request, response) => {
    if (request.method === "GET" && request.url === "/health") {
      sendJson(response, 200, { ok: true });
      return;
    }
    if (request.method !== "POST" || request.url !== "/v1/analyze") {
      sendJson(response, 404, { error: "Not found." });
      return;
    }
    if (!authorized(request.headers.authorization, config.accessToken)) {
      sendJson(response, 401, { error: "Unauthorized." });
      return;
    }

    try {
      const { query, passages } = validateRequest(await readJson(request));
      const rawAnalysis = await analyze(config.upstream, query, passages);
      const analysis = validateAnalysis(rawAnalysis, query, passages);
      sendJson(response, 200, { version: 1, analysis });
    } catch (error) {
      const message = error instanceof Error
        ? error.message
        : "Unknown server error.";
      const clientError = /^(Unsupported|query|passages|Passage|Each|At most|Request body)/u
        .test(message);
      sendJson(response, clientError ? 400 : 502, { error: message });
    }
  });
}
