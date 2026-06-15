local CBUtil = require("characterbrain_util")

local Validator = {}

local allowed_evidence_kinds = {
    description = true,
    action = true,
    speech = true,
    status = true,
}

local function passageMap(passages)
    local result = {}
    for _, passage in ipairs(passages) do
        result[passage.id] = passage
    end
    return result
end

local function validCitation(item, passages_by_id)
    if type(item) ~= "table" or type(item.passage_id) ~= "string"
        or type(item.quote) ~= "string" then
        return nil
    end
    local passage = passages_by_id[item.passage_id]
    local quote = CBUtil.normalizeWhitespace(item.quote)
    if not passage or #quote < 8 or not CBUtil.containsLiteral(passage.text, quote) then
        return nil
    end
    return passage, quote
end

function Validator.validate(response, query, passages)
    if type(response) ~= "table" then
        return nil, "The analysis response is not a JSON object."
    end

    local passages_by_id = passageMap(passages)
    local accepted = {
        canonical_name = query,
        aliases = {},
        evidence = {},
        connections = {},
        rejected_count = math.min(
            math.max(math.floor(tonumber(response.rejected_count) or 0), 0),
            9999
        ),
    }

    local canonical = CBUtil.normalizeWhitespace(response.canonical_name)
    if canonical ~= "" then
        local canonical_seen = CBUtil.normalizeName(canonical) == CBUtil.normalizeName(query)
        if not canonical_seen then
            for _, passage in ipairs(passages) do
                if passage.text:lower():find(canonical:lower(), 1, true) then
                    canonical_seen = true
                    break
                end
            end
        end
        if canonical_seen then
            accepted.canonical_name = canonical
        end
    end

    for _, alias in ipairs(response.aliases or {}) do
        local passage, quote = validCitation(alias, passages_by_id)
        local name = CBUtil.normalizeWhitespace(alias.name)
        if passage and name ~= ""
            and CBUtil.containsLiteral(quote, name)
            and (CBUtil.containsLiteral(quote, query)
                or CBUtil.containsLiteral(quote, accepted.canonical_name)) then
            table.insert(accepted.aliases, {
                name = name,
                passage_id = alias.passage_id,
                quote = quote,
            })
        else
            accepted.rejected_count = accepted.rejected_count + 1
        end
    end

    for _, item in ipairs(response.evidence or {}) do
        local passage, quote = validCitation(item, passages_by_id)
        if passage and allowed_evidence_kinds[item.kind] then
            table.insert(accepted.evidence, {
                kind = item.kind,
                passage_id = item.passage_id,
                quote = quote,
            })
        else
            accepted.rejected_count = accepted.rejected_count + 1
        end
    end

    for _, connection in ipairs(response.connections or {}) do
        local passage, quote = validCitation(connection, passages_by_id)
        local name = CBUtil.normalizeWhitespace(connection.name)
        if passage and name ~= ""
            and CBUtil.containsLiteral(quote, name)
            and (CBUtil.containsLiteral(quote, query)
                or CBUtil.containsLiteral(quote, accepted.canonical_name)) then
            table.insert(accepted.connections, {
                name = name,
                passage_id = connection.passage_id,
                quote = quote,
            })
        else
            accepted.rejected_count = accepted.rejected_count + 1
        end
    end

    return accepted
end

return Validator
