const ALLOWED_KINDS = new Set([
  "description",
  "action",
  "speech",
  "status",
]);

export function normalizeWhitespace(value) {
  return typeof value === "string"
    ? value.trim().replace(/\s+/gu, " ")
    : "";
}

function containsLiteral(haystack, needle) {
  const normalizedHaystack = normalizeWhitespace(haystack);
  const normalizedNeedle = normalizeWhitespace(needle);
  return normalizedNeedle.length > 0 &&
    normalizedHaystack.includes(normalizedNeedle);
}

function validCitation(item, passagesById) {
  if (!item || typeof item !== "object") {
    return null;
  }
  const passage = passagesById.get(item.passage_id);
  const quote = normalizeWhitespace(item.quote);
  if (!passage || quote.length < 8 || !containsLiteral(passage.text, quote)) {
    return null;
  }
  return { passage, quote };
}

export function validateRequest(body) {
  if (!body || typeof body !== "object" || body.version !== 1) {
    throw new Error("Unsupported or missing protocol version.");
  }
  const query = normalizeWhitespace(body.query);
  if (!query || query.length > 80) {
    throw new Error("query must contain 1 to 80 characters.");
  }
  if (!Array.isArray(body.passages) || body.passages.length === 0) {
    throw new Error("passages must be a non-empty array.");
  }
  if (body.passages.length > 60) {
    throw new Error("At most 60 passages are allowed.");
  }

  let totalCharacters = 0;
  const seenIds = new Set();
  const passages = body.passages.map((item) => {
    const id = normalizeWhitespace(item?.id);
    const text = normalizeWhitespace(item?.text);
    if (!/^p[1-9][0-9]*$/u.test(id) || seenIds.has(id)) {
      throw new Error("Each passage must have a unique p<number> id.");
    }
    if (!text) {
      throw new Error("Passage text cannot be empty.");
    }
    seenIds.add(id);
    totalCharacters += text.length;
    return { id, text };
  });
  if (totalCharacters > 60_000) {
    throw new Error("Passage text exceeds the 60,000 character limit.");
  }

  return { query, passages };
}

export function validateAnalysis(raw, query, passages) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new Error("Model response is not a JSON object.");
  }

  const passagesById = new Map(passages.map((passage) => [
    passage.id,
    passage,
  ]));
  const accepted = {
    canonical_name: query,
    aliases: [],
    evidence: [],
    connections: [],
    rejected_count: 0,
  };

  const canonicalName = normalizeWhitespace(raw.canonical_name);
  const canonicalIsVisible = canonicalName.toLowerCase() === query.toLowerCase() ||
    passages.some(({ text }) =>
      text.toLowerCase().includes(canonicalName.toLowerCase())
    );
  if (canonicalName && canonicalIsVisible) {
    accepted.canonical_name = canonicalName;
  }

  for (const alias of Array.isArray(raw.aliases) ? raw.aliases : []) {
    const citation = validCitation(alias, passagesById);
    const name = normalizeWhitespace(alias?.name);
    if (
      citation &&
      name &&
      containsLiteral(citation.quote, name) &&
      (
        containsLiteral(citation.quote, query) ||
        containsLiteral(citation.quote, accepted.canonical_name)
      )
    ) {
      accepted.aliases.push({
        name,
        passage_id: alias.passage_id,
        quote: citation.quote,
      });
    } else {
      accepted.rejected_count += 1;
    }
  }

  for (const item of Array.isArray(raw.evidence) ? raw.evidence : []) {
    const citation = validCitation(item, passagesById);
    if (citation && ALLOWED_KINDS.has(item.kind)) {
      accepted.evidence.push({
        kind: item.kind,
        passage_id: item.passage_id,
        quote: citation.quote,
      });
    } else {
      accepted.rejected_count += 1;
    }
  }

  for (
    const connection of Array.isArray(raw.connections) ? raw.connections : []
  ) {
    const citation = validCitation(connection, passagesById);
    const name = normalizeWhitespace(connection?.name);
    if (
      citation &&
      name &&
      containsLiteral(citation.quote, name) &&
      (
        containsLiteral(citation.quote, query) ||
        containsLiteral(citation.quote, accepted.canonical_name)
      )
    ) {
      accepted.connections.push({
        name,
        passage_id: connection.passage_id,
        quote: citation.quote,
      });
    } else {
      accepted.rejected_count += 1;
    }
  }

  return accepted;
}
