import test from "node:test";
import assert from "node:assert/strict";

import { createApp } from "../src/app.js";

const config = {
  accessToken: "test-token",
  upstream: {},
};

async function withServer(analyze, callback) {
  const server = createApp(config, { analyze });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const { port } = server.address();
    await callback(`http://127.0.0.1:${port}`);
  } finally {
    await new Promise((resolve, reject) =>
      server.close((error) => error ? reject(error) : resolve())
    );
  }
}

test("requires the backend access token", async () => {
  await withServer(async () => ({}), async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/analyze`, {
      method: "POST",
      body: "{}",
    });
    assert.equal(response.status, 401);
  });
});

test("returns locally validated analysis", async () => {
  await withServer(async () => ({
    canonical_name: "Strider",
    aliases: [],
    evidence: [{
      kind: "action",
      passage_id: "p1",
      quote: "Strider watched the door",
    }],
    connections: [],
  }), async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/analyze`, {
      method: "POST",
      headers: {
        authorization: "Bearer test-token",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        version: 1,
        query: "Strider",
        passages: [{ id: "p1", text: "Strider watched the door." }],
      }),
    });
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.analysis.evidence.length, 1);
  });
});
