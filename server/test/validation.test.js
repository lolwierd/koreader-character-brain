import test from "node:test";
import assert from "node:assert/strict";

import { validateAnalysis, validateRequest } from "../src/validation.js";

test("request validation normalizes input", () => {
  assert.deepEqual(validateRequest({
    version: 1,
    query: "  Strider ",
    passages: [{ id: "p1", text: "  Strider watched the door. " }],
  }), {
    query: "Strider",
    passages: [{ id: "p1", text: "Strider watched the door." }],
  });
});

test("analysis rejects generated spoilers", () => {
  const result = validateAnalysis({
    canonical_name: "Strider",
    aliases: [],
    evidence: [{
      kind: "status",
      passage_id: "p1",
      quote: "Strider is secretly the king",
    }],
    connections: [],
  }, "Strider", [{ id: "p1", text: "Strider watched the door." }]);

  assert.equal(result.evidence.length, 0);
  assert.equal(result.rejected_count, 1);
});

test("analysis accepts exact evidence", () => {
  const result = validateAnalysis({
    canonical_name: "Strider",
    aliases: [],
    evidence: [{
      kind: "action",
      passage_id: "p1",
      quote: "Strider watched the door",
    }],
    connections: [],
  }, "Strider", [{ id: "p1", text: "Strider watched the door." }]);

  assert.equal(result.evidence.length, 1);
});
