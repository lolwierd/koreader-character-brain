import { createServer } from "node:http";
import test from "node:test";
import assert from "node:assert/strict";

import { analyzeWithUpstream } from "../src/upstream.js";

test("model selection stays on the server", async () => {
  let received;
  const upstream = createServer(async (request, response) => {
    const chunks = [];
    for await (const chunk of request) {
      chunks.push(chunk);
    }
    received = {
      url: request.url,
      authorization: request.headers.authorization,
      body: JSON.parse(Buffer.concat(chunks).toString("utf8")),
    };
    const body = JSON.stringify({
      choices: [{
        message: {
          content: JSON.stringify({
            canonical_name: "Strider",
            aliases: [],
            evidence: [],
            connections: [],
          }),
        },
      }],
    });
    response.writeHead(200, {
      "content-type": "application/json",
      "content-length": Buffer.byteLength(body),
    });
    response.end(body);
  });
  await new Promise((resolve) => upstream.listen(0, "127.0.0.1", resolve));

  try {
    const { port } = upstream.address();
    const result = await analyzeWithUpstream({
      baseUrl: `http://127.0.0.1:${port}/v1`,
      apiKey: "provider-secret",
      model: "change-me-on-the-server",
      siteUrl: "",
      appName: "Character Brain",
      maxTokens: 1000,
      timeoutMs: 5000,
    }, "Strider", [{ id: "p1", text: "Strider watched the door." }]);

    assert.equal(result.canonical_name, "Strider");
    assert.equal(received.url, "/v1/chat/completions");
    assert.equal(received.authorization, "Bearer provider-secret");
    assert.equal(received.body.model, "change-me-on-the-server");
    assert.equal(received.body.messages[1].content.includes("Strider"), true);
  } finally {
    await new Promise((resolve, reject) =>
      upstream.close((error) => error ? reject(error) : resolve())
    );
  }
});
